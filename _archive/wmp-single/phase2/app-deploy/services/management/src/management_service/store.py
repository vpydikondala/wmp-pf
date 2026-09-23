from __future__ import annotations

import json
import os
from contextlib import contextmanager
from pathlib import Path
from typing import Any

import boto3
import psycopg
from psycopg.rows import dict_row


def _required(name: str) -> str:
    value = os.getenv(name)
    if not value:
        raise RuntimeError(f"Required environment variable {name} is not set")
    return value


def _secret() -> dict[str, Any]:
    arn = _required("RDS_SECRET_ARN")
    region = os.getenv("AWS_REGION")
    response = boto3.client("secretsmanager", region_name=region).get_secret_value(SecretId=arn)
    return json.loads(response["SecretString"])


def database_dsn() -> str:
    secret = _secret()
    return (
        f"host={_required('RDS_ENDPOINT')} port={os.getenv('RDS_PORT', '5432')} "
        f"dbname={os.getenv('RDS_DATABASE', 'occupancy')} "
        f"user={secret['username']} password={secret['password']} connect_timeout=10"
    )


@contextmanager
def connection():
    with psycopg.connect(database_dsn(), row_factory=dict_row) as conn:
        yield conn
        conn.commit()


def apply_migrations() -> None:
    migration_dir = Path(os.getenv("MANAGEMENT_MIGRATIONS_PATH", "/app/migrations"))
    with connection() as conn:
        conn.execute("CREATE TABLE IF NOT EXISTS schema_migrations (version TEXT PRIMARY KEY, applied_at TIMESTAMPTZ NOT NULL DEFAULT NOW())")
        applied = {row["version"] for row in conn.execute("SELECT version FROM schema_migrations").fetchall()}
        for path in sorted(migration_dir.glob("*.sql")):
            if path.name in applied:
                continue
            for statement in path.read_text(encoding="utf-8").split(";"):
                if statement.strip():
                    conn.execute(statement)
            conn.execute("INSERT INTO schema_migrations(version) VALUES (%s)", (path.name,))
