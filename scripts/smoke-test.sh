#!/usr/bin/env bash
set -euo pipefail
ENVIRONMENT="${1:?environment required}"
BASE_URL=${SMOKE_BASE_URL:?SMOKE_BASE_URL must be supplied}
echo "Smoke testing ${ENVIRONMENT}: ${BASE_URL}"
for _ in $(seq 1 20); do
  if curl -fsS "${BASE_URL%/}/health" | grep -q '"status":"ok"'; then
    echo "Health check passed"
    exit 0
  fi
  sleep 5
done
echo "Health check failed" >&2
exit 1
