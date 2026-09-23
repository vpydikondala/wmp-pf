import json

from fastapi.testclient import TestClient

from inbound_service import app as app_module


class FakeS3:
    def __init__(self):
        self.objects = []

    def put_object(self, **kwargs):
        self.objects.append(kwargs)
        return {}


class FakeSQS:
    def __init__(self):
        self.messages = []

    def send_message(self, **kwargs):
        self.messages.append(kwargs)
        return {"MessageId": "1"}


def test_health():
    client = TestClient(app_module.app)
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json()["status"] == "ok"


def test_webhook_lands_s3_and_enqueues(monkeypatch):
    fake_s3 = FakeS3()
    fake_sqs = FakeSQS()
    monkeypatch.setenv("DATA_BUCKET", "data-bucket")
    monkeypatch.setenv("PROCESSING_QUEUE_URL", "queue-url")
    monkeypatch.setenv("MERAKI_SECRET_ARN", "secret")
    monkeypatch.setenv("WEBHOOK_AUTH_REQUIRED", "true")
    monkeypatch.setattr(app_module, "s3_client", lambda: fake_s3)
    monkeypatch.setattr(app_module, "sqs_client", lambda: fake_sqs)
    monkeypatch.setattr(app_module, "get_json_secret", lambda _: {"webhook_secret": "expected"})

    client = TestClient(app_module.app)
    payload = {"event_id": "evt-1", "organizationId": "org-1", "type": "occupancy", "value": 1}
    response = client.post(
        "/api/v1/meraki/webhook",
        json=payload,
        headers={"X-Meraki-Secret": "expected"},
    )
    assert response.status_code == 202
    assert len(fake_s3.objects) == 1
    assert json.loads(fake_s3.objects[0]["Body"])["event_id"] == "evt-1"
    assert len(fake_sqs.messages) == 1
    queued = json.loads(fake_sqs.messages[0]["MessageBody"])
    assert queued["event_id"] == "evt-1"
    assert queued["source"] == "inbound"


def test_webhook_rejects_bad_secret(monkeypatch):
    monkeypatch.setenv("MERAKI_SECRET_ARN", "secret")
    monkeypatch.setenv("WEBHOOK_AUTH_REQUIRED", "true")
    monkeypatch.setattr(app_module, "get_json_secret", lambda _: {"webhook_secret": "expected"})
    client = TestClient(app_module.app)
    response = client.post("/api/v1/meraki/webhook", json={}, headers={"X-Meraki-Secret": "wrong"})
    assert response.status_code == 401
