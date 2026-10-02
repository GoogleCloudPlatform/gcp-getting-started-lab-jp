"""car-advisor — the robo-advisory operator's portfolio explainer.

FastAPI service; one container on Azure Container Apps. A question about a
portfolio is answered from the fund documentation held in blob storage and
indexed in AI Search, and every answer is written to Cosmos DB so the customer
can re-read it.

Env vars (all set on the container app):
    CAR_OPENAI_ENDPOINT      model account endpoint
    CAR_OPENAI_DEPLOYMENT    deployment name on that account
    CAR_OPENAI_API_VERSION   dated wire contract for the model API
    CAR_SEARCH_ENDPOINT      search service endpoint
    CAR_SEARCH_INDEX         index name                    (default: fund-docs)
    CAR_COSMOS_ENDPOINT      conversation store endpoint
    CAR_COSMOS_DATABASE      database name                 (default: explainer)
    CAR_COSMOS_CONTAINER     container name                (default: chat-history)
    CAR_DOCS_ACCOUNT         documentation storage account
    CAR_DOCS_BLOB_ENDPOINT   blob endpoint for that account
    CAR_DOCS_CONTAINER       container holding fund notes  (default: docs)
    LLM_MODE                 "live" or "stub"              (default: stub)
    PORT                     listen port for uvicorn       (default: 8000)
"""

from __future__ import annotations

import os
import time
import uuid
from typing import Optional

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel

import azure_clients
import rag

LLM_MODE = os.environ.get("LLM_MODE", "stub")

app = FastAPI(title="car-advisor", version="2.1.0")


class ExplainRequest(BaseModel):
    session_id: Optional[str] = None
    question: str


@app.get("/health/live")
def liveness():
    """Is this process alive? Nothing else.

    This is what the platform's liveness probe calls, and a liveness probe that
    consults a dependency is a way of restarting the app every time something
    it talks to has a bad day. It touches nothing outside this process, so the
    only thing it can report on is the only thing a restart would fix.
    """
    return {"status": "alive", "service": "car-advisor"}


@app.get("/health")
def health():
    """Dependency substatus. Never raises: always HTTP 200.

    Each dependency below is probed under a deadline, so this answers in
    seconds even when a service is unreachable — but it does reach the network,
    which is why the liveness probe calls /health/live instead.
    """
    dependencies = {
        "search": azure_clients.probe_search(),
        "conversations": azure_clients.probe_cosmos(),
        "documents": azure_clients.probe_blob(),
    }
    status = "ok" if all(d["ok"] for d in dependencies.values()) else "degraded"
    return {
        "status": status,
        "service": "car-advisor",
        "llm_mode": LLM_MODE,
        "dependencies": dependencies,
    }


@app.post("/explain")
def explain(request: ExplainRequest):
    """Answer one question about a portfolio and record the exchange."""
    question = request.question.strip()
    if not question:
        raise HTTPException(status_code=400, detail="question must not be empty")

    session_id = request.session_id or f"sess-{uuid.uuid4().hex[:12]}"

    try:
        result = rag.explain(question, LLM_MODE)
    except Exception as exc:  # noqa: BLE001 — surface as 502, not a stack trace
        raise HTTPException(
            status_code=502, detail=f"explanation failed: {type(exc).__name__}"
        ) from exc

    record = {
        "id": f"{session_id}-{uuid.uuid4().hex[:8]}",
        "sessionId": session_id,
        "question": question,
        "answer": result["answer"],
        "citations": result["citations"],
        "mode": result["mode"],
        "createdAt": time.time_ns(),
    }
    # An unreachable conversation store must not lose the answer we already
    # have. save_turn swallows its own failures and reports back as False.
    try:
        stored = azure_clients.save_turn(record)
    except Exception:  # noqa: BLE001 — the answer is worth more than the record
        stored = False

    return {
        "session_id": session_id,
        "answer": result["answer"],
        "citations": result["citations"],
        "llm_mode": result["mode"],
        "stored": stored,
    }


@app.get("/history/{session_id}")
def history(session_id: str):
    """Every explanation given in one session, oldest first."""
    turns = azure_clients.read_session(session_id)
    if not turns:
        raise HTTPException(status_code=404, detail="session not found")
    return {
        "session_id": session_id,
        "turns": turns,
        "count": len(turns),
    }


@app.post("/admin/reindex")
def reindex():
    """Rebuild the search index from the documentation in blob storage.

    This runs inside the app rather than from an operator's machine because the
    search service only answers on its private endpoint, and because Basic-tier
    services cannot run a skillset indexer behind one. The app is the indexer.
    """
    created = azure_clients.ensure_index()
    corpus = azure_clients.read_corpus()
    documents = rag.corpus_to_documents(corpus)
    uploaded = azure_clients.upload_documents(documents) if documents else 0
    return {
        "index": azure_clients.SEARCH_INDEX,
        "index_ready": created,
        "documents_found": len(documents),
        "documents_indexed": uploaded,
    }


@app.get("/admin/azure-check")
def azure_check():
    """Per-service SDK ping dashboard.

    Post-migration this same page becomes the parity dashboard, so the six keys
    and the all_ok flag are a stable contract checked by scripts/smoke-test.sh.
    """
    checks = {
        "managed_identity": azure_clients.probe_identity(),
        "openai": azure_clients.probe_openai(),
        "search": azure_clients.probe_search(),
        "cosmos": azure_clients.probe_cosmos(),
        "blob_storage": azure_clients.probe_blob(),
        "telemetry": azure_clients.probe_telemetry(),
    }
    return {
        "all_ok": all(check["ok"] for check in checks.values()),
        "llm_mode": LLM_MODE,
        "services": checks,
    }
