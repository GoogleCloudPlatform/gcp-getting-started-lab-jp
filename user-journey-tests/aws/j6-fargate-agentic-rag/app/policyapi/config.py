"""Runtime configuration for the policy copilot.

One frozen snapshot of the environment, taken at import. The ECS task
definition is the only writer of these variables; nothing else in the code
base touches os.environ.
"""

from __future__ import annotations

import os
from dataclasses import dataclass


def _text(name: str, fallback: str) -> str:
    value = os.environ.get(name, "").strip()
    return value or fallback


def _number(name: str, fallback: float) -> float:
    try:
        return float(os.environ[name])
    except (KeyError, ValueError):
        return fallback


@dataclass(frozen=True)
class Config:
    service_name: str
    answer_mode: str          # "pipeline" (deterministic, no model) or "model"
    bedrock_model_id: str     # bound through LiteLLM's bedrock/ route
    conversations_table: str
    kb_secret_arn: str        # Secrets Manager JSON: host/port/user/password/dbname
    kb_host: str
    kb_database: str
    history_window: int       # turns replayed into the model's context
    turn_ttl_days: int        # DynamoDB TTL for conversation turns
    weak_match_rank: float    # pipeline mode: rank below this triggers a retry search

    @property
    def litellm_route(self) -> str:
        return f"bedrock/{self.bedrock_model_id}"

    @staticmethod
    def load() -> "Config":
        return Config(
            service_name="policy-copilot",
            answer_mode=_text("ANSWER_MODE", "pipeline"),
            bedrock_model_id=_text("BEDROCK_MODEL_ID", "jp.anthropic.claude-sonnet-4-6"),
            conversations_table=_text("CONVERSATIONS_TABLE", "arc-conversations"),
            kb_secret_arn=_text("KB_SECRET_ARN", ""),
            kb_host=_text("KB_HOST", ""),
            kb_database=_text("KB_DATABASE", "policykb"),
            history_window=int(_number("HISTORY_WINDOW", 6)),
            turn_ttl_days=int(_number("TURN_TTL_DAYS", 30)),
            weak_match_rank=_number("WEAK_MATCH_RANK", 0.05),
        )


CFG = Config.load()
