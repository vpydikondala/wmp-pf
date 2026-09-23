import io
import json

from processor_service import worker


class FakeBody:
    def __init__(self, payload):
        self.payload = payload
    def read(self):
        return json.dumps(self.payload).encode()


class FakeS3:
    def get_object(self, **kwargs):
        return {"Body": FakeBody({"type": "occupancy", "value": 1, "deviceSerial": "Q2XX-1234"})}


class FakeSQS:
    def __init__(self):
        self.messages = []
    def send_message(self, **kwargs):
        self.messages.append(kwargs)


class FakeCursor:
    def __init__(self):
        self.executions = []
    def __enter__(self):
        return self
    def __exit__(self, *args):
        return False
    def execute(self, sql, params=None):
        self.executions.append((sql, params))


class FakeConnection:
    def __init__(self):
        self.cursor_obj = FakeCursor()
        self.committed = False
    def cursor(self):
        return self.cursor_obj
    def commit(self):
        self.committed = True


def test_normalize_extracts_occupancy():
    record = worker.normalize(
        {"type": "occupancy", "value": "1", "deviceSerial": "Q2XX"},
        {"event_id": "evt-1", "tenant_id": "org-1", "source": "inbound", "key": "raw.json"},
    )
    assert record["occupancy_value"] == 1.0
    assert record["device_serial"] == "Q2XX"


def test_process_message_writes_db_and_datalake(monkeypatch):
    sqs = FakeSQS()
    monkeypatch.setenv("DATALAKE_QUEUE_URL", "datalake")
    monkeypatch.setattr(worker, "s3_client", lambda: FakeS3())
    monkeypatch.setattr(worker, "sqs_client", lambda: sqs)
    connection = FakeConnection()
    message = json.dumps({
        "bucket": "bucket",
        "key": "raw.json",
        "source": "inbound",
        "tenant_id": "org-1",
        "event_id": "evt-1",
    })
    result = worker.process_message(message, connection)
    assert connection.committed
    assert len(connection.cursor_obj.executions) == 2
    assert result["event_id"] == "evt-1"
    assert len(sqs.messages) == 1
