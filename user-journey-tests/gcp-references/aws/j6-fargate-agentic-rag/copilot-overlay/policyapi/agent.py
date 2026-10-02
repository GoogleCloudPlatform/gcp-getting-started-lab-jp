"""The policy copilot's agent definition — migrated to Agent Runtime.

The agent is the journey's agent: same name, same playbook, same three
tools. Exactly one line changed — the model binding. On AWS it was

    LiteLlm(model="bedrock/jp.anthropic.claude-sonnet-4-6")

(the Tokyo geo inference profile, signed by the task role). Here the model
is a native Gemini id and the LiteLLM wrapper — and the litellm dependency
with it — is simply gone: Agent Runtime authenticates to the model itself.
Zero-model-risk alternative once Model Garden access is enabled for the
project: LiteLlm(model="vertex_ai/claude-sonnet-4-6") — verify it SERVES
before recommending it.
"""

from __future__ import annotations

import os

from google.adk.agents import Agent
from google.adk.apps import App

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
    model=os.environ.get("MODEL_BINDING", "gemini-3.7-flash"),
    description="Retrieval-loop assistant over the company policy knowledge base.",
    instruction=PLAYBOOK,
    tools=[search_kb, lookup_document, browse_topics],
)

app = App(root_agent=root_agent, name="policy-copilot")
