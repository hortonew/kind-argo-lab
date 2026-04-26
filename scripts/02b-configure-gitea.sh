#!/usr/bin/env bash
set -euo pipefail

GITEA_URL="http://localhost:3000"
GITEA_NAMESPACE="gitea"
ADMIN_USER="admin"
ADMIN_PASS="adminpass"
ORG="argo-lab"
GITEA_AUTH_URL="http://${ADMIN_USER}:${ADMIN_PASS}@localhost:3000"

kubectl -n "${GITEA_NAMESPACE}" port-forward svc/gitea-http 3000:3000 >/tmp/gitea-port-forward.log 2>&1 &
PF_PID=$!
trap 'kill ${PF_PID} >/dev/null 2>&1 || true' EXIT

for _ in {1..25}; do
  if curl -fsS "${GITEA_URL}/api/healthz" >/dev/null 2>&1; then
    break
  fi
  sleep 2
done

if ! curl -fsS -u "${ADMIN_USER}:${ADMIN_PASS}" "${GITEA_URL}/api/v1/orgs/${ORG}" >/dev/null 2>&1; then
  curl -fsS -X POST -u "${ADMIN_USER}:${ADMIN_PASS}" \
    -H "Content-Type: application/json" \
    -d "{\"username\":\"${ORG}\",\"visibility\":\"public\"}" \
    "${GITEA_URL}/api/v1/orgs"
fi

for repo in platform demo-app; do
  if ! curl -fsS -u "${ADMIN_USER}:${ADMIN_PASS}" "${GITEA_URL}/api/v1/repos/${ORG}/${repo}" >/dev/null 2>&1; then
    curl -fsS -X POST -u "${ADMIN_USER}:${ADMIN_PASS}" \
      -H "Content-Type: application/json" \
      -d "{\"name\":\"${repo}\",\"private\":false}" \
      "${GITEA_URL}/api/v1/orgs/${ORG}/repos"
  fi
done

WORKDIR="$(mktemp -d)"
trap 'rm -rf "${WORKDIR}"; kill ${PF_PID} >/dev/null 2>&1 || true' EXIT

# -L: dereference any symlinks during copy. Currently unused (subcharts
# are shipped as packaged .tgz files under charts/<consumer>/charts/),
# but kept defensive in case a future chart pulls in a symlinked file.
cp -RL charts envs apps "${WORKDIR}/"
(
  cd "${WORKDIR}"
  git init -b main
  git config user.name "lab-bot"
  git config user.email "lab-bot@local"
  git add charts envs apps
  git commit -m "bootstrap platform repo"
  git remote add origin "${GITEA_AUTH_URL}/${ORG}/platform.git"
  GIT_TERMINAL_PROMPT=0 git push -u origin main --force
)

mkdir -p "${WORKDIR}/demo-app/deploy"
cat > "${WORKDIR}/demo-app/deploy/deployment.yaml" <<MANIFEST
apiVersion: apps/v1
kind: Deployment
metadata:
  name: demo-deployment
  namespace: demo
spec:
  replicas: 1
  selector:
    matchLabels:
      app: demo-app
  template:
    metadata:
      labels:
        app: demo-app
    spec:
      containers:
        - name: nginx
          image: localhost:5001/demo-app:v1
          ports:
            - containerPort: 80
MANIFEST

cat > "${WORKDIR}/demo-app/deploy/service.yaml" <<MANIFEST
apiVersion: v1
kind: Service
metadata:
  name: demo-service
  namespace: demo
spec:
  selector:
    app: demo-app
  ports:
    - port: 80
      targetPort: 80
MANIFEST

cat > "${WORKDIR}/demo-app/deploy/rollout.yaml" <<MANIFEST
apiVersion: argoproj.io/v1alpha1
kind: Rollout
metadata:
  name: demo-rollout
  namespace: demo
spec:
  replicas: 2
  strategy:
    canary:
      steps:
        - setWeight: 20
        - pause: {}
  selector:
    matchLabels:
      app: demo-app
  template:
    metadata:
      labels:
        app: demo-app
    spec:
      containers:
        - name: nginx
          image: localhost:5001/demo-app:v1
          ports:
            - containerPort: 80
MANIFEST

(
  cd "${WORKDIR}/demo-app"
  git init -b main
  git config user.name "lab-bot"
  git config user.email "lab-bot@local"
  git add deploy
  git commit -m "bootstrap demo-app repo"
  git remote add origin "${GITEA_AUTH_URL}/${ORG}/demo-app.git"
  GIT_TERMINAL_PROMPT=0 git push -u origin main --force
)

echo "Gitea org and repos are bootstrapped"
