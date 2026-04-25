#!/usr/bin/env bash
# Verifies the full deploy chain on the sync-waves-demo Application:
#   1. PreSync   migration Job ran and Succeeded
#   2. Deploy    Service + Deployment are reconciled
#   3. PostSync  e2e probe Job ran and Succeeded
#   4. Argo CD Notifications fired on-sync-succeeded and the rendered
#      template body shows up in argocd-notifications-controller logs
set -euo pipefail

NS=sync-waves-demo
APP=sync-waves-demo

echo "[chain] waiting for Application ${APP} Synced+Healthy"
kubectl -n argocd wait --for=jsonpath='{.status.sync.status}'=Synced "application/${APP}" --timeout=300s
kubectl -n argocd wait --for=jsonpath='{.status.health.status}'=Healthy "application/${APP}" --timeout=300s

echo "[chain] verifying PreSync hook (sync-waves-demo-presync) Succeeded"
PRESYNC_PHASE=$(kubectl -n argocd get app "${APP}" \
  -o jsonpath='{range .status.operationState.syncResult.resources[?(@.name=="sync-waves-demo-presync")]}{.hookPhase}{"\n"}{end}' \
  | tail -1)
echo "[chain]   presync hookPhase=${PRESYNC_PHASE:-<none>}"
if [[ "${PRESYNC_PHASE}" != "Succeeded" ]]; then
  echo "[chain] FAIL: PreSync did not Succeed"
  exit 1
fi

echo "[chain] verifying PostSync hook (sync-waves-demo-postsync) Succeeded"
POSTSYNC_PHASE=$(kubectl -n argocd get app "${APP}" \
  -o jsonpath='{range .status.operationState.syncResult.resources[?(@.name=="sync-waves-demo-postsync")]}{.hookPhase}{"\n"}{end}' \
  | tail -1)
echo "[chain]   postsync hookPhase=${POSTSYNC_PHASE:-<none>}"
if [[ "${POSTSYNC_PHASE}" != "Succeeded" ]]; then
  echo "[chain] FAIL: PostSync e2e did not Succeed"
  exit 1
fi

echo "[chain] verifying Service responds with expected greeting from inside the cluster"
kubectl -n "${NS}" run chain-probe --rm -i --restart=Never --image=curlimages/curl:8.10.1 -- \
  sh -c 'curl -fsS http://sync-waves-app.sync-waves-demo.svc.cluster.local/ | grep -q "hello from wave 0"'

echo "[chain] verifying argocd-notifications-controller dispatched on-sync-succeeded alert for ${APP}"
# Controller logs "Notification ... sent" when alertmanager dispatch succeeds.
if ! kubectl -n argocd logs deploy/argocd-notifications-controller --tail=2000 \
    | grep -E "(app-sync-succeeded-alert|ArgoCDSyncSucceeded).*${APP}|${APP}.*(app-sync-succeeded-alert|ArgoCDSyncSucceeded)|Sending.*${APP}" >/dev/null; then
  # Fallback: webhook-logger should have received the alertmanager-routed alert body.
  if ! kubectl -n monitoring logs deploy/webhook-logger --tail=2000 \
      | grep -E "ArgoCDSyncSucceeded|sync-waves-demo" >/dev/null; then
    echo "[chain] FAIL: notification dispatch evidence for ${APP} not found"
    kubectl -n argocd logs deploy/argocd-notifications-controller --tail=200 | tail -50 || true
    exit 1
  fi
fi

echo "[chain] deploy-chain verification passed"
