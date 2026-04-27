#!/usr/bin/env bash
# Force-push the local working tree (charts/, envs/, apps/) into the
# gitea-hosted "platform" repo that Argo CD watches.
#
# This NEVER touches your real ~/git/kind-argo-lab repo: it copies the
# files into a mktemp dir, does a fresh `git init` there, commits with
# --no-verify, and force-pushes to gitea. Same shape as the bootstrap
# block in scripts/02b-configure-gitea.sh, minus org/repo creation and
# the demo-app push.
set -euo pipefail

GITEA_URL="http://localhost:3000"
GITEA_NAMESPACE="gitea"
ADMIN_USER="admin"
ADMIN_PASS="adminpass"
ORG="argo-lab"
GITEA_AUTH_URL="http://${ADMIN_USER}:${ADMIN_PASS}@localhost:3000"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

PF_PID=""
if ! curl -fsS "${GITEA_URL}/api/healthz" >/dev/null 2>&1; then
  kubectl -n "${GITEA_NAMESPACE}" port-forward svc/gitea-http 3000:3000 \
    >/tmp/gitea-port-forward-push.log 2>&1 &
  PF_PID=$!
  for _ in {1..25}; do
    if curl -fsS "${GITEA_URL}/api/healthz" >/dev/null 2>&1; then
      break
    fi
    sleep 1
  done
fi

WORKDIR="$(mktemp -d)"
cleanup() {
  rm -rf "${WORKDIR}"
  if [[ -n "${PF_PID}" ]]; then
    kill "${PF_PID}" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

cp -RL "${REPO_ROOT}/charts" "${REPO_ROOT}/envs" "${REPO_ROOT}/apps" "${WORKDIR}/"

TIMESTAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
MESSAGE="${1:-lab sync ${TIMESTAMP}}"

(
  cd "${WORKDIR}"
  git init -b main >/dev/null
  git config user.name "lab-bot"
  git config user.email "lab-bot@local"
  git add charts envs apps
  git commit --no-verify -m "${MESSAGE}" >/dev/null
  git remote add origin "${GITEA_AUTH_URL}/${ORG}/platform.git"
  GIT_TERMINAL_PROMPT=0 git push -u origin main --force
)

echo "Pushed working tree to gitea platform repo: ${MESSAGE}"
