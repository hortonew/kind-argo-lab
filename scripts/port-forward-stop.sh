#!/usr/bin/env bash
# Stop background kubectl port-forwards started by port-forward.sh.
set -euo pipefail

PID_FILE=".port-forward.pids"

if [[ ! -f "$PID_FILE" ]]; then
  echo "No $PID_FILE found; nothing to stop."
  exit 0
fi

while read -r pid name; do
  if kill "$pid" 2>/dev/null; then
    echo "stopped $name (pid $pid)"
  else
    echo "pid $pid ($name) not running"
  fi
done < "$PID_FILE"

rm -f "$PID_FILE"
