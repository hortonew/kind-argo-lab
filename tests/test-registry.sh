#!/usr/bin/env bash
set -euo pipefail

response="$(curl -fsS http://localhost:5001/v2/demo-app/tags/list)"
echo "${response}" | grep -q '"v1"'
echo "${response}" | grep -q '"v2"'

echo "registry tags verified"
