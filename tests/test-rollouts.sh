#!/usr/bin/env bash
set -euo pipefail

# Disable Argo selfHeal so it doesn't revert our test patch.
kubectl -n argocd patch application demo-app --type merge \
  -p '{"spec":{"syncPolicy":{"automated":{"selfHeal":false,"prune":true}}}}' >/dev/null

restore() {
  kubectl -n argocd patch application demo-app --type merge \
    -p '{"spec":{"syncPolicy":{"automated":{"selfHeal":true,"prune":true}}}}' >/dev/null || true
}
trap restore EXIT

# Pick a target image distinct from current to force a new revision.
current="$(kubectl -n demo get rollout demo-rollout -o jsonpath='{.spec.template.spec.containers[0].image}')"
if [[ "${current}" == *":v2" ]]; then target="localhost:5001/demo-app:v1"; else target="localhost:5001/demo-app:v2"; fi

kubectl -n demo patch rollout demo-rollout --type merge \
  -p "{\"spec\":{\"template\":{\"spec\":{\"containers\":[{\"name\":\"nginx\",\"image\":\"${target}\"}]}}}}" >/dev/null

# Wait for canary pause via .status.phase JSON.
phase=""
for _ in {1..60}; do
  phase="$(kubectl -n demo get rollout demo-rollout -o jsonpath='{.status.phase}' 2>/dev/null || true)"
  [[ "${phase}" == "Paused" ]] && break
  sleep 2
done
[[ "${phase}" == "Paused" ]]

kubectl argo rollouts promote demo-rollout -n demo
kubectl argo rollouts status demo-rollout -n demo --timeout 120s

echo "rollout promotion verified (${current} -> ${target})"
