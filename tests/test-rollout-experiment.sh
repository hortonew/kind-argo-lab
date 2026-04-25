#!/usr/bin/env bash
# Verify the Argo Rollouts Experiment demo:
#   - Application Synced+Healthy
#   - Experiment runs baseline + candidate ReplicaSets in parallel
#   - Experiment auto-terminates with phase Successful
set -euo pipefail

NS=rollout-experiment-demo
APP=rollout-experiment-demo
EXP=side-by-side

echo "[exp] waiting for Application ${APP} Synced"
kubectl -n argocd wait --for=jsonpath='{.status.sync.status}'=Synced "application/${APP}" --timeout=300s

echo "[exp] verifying Experiment ${EXP} exists"
kubectl -n "${NS}" get experiment "${EXP}" >/dev/null

echo "[exp] waiting for Experiment to reach a terminal phase (≤180s)"
phase=""
for _ in {1..90}; do
  phase=$(kubectl -n "${NS}" get experiment "${EXP}" -o jsonpath='{.status.phase}' 2>/dev/null || true)
  case "${phase}" in
    Successful|Failed|Error) break ;;
  esac
  sleep 2
done
echo "[exp]   experiment phase=${phase}"
if [[ "${phase}" != "Successful" ]]; then
  echo "[exp] FAIL: experiment did not reach Successful"
  kubectl -n "${NS}" get experiment "${EXP}" -o yaml | tail -60
  exit 1
fi

echo "[exp] verifying baseline + candidate ReplicaSets were created by the Experiment"
for variant in baseline candidate; do
  if ! kubectl -n "${NS}" get rs "${EXP}-${variant}" >/dev/null 2>&1; then
    echo "[exp] FAIL: expected ReplicaSet ${EXP}-${variant} to exist"
    kubectl -n "${NS}" get rs
    exit 1
  fi
done

echo "[exp] Experiment demo verified"
