#!/usr/bin/env bash
set -euo pipefail

name="$(argo submit --from workflowtemplate/hello-world -n argo --wait -o name)"
argo logs "${name}" -n argo | grep -q 'hello from argo workflows'

echo "workflow hello-world verified"
