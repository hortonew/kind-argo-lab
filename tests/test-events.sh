#!/usr/bin/env bash
set -euo pipefail

GITEA_URL="http://localhost:3000"
ADMIN_USER="admin"
ADMIN_PASS="adminpass"
ORG="argo-lab"
REPO="demo-app"

kubectl -n gitea port-forward svc/gitea-http 3000:3000 >/tmp/gitea-events-pf.log 2>&1 &
PF_PID=$!
trap 'kill ${PF_PID} >/dev/null 2>&1 || true' EXIT
for _ in {1..20}; do
  curl -fsS "${GITEA_URL}/api/v1/version" >/dev/null 2>&1 && break
  sleep 1
done

before_count="$(kubectl -n argo get workflows --no-headers 2>/dev/null | wc -l | tr -d ' ')"

filename="deploy/event-trigger-$(date +%s).txt"
# Trigger event with a new commit through Gitea API.
curl -fsS -X POST -u "${ADMIN_USER}:${ADMIN_PASS}" \
  -H "Content-Type: application/json" \
  -d '{"content":"ZHVtbXk=","message":"trigger events flow","branch":"main"}' \
  "${GITEA_URL}/api/v1/repos/${ORG}/${REPO}/contents/${filename}" >/dev/null

for _ in {1..20}; do
  current_count="$(kubectl -n argo get workflows --no-headers 2>/dev/null | wc -l | tr -d ' ')"
  if (( current_count > before_count )); then
    break
  fi
  sleep 2
done

latest="$(kubectl -n argo get workflows --sort-by=.metadata.creationTimestamp -o jsonpath='{.items[-1:].metadata.name}')"
kubectl -n argo wait --for=jsonpath='{.status.phase}'=Succeeded "workflow/${latest}" --timeout=90s

echo "events sensor trigger verified"
