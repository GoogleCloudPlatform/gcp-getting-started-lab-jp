"""rag.py — retrieval and explanation for the portfolio explainer.

Two modes, selected by the LLM_MODE env var (read by main.py, passed in):

  * "live" — retrieve, build the prompt, call the model through the
    azure_clients funnel.
  * "stub" — retrieve exactly the same way, build the same prompt, then compose
    a deterministic analysis from the retrieved passages instead of calling the
    model. The retrieval, the citation set and the persistence path are all
    identical, so everything except the wording of the final paragraph is
    exercised in either mode. It is also the fallback the desk can flip on
    without a redeploy when the model account is throttling.

The mode changes ONE call. Nothing above or below it branches.
"""

from __future__ import annotations

import re
from typing import Any

import azure_clients

SYSTEM_PROMPT = (
    "You are a robo-advisory portfolio explainer. Explain in plain language "
    "why the customer's portfolio holds what it holds, using only the fund "
    "documentation provided. Cite each fund you mention by its code. Never "
    "give personalised investment advice, never predict returns, and if the "
    "documentation does not cover the question, say so."
)

MAX_TOKENS = 500
TOP_K = 3


def build_prompt(question: str, passages: list[dict[str, Any]]) -> list[dict[str, str]]:
    """The message list handed to the model. Built the same way in both modes."""
    if passages:
        context = "\n\n".join(
            f"[{p['fund']}] {p['title']}\n{p['content']}" for p in passages
        )
    else:
        context = "(no fund documentation matched this question)"
    return [
        {"role": "system", "content": SYSTEM_PROMPT},
        {
            "role": "user",
            "content": f"Fund documentation:\n{context}\n\nQuestion: {question}",
        },
    ]


def _stub_answer(question: str, passages: list[dict[str, Any]]) -> str:
    """A deterministic analysis assembled from what retrieval returned.

    Same inputs always produce the same string, which is what lets an acceptance
    check assert on it.
    """
    if not passages:
        return (
            "[stub] The fund documentation on file does not cover "
            f'"{_first_sentence(question)}". A member of the advisory desk will '
            "follow up."
        )
    funds = ", ".join(p["fund"] for p in passages)
    leading = passages[0]
    return (
        f"[stub] Your holdings touch {len(passages)} fund(s): {funds}. "
        f"{leading['title']} is the largest of them — {_first_sentence(leading['content'])} "
        f'This addresses "{_first_sentence(question)}" from the documentation on '
        "file only; it is not personalised advice."
    )


def _first_sentence(text: str) -> str:
    """First sentence of a passage, trimmed. Used to keep the stub readable."""
    cleaned = " ".join(text.split())
    match = re.search(r"^(.{0,180}?[.!?])(\s|$)", cleaned)
    if match:
        return match.group(1)
    return cleaned[:180]


def explain(question: str, mode: str) -> dict[str, Any]:
    """Answer one question. Returns the answer, its citations, and the mode used.

    Retrieval runs first and identically in both modes — that is the point of
    the stub. Only the generate step differs.
    """
    passages = azure_clients.search_documents(question, top=TOP_K)
    messages = build_prompt(question, passages)

    if mode == "stub":
        answer = _stub_answer(question, passages)
    else:
        answer = azure_clients.chat(messages, max_tokens=MAX_TOKENS)

    return {
        "answer": answer,
        "citations": [
            {"fund": p["fund"], "title": p["title"], "id": p["id"]} for p in passages
        ],
        "mode": mode,
        "prompt_messages": len(messages),
    }


def corpus_to_documents(corpus: list[dict[str, str]]) -> list[dict[str, Any]]:
    """Turn the markdown files in blob storage into index documents.

    Each file is one fund note. The first line is its title, the filename stem
    (upper-cased) is the fund code, and the rest is the body. Keys must be
    URL-safe for the search service, so the stem is used verbatim as the id.
    """
    documents = []
    for entry in corpus:
        stem = entry["name"].rsplit(".", 1)[0]
        lines = entry["text"].strip().splitlines()
        title = lines[0].lstrip("# ").strip() if lines else stem
        body = "\n".join(lines[1:]).strip()
        documents.append(
            {
                "id": stem,
                "title": title,
                "content": body,
                "fund": stem.upper(),
            }
        )
    return documents
