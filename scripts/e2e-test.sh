#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

run_step() {
  local name="$1"
  local cmd="$2"
  echo "==> ${name}"
  if bash -c "${cmd}"; then
    echo "PASS: ${name}"
  else
    echo "FAIL: ${name}"
    exit 1
  fi
}

run_step "create cluster" "${ROOT_DIR}/scripts/01-create-cluster.sh"
run_step "deploy gitea" "${ROOT_DIR}/scripts/02-deploy-gitea.sh"
run_step "configure gitea" "${ROOT_DIR}/scripts/02b-configure-gitea.sh"
run_step "push demo image" "${ROOT_DIR}/scripts/03-push-demo-image.sh"
run_step "bootstrap argocd" "${ROOT_DIR}/scripts/04-bootstrap-argocd.sh"
run_step "configure webhook" "${ROOT_DIR}/scripts/035b-configure-gitea-webhook.sh"

run_step "registry smoke" "${ROOT_DIR}/tests/test-registry.sh"
run_step "gitea smoke" "${ROOT_DIR}/tests/test-gitea.sh"
run_step "argocd smoke" "${ROOT_DIR}/tests/test-argocd.sh"
run_step "rollouts smoke" "${ROOT_DIR}/tests/test-rollouts.sh"
run_step "workflows smoke" "${ROOT_DIR}/tests/test-workflows.sh"
run_step "events smoke" "${ROOT_DIR}/tests/test-events.sh"
run_step "image updater smoke" "${ROOT_DIR}/tests/test-image-updater.sh"
run_step "notifications smoke" "${ROOT_DIR}/tests/test-notifications.sh"
run_step "e2e chain smoke" "${ROOT_DIR}/tests/test-e2e-chain.sh"
run_step "deploy chain smoke" "${ROOT_DIR}/tests/test-deploy-chain.sh"
run_step "rollout bluegreen demo" "${ROOT_DIR}/tests/test-rollout-bluegreen.sh"
run_step "rollout analysis demo" "${ROOT_DIR}/tests/test-rollout-analysis.sh"
run_step "rollout experiment demo" "${ROOT_DIR}/tests/test-rollout-experiment.sh"
run_step "calendar event demo" "${ROOT_DIR}/tests/test-calendar-event.sh"
run_step "playwright e2e demo" "${ROOT_DIR}/tests/test-playwright-e2e.sh"

echo "All E2E checks passed"
