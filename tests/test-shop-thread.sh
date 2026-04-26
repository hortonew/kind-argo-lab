#!/usr/bin/env bash
# Verify the Shop app's PreSync/PostSync hook chain (implemented as Argo
# Workflows in the `argo` namespace):
#   - Application Synced+Healthy
#   - mattermost-creds Secret exists in argo namespace
#   - shop-mm-thread ConfigMap (in argo ns) holds a root_id
#   - Mattermost thread has parent + ≥3 replies (migration, sync ok, e2e)
set -euo pipefail

HOOK_NS=argo
APP=shop
SECRET=mattermost-creds
THREAD_CM=shop-mm-thread

echo "[shop] waiting for Application ${APP} Synced+Healthy"
kubectl -n argocd wait --for=jsonpath='{.status.sync.status}'=Synced "application/${APP}" --timeout=600s
kubectl -n argocd wait --for=jsonpath='{.status.health.status}'=Healthy "application/${APP}" --timeout=600s

echo "[shop] waiting for ${SECRET} Secret in ${HOOK_NS} (≤300s)"
for _ in {1..60}; do
  if kubectl -n "${HOOK_NS}" get secret "${SECRET}" >/dev/null 2>&1; then
    break
  fi
  sleep 5
done
if ! kubectl -n "${HOOK_NS}" get secret "${SECRET}" >/dev/null 2>&1; then
  echo "[shop] FAIL: ${SECRET} not created — mattermost bootstrap Job logs:"
  kubectl -n mattermost logs job/mattermost-bootstrap --tail=80 || true
  exit 1
fi

echo "[shop] reading root_id from ConfigMap ${HOOK_NS}/${THREAD_CM}"
ROOT_ID=""
for _ in {1..30}; do
  ROOT_ID=$(kubectl -n "${HOOK_NS}" get cm "${THREAD_CM}" -o jsonpath='{.data.root_id}' 2>/dev/null || true)
  [[ -n "${ROOT_ID}" ]] && break
  sleep 5
done
if [[ -z "${ROOT_ID}" ]]; then
  echo "[shop] FAIL: ${THREAD_CM} ConfigMap missing or empty (PreSync wave -2 didn't run?)"
  kubectl -n "${HOOK_NS}" get cm "${THREAD_CM}" -o yaml || true
  exit 1
fi
echo "[shop]   root_id=${ROOT_ID}"

echo "[shop] querying Mattermost thread"
TOKEN=$(kubectl -n "${HOOK_NS}" get secret "${SECRET}" -o jsonpath='{.data.token}' | base64 -d)
URL=$(kubectl -n "${HOOK_NS}" get secret "${SECRET}" -o jsonpath='{.data.url}' | base64 -d)

# PostSync hooks may still be running when sync first reports Healthy
# (PostSync runs *after* Healthy), so retry until thread has the
# expected reply count.
REPLIES=0
for _ in {1..30}; do
  REPLIES=$(kubectl -n mattermost run shop-probe --rm --restart=Never --quiet --attach \
    --image=badouralix/curl-jq:latest --command -- sh -c \
    "curl -fsS -H 'Authorization: Bearer ${TOKEN}' '${URL}/api/v4/posts/${ROOT_ID}/thread' | jq '.order | length'" \
    2>/dev/null | grep -E '^[0-9]+$' | head -1 || echo 0)
  echo "[shop]   thread post count (incl. parent)=${REPLIES}"
  if [[ "${REPLIES}" =~ ^[0-9]+$ ]] && (( REPLIES >= 4 )); then
    break
  fi
  sleep 5
done

if ! [[ "${REPLIES}" =~ ^[0-9]+$ ]]; then
  echo "[shop] FAIL: could not parse thread post count"
  exit 1
fi
if (( REPLIES < 4 )); then
  echo "[shop] FAIL: expected ≥4 posts in thread (parent + migration + sync-ok + e2e), got ${REPLIES}"
  exit 1
fi

echo "[shop] Shop sync hooks demo verified"
