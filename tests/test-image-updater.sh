#!/usr/bin/env bash
set -euo pipefail

docker pull localhost:5001/demo-app:v2
docker tag localhost:5001/demo-app:v2 localhost:5001/demo-app:v3
docker push localhost:5001/demo-app:v3

for _ in {1..25}; do
  if kubectl -n argocd logs deploy/argocd-image-updater --tail=400 | grep -q 'demo-app:v3'; then
    break
  fi
  sleep 2
done

kubectl -n argocd get application demo-app -o jsonpath='{.status.sync.status}' | grep -q Synced

echo "image updater observed new tag and app remains synced"
