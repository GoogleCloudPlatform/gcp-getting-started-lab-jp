"""HTTP surface of the policy copilot (FastAPI, one container on Fargate).

Routes:
    GET  /healthz                     liveness + answer mode
    GET  /diagnostics                 per-dependency pass/fail dashboard
    POST /ask                         one question -> cited answer (+ retrieval steps)
    GET  /conversations/{id}          the stored turn log
    GET  /kb/documents/{ref}          one policy document, full text
    GET  /kb/topics                   topic inventory
"""

from __future__ import annotations

from typing import Any, Optional

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field

from . import kb, memory
from .clients import identity, secret_payload
from .config import CFG
from .assistant.runtime import answer_question

app = FastAPI(title=CFG.service_name, version="0.9.0")


class Question(BaseModel):
    question: str = Field(min_length=1, max_length=2000)
    conversation_id: Optional[str] = None


def _probe(check) -> str:
    try:
        check()
        return "pass"
    except Exception as exc:  # noqa: BLE001 — dashboards report, never raise
        return f"fail:{type(exc).__name__}"


@app.get("/healthz")
def healthz() -> dict[str, str]:
    return {"service": CFG.service_name, "status": "up", "answer_mode": CFG.answer_mode}


@app.get("/diagnostics")
def diagnostics() -> dict[str, str]:
    """Stable four-key contract; scripts/smoke-test.sh asserts each is 'pass'."""
    return {
        "identity": _probe(lambda: identity().get_caller_identity()),
        "conversations": _probe(memory.healthcheck),
        "knowledge_base": _probe(kb.healthcheck),
        "credentials": _probe(_check_credentials),
    }


def _check_credentials() -> None:
    if not CFG.kb_secret_arn:
        raise RuntimeError("KB_SECRET_ARN unset")
    secret_payload(CFG.kb_secret_arn)


@app.post("/ask")
async def ask(q: Question) -> dict[str, Any]:
    question = q.question.strip()
    if not question:
        raise HTTPException(status_code=422, detail="question is empty")

    conversation_id = q.conversation_id or memory.new_conversation_id()
    history: list[tuple[str, str]] = []
    if q.conversation_id:
        history = memory.recent_exchange(conversation_id, CFG.history_window)
        if not history:
            raise HTTPException(status_code=404, detail="unknown conversation_id")

    try:
        result = await answer_question(question, history)
    except Exception as exc:  # noqa: BLE001 — model-backend failures are a 502, not a crash
        raise HTTPException(
            status_code=502,
            detail=f"answering backend unavailable: {type(exc).__name__}",
        ) from exc

    memory.append_turn(conversation_id, "user", question, [])
    memory.append_turn(conversation_id, "copilot", result.text, result.steps)

    return {
        "conversation_id": conversation_id,
        "answer": result.text,
        "sources": result.sources,
        "steps": result.steps,
    }


@app.get("/conversations/{conversation_id}")
def conversation(conversation_id: str) -> dict[str, Any]:
    log = memory.turns(conversation_id)
    if not log:
        raise HTTPException(status_code=404, detail="unknown conversation_id")
    return {"conversation_id": conversation_id, "turn_count": len(log), "turns": log}


@app.get("/kb/documents/{ref}")
def kb_document(ref: str) -> dict[str, Any]:
    doc = kb.document(ref)
    if doc is None:
        raise HTTPException(status_code=404, detail=f"no document {ref.upper()}")
    doc["effective_from"] = str(doc["effective_from"])
    return doc


@app.get("/kb/topics")
def kb_topics() -> dict[str, Any]:
    return {"topics": kb.topics()}
