# Outbound service

Long-running worker that calls configured Cisco Meraki REST paths through the private APP subnet/NAT path. Each successful API response is wrapped in a telemetry envelope, stored durably in S3, and a pointer is published to the processing queue.

Required: `DATA_BUCKET`, `PROCESSING_QUEUE_URL`, `MERAKI_SECRET_ARN`.
Optional: `MERAKI_BASE_URL`, `MERAKI_POLL_PATHS`, `MERAKI_POLL_INTERVAL_SECONDS`, `MERAKI_HTTP_TIMEOUT_SECONDS`, `MERAKI_FAILURE_BACKOFF_SECONDS`.

Run one polling cycle with `python -m outbound_service.worker --once`.
