from __future__ import annotations

import json
import os
import time

import boto3
import httpx
import psycopg
from botocore.config import Config

AWS_ENDPOINT = os.getenv("AWS_ENDPOINT_URL", "http://localhost:4566")
REGION = os.getenv("AWS_REGION", "eu-west-2")
INBOUND_URL = os.getenv("INBOUND_URL", "http://localhost:8080")


def client(service):
    kwargs = {"endpoint_url": AWS_ENDPOINT, "region_name": REGION,
              "aws_access_key_id": "test", "aws_secret_access_key": "test"}
    if service == "s3":
        kwargs["config"] = Config(s3={"addressing_style": "path"})
    return boto3.client(service, **kwargs)


def wait_until(predicate, timeout=30, interval=1):
    end = time.time() + timeout
    last = None
    while time.time() < end:
        try:
            value = predicate()
            if value:
                return value
            last = value
        except Exception as exc:
            last = exc
        time.sleep(interval)
    raise AssertionError(f"condition not met in {timeout}s; last={last!r}")


def test_inbound_to_processor_to_database_and_datalake():
    payload = {
        "event_id": "integration-webhook-1",
        "organizationId": "org-1",
        "type": "occupancy",
        "deviceSerial": "Q2XX-INTEGRATION",
        "clientMac": "00:11:22:33:44:55",
        "value": 1,
    }
    response = httpx.post(
        f"{INBOUND_URL}/api/v1/meraki/webhook",
        json=payload,
        headers={"X-Meraki-Secret": "integration-webhook-secret"},
        timeout=10,
    )
    assert response.status_code == 202, response.text

    s3 = client("s3")
    key = response.json()["s3_key"]
    obj = s3.get_object(Bucket="integration-data", Key=key)
    assert json.loads(obj["Body"].read())["event_id"] == "integration-webhook-1"

    def db_row():
        with psycopg.connect("host=localhost port=5432 dbname=occupancy user=platform_admin password=integration-password") as conn:
            with conn.cursor() as cur:
                cur.execute("SELECT event_id, occupancy_value FROM occupancy_events WHERE event_id=%s", ("integration-webhook-1",))
                return cur.fetchone()

    row = wait_until(db_row)
    assert row[0] == "integration-webhook-1"
    assert row[1] == 1.0

    sqs = client("sqs")
    queue_url = sqs.get_queue_url(QueueName="integration-datalake")["QueueUrl"]

    def dl_message():
        result = sqs.receive_message(QueueUrl=queue_url, MaxNumberOfMessages=10, WaitTimeSeconds=1)
        for item in result.get("Messages", []):
            body = json.loads(item["Body"])
            if body.get("event_id") == "integration-webhook-1":
                return body
        return None

    delivered = wait_until(dl_message)
    assert delivered["tenant_id"] == "org-1"


def test_outbound_meraki_poll_reaches_processing_pipeline():
    def db_row():
        with psycopg.connect("host=localhost port=5432 dbname=occupancy user=platform_admin password=integration-password") as conn:
            with conn.cursor() as cur:
                cur.execute("SELECT event_id, source FROM occupancy_events WHERE source='outbound' ORDER BY processed_at DESC LIMIT 1")
                return cur.fetchone()

    row = wait_until(db_row, timeout=40)
    assert row[1] == "outbound"
