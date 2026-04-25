#!/usr/bin/env bash
set -euo pipefail

# Wait for the demo-app Application CR to exist (root-app may still be rendering it).
for _ in {1..60}; do
  if kubectl -n argocd get application demo-app >/dev/null 2>&1; then
    break
  fi
  sleep 5
done

kubectl wait --for=jsonpath='{.status.sync.status}'=Synced application/demo-app -n argocd --timeout=600s
kubectl wait --for=jsonpath='{.status.health.status}'=Healthy application/demo-app -n argocd --timeout=600s
kubectl -n demo get pods -l app=demo-app | grep -q demo

kubectl -n argocd logs deploy/argocd-notifications-controller --tail=500 | grep -Ei 'sync|application' >/dev/null

echo "argocd sync and notifications verified"
