"""The policy copilot's agent definition (google-adk).

The model is a Bedrock model bound through LiteLLM's `bedrock/…` route — the
task role's credentials carry the call, so no API key exists anywhere in
this service. Importing this module never contacts Bedrock.
"""

from __future__ import annotations

from google.adk.agents import Agent
from google.adk.models.lite_llm import LiteLlm

from ..config import CFG
from .tools import browse_topics, lookup_document, search_kb

PLAYBOOK = """\
You are the internal policy copilot of a mid-size logistics company.
You answer ONLY from the policy knowledge base, retrieved through your tools.

Work each question as a retrieval loop, not a single lookup:
1. Turn the question into focused search terms and call search_kb.
2. Judge the hits. If the best rank is weak, nothing matches, or the hits are
   off-topic: reformulate (synonyms, fewer words, or a topic filter from
   browse_topics) and search AGAIN before answering.
3. When the user needs specifics — amounts, deadlines, approvers, exact
   wording — call lookup_document on the best document and quote from it.
4. Answer briefly and cite every claim like [EXP-100 §2]. Multiple claims
   need multiple citations.
5. If two searches produce nothing relevant, say the knowledge base has no
   answer and name the topics that exist. Never invent policy.
"""

root_agent = Agent(
    name="policy_copilot",
    model=LiteLlm(model=CFG.litellm_route),
    description="Retrieval-loop assistant over the company policy knowledge base.",
    instruction=PLAYBOOK,
    tools=[search_kb, lookup_document, browse_topics],
)
