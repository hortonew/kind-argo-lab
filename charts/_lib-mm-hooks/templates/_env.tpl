{{/*
=============================================================================
mm-hooks library — env / cleanup helpers
=============================================================================
These helpers are intended to be `include`d from per-chart hook Workflow
templates (e.g. shop's PreSync migration Workflow) so every step that posts
into the thread shares the same env wiring.
*/}}

{{/*
mm-hooks.hookImage — default image for hook steps that only need curl + jq
(plain HTTP-only steps, e.g. PreSync migration reply). Consumers may
override by setting `.Values.hookImage`.
*/}}
{{- define "mm-hooks.hookImage" -}}
{{- default "badouralix/curl-jq:latest" .Values.hookImage -}}
{{- end -}}

{{/*
mm-hooks.kubectlImage — default image for hook steps that need kubectl too
(thread-start writes the CM; terminal hooks delete it). Consumers may
override by setting `.Values.kubectlImage`.
*/}}
{{- define "mm-hooks.kubectlImage" -}}
{{- default "alpine/k8s:1.30.0" .Values.kubectlImage -}}
{{- end -}}


{{/*
mm-hooks.replyEnv — env block for any hook step that REPLIES into the thread.
Reads ROOT_ID from the shared ConfigMap via configMapKeyRef (no kubectl).
`optional: true` keeps the pod startable even if the CM is missing — matters
for the SyncFail hook when wave -2 itself failed before creating the CM.

THREAD_REPLIES gates the `post_reply` helper (mm-hooks.replyFunc): when
"false", per-stage progress replies are suppressed and the parent
attachment status card becomes the sole signal. Failure-path replies that
use raw curl (SyncFail, intentionally failing migrations) always fire.
Source of truth: .Values.threadStageReplies (default true).
*/}}
{{- define "mm-hooks.replyEnv" -}}
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
- name: THREAD_REPLIES
  value: "{{ if hasKey .Values "threadStageReplies" }}{{ .Values.threadStageReplies }}{{ else }}true{{ end }}"
{{- end -}}

{{/*
mm-hooks.statusSource — emits the update_status shell function definition
followed by a newline. Include at the top of a hook's `source:` block so
that the rest of the script can call `update_status '<steps-json>' [color]`.
Wraps mm-hooks.statusFunc for convenient one-liner inclusion.
*/}}
{{- define "mm-hooks.statusSource" -}}
{{ include "mm-hooks.statusFunc" . }}
{{- end -}}

{{/*
mm-hooks.cleanupEnv — replyEnv plus NS + THREAD_CM, for terminal hooks that
need kubectl access to delete the thread ConfigMap on completion.
*/}}
{{- define "mm-hooks.cleanupEnv" -}}
- name: NS
  value: {{ .Values.hookNamespace }}
- name: THREAD_CM
  value: {{ .Values.threadConfigMap }}
{{ include "mm-hooks.replyEnv" . }}
{{- end -}}

{{/*
mm-hooks.cleanupCmd — shell snippet to drop the thread ConfigMap. Call from
the terminal hook on each path (highest-wave PostSync, or SyncFail). Safe
to run when the CM doesn't exist (--ignore-not-found).
*/}}
{{- define "mm-hooks.cleanupCmd" -}}
echo "[{{ .Values.hookNamePrefix }}] cleaning up thread ConfigMap $NS/$THREAD_CM"
kubectl -n "$NS" delete configmap "$THREAD_CM" --ignore-not-found
{{- end -}}
