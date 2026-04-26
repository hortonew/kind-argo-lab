#!/usr/bin/env bash
# Wait for the root app-of-apps tree to land and for every Argo CD Application
# to reach Synced + Healthy. Without this, "just up" returns while half the
# stack is still being rendered, and follow-on commands hit transient errors.
set -euo pipefail

NS="argocd"
TIMEOUT="${TIMEOUT:-600s}"

echo "==> waiting for root-app to be Synced+Healthy"
kubectl -n "${NS}" wait --for=jsonpath='{.status.sync.status}'=Synced \
  application/root-app --timeout="${TIMEOUT}"
kubectl -n "${NS}" wait --for=jsonpath='{.status.health.status}'=Healthy \
  application/root-app --timeout="${TIMEOUT}"

echo "==> waiting for child Applications to register"
# root-app fans out into ~15+ child Applications. Give the controller a beat
# to materialize them before we wait, otherwise `kubectl wait` races and exits
# successfully against an empty list.
for _ in {1..30}; do
  count=$(kubectl -n "${NS}" get applications --no-headers 2>/dev/null | wc -l | tr -d ' ')
  if [[ "${count}" -gt 5 ]]; then
    break
  fi
  sleep 2
done

echo "==> waiting for every Application to be Synced"
kubectl -n "${NS}" wait --for=jsonpath='{.status.sync.status}'=Synced \
  application --all --timeout="${TIMEOUT}"

echo "==> waiting for every Application to be Healthy"
kubectl -n "${NS}" wait --for=jsonpath='{.status.health.status}'=Healthy \
  application --all --timeout="${TIMEOUT}"

echo
echo "All Argo CD Applications are Synced + Healthy:"
kubectl -n "${NS}" get applications -o custom-columns=NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status
