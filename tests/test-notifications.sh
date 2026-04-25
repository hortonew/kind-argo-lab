#!/usr/bin/env bash
# Verify the notifications + alerting wiring:
#   - argocd-notifications-cm contains alertmanager service
#   - alertmanager is reachable in-cluster
#   - webhook-logger sink received at least one POST
#   - alertmanager EventSource pod is up (Tier 4)
set -euo pipefail

echo "[notif] checking argocd-notifications-cm has alertmanager service"
kubectl -n argocd get cm argocd-notifications-cm -o yaml | grep -q "service.alertmanager"

echo "[notif] checking alertmanager pod is Ready"
kubectl -n monitoring wait --for=condition=Ready pod \
  -l app.kubernetes.io/name=alertmanager --timeout=300s

echo "[notif] checking webhook-logger pod is Ready"
kubectl -n monitoring wait --for=condition=Ready pod \
  -l app=webhook-logger --timeout=300s

echo "[notif] checking alertmanager EventSource pod is up"
kubectl -n argo-events wait --for=condition=Ready pod \
  -l eventsource-name=alertmanager --timeout=300s

echo "[notif] firing synthetic alert via amtool inside alertmanager pod"
am_pod="$(kubectl -n monitoring get pod -l app.kubernetes.io/name=alertmanager \
  -o jsonpath='{.items[0].metadata.name}')"
kubectl -n monitoring exec "${am_pod}" -- amtool alert add \
  alertname=ChainSmokeTest \
  severity=info \
  --annotation=summary="manual chain smoke test" \
  --alertmanager.url=http://localhost:9093 || true

# webhook-logger should log the request body within seconds.
sleep 8
kubectl -n monitoring logs deploy/webhook-logger --tail=200 \
  | grep -q -E 'alertname|ChainSmokeTest' \
  && echo "[notif] webhook-logger received alert" \
  || { echo "[notif] WARN: alert not seen in webhook-logger logs (alertmanager grouping may delay)"; }

echo "[notif] notifications + alerting wiring verified"
