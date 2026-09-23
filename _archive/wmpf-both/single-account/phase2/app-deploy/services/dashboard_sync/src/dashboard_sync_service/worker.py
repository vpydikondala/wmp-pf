from __future__ import annotations

import argparse
import json
import logging
import os
import time
from datetime import UTC, datetime
from typing import Any

import httpx

from occupancy_common.aws import get_json_secret, s3_client, sqs_client
from occupancy_common.events import processing_message, raw_key, stable_event_id, tenant_id
from occupancy_common.logging import configure_logging

configure_logging()
logger = logging.getLogger(__name__)


def _required(name: str) -> str:
    value = os.getenv(name)
    if not value:
        raise RuntimeError(f"Required environment variable {name} is not set")
    return value


def _paths() -> list[str]:
    raw = os.getenv("MERAKI_POLL_PATHS", "/organizations")
    return [part.strip() for part in raw.split(",") if part.strip()]


def _credentials() -> dict[str, Any]:
    return get_json_secret(_required("MERAKI_SECRET_ARN"))


def _headers() -> dict[str, str]:
    secret = _credentials()
    token = secret.get("api_key") or secret.get("access_token")
    if not token:
        raise RuntimeError("Meraki secret must contain api_key or access_token")
    return {
        "Authorization": f"Bearer {token}",
        "Accept": "application/json",
        "User-Agent": "workplace-management-dashboard_sync/1.0",
    }


def poll_once(client: httpx.Client | None = None) -> int:
    bucket = _required("DATA_BUCKET")
    queue_url = _required("PROCESSING_QUEUE_URL")
    base_url = os.getenv("MERAKI_BASE_URL", "https://api.meraki.com/api/v1").rstrip("/")
    timeout = float(os.getenv("MERAKI_HTTP_TIMEOUT_SECONDS", "20"))
    own_client = client is None
    client = client or httpx.Client(timeout=timeout, headers=_headers())
    count = 0
    try:
        for path in _paths():
            url = f"{base_url}/{path.lstrip('/')}"
            response = client.get(url)
            if response.status_code == 429:
                retry_after = int(response.headers.get("Retry-After", "1"))
                raise RuntimeError(f"Meraki rate limited request; retry_after={retry_after}")
            response.raise_for_status()
            payload: Any = response.json()
            envelope = {
                "event_id": stable_event_id({"path": path, "payload": payload, "at": datetime.now(UTC).isoformat()}),
                "tenant_id": tenant_id(payload if isinstance(payload, dict) else {}),
                "event_type": "meraki_poll",
                "api_path": path,
                "observed_at": datetime.now(UTC).isoformat(),
                "payload": payload,
            }
            event_id = envelope["event_id"]
            tenant = envelope["tenant_id"]
            key = raw_key("dashboard_sync", tenant, event_id)
            s3_client().put_object(
                Bucket=bucket,
                Key=key,
                Body=json.dumps(envelope, separators=(",", ":"), default=str).encode(),
                ContentType="application/json",
                Metadata={"source": "dashboard_sync", "tenant-id": tenant, "event-id": event_id},
            )
            sqs_client().send_message(
                QueueUrl=queue_url,
                MessageBody=json.dumps(processing_message(
                    bucket=bucket,
                    key=key,
                    source="dashboard_sync",
                    tenant=tenant,
                    event_id=event_id,
                )),
            )
            count += 1
            logger.info("polled Meraki path=%s event_id=%s", path, event_id)
    finally:
        if own_client:
            client.close()
    return count


def run_forever() -> None:
    interval = int(os.getenv("MERAKI_POLL_INTERVAL_SECONDS", "300"))
    failure_sleep = int(os.getenv("MERAKI_FAILURE_BACKOFF_SECONDS", "30"))
    while True:
        try:
            poll_once()
            time.sleep(interval)
        except Exception:
            logger.exception("dashboard_sync poll failed")
            time.sleep(failure_sleep)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--once", action="store_true", help="Poll configured paths once and exit")
    args = parser.parse_args()
    if args.once:
        poll_once()
    else:
        run_forever()


if __name__ == "__main__":
    main()
