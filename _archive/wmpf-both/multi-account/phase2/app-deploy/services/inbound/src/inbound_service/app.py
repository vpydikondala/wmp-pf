from __future__ import annotations

import json
import logging
import os
from typing import Any

from fastapi import FastAPI, Header, HTTPException, Request, status

from occupancy_common.aws import get_json_secret, s3_client, sqs_client
from occupancy_common.events import processing_message, raw_key, stable_event_id, tenant_id
from occupancy_common.logging import configure_logging

configure_logging()
logger = logging.getLogger(__name__)

app = FastAPI(title="Occupancy Inbound Service", version="1.0.0")


def _required(name: str) -> str:
    value = os.getenv(name)
    if not value:
        raise RuntimeError(f"Required environment variable {name} is not set")
    return value


def _authorise(secret_header: str | None) -> None:
    if os.getenv("WEBHOOK_AUTH_REQUIRED", "true").lower() not in {"1", "true", "yes"}:
        return
    secret_arn = os.getenv("MERAKI_SECRET_ARN")
    if not secret_arn:
        raise HTTPException(status_code=status.HTTP_503_SERVICE_UNAVAILABLE, detail="Webhook secret is not configured")
    expected = get_json_secret(secret_arn).get("webhook_secret")
    if not expected or secret_header != expected:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid webhook secret")


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok", "service": "inbound"}


@app.post("/api/v1/meraki/webhook", status_code=status.HTTP_202_ACCEPTED)
async def meraki_webhook(
    request: Request,
    x_meraki_secret: str | None = Header(default=None),
    x_tenant_id: str | None = Header(default=None),
    x_event_id: str | None = Header(default=None),
) -> dict[str, str]:
    _authorise(x_meraki_secret)
    try:
        payload: Any = await request.json()
    except Exception as exc:
        raise HTTPException(status_code=400, detail="Body must be valid JSON") from exc
    if not isinstance(payload, dict):
        raise HTTPException(status_code=400, detail="Webhook body must be a JSON object")

    bucket = _required("DATA_BUCKET")
    queue_url = _required("PROCESSING_QUEUE_URL")
    event_id = stable_event_id(payload, x_event_id)
    tenant = tenant_id(payload, x_tenant_id)
    key = raw_key("inbound", tenant, event_id)
    body = json.dumps(payload, separators=(",", ":"), default=str).encode()

    s3_client().put_object(
        Bucket=bucket,
        Key=key,
        Body=body,
        ContentType="application/json",
        Metadata={"source": "inbound", "tenant-id": tenant, "event-id": event_id},
    )
    message = processing_message(bucket=bucket, key=key, source="inbound", tenant=tenant, event_id=event_id)
    sqs_client().send_message(QueueUrl=queue_url, MessageBody=json.dumps(message))
    logger.info("accepted webhook event_id=%s tenant=%s key=%s", event_id, tenant, key)
    return {"status": "accepted", "event_id": event_id, "tenant_id": tenant, "s3_key": key}
