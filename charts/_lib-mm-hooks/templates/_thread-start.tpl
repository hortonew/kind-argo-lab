{{/*
mm-hooks.thread-start — PreSync wave -2 Workflow that opens a fresh
Mattermost thread and stashes the parent post id in a ConfigMap so every
later hook (in this sync) can reply into the same thread.

The parent post carries a props.attachments status card (all steps pending)
so the deployment status is visible in the channel feed without entering
the thread. Later hooks PATCH this post to update progress.

Required values: hookNamePrefix, hookNamespace, hookServiceAccount,
                 kubectlImage, threadConfigMap, messages.threadStart,
                 statusSteps.
*/}}
{{- define "mm-hooks.thread-start" -}}
---
apiVersion: argoproj.io/v1alpha1
kind: Workflow
metadata:
  name: {{ .Values.hookNamePrefix }}-thread-start
  namespace: {{ .Values.hookNamespace }}
  annotations:
    argocd.argoproj.io/hook: PreSync
    argocd.argoproj.io/sync-wave: "-2"
    argocd.argoproj.io/hook-delete-policy: BeforeHookCreation
spec:
  entrypoint: main
  serviceAccountName: {{ .Values.hookServiceAccount }}
  ttlStrategy:
    secondsAfterCompletion: 600
  templates:
    - name: main
      script:
        image: {{ include "mm-hooks.kubectlImage" . }}
        env:
          - name: MM_URL
            valueFrom: { secretKeyRef: { name: mattermost-creds, key: url } }
          - name: MM_TOKEN
            valueFrom: { secretKeyRef: { name: mattermost-creds, key: token } }
          - name: MM_CHANNEL
            valueFrom: { secretKeyRef: { name: mattermost-creds, key: channel_id } }
          - name: NS
            value: {{ .Values.hookNamespace }}
          - name: THREAD_CM
            value: {{ .Values.threadConfigMap }}
          - name: MSG
            value: {{ .Values.messages.threadStart | quote }}
          - name: INITIAL_STEPS
            value: {{ include "mm-hooks.initialAttachment" . | squote }}
        command: [sh]
        source: |
          set -eu
          FIELDS=$(echo "$INITIAL_STEPS" | jq -c '[.[] | {
            title: .label,
            value: "Pending",
            short: true
          }]')
          ATTACH=$(jq -nc --argjson f "$FIELDS" \
            '{attachments:[{color:"#2196F3",fields:$f}]}')
          body=$(jq -nc --arg c "$MM_CHANNEL" --arg m "$MSG" --argjson p "$ATTACH" \
                  '{channel_id:$c,message:$m,props:$p}')
          ROOT_ID=$(curl -fsS -X POST "$MM_URL/api/v4/posts" \
            -H "Authorization: Bearer $MM_TOKEN" \
            -H 'Content-Type: application/json' \
            -d "$body" | jq -r .id)
          echo "[{{ .Values.hookNamePrefix }}] parent post id=$ROOT_ID"
          kubectl -n "$NS" create configmap "$THREAD_CM" \
            --from-literal=root_id="$ROOT_ID" \
            --dry-run=client -o yaml | kubectl apply -f -
          echo "[{{ .Values.hookNamePrefix }}] root_id written to $NS/$THREAD_CM"
{{- end -}}
