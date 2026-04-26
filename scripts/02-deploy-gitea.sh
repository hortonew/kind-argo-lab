#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="gitea"
RELEASE="gitea"

kubectl create namespace "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

if ! helm repo list | awk '{print $1}' | grep -qx "gitea-charts"; then
  helm repo add gitea-charts https://dl.gitea.com/charts/ >/dev/null
fi
helm repo update >/dev/null

helm upgrade --install "${RELEASE}" gitea-charts/gitea \
  --namespace "${NAMESPACE}" \
  --set gitea.admin.username=admin \
  --set gitea.admin.password=adminpass \
  --set gitea.config.server.ROOT_URL=http://localhost:3000/ \
  --set gitea.replicaCount=1 \
  --set service.http.type=NodePort \
  --set service.http.nodePort=30000 \
  --set valkey-cluster.enabled=false \
  --set valkey.enabled=false \
  --set postgresql-ha.enabled=false \
  --set postgresql.enabled=false \
  --set persistence.enabled=false \
  --set gitea.config.cache.ADAPTER=memory \
  --set gitea.config.database.DB_TYPE=sqlite3 \
  --set gitea.config.webhook.ALLOWED_HOST_LIST='private\,*.svc\,*.svc.cluster.local\,argocd-server.argocd.svc.cluster.local\,eventsource-svc.argo-events.svc.cluster.local' \
  --set gitea.config.webhook.SKIP_TLS_VERIFY=true \
  --wait --timeout 5m

kubectl -n "${NAMESPACE}" rollout status deploy/gitea --timeout=300s

echo "Gitea is deployed and reachable through NodePort 30000"
