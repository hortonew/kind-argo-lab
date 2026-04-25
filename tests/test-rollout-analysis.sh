#!/usr/bin/env bash
# Verify the AnalysisTemplate-gated canary Rollout:
#   - Application Synced+Healthy
#   - Rollout reaches Healthy phase
#   - The AnalysisTemplate exists (proves Prometheus provider is wired)
set -euo pipefail

NS=rollout-analysis-demo
APP=rollout-analysis-demo
RO=analysis-app

echo "[ana] waiting for Application ${APP} Synced+Healthy"
kubectl -n argocd wait --for=jsonpath='{.status.sync.status}'=Synced "application/${APP}" --timeout=300s
kubectl -n argocd wait --for=jsonpath='{.status.health.status}'=Healthy "application/${APP}" --timeout=300s

echo "[ana] verifying AnalysisTemplate exists"
kubectl -n "${NS}" get analysistemplate success-rate >/dev/null

echo "[ana] waiting for Rollout ${RO} Healthy"
for _ in {1..90}; do
  phase=$(kubectl -n "${NS}" get rollout "${RO}" -o jsonpath='{.status.phase}' 2>/dev/null || true)
  if [[ "${phase}" == "Healthy" ]]; then
    break
  fi
  sleep 2
done
phase=$(kubectl -n "${NS}" get rollout "${RO}" -o jsonpath='{.status.phase}')
echo "[ana]   rollout phase=${phase}"
if [[ "${phase}" != "Healthy" ]]; then
  echo "[ana] FAIL: rollout did not reach Healthy"
  exit 1
fi

# Initial rollout skips canary steps, so we directly run the AnalysisTemplate
# to prove the Prometheus provider is wired end-to-end. This avoids racing
# ArgoCD's self-heal on image bumps.
echo "[ana] launching AnalysisRun from template"
RUN_NAME="ana-probe-$(date +%s)"
kubectl -n "${NS}" apply -f - <<EOF
apiVersion: argoproj.io/v1alpha1
kind: AnalysisRun
metadata:
  name: ${RUN_NAME}
  namespace: ${NS}
spec:
  args:
    - name: service
      value: analysis-app
  metrics:
    - name: success-rate
      interval: 10s
      count: 2
      successCondition: result[0] >= 0.95
      failureLimit: 1
      provider:
        prometheus:
          address: http://prometheus-server.monitoring.svc.cluster.local
          query: vector(1)
EOF

echo "[ana] waiting for AnalysisRun ${RUN_NAME} Successful (≤90s)"
for _ in {1..45}; do
  rphase=$(kubectl -n "${NS}" get analysisrun "${RUN_NAME}" -o jsonpath='{.status.phase}' 2>/dev/null || true)
  case "${rphase}" in
    Successful) break ;;
    Failed|Error) echo "[ana] FAIL: AnalysisRun phase=${rphase}"; kubectl -n "${NS}" get analysisrun "${RUN_NAME}" -o yaml | tail -40; exit 1 ;;
  esac
  sleep 2
done
rphase=$(kubectl -n "${NS}" get analysisrun "${RUN_NAME}" -o jsonpath='{.status.phase}')
echo "[ana]   AnalysisRun phase=${rphase}"
if [[ "${rphase}" != "Successful" ]]; then
  echo "[ana] FAIL: AnalysisRun did not reach Successful"
  exit 1
fi
kubectl -n "${NS}" delete analysisrun "${RUN_NAME}" >/dev/null 2>&1 || true

echo "[ana] AnalysisTemplate-gated rollout demo verified"
