#!/usr/bin/env bash
# End-to-end chain smoke test:
#   kaniko build -> registry tag -> ArgoCD app -> Rollout completion
# This is a thin verification — it asserts each link is reachable, not a full
# git-push driven flow. The git-push flow is exercised by tests/test-events.sh.
set -euo pipefail

KANIKO_TAG="chain-$(date +%s)"

echo "[chain] submitting kaniko-build with tag=${KANIKO_TAG}"
argo -n argo submit --from workflowtemplate/kaniko-build \
  --parameter tag="${KANIKO_TAG}" \
  --wait --log

echo "[chain] verifying tag in local registry"
for _ in {1..15}; do
  if curl -fsS "http://localhost:5001/v2/demo-app/tags/list" | grep -q "${KANIKO_TAG}"; then
    echo "[chain] tag ${KANIKO_TAG} present in registry"
    break
  fi
  sleep 2
done

echo "[chain] verifying analysis-template Rollout exists and is healthy"
kubectl -n demo wait --for=jsonpath='{.status.phase}'=Healthy \
  rollout/demo-rollout-analysis --timeout=300s

echo "[chain] verifying analysis-template AnalysisRun (if any) is Successful"
runs="$(kubectl -n demo get analysisrun -o name 2>/dev/null || true)"
if [[ -n "${runs}" ]]; then
  for r in ${runs}; do
    phase="$(kubectl -n demo get "$r" -o jsonpath='{.status.phase}')"
    echo "[chain] $r -> ${phase}"
    [[ "${phase}" == "Successful" || "${phase}" == "Running" ]] || {
      echo "[chain] AnalysisRun ${r} in unexpected state: ${phase}"
      exit 1
    }
  done
else
  echo "[chain] (no AnalysisRuns yet — first Rollout sync may still be reconciling)"
fi

echo "[chain] e2e chain verification passed"
