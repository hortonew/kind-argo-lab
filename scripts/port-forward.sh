#!/usr/bin/env bash
# Background kubectl port-forwards for every UI/API in the lab.
# PIDs recorded to .port-forward.pids ; logs to .port-forward.log
# Stop with: just port-forward-stop
set -euo pipefail

PID_FILE=".port-forward.pids"
LOG_FILE=".port-forward.log"

if [[ -f "$PID_FILE" ]]; then
  echo "Port-forwards already running (see $PID_FILE). Run 'just port-forward-stop' first." >&2
  exit 1
fi

: > "$LOG_FILE"
: > "$PID_FILE"

# name | namespace | svc | local:remote
forwards=(
  "argocd|argocd|svc/argocd-server|8080:443"
  "argo-workflows|argo|svc/argo-workflows-server|2746:2746"
  "argo-rollouts|argo-rollouts|svc/argo-rollouts-dashboard|3100:3100"
  "gitea|gitea|svc/gitea-http|3000:3000"
  "prometheus|monitoring|svc/prometheus-server|9090:80"
  "alertmanager|monitoring|svc/alertmanager|9093:9093"
  "grafana|monitoring|svc/grafana|3001:80"
  "minio-console|minio|svc/minio-console|9001:9001"
  "minio-api|minio|svc/minio|9000:9000"
  "webhook-logger|monitoring|svc/webhook-logger|8081:8080"
  "mattermost|mattermost|svc/mattermost|8065:8065"
)

for entry in "${forwards[@]}"; do
  IFS='|' read -r name ns svc mapping <<< "$entry"
  kubectl -n "$ns" port-forward "$svc" "$mapping" >>"$LOG_FILE" 2>&1 &
  pid=$!
  echo "$pid $name" >> "$PID_FILE"
done

# Give kubectl a moment to bind ports.
sleep 2

argocd_pw="$(kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' 2>/dev/null | base64 -d 2>/dev/null || echo '<not-found>')"

cat <<EOF

Lab URLs (port-forwards backgrounded; logs: $LOG_FILE)

  ArgoCD            https://localhost:8080         user: admin   pass: ${argocd_pw}
  Argo Workflows    http://localhost:2746
  Argo Rollouts     http://localhost:3100/rollouts/demo
  Gitea             http://localhost:3000          user: admin   pass: adminpass
  Gitea (NodePort)  http://localhost:30000         (also exposed via kind extraPortMappings)
  Local registry    http://localhost:5001/v2/_catalog
  Prometheus        http://localhost:9090
  Alertmanager      http://localhost:9093
  Grafana           http://localhost:3001          user: admin   pass: admin   (anonymous viewer)
  MinIO console     http://localhost:9001          user: minioadmin   pass: minioadmin
  MinIO API (S3)    http://localhost:9000
  Webhook logger    http://localhost:8081          (alert sink; tail logs: kubectl -n monitoring logs deploy/webhook-logger -f)
  Mattermost        http://localhost:8065          user: admin   pass: lab-admin

Stop with: just port-forward-stop
EOF
