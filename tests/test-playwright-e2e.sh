#!/usr/bin/env bash
# Submit the Playwright WorkflowTemplate, wait for completion, and verify
# that artifacts were uploaded to the MinIO bucket `argo-artifacts`.
set -euo pipefail

NS=argo
WT=playwright-e2e
APP=playwright-e2e-demo

echo "[pw] waiting for Application ${APP} Synced"
kubectl -n argocd wait --for=jsonpath='{.status.sync.status}'=Synced "application/${APP}" --timeout=300s

echo "[pw] verifying WorkflowTemplate ${WT} exists"
kubectl -n "${NS}" get workflowtemplate "${WT}" >/dev/null

echo "[pw] submitting Workflow from template"
WF_NAME=$(kubectl -n "${NS}" create -f - <<EOF | awk '{print $1}' | sed 's|workflow.argoproj.io/||'
apiVersion: argoproj.io/v1alpha1
kind: Workflow
metadata:
  generateName: pw-e2e-
  namespace: ${NS}
spec:
  workflowTemplateRef:
    name: ${WT}
EOF
)
echo "[pw]   submitted ${WF_NAME}"

echo "[pw] waiting for Workflow phase Succeeded (≤10m)"
for _ in $(seq 1 120); do
  phase=$(kubectl -n "${NS}" get workflow "${WF_NAME}" -o jsonpath='{.status.phase}' 2>/dev/null || true)
  case "${phase}" in
    Succeeded) break ;;
    Failed|Error)
      echo "[pw] FAIL: workflow ended with phase=${phase}"
      kubectl -n "${NS}" get workflow "${WF_NAME}" -o yaml | tail -100
      exit 1
      ;;
  esac
  sleep 5
done
phase=$(kubectl -n "${NS}" get workflow "${WF_NAME}" -o jsonpath='{.status.phase}')
if [[ "${phase}" != "Succeeded" ]]; then
  echo "[pw] FAIL: timed out waiting for Succeeded (last phase=${phase})"
  exit 1
fi
echo "[pw]   workflow Succeeded"

echo "[pw] verifying artifacts are present in MinIO bucket argo-artifacts"
# Run a one-off mc pod against the in-cluster MinIO and list bucket contents.
listing=$(kubectl -n minio run mc-probe --rm -i --restart=Never \
  --image=minio/mc:RELEASE.2024-10-08T09-37-26Z \
  --env=MC_HOST_lab="http://minioadmin:minioadmin@minio.minio.svc.cluster.local:9000" \
  --command -- mc ls --recursive lab/argo-artifacts/ 2>/dev/null || true)
echo "${listing}"
if ! echo "${listing}" | grep -q "${WF_NAME}"; then
  echo "[pw] FAIL: no artifacts for ${WF_NAME} found in bucket"
  exit 1
fi
echo "[pw]   artifacts present"

echo "[pw] Playwright + MinIO artifacts demo verified"
