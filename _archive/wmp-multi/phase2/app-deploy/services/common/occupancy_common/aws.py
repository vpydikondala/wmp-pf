from __future__ import annotations

import json
import os
from functools import lru_cache
from typing import Any

import boto3
from botocore.config import Config


def _client(service: str):
    endpoint = os.getenv("AWS_ENDPOINT_URL")
    kwargs: dict[str, Any] = {
        "region_name": os.getenv("AWS_REGION", "eu-west-2"),
    }
    if endpoint:
        kwargs["endpoint_url"] = endpoint
    if service == "s3":
        kwargs["config"] = Config(s3={"addressing_style": "path"})
    return boto3.client(service, **kwargs)


@lru_cache(maxsize=None)
def s3_client():
    return _client("s3")


@lru_cache(maxsize=None)
def sqs_client():
    return _client("sqs")


@lru_cache(maxsize=None)
def secrets_client():
    return _client("secretsmanager")


@lru_cache(maxsize=64)
def get_json_secret(secret_arn: str) -> dict[str, Any]:
    response = secrets_client().get_secret_value(SecretId=secret_arn)
    value = response.get("SecretString")
    if not value:
        raise RuntimeError(f"Secret {secret_arn} does not contain SecretString")
    data = json.loads(value)
    if not isinstance(data, dict):
        raise RuntimeError(f"Secret {secret_arn} must contain a JSON object")
    return data
