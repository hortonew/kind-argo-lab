#!/usr/bin/env bash
set -euo pipefail

CLUSTER_NAME="argo-lab"
REGISTRY_NAME="local-registry"
REGISTRY_HOST_PORT="5001"
REGISTRY_CONTAINER_PORT="5000"

if ! docker info >/dev/null 2>&1; then
  echo "docker is not running"
  exit 1
fi

if [[ "$(docker inspect -f '{{.State.Running}}' "${REGISTRY_NAME}" 2>/dev/null || true)" != "true" ]]; then
  docker run -d --restart=always \
    -p "127.0.0.1:${REGISTRY_HOST_PORT}:${REGISTRY_CONTAINER_PORT}" \
    --name "${REGISTRY_NAME}" \
    registry:2
fi

if ! kind get clusters | grep -qx "${CLUSTER_NAME}"; then
  kind create cluster --name "${CLUSTER_NAME}" --config kind-config.yaml
fi

docker network connect "kind" "${REGISTRY_NAME}" 2>/dev/null || true

# Configure each node to use the local registry via the modern hosts.toml pattern.
REGISTRY_DIR="/etc/containerd/certs.d/localhost:${REGISTRY_HOST_PORT}"
for node in $(kind get nodes --name "${CLUSTER_NAME}"); do
  docker exec "${node}" mkdir -p "${REGISTRY_DIR}"
  cat <<HOSTS | docker exec -i "${node}" cp /dev/stdin "${REGISTRY_DIR}/hosts.toml"
[host."http://${REGISTRY_NAME}:${REGISTRY_CONTAINER_PORT}"]
  capabilities = ["pull", "resolve"]
HOSTS
done

# Ensure kind context is written into ~/.kube/config (first entry of KUBECONFIG)
# and make it the active context for downstream scripts.
kind export kubeconfig --name "${CLUSTER_NAME}"
kubectl config use-context "kind-${CLUSTER_NAME}" >/dev/null

# Wait for the API server to be reachable before applying anything.
for _ in {1..30}; do
  if kubectl --context "kind-${CLUSTER_NAME}" get --raw=/readyz >/dev/null 2>&1; then
    break
  fi
  sleep 2
done

cat <<CM | kubectl --context "kind-${CLUSTER_NAME}" apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: local-registry-hosting
  namespace: kube-public
data:
  localRegistryHosting.v1: |
    host: "localhost:${REGISTRY_HOST_PORT}"
    help: "https://kind.sigs.k8s.io/docs/user/local-registry/"
CM

echo "kind cluster and local registry are ready"
