#!/usr/bin/env bash
set -euo pipefail
BASE_URL=${SMOKE_BASE_URL:?SMOKE_BASE_URL required}
SECRET=${WEBHOOK_SECRET:?WEBHOOK_SECRET required}
EVENT_ID="smoke-$(date +%s)-${RANDOM}"
BODY=$(cat <<JSON
{"event_id":"${EVENT_ID}","organizationId":"smoke-org","type":"occupancy","deviceSerial":"SMOKE-DEVICE","value":1}
JSON
)
STATUS=$(curl -sS -o /tmp/smoke-response.json -w '%{http_code}' \
  -H 'Content-Type: application/json' \
  -H "X-Meraki-Secret: ${SECRET}" \
  -d "$BODY" \
  "${BASE_URL%/}/api/v1/meraki/webhook")
test "$STATUS" = "202"
grep -q "$EVENT_ID" /tmp/smoke-response.json
cat /tmp/smoke-response.json
