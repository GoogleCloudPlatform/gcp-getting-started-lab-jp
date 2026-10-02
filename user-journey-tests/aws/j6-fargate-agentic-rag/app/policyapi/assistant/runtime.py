"""Answering engine: deterministic pipeline mode, or the live ADK agent.

`pipeline` (the default) executes the same retrieval loop the agent's
playbook prescribes — search, judge, refine, cite — as plain code with no
model call at all. It exists because the fixture must run end-to-end in
accounts where Bedrock has zero quota, and because deterministic answers make
the smoke tests byte-stable. `model` mode runs the real google-adk agent.

Both modes record their retrieval actions as `steps`, so callers can see the
loop (the second, refined search is what makes the copilot *agentic* rather
than a one-shot RAG lookup).
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field
from typing import Any

from google.adk.runners import InMemoryRunner
from google.genai import types

from ..config import CFG
from . import tools
from .agent import root_agent

_CITATION = re.compile(r"\[[A-Z]{3}-\d{3} §\d+\]")
_STOPWORDS = frozenset(
    "a an and are can do does for how i in is it of on our the to we what when where who why with".split()
)


@dataclass
class Answer:
    text: str
    steps: list[dict[str, Any]] = field(default_factory=list)

    @property
    def sources(self) -> list[str]:
        return sorted({c.strip("[]").split(" ")[0] for c in _CITATION.findall(self.text)})


def _broaden(question: str) -> str:
    """Refinement heuristic: OR the meaty words so full-text search trades
    precision for recall — the code-mode equivalent of the playbook's
    "reformulate and search AGAIN" step."""
    words = [w for w in re.findall(r"[a-z0-9']+", question.lower()) if w not in _STOPWORDS]
    return " OR ".join(sorted(set(words), key=lambda w: (-len(w), w))[:4])


def _cite(hit: dict[str, Any]) -> str:
    return f"[{hit['ref']} §{hit['position']}]"


def _usable(result: dict[str, Any]) -> list[dict[str, Any]]:
    """Hits worth answering from. Trigram (fuzzy) hits never qualify in
    pipeline mode — they match on shared filler words often enough to cite
    the wrong policy, and an honest "no match" beats a confident miss. Only
    ranked full-text hits above the floor can back a citation."""
    if result.get("state") != "ok" or result.get("method") != "fulltext":
        return []
    hits = result.get("hits", [])
    return hits if hits and hits[0]["rank"] >= CFG.weak_match_rank else []


def _pipeline_answer(question: str) -> Answer:
    """The playbook as code: search → judge → broaden → (detail) → cite."""
    answer = Answer(text="")

    first = tools.search_kb(question, "")
    answer.steps.append({"action": "search_kb", "query": question,
                         "matched": len(first.get("hits", []))})
    hits = _usable(first)

    if not hits:
        broadened = _broaden(question)
        second = tools.search_kb(broadened, "")
        answer.steps.append({"action": "search_kb", "query": broadened,
                             "matched": len(second.get("hits", []))})
        hits = _usable(second)

    if not hits:
        listing = tools.browse_topics("no matches after two searches")
        answer.steps.append({"action": "browse_topics", "matched": len(listing.get("topics", []))})
        names = ", ".join(t["topic"] for t in listing.get("topics", []))
        answer.text = (
            "The policy knowledge base has no section matching that question. "
            f"Topics it does cover: {names}."
        )
        return answer

    top = hits[0]
    detail = tools.lookup_document(top["ref"])
    answer.steps.append({"action": "lookup_document", "ref": top["ref"],
                         "matched": len(detail.get("sections", []))})

    lines = [f"According to {top['title']} {_cite(top)}: {top['excerpt'].strip()}"]
    for extra in hits[1:3]:
        if extra["ref"] != top["ref"] or extra["position"] != top["position"]:
            lines.append(f"See also {_cite(extra)}: {extra['heading']}.")
    if detail.get("state") == "ok":
        lines.append(f"Full text: {top['ref']} — {detail['title']} (owner: {detail['owner_team']}).")
    answer.text = "\n".join(lines)
    return answer


async def _model_answer(question: str, history: list[tuple[str, str]]) -> Answer:
    """One live agent turn; prior turns are replayed as a context preamble."""
    preamble = ""
    if history:
        replay = "\n".join(f"{speaker}: {text}" for speaker, text in history)
        preamble = f"Conversation so far:\n{replay}\n\nCurrent question: "

    runner = InMemoryRunner(agent=root_agent, app_name=CFG.service_name)
    session = await runner.session_service.create_session(
        app_name=CFG.service_name, user_id="policy-desk"
    )

    answer = Answer(text="")
    async for event in runner.run_async(
        user_id=session.user_id,
        session_id=session.id,
        new_message=types.Content(role="user", parts=[types.Part(text=preamble + question)]),
    ):
        for part in event.content.parts if event.content and event.content.parts else []:
            if part.function_call:
                args = dict(part.function_call.args or {})
                answer.steps.append({"action": part.function_call.name, **{
                    k: v for k, v in args.items() if isinstance(v, (str, int, float))
                }})
        if event.is_final_response() and event.content and event.content.parts:
            answer.text = "".join(p.text for p in event.content.parts if p.text)
    if not answer.text:
        answer.text = "The copilot returned no answer; try rephrasing."
    return answer


async def answer_question(question: str, history: list[tuple[str, str]]) -> Answer:
    if CFG.answer_mode == "model":
        return await _model_answer(question, history)
    return _pipeline_answer(question)
