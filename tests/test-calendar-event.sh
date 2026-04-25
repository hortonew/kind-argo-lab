#!/usr/bin/env bash
# Verify the calendar EventSource fires and the Sensor creates Workflows.
set -euo pipefail

APP=calendar-event-demo
NS_EVENTS=argo-events
NS_WF=argo

echo "[cal] waiting for Application ${APP} Synced"
kubectl -n argocd wait --for=jsonpath='{.status.sync.status}'=Synced "application/${APP}" --timeout=300s

echo "[cal] verifying EventSource + Sensor exist"
kubectl -n "${NS_EVENTS}" get eventsource calendar >/dev/null
kubectl -n "${NS_EVENTS}" get sensor calendar-workflow-sensor >/dev/null

echo "[cal] waiting up to 90s for at least one triggered Workflow"
deadline=$(( $(date +%s) + 90 ))
count=0
while (( $(date +%s) < deadline )); do
  count=$(kubectl -n "${NS_WF}" get workflows -l triggered-by=calendar-event-demo \
            --no-headers 2>/dev/null | wc -l | tr -d ' ')
  if (( count > 0 )); then
    break
  fi
  sleep 5
done

if (( count == 0 )); then
  echo "[cal] FAIL: no calendar-triggered Workflows seen in 90s"
  kubectl -n "${NS_EVENTS}" get pods
  exit 1
fi
echo "[cal]   ${count} triggered Workflow(s) observed"

echo "[cal] calendar EventSource demo verified"
