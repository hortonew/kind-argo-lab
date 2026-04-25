#!/usr/bin/env bash
set -euo pipefail

REGISTRY="localhost:5001"
IMAGE="demo-app"

docker pull nginx:stable-alpine

for tag in v1 v2; do
  docker tag nginx:stable-alpine "${REGISTRY}/${IMAGE}:${tag}"
  docker push "${REGISTRY}/${IMAGE}:${tag}"
done

kubectl run registry-check --rm -i --restart=Never --image=curlimages/curl:8.8.0 -- \
  curl -fsS "http://local-registry:5000/v2/${IMAGE}/tags/list" >/tmp/registry-tags.json

grep -q '"v1"' /tmp/registry-tags.json
grep -q '"v2"' /tmp/registry-tags.json

echo "demo images pushed and reachable from cluster"
