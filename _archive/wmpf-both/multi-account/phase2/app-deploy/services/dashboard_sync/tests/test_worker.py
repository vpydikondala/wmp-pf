import json

import httpx

from dashboard_sync_service import worker


class FakeS3:
    def __init__(self):
        self.objects = []
    def put_object(self, **kwargs):
        self.objects.append(kwargs)


class FakeSQS:
    def __init__(self):
        self.messages = []
    def send_message(self, **kwargs):
        self.messages.append(kwargs)


def test_poll_once_lands_and_enqueues(monkeypatch):
    fake_s3 = FakeS3()
    fake_sqs = FakeSQS()
    monkeypatch.setenv("DATA_BUCKET", "bucket")
    monkeypatch.setenv("PROCESSING_QUEUE_URL", "queue")
    monkeypatch.setenv("MERAKI_BASE_URL", "https://example.test/api/v1")
    monkeypatch.setenv("MERAKI_POLL_PATHS", "/organizations")
    monkeypatch.setattr(worker, "s3_client", lambda: fake_s3)
    monkeypatch.setattr(worker, "sqs_client", lambda: fake_sqs)

    def handler(request: httpx.Request):
        assert request.url.path == "/api/v1/organizations"
        return httpx.Response(200, json=[{"id": "org-1", "name": "Example"}])

    client = httpx.Client(transport=httpx.MockTransport(handler))
    assert worker.poll_once(client) == 1
    assert len(fake_s3.objects) == 1
    body = json.loads(fake_s3.objects[0]["Body"])
    assert body["event_type"] == "meraki_poll"
    assert len(fake_sqs.messages) == 1


def test_poll_once_raises_on_rate_limit(monkeypatch):
    monkeypatch.setenv("DATA_BUCKET", "bucket")
    monkeypatch.setenv("PROCESSING_QUEUE_URL", "queue")
    monkeypatch.setenv("MERAKI_BASE_URL", "https://example.test/api/v1")
    monkeypatch.setenv("MERAKI_POLL_PATHS", "/organizations")
    client = httpx.Client(transport=httpx.MockTransport(lambda _: httpx.Response(429, headers={"Retry-After": "2"})))
    try:
        worker.poll_once(client)
        assert False, "expected rate limit failure"
    except RuntimeError as exc:
        assert "rate limited" in str(exc)
