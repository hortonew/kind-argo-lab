#!/usr/bin/env bash
# Verify the Argo Rollouts blueGreen demo:
#   - Application Synced+Healthy
#   - Rollout reaches Healthy phase with the active service serving traffic
set -euo pipefail

NS=bluegreen-demo
APP=rollout-bluegreen-demo
RO=bluegreen-app

echo "[bg] waiting for Application ${APP} Synced+Healthy"
kubectl -n argocd wait --for=jsonpath='{.status.sync.status}'=Synced "application/${APP}" --timeout=300s
kubectl -n argocd wait --for=jsonpath='{.status.health.status}'=Healthy "application/${APP}" --timeout=300s

echo "[bg] waiting for Rollout ${RO} Healthy"
for _ in {1..60}; do
  phase=$(kubectl -n "${NS}" get rollout "${RO}" -o jsonpath='{.status.phase}' 2>/dev/null || true)
  if [[ "${phase}" == "Healthy" ]]; then
    break
  fi
  sleep 2
done
phase=$(kubectl -n "${NS}" get rollout "${RO}" -o jsonpath='{.status.phase}')
echo "[bg]   rollout phase=${phase}"
if [[ "${phase}" != "Healthy" ]]; then
  echo "[bg] FAIL: rollout did not reach Healthy"
  exit 1
fi

echo "[bg] verifying both active and preview Services exist"
kubectl -n "${NS}" get svc bluegreen-active >/dev/null
kubectl -n "${NS}" get svc bluegreen-preview >/dev/null

echo "[bg] verifying activeService responds via in-cluster curl"
kubectl -n "${NS}" run bg-probe --rm -i --restart=Never --image=curlimages/curl:8.10.1 -- \
  curl -fsS http://bluegreen-active.${NS}.svc.cluster.local/ >/dev/null

echo "[bg] blueGreen rollout demo verified"
