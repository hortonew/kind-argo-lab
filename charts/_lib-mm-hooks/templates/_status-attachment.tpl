{{/*
=============================================================================
mm-hooks library — live-updating status attachment
=============================================================================
Provides a reusable shell function (`update_status`) that PATCHes the parent
post's props.attachments so the deployment status card is visible in the
channel feed without entering the thread.

Requires: MM_URL, MM_TOKEN, ROOT_ID env vars (provided by mm-hooks.replyEnv).
*/}}

{{/*
mm-hooks.statusFunc — shell function definition. Include at the top of any
hook's `source:` block. Callers pass a JSON array of step objects and an
optional hex color:

  update_status '[{"label":"Migration","status":"done"},...]' '#4CAF50'

Recognised statuses: done, running, failed, anything else → Pending.
No-ops when ROOT_ID is empty (thread-start never ran).
*/}}
{{- define "mm-hooks.statusFunc" -}}
update_status() {
  [ -n "${ROOT_ID:-}" ] || return 0
  _color="${2:-#2196F3}"
  _fields=$(echo "$1" | jq -c '[.[] | {
    title: .label,
    value: (if .status == "done" then ":white_check_mark: Complete"
            elif .status == "running" then ":hourglass_flowing_sand: Running..."
            elif .status == "failed" then ":x: Failed"
            else "Pending" end),
    short: true
  }]')
  curl -fsS -X PUT "$MM_URL/api/v4/posts/$ROOT_ID/patch" \
    -H "Authorization: Bearer $MM_TOKEN" \
    -H 'Content-Type: application/json' \
    -d "$(jq -nc --argjson f "$_fields" --arg c "$_color" \
         '{props:{attachments:[{color:$c,fields:$f}]}}')" \
    >/dev/null
}
{{- end -}}

{{/*
mm-hooks.initialAttachment — jq expression that builds the initial
props.attachments JSON with every step in "Pending" state. Used by
thread-start to create the parent post with the status card.

Reads the step labels from .Values.statusSteps (a list of {label:} objects).
*/}}
{{- define "mm-hooks.initialAttachment" -}}
{{- $steps := list -}}
{{- range .Values.statusSteps -}}
  {{- $steps = append $steps (printf "{\"label\":%s,\"status\":\"pending\"}" (.label | toJson)) -}}
{{- end -}}
[{{ join "," $steps }}]
{{- end -}}
