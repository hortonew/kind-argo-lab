{{/*
Common env block for hook Workflow steps that REPLY into the existing
thread. Reads root_id from the shared ConfigMap via configMapKeyRef
(no kubectl needed). The ConfigMap is created by the PreSync wave -2
thread-start Workflow.

`optional: true` keeps the pod startable even if the CM is missing,
which matters for the SyncFail hook (it may run when wave -2 itself
failed, before the CM existed).
*/}}
{{- define "shop.replyEnv" -}}
- name: MM_URL
  valueFrom: { secretKeyRef: { name: mattermost-creds, key: url } }
- name: MM_TOKEN
  valueFrom: { secretKeyRef: { name: mattermost-creds, key: token } }
- name: MM_CHANNEL
  valueFrom: { secretKeyRef: { name: mattermost-creds, key: channel_id } }
- name: ROOT_ID
  valueFrom:
    configMapKeyRef:
      name: {{ .Values.threadConfigMap }}
      key: root_id
      optional: true
{{- end -}}
