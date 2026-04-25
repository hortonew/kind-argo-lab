#!/usr/bin/env bash
set -euo pipefail

GITEA_URL="http://localhost:3000"
GITEA_NAMESPACE="gitea"
ADMIN_USER="admin"
ADMIN_PASS="adminpass"
ORG="argo-lab"
REPO="demo-app"
HOOK_URL="http://eventsource-svc.argo-events.svc.cluster.local:12000/gitea"

kubectl -n "${GITEA_NAMESPACE}" port-forward svc/gitea-http 3000:3000 >/tmp/gitea-port-forward.log 2>&1 &
PF_PID=$!
trap 'kill ${PF_PID} >/dev/null 2>&1 || true' EXIT

for _ in {1..25}; do
  if curl -fsS "${GITEA_URL}/api/healthz" >/dev/null 2>&1; then
    break
  fi
  sleep 2
done

PAYLOAD="{\"type\":\"gitea\",\"active\":true,\"config\":{\"url\":\"${HOOK_URL}\",\"content_type\":\"json\"},\"events\":[\"push\"]}"

curl -fsS -X POST -u "${ADMIN_USER}:${ADMIN_PASS}" \
  -H "Content-Type: application/json" \
  -d "${PAYLOAD}" \
  "${GITEA_URL}/api/v1/repos/${ORG}/${REPO}/hooks" >/dev/null

echo "Gitea webhook configured for ${ORG}/${REPO}"
