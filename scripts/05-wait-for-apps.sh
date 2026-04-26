#!/usr/bin/env bash
# Wait for the root app-of-apps tree to land and for every Argo CD Application
# to reach Synced + Healthy. Without this, "just up" returns while half the
# stack is still being rendered, and follow-on commands hit transient errors.
#
# Apps in $MANUAL_SYNC_APPS are skipped — they have no automated sync policy
# (e.g. shop-failed-deploy is intentionally broken to demo SyncFail hooks)
# and would never reach Synced on their own.
set -euo pipefail

NS="argocd"
TIMEOUT="${TIMEOUT:-600s}"
EXPECTED_COUNT="${EXPECTED_COUNT:-20}"
MANUAL_SYNC_APPS=(shop-failed-deploy)

echo "==> waiting for root-app to be Synced+Healthy"
kubectl -n "${NS}" wait --for=jsonpath='{.status.sync.status}'=Synced \
  application/root-app --timeout="${TIMEOUT}"
kubectl -n "${NS}" wait --for=jsonpath='{.status.health.status}'=Healthy \
  application/root-app --timeout="${TIMEOUT}"

echo "==> waiting for child Applications to register (expecting >= ${EXPECTED_COUNT})"
# root-app fans out into ~20+ child Applications. Wait until the controller
# has materialized at least EXPECTED_COUNT of them before snapshotting the
# wait set, otherwise `kubectl wait --all` races and silently misses apps
# created after it started watching. If the count plateaus below the target
# for a while, proceed anyway — the chart list may have shrunk.
prev=-1
stable=0
for i in {1..60}; do
  count=$(kubectl -n "${NS}" get applications --no-headers 2>/dev/null | wc -l | tr -d ' ')
  if [[ "${count}" -ge "${EXPECTED_COUNT}" ]]; then
    echo "    ${count} Applications registered"
    break
  fi
  if [[ "${count}" -eq "${prev}" ]]; then
    stable=$((stable + 1))
  else
    stable=0
    echo "    [${i}/60] ${count}/${EXPECTED_COUNT} Applications registered..."
  fi
  if [[ "${stable}" -ge 5 ]]; then
    echo "    count stable at ${count} for 10s, proceeding"
    break
  fi
  prev="${count}"
  sleep 2
done

# Build the list of apps to wait on, excluding manual-sync apps. Avoid
# `mapfile` so this works on macOS's default bash 3.2.
SYNC_APPS=()
while IFS= read -r app; do
  name="${app#application.argoproj.io/}"
  skip=0
  for m in "${MANUAL_SYNC_APPS[@]}"; do
    [[ "${name}" == "${m}" ]] && skip=1 && break
  done
  [[ "${skip}" -eq 0 ]] && SYNC_APPS+=("${app}")
done < <(kubectl -n "${NS}" get applications -o name)

echo "==> waiting for every auto-sync Application to be Synced (skipping: ${MANUAL_SYNC_APPS[*]})"
kubectl -n "${NS}" wait --for=jsonpath='{.status.sync.status}'=Synced \
  "${SYNC_APPS[@]}" --timeout="${TIMEOUT}"

echo "==> waiting for every auto-sync Application to be Healthy"
kubectl -n "${NS}" wait --for=jsonpath='{.status.health.status}'=Healthy \
  "${SYNC_APPS[@]}" --timeout="${TIMEOUT}"

echo
echo "All Argo CD Applications:"
kubectl -n "${NS}" get applications -o custom-columns=NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status
