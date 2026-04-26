{{/*
mm-hooks.rbac — emits the ServiceAccount + Role + RoleBinding that every
hook Workflow runs as. All three are themselves PreSync wave -3 hooks so
they exist before wave -2 (thread-start) tries to use the SA. SA persists
across syncs (no HookSucceeded delete-policy).

Required values: hookNamespace, hookServiceAccount.
*/}}
{{- define "mm-hooks.rbac" -}}
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: {{ .Values.hookServiceAccount }}
  namespace: {{ .Values.hookNamespace }}
  annotations:
    argocd.argoproj.io/hook: PreSync
    argocd.argoproj.io/sync-wave: "-3"
    argocd.argoproj.io/hook-delete-policy: BeforeHookCreation
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: {{ .Values.hookServiceAccount }}
  namespace: {{ .Values.hookNamespace }}
  annotations:
    argocd.argoproj.io/hook: PreSync
    argocd.argoproj.io/sync-wave: "-3"
    argocd.argoproj.io/hook-delete-policy: BeforeHookCreation
rules:
  # Thread-id ConfigMap: read by every reply hook, written by thread-start,
  # deleted by the terminal hook on each path.
  - apiGroups: [""]
    resources: ["configmaps"]
    verbs: ["get", "list", "create", "update", "patch", "delete"]
  # Workflow executor needs to manage its own pods + report results.
  - apiGroups: [""]
    resources: ["pods", "pods/log"]
    verbs: ["get", "list", "watch", "create", "delete", "patch"]
  - apiGroups: [""]
    resources: ["pods/exec"]
    verbs: ["create"]
  - apiGroups: ["argoproj.io"]
    resources: ["workflowtaskresults", "workflowtasksets", "workflowtasksets/status"]
    verbs: ["create", "get", "list", "watch", "patch", "update"]
  # Some hooks (e.g. shop's PostSync e2e) submit child Workflows from a
  # WorkflowTemplate and poll them to completion.
  - apiGroups: ["argoproj.io"]
    resources: ["workflows", "workflowtemplates"]
    verbs: ["create", "get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: {{ .Values.hookServiceAccount }}
  namespace: {{ .Values.hookNamespace }}
  annotations:
    argocd.argoproj.io/hook: PreSync
    argocd.argoproj.io/sync-wave: "-3"
    argocd.argoproj.io/hook-delete-policy: BeforeHookCreation
subjects:
  - kind: ServiceAccount
    name: {{ .Values.hookServiceAccount }}
    namespace: {{ .Values.hookNamespace }}
roleRef:
  kind: Role
  name: {{ .Values.hookServiceAccount }}
  apiGroup: rbac.authorization.k8s.io
{{- end -}}
