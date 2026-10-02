"""fac-api — FAQ assistant for the support desk (fictional).

FastAPI service; one container on ECS Fargate. Conversation turns are stored
per conversation id, replies come from llm.generate(), and archived
transcripts are written to object storage as JSON.

Env vars (all set in the task definition):
    TABLE_NAME   conversation store name        (default: fac-conversations)
    BUCKET       transcript bucket name          (required for archiving)
    MODEL_ID     model / inference profile id
    LLM_MODE     "live" or "stub"                (default: live)
    PORT         listen port for uvicorn         (default: 8000)
"""

import json
import os
import time
import uuid
from typing import Optional

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel

import aws_clients
import llm

TABLE_NAME = os.environ.get("TABLE_NAME", "fac-conversations")
BUCKET = os.environ.get("BUCKET", "")
MODEL_ID = os.environ.get("MODEL_ID", "apac.amazon.nova-micro-v1:0")
LLM_MODE = os.environ.get("LLM_MODE", "live")
HISTORY_WINDOW = 10  # newest turns fed to the model

app = FastAPI(title="fac-api", version="1.4.2")


class ChatRequest(BaseModel):
    conversation_id: Optional[str] = None
    message: str


# ---------------------------------------------------------------------------
# storage helpers (DynamoDB item <-> plain dict)
# ---------------------------------------------------------------------------

def _put_turn(conversation_id, ts, role, content):
    aws_clients.dynamodb().put_item(
        TableName=TABLE_NAME,
        Item={
            "conversation_id": {"S": conversation_id},
            "ts": {"N": str(ts)},
            "role": {"S": role},
            "content": {"S": content},
        },
    )


def _query_turns(conversation_id, limit=None, newest_first=False):
    kwargs = {
        "TableName": TABLE_NAME,
        "KeyConditionExpression": "conversation_id = :cid",
        "ExpressionAttributeValues": {":cid": {"S": conversation_id}},
        "ScanIndexForward": not newest_first,
    }
    if limit:
        kwargs["Limit"] = limit
    items = aws_clients.dynamodb().query(**kwargs).get("Items", [])
    return [
        {
            "role": item["role"]["S"],
            "content": item["content"]["S"],
            "ts": int(item["ts"]["N"]),
        }
        for item in items
    ]


# ---------------------------------------------------------------------------
# routes
# ---------------------------------------------------------------------------

@app.get("/health")
def health():
    """Liveness + dependency substatus. Never raises: always HTTP 200."""
    dependencies = {}
    try:
        aws_clients.dynamodb().describe_table(TableName=TABLE_NAME)
        dependencies["database"] = "ok"
    except Exception as exc:  # noqa: BLE001 — health must never raise
        dependencies["database"] = f"fail: {type(exc).__name__}"
    try:
        aws_clients.s3().head_bucket(Bucket=BUCKET)
        dependencies["storage"] = "ok"
    except Exception as exc:  # noqa: BLE001
        dependencies["storage"] = f"fail: {type(exc).__name__}"

    status = "ok" if all(v == "ok" for v in dependencies.values()) else "degraded"
    return {
        "status": status,
        "service": "fac-api",
        "llm_mode": LLM_MODE,
        "dependencies": dependencies,
    }


@app.post("/chat")
def chat(request: ChatRequest):
    message = request.message.strip()
    if not message:
        raise HTTPException(status_code=400, detail="message must not be empty")

    conversation_id = request.conversation_id or f"conv-{uuid.uuid4().hex[:12]}"

    history = _query_turns(conversation_id, limit=HISTORY_WINDOW, newest_first=True)
    history.reverse()  # chronological order for the model
    history.append({"role": "user", "content": message, "ts": 0})

    reply = llm.generate(
        [{"role": t["role"], "content": t["content"]} for t in history],
        MODEL_ID,
        LLM_MODE,
    )

    user_ts = time.time_ns()
    assistant_ts = max(time.time_ns(), user_ts + 1)
    _put_turn(conversation_id, user_ts, "user", message)
    _put_turn(conversation_id, assistant_ts, "assistant", reply)

    return {
        "conversation_id": conversation_id,
        "reply": reply,
        "llm_mode": LLM_MODE,
    }


@app.get("/conversations/{conversation_id}")
def get_conversation(conversation_id: str):
    turns = _query_turns(conversation_id)
    if not turns:
        raise HTTPException(status_code=404, detail="conversation not found")
    return {
        "conversation_id": conversation_id,
        "turns": turns,
        "count": len(turns),
    }


@app.post("/conversations/{conversation_id}/archive")
def archive_conversation(conversation_id: str):
    turns = _query_turns(conversation_id)
    if not turns:
        raise HTTPException(status_code=404, detail="conversation not found")

    object_key = f"transcripts/{conversation_id}.json"
    transcript = {
        "conversation_id": conversation_id,
        "archived_at_ns": time.time_ns(),
        "turns": turns,
    }
    aws_clients.s3().put_object(
        Bucket=BUCKET,
        Key=object_key,
        Body=json.dumps(transcript, ensure_ascii=False).encode("utf-8"),
        ContentType="application/json",
    )
    return {
        "conversation_id": conversation_id,
        "object_key": object_key,
        "turn_count": len(turns),
    }


@app.get("/admin/aws-check")
def aws_check():
    """Per-service SDK ping dashboard: {service: "ok" | "fail: <Error>"}.

    Post-migration this same page becomes the parity dashboard, so the four
    keys are a stable contract checked by scripts/smoke-test.sh.
    """
    checks = {}

    try:
        aws_clients.s3().head_bucket(Bucket=BUCKET)
        checks["s3"] = "ok"
    except Exception as exc:  # noqa: BLE001 — dashboard must never raise
        checks["s3"] = f"fail: {type(exc).__name__}"

    try:
        aws_clients.dynamodb().describe_table(TableName=TABLE_NAME)
        checks["dynamodb"] = "ok"
    except Exception as exc:  # noqa: BLE001
        checks["dynamodb"] = f"fail: {type(exc).__name__}"

    try:
        # Control-plane ping only (works even where invocation quotas are 0).
        # ListFoundationModels takes no maxResults parameter — filter by
        # provider to keep the response small (API verified 2026-07).
        aws_clients.bedrock().list_foundation_models(byProvider="Amazon")
        checks["bedrock"] = "ok"
    except Exception as exc:  # noqa: BLE001
        checks["bedrock"] = f"fail: {type(exc).__name__}"

    try:
        aws_clients.sts().get_caller_identity()
        checks["sts"] = "ok"
    except Exception as exc:  # noqa: BLE001
        checks["sts"] = f"fail: {type(exc).__name__}"

    return checks
