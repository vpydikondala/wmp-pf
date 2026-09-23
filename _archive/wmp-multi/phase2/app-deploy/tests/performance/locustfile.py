from __future__ import annotations

import os
import uuid

from locust import HttpUser, between, events, task

WEBHOOK_SECRET = os.getenv("WEBHOOK_SECRET", "integration-webhook-secret")
P95_LIMIT_MS = float(os.getenv("PERF_P95_LIMIT_MS", "1500"))
MIN_RPS = float(os.getenv("PERF_MIN_RPS", "1"))


class InboundTelemetryUser(HttpUser):
    wait_time = between(0.05, 0.2)

    @task
    def publish_occupancy(self):
        event_id = str(uuid.uuid4())
        payload = {
            "event_id": event_id,
            "organizationId": "perf-org",
            "type": "occupancy",
            "deviceSerial": f"Q2XX-{event_id[:8]}",
            "clientMac": "00:11:22:33:44:55",
            "value": 1,
        }
        with self.client.post(
            "/api/v1/meraki/webhook",
            json=payload,
            headers={"X-Meraki-Secret": WEBHOOK_SECRET},
            name="POST /api/v1/meraki/webhook",
            catch_response=True,
        ) as response:
            if response.status_code != 202:
                response.failure(f"expected 202, got {response.status_code}: {response.text}")


@events.quitting.add_listener
def enforce_nfr(environment, **_kwargs):
    total = environment.stats.total
    p95 = total.get_response_time_percentile(0.95) or 0
    rps = total.total_rps or 0
    if total.fail_ratio > float(os.getenv("PERF_FAIL_RATIO", "0.01")):
        environment.process_exit_code = 20
    elif p95 > P95_LIMIT_MS:
        environment.process_exit_code = 21
    elif rps < MIN_RPS:
        environment.process_exit_code = 22
