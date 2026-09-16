#!/usr/bin/env bash
set -euo pipefail
HOST=${1:-${PERF_BASE_URL:-http://localhost:8080}}
USERS=${PERF_USERS:-25}
SPAWN_RATE=${PERF_SPAWN_RATE:-5}
DURATION=${PERF_DURATION:-60s}
FAIL_RATIO=${PERF_FAIL_RATIO:-0.01}
export PERF_FAIL_RATIO="$FAIL_RATIO"

python -m pip install -r tests/performance/requirements.txt
locust -f tests/performance/locustfile.py --headless \
  --host "$HOST" \
  -u "$USERS" \
  -r "$SPAWN_RATE" \
  -t "$DURATION" \
  --only-summary
