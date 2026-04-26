#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="argocd"
ARGOCD_SERVER="localhost:8080"
GITEA_REPO_URL="http://gitea-http.gitea.svc.cluster.local:3000/argo-lab/platform.git"

kubectl create namespace "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -
kubectl apply --server-side --force-conflicts -n "${NAMESPACE}" -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

kubectl -n "${NAMESPACE}" rollout status deploy/argocd-server --timeout=300s
kubectl -n "${NAMESPACE}" rollout status deploy/argocd-repo-server --timeout=300s
kubectl -n "${NAMESPACE}" rollout status sts/argocd-application-controller --timeout=300s

kubectl -n "${NAMESPACE}" patch configmap argocd-cm --type merge -p '{"data":{"resource.customizations.health.argoproj.io_Rollout":"hs = {}\nif obj.status ~= nil then\n  if obj.status.phase == \"Healthy\" then\n    hs.status = \"Healthy\"\n    hs.message = \"Rollout is healthy\"\n    return hs\n  end\nend\nhs.status = \"Progressing\"\nhs.message = \"Waiting for rollout to become healthy\"\nreturn hs"}}'

kubectl -n "${NAMESPACE}" port-forward svc/argocd-server 8080:443 >/tmp/argocd-port-forward.log 2>&1 &
PF_PID=$!
trap 'kill ${PF_PID} >/dev/null 2>&1 || true' EXIT

for _ in {1..25}; do
  if curl -kfsS "https://${ARGOCD_SERVER}" >/dev/null 2>&1; then
    break
  fi
  sleep 2
done

ADMIN_PASSWORD="$(kubectl -n "${NAMESPACE}" get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d)"

if argocd login "${ARGOCD_SERVER}" --username admin --password "${ADMIN_PASSWORD}" --insecure >/dev/null 2>&1; then
  if ! argocd repo get "${GITEA_REPO_URL}" >/dev/null 2>&1; then
    argocd repo add "${GITEA_REPO_URL}" --username admin --password adminpass --insecure-skip-server-verification
  fi
else
  echo "warning: argocd CLI login failed; skipping repo add (repo may already exist)"
fi

kubectl apply -f envs/lab/app-of-apps.yaml

echo "ArgoCD bootstrapped with root app-of-apps"
