from __future__ import annotations

import argparse
import json
import logging
import os
import time
from datetime import UTC, datetime
from typing import Any

import psycopg

from occupancy_common.aws import get_json_secret, s3_client, sqs_client
from occupancy_common.logging import configure_logging

configure_logging()
logger = logging.getLogger(__name__)

DDL = """
CREATE TABLE IF NOT EXISTS occupancy_events (
    event_id TEXT PRIMARY KEY,
    tenant_id TEXT NOT NULL,
    source TEXT NOT NULL,
    event_type TEXT,
    observed_at TIMESTAMPTZ,
    device_serial TEXT,
    client_mac TEXT,
    occupancy_value DOUBLE PRECISION,
    raw_s3_key TEXT NOT NULL,
    payload JSONB NOT NULL,
    processed_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
)
"""

UPSERT = """
INSERT INTO occupancy_events (
    event_id, tenant_id, source, event_type, observed_at,
    device_serial, client_mac, occupancy_value, raw_s3_key, payload, processed_at
) VALUES (
    %(event_id)s, %(tenant_id)s, %(source)s, %(event_type)s, %(observed_at)s,
    %(device_serial)s, %(client_mac)s, %(occupancy_value)s, %(raw_s3_key)s,
    %(payload)s::jsonb, NOW()
)
ON CONFLICT (event_id) DO UPDATE SET
    tenant_id = EXCLUDED.tenant_id,
    source = EXCLUDED.source,
    event_type = EXCLUDED.event_type,
    observed_at = EXCLUDED.observed_at,
    device_serial = EXCLUDED.device_serial,
    client_mac = EXCLUDED.client_mac,
    occupancy_value = EXCLUDED.occupancy_value,
    raw_s3_key = EXCLUDED.raw_s3_key,
    payload = EXCLUDED.payload,
    processed_at = NOW()
"""


def _required(name: str) -> str:
    value = os.getenv(name)
    if not value:
        raise RuntimeError(f"Required environment variable {name} is not set")
    return value


def database_dsn() -> str:
    secret = get_json_secret(_required("RDS_SECRET_ARN"))
    username = secret.get("username")
    password = secret.get("password")
    if not username or not password:
        raise RuntimeError("RDS secret must contain username and password")
    host = _required("RDS_ENDPOINT")
    port = os.getenv("RDS_PORT", "5432")
    dbname = os.getenv("RDS_DATABASE", "occupancy")
    return f"host={host} port={port} dbname={dbname} user={username} password={password} connect_timeout=10"


def normalize(payload: dict[str, Any], message: dict[str, Any]) -> dict[str, Any]:
    inner = payload.get("payload") if isinstance(payload.get("payload"), dict) else payload
    event_type = payload.get("event_type") or payload.get("type") or inner.get("type") or inner.get("eventType")
    observed_at = payload.get("observed_at") or payload.get("occurredAt") or payload.get("timestamp") or inner.get("timestamp")
    device_serial = payload.get("device_serial") or payload.get("deviceSerial") or inner.get("serial") or inner.get("deviceSerial")
    client_mac = payload.get("client_mac") or payload.get("clientMac") or inner.get("clientMac") or inner.get("client_mac")
    occupancy = payload.get("occupancy_value")
    if occupancy is None:
        occupancy = payload.get("value")
    if occupancy is None and isinstance(inner, dict):
        occupancy = inner.get("occupancy") or inner.get("value")
    try:
        occupancy_value = float(occupancy) if occupancy is not None else None
    except (TypeError, ValueError):
        occupancy_value = None
    return {
        "event_id": str(message["event_id"]),
        "tenant_id": str(message.get("tenant_id", "default")),
        "source": str(message.get("source", "unknown")),
        "event_type": str(event_type) if event_type is not None else None,
        "observed_at": observed_at,
        "device_serial": str(device_serial) if device_serial is not None else None,
        "client_mac": str(client_mac) if client_mac is not None else None,
        "occupancy_value": occupancy_value,
        "raw_s3_key": str(message["key"]),
        "payload": json.dumps(payload, separators=(",", ":"), default=str),
    }


def process_message(message_body: str, connection: psycopg.Connection[Any]) -> dict[str, Any]:
    message = json.loads(message_body)
    obj = s3_client().get_object(Bucket=message["bucket"], Key=message["key"])
    payload = json.loads(obj["Body"].read())
    if not isinstance(payload, dict):
        raise ValueError("Raw telemetry object must be a JSON object")
    record = normalize(payload, message)
    with connection.cursor() as cur:
        cur.execute(DDL)
        cur.execute(UPSERT, record)
    connection.commit()

    datalake_message = {
        "schema_version": "1",
        "event_id": record["event_id"],
        "tenant_id": record["tenant_id"],
        "source": record["source"],
        "event_type": record["event_type"],
        "observed_at": record["observed_at"],
        "device_serial": record["device_serial"],
        "client_mac": record["client_mac"],
        "occupancy_value": record["occupancy_value"],
        "raw_s3_key": record["raw_s3_key"],
        "processed_at": datetime.now(UTC).isoformat(),
    }
    sqs_client().send_message(
        QueueUrl=_required("DATALAKE_QUEUE_URL"),
        MessageBody=json.dumps(datalake_message, separators=(",", ":"), default=str),
    )
    logger.info("processed event_id=%s source=%s", record["event_id"], record["source"])
    return datalake_message


def receive_once(connection: psycopg.Connection[Any]) -> int:
    queue_url = _required("PROCESSING_QUEUE_URL")
    wait = int(os.getenv("PROCESSOR_POLL_WAIT_SECONDS", "20"))
    response = sqs_client().receive_message(
        QueueUrl=queue_url,
        MaxNumberOfMessages=10,
        WaitTimeSeconds=wait,
        AttributeNames=["ApproximateReceiveCount"],
    )
    messages = response.get("Messages", [])
    processed = 0
    for message in messages:
        process_message(message["Body"], connection)
        sqs_client().delete_message(QueueUrl=queue_url, ReceiptHandle=message["ReceiptHandle"])
        processed += 1
    return processed


def run_forever() -> None:
    reconnect_delay = int(os.getenv("PROCESSOR_FAILURE_BACKOFF_SECONDS", "5"))
    while True:
        try:
            with psycopg.connect(database_dsn()) as connection:
                while True:
                    receive_once(connection)
        except Exception:
            logger.exception("processor loop failed; message remains on queue for retry/DLQ")
            time.sleep(reconnect_delay)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--once", action="store_true", help="Receive one SQS batch and exit")
    args = parser.parse_args()
    if args.once:
        with psycopg.connect(database_dsn()) as connection:
            receive_once(connection)
    else:
        run_forever()


if __name__ == "__main__":
    main()
