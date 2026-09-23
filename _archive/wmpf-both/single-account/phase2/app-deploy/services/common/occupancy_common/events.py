from __future__ import annotations

import hashlib
import json
import uuid
from datetime import UTC, datetime
from typing import Any


def utc_now() -> datetime:
    return datetime.now(UTC)


def iso_now() -> str:
    return utc_now().isoformat()


def stable_event_id(payload: dict[str, Any], supplied: str | None = None) -> str:
    if supplied:
        return supplied[:128]
    for key in ("event_id", "eventId", "id", "messageId"):
        value = payload.get(key)
        if value:
            return str(value)[:128]
    encoded = json.dumps(payload, sort_keys=True, separators=(",", ":"), default=str).encode()
    return hashlib.sha256(encoded).hexdigest()


def tenant_id(payload: dict[str, Any], supplied: str | None = None) -> str:
    if supplied:
        return supplied[:128]
    for key in ("tenant_id", "tenantId", "organizationId", "organization_id"):
        value = payload.get(key)
        if value:
            return str(value)[:128]
    return "default"


def raw_key(source: str, tenant: str, event_id: str, when: datetime | None = None) -> str:
    dt = when or utc_now()
    safe_tenant = tenant.replace("/", "_")
    safe_event = event_id.replace("/", "_")
    return f"raw/{source}/{safe_tenant}/{dt:%Y/%m/%d}/{safe_event}.json"


def processing_message(*, bucket: str, key: str, source: str, tenant: str, event_id: str) -> dict[str, str]:
    return {
        "schema_version": "1",
        "bucket": bucket,
        "key": key,
        "source": source,
        "tenant_id": tenant,
        "event_id": event_id,
        "enqueued_at": iso_now(),
        "message_id": str(uuid.uuid4()),
    }
