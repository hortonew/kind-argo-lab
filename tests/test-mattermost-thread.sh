#!/usr/bin/env bash
# Verify the Mattermost threaded notification demo:
#   - Application Synced
#   - mattermost-creds Secret exists in argo namespace (bootstrap done)
#   - Submit the WorkflowTemplate, wait for Succeeded
#   - Query Mattermost API: parent post has 3 in-thread replies
set -euo pipefail

NS=argo
APP=mattermost-thread-demo
WFT=mattermost-thread-demo
SECRET=mattermost-creds

echo "[mm] waiting for Application ${APP} Synced"
kubectl -n argocd wait --for=jsonpath='{.status.sync.status}'=Synced "application/${APP}" --timeout=300s

echo "[mm] waiting for mattermost Application Synced+Healthy"
kubectl -n argocd wait --for=jsonpath='{.status.sync.status}'=Synced "application/mattermost" --timeout=300s
kubectl -n argocd wait --for=jsonpath='{.status.health.status}'=Healthy "application/mattermost" --timeout=300s

echo "[mm] waiting for ${SECRET} Secret in ${NS} (≤300s)"
for _ in {1..60}; do
  if kubectl -n "${NS}" get secret "${SECRET}" >/dev/null 2>&1; then
    break
  fi
  sleep 5
done
if ! kubectl -n "${NS}" get secret "${SECRET}" >/dev/null 2>&1; then
  echo "[mm] FAIL: ${SECRET} not created — bootstrap Job logs:"
  kubectl -n mattermost logs job/mattermost-bootstrap --tail=80 || true
  exit 1
fi

echo "[mm] submitting WorkflowTemplate ${WFT}"
WF_NAME=$(kubectl -n "${NS}" create -f - -o jsonpath='{.metadata.name}' <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Workflow
metadata:
  generateName: mm-thread-test-
  namespace: ${NS}
spec:
  workflowTemplateRef:
    name: ${WFT}
EOF
)
echo "[mm]   submitted ${WF_NAME}"

echo "[mm] waiting for ${WF_NAME} to finish (≤180s)"
phase=""
for _ in {1..90}; do
  phase=$(kubectl -n "${NS}" get wf "${WF_NAME}" -o jsonpath='{.status.phase}' 2>/dev/null || true)
  case "${phase}" in
    Succeeded|Failed|Error) break ;;
  esac
  sleep 2
done
echo "[mm]   workflow phase=${phase}"
if [[ "${phase}" != "Succeeded" ]]; then
  echo "[mm] FAIL: workflow did not Succeed"
  kubectl -n "${NS}" get wf "${WF_NAME}" -o yaml | tail -80
  exit 1
fi

echo "[mm] reading parent root_id from start node output"
ROOT_ID=$(kubectl -n "${NS}" get wf "${WF_NAME}" -o json \
  | jq -r '[.status.nodes[] | select(.displayName=="start")][0].outputs.parameters[] | select(.name=="root_id").value')
if [[ -z "${ROOT_ID}" || "${ROOT_ID}" == "null" ]]; then
  echo "[mm] FAIL: could not extract root_id from workflow"
  exit 1
fi
echo "[mm]   root_id=${ROOT_ID}"

echo "[mm] querying Mattermost thread"
TOKEN=$(kubectl -n "${NS}" get secret "${SECRET}" -o jsonpath='{.data.token}' | base64 -d)
URL=$(kubectl -n "${NS}" get secret "${SECRET}" -o jsonpath='{.data.url}' | base64 -d)

REPLIES=$(kubectl -n mattermost run mm-probe --rm --restart=Never --quiet --attach \
  --image=badouralix/curl-jq:latest --command -- sh -c \
  "curl -fsS -H 'Authorization: Bearer ${TOKEN}' '${URL}/api/v4/posts/${ROOT_ID}/thread' | jq '.order | length'" \
  2>/dev/null | grep -E '^[0-9]+$' | head -1)

echo "[mm]   thread post count (incl. parent)=${REPLIES}"
if ! [[ "${REPLIES}" =~ ^[0-9]+$ ]]; then
  echo "[mm] FAIL: could not parse thread post count"
  exit 1
fi
if (( REPLIES < 4 )); then
  echo "[mm] FAIL: expected ≥4 posts in thread (parent + 3 replies), got ${REPLIES}"
  exit 1
fi

echo "[mm] Mattermost threaded notification demo verified"
