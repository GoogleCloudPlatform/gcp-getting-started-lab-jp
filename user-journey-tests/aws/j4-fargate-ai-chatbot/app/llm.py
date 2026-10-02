"""llm.py — reply generation for the support desk (fictional) FAQ assistant.

Two modes, selected by the LLM_MODE env var (read by main.py, passed in):

  * "live" — call the model through the Converse API (aws_clients funnel).
  * "stub" — deterministic canned reply; keeps the whole request path
    (persistence, archiving, health checks) exercisable in environments
    where model invocation is unavailable, and doubles as the incident
    fallback the support team can flip on without a redeploy.
"""

import aws_clients

SYSTEM_PROMPT = (
    "You are the support desk assistant. Answer briefly and politely "
    "in the customer's language. If you are unsure, tell the customer a "
    "human agent will follow up. Never invent account or billing details."
)

MAX_TOKENS = 300


def generate(history, model_id, mode):
    """Produce the assistant reply for a conversation.

    history: list of {"role": "user"|"assistant", "content": str} dicts in
    chronological order, ending with the newest user message.
    """
    if mode == "stub":
        last_message = history[-1]["content"] if history else ""
        return (
            "[stub] Thanks for contacting the support desk. You said: "
            f"{last_message[:80]}"
        )

    # The Converse API requires the message list to start with a user turn
    # and alternate strictly; turns are stored pairwise so this is normally
    # already true, but trim defensively after the history-window cut.
    while history and history[0]["role"] != "user":
        history = history[1:]

    messages = [
        {"role": turn["role"], "content": [{"text": turn["content"]}]}
        for turn in history
    ]
    response = aws_clients.bedrock_runtime().converse(
        modelId=model_id,
        system=[{"text": SYSTEM_PROMPT}],
        messages=messages,
        inferenceConfig={"maxTokens": MAX_TOKENS},
    )
    return response["output"]["message"]["content"][0]["text"]
