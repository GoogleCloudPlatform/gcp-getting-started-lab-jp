"""AWS SDK handles, one per service, memoized.

The Bedrock model is deliberately absent here: the assistant reaches it
through LiteLLM's `bedrock/…` route (see assistant/agent.py), and LiteLLM
constructs its own boto3 session from the task-role credentials.
"""

from __future__ import annotations

import json
from functools import lru_cache
from typing import Any

import boto3


@lru_cache(maxsize=1)
def conversations_table(name: str) -> Any:
    """High-level Table handle for the conversation log."""
    return boto3.resource("dynamodb").Table(name)


@lru_cache(maxsize=1)
def secrets() -> Any:
    return boto3.client("secretsmanager")


@lru_cache(maxsize=1)
def identity() -> Any:
    return boto3.client("sts")


@lru_cache(maxsize=8)
def secret_payload(arn: str) -> dict[str, Any]:
    """Secrets Manager JSON secret, cached for the life of the process."""
    raw = secrets().get_secret_value(SecretId=arn)["SecretString"]
    payload = json.loads(raw)
    if not isinstance(payload, dict):
        raise TypeError(f"secret {arn} did not contain a JSON object")
    return payload
