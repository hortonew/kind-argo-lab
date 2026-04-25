#!/usr/bin/env bash
set -euo pipefail

GITEA_NAMESPACE="gitea"
GITEA_URL="http://localhost:3000"
ADMIN_USER="admin"
ADMIN_PASS="adminpass"

kubectl -n "${GITEA_NAMESPACE}" port-forward svc/gitea-http 3000:3000 >/tmp/gitea-test-pf.log 2>&1 &
PF_PID=$!
trap 'kill ${PF_PID} 2>/dev/null || true' EXIT
for _ in {1..15}; do
  curl -fsS "${GITEA_URL}/api/v1/version" >/dev/null 2>&1 && break
  sleep 1
done

repos="$(curl -fsS -u "${ADMIN_USER}:${ADMIN_PASS}" "${GITEA_URL}/api/v1/orgs/argo-lab/repos")"
echo "${repos}" | jq -e '.[] | select(.name=="demo-app")' >/dev/null

echo "gitea repository exists"
