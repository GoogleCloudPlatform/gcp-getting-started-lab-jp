"""fac-api — FAQ assistant for the support desk (fictional) — GCP port.

Same FastAPI service as the journey app, one container on Cloud Run.
Route signatures and response schemas are IDENTICAL to the AWS version —
scripts/smoke-test.sh must pass unmodified — only the backing services
change: Firestore for turns, Cloud Storage for transcripts, Vertex AI
Gemini for replies.

Env vars (set by deploy/07-cloud-run.sh):
    TABLE_NAME   Firestore database id            (default: fac-conversations)
    BUCKET       transcript bucket name            (required for archiving)
    MODEL_ID     Vertex model id                   (default set at deploy)
    LLM_MODE     "live" or "stub"                  (default: live)
    PORT         injected by Cloud Run
"""

import json
import os
import time
import uuid
from typing import Optional

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel

import gcp_clients
import llm

TABLE_NAME = os.environ.get("TABLE_NAME", "fac-conversations")
BUCKET = os.environ.get("BUCKET", "")
MODEL_ID = os.environ.get("MODEL_ID", "gemini-2.5-flash-lite")
LLM_MODE = os.environ.get("LLM_MODE", "live")
HISTORY_WINDOW = 10  # newest turns fed to the model

app = FastAPI(title="fac-api", version="1.4.2")


class ChatRequest(BaseModel):
    conversation_id: Optional[str] = None
    message: str


# ---------------------------------------------------------------------------
# storage helpers (Firestore: conversations/<id>/turns/<ts>)
# ---------------------------------------------------------------------------

def _turns(conversation_id):
    return (
        gcp_clients.firestore_db(TABLE_NAME)
        .collection("conversations")
        .document(conversation_id)
        .collection("turns")
    )


def _put_turn(conversation_id, ts, role, content):
    _turns(conversation_id).document(str(ts)).set(
        {"role": role, "content": content, "ts": ts}
    )


def _query_turns(conversation_id, limit=None, newest_first=False):
    query = _turns(conversation_id).order_by(
        "ts",
        direction=gcp_clients.DESCENDING if newest_first else gcp_clients.ASCENDING,
    )
    if limit:
        query = query.limit(limit)
    return [
        {
            "role": doc.get("role"),
            "content": doc.get("content"),
            "ts": int(doc.get("ts")),
        }
        for doc in query.stream()
    ]


# ---------------------------------------------------------------------------
# routes
# ---------------------------------------------------------------------------

@app.get("/health")
def health():
    """Liveness + dependency substatus. Never raises: always HTTP 200."""
    dependencies = {}
    try:
        gcp_clients.firestore_db(TABLE_NAME).collection("conversations").limit(1).get()
        dependencies["database"] = "ok"
    except Exception as exc:  # noqa: BLE001 — health must never raise
        dependencies["database"] = f"fail: {type(exc).__name__}"
    try:
        # objects.list ping — the runtime SA has objectAdmin on the bucket
        # (buckets.get would need an extra role, so mirror head_bucket this way)
        list(gcp_clients.storage_client().list_blobs(BUCKET, max_results=1))
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
    gcp_clients.storage_client().bucket(BUCKET).blob(object_key).upload_from_string(
        json.dumps(transcript, ensure_ascii=False).encode("utf-8"),
        content_type="application/json",
    )
    return {
        "conversation_id": conversation_id,
        "object_key": object_key,
        "turn_count": len(turns),
    }


@app.get("/admin/aws-check")
def aws_check():
    """Per-service ping dashboard: {service: "ok" | "fail: <Error>"}.

    The four keys are the stable contract from the AWS deployment
    (smoke-test.sh asserts them), so they keep their AWS names while the
    pings behind them hit the replacement GCP services:
        s3 -> Cloud Storage, dynamodb -> Firestore,
        bedrock -> Vertex AI,  sts -> ADC identity.
    """
    checks = {}

    try:
        list(gcp_clients.storage_client().list_blobs(BUCKET, max_results=1))
        checks["s3"] = "ok"
    except Exception as exc:  # noqa: BLE001 — dashboard must never raise
        checks["s3"] = f"fail: {type(exc).__name__}"

    try:
        gcp_clients.firestore_db(TABLE_NAME).collection("conversations").limit(1).get()
        checks["dynamodb"] = "ok"
    except Exception as exc:  # noqa: BLE001
        checks["dynamodb"] = f"fail: {type(exc).__name__}"

    try:
        # Free control-plane-ish ping that also proves model access.
        gcp_clients.genai_client().models.count_tokens(
            model=MODEL_ID, contents="ping"
        )
        checks["bedrock"] = "ok"
    except Exception as exc:  # noqa: BLE001
        checks["bedrock"] = f"fail: {type(exc).__name__}"

    try:
        gcp_clients.identity_email()
        checks["sts"] = "ok"
    except Exception as exc:  # noqa: BLE001
        checks["sts"] = f"fail: {type(exc).__name__}"

    return checks
