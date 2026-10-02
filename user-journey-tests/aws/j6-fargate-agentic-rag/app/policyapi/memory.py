"""Conversation log: one DynamoDB item per turn.

Composite key (conversation_id, turn_at) makes a conversation an ordered
partition of small items — turns are appended, never rewritten, and TTL
expires whole conversations by attrition. The assistant replays a window of
recent turns into its context on every request (see assistant/runtime.py),
so there is no framework session object persisted anywhere.
"""

from __future__ import annotations

import json
import time
import uuid
from decimal import Decimal
from typing import Any

from boto3.dynamodb.conditions import Key

from .clients import conversations_table
from .config import CFG


def new_conversation_id() -> str:
    return uuid.uuid4().hex[:20]


def append_turn(conversation_id: str, speaker: str, text: str, steps: list[dict[str, Any]]) -> None:
    conversations_table(CFG.conversations_table).put_item(
        Item={
            "conversation_id": conversation_id,
            "turn_at": Decimal(str(time.time_ns() // 1_000_000)),  # epoch ms, monotonic enough
            "speaker": speaker,
            "text": text,
            "steps": json.dumps(steps, ensure_ascii=False),
            "expires_at": Decimal(int(time.time()) + CFG.turn_ttl_days * 86400),
        }
    )


def turns(conversation_id: str, limit: int = 50) -> list[dict[str, Any]]:
    """Turns in chronological order (DynamoDB returns the partition sorted)."""
    response = conversations_table(CFG.conversations_table).query(
        KeyConditionExpression=Key("conversation_id").eq(conversation_id),
        Limit=limit,
    )
    items = response.get("Items", [])
    for item in items:
        item["turn_at"] = int(item["turn_at"])
        item["steps"] = json.loads(item.get("steps") or "[]")
    return items


def recent_exchange(conversation_id: str, window: int) -> list[tuple[str, str]]:
    """The last `window` (speaker, text) pairs for context replay."""
    all_turns = turns(conversation_id)
    return [(t["speaker"], t["text"]) for t in all_turns[-window:]]


def healthcheck() -> None:
    conversations_table(CFG.conversations_table).load()
