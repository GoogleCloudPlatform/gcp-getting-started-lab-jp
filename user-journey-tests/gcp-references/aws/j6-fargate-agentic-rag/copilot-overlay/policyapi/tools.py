"""Function tools the policy copilot can invoke.

Plain functions — google-adk wraps each as a FunctionTool. The docstrings are
what the model reads, so they state argument semantics exactly. Every tool
degrades to a `"state": "unavailable"` result instead of raising: retrieval
failures are the model's problem to explain, not a 500.
"""

from __future__ import annotations

from typing import Any

from . import kb


def search_kb(query: str, topic: str) -> dict[str, Any]:
    """Search the policy knowledge base and return ranked matching sections.

    Args:
        query: Search terms or a natural-language question. Rephrase and
            search again if the first attempt returns nothing relevant.
        topic: Restrict to one topic slug from browse_topics (for example
            "travel" or "security"), or pass "" to search all topics.

    Returns:
        dict with state and hits; each hit has ref, title, topic, position,
        heading, excerpt and rank (higher rank = better match).
    """
    try:
        method = "fulltext"
        hits = kb.fulltext_search(query, topic.strip().lower())
        if not hits:
            method = "fuzzy"
            hits = kb.fuzzy_search(query)
        return {
            "state": "ok",
            "method": method,  # fuzzy ranks are trigram similarity, a different scale
            "hits": [dict(h, rank=float(h["rank"])) for h in hits],
        }
    except Exception as exc:  # noqa: BLE001 — degrade, never raise
        return {"state": "unavailable", "why": type(exc).__name__}


def lookup_document(ref: str) -> dict[str, Any]:
    """Fetch one policy document in full, with all its numbered sections.

    Args:
        ref: Document reference like "EXP-100" (three letters, dash, number).

    Returns:
        dict with state, and on success ref, title, topic, owner_team,
        effective_from and sections (position, heading, body).
    """
    try:
        doc = kb.document(ref)
    except Exception as exc:  # noqa: BLE001
        return {"state": "unavailable", "why": type(exc).__name__}
    if doc is None:
        return {"state": "not_found", "ref": ref.strip().upper()}
    doc["effective_from"] = str(doc["effective_from"])
    return {"state": "ok", **doc}


def browse_topics(purpose: str) -> dict[str, Any]:
    """List every policy topic and how many documents each contains.

    Args:
        purpose: One line on why you need the list (logged for audit).

    Returns:
        dict with state and topics (topic, documents).
    """
    del purpose  # audit hook only; the argument keeps calls self-describing
    try:
        return {"state": "ok", "topics": kb.topics()}
    except Exception as exc:  # noqa: BLE001
        return {"state": "unavailable", "why": type(exc).__name__}
