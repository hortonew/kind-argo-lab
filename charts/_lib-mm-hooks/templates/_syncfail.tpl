{{/*
mm-hooks.syncfail — SyncFail Workflow. Posts the abort notice into the
thread opened by PreSync wave -2 and then drops the thread ConfigMap as
the terminal action on the failure path.

If wave -2 itself failed before creating the CM, ROOT_ID is empty and we
fall back to a top-level post so the failure is still visible.

Required values: hookNamePrefix, hookNamespace, hookServiceAccount,
                 kubectlImage, threadConfigMap, messages.syncFail.
*/}}
{{- define "mm-hooks.syncfail" -}}
---
apiVersion: argoproj.io/v1alpha1
kind: Workflow
metadata:
  name: {{ .Values.hookNamePrefix }}-syncfail
  namespace: {{ .Values.hookNamespace }}
  annotations:
    argocd.argoproj.io/hook: SyncFail
    argocd.argoproj.io/hook-delete-policy: BeforeHookCreation
spec:
  entrypoint: main
  serviceAccountName: {{ .Values.hookServiceAccount }}
  ttlStrategy:
    secondsAfterCompletion: 600
  templates:
    - name: main
      script:
        # kubectlImage so we can also clean up the thread CM in the same step.
        image: {{ include "mm-hooks.kubectlImage" . }}
        env:
          {{- include "mm-hooks.cleanupEnv" . | nindent 10 }}
          - name: MSG
            value: {{ .Values.messages.syncFail | quote }}
        command: [sh]
        source: |
          set -eu
          if [ -n "${ROOT_ID:-}" ]; then
            body=$(jq -nc --arg c "$MM_CHANNEL" --arg m "$MSG" --arg r "$ROOT_ID" \
                    '{channel_id:$c,message:$m,root_id:$r}')
          else
            body=$(jq -nc --arg c "$MM_CHANNEL" --arg m "$MSG" \
                    '{channel_id:$c,message:$m}')
          fi
          curl -fsS -X POST "$MM_URL/api/v4/posts" \
            -H "Authorization: Bearer $MM_TOKEN" \
            -H 'Content-Type: application/json' \
            -d "$body" | jq -r '"[{{ .Values.hookNamePrefix }}] failure post id=" + .id'

          {{ include "mm-hooks.cleanupCmd" . | nindent 10 }}
{{- end -}}
