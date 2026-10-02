"""llm.py — reply generation for the support desk (fictional) FAQ assistant (GCP port).

Same contract as the journey's llm.py, with the Bedrock Converse call
replaced by Vertex AI Gemini through google-genai:

  * "live" — generate_content on the model in MODEL_ID (gemini-2.5-flash-lite
    by default, verified 2026-07; env-overridable).
  * "stub" — byte-identical deterministic reply to the AWS version, so parity
    hashes match when both sides run stubbed.
"""

import gcp_clients
from google.genai import types

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

    # Gemini requires the turn list to start with a user turn; trim
    # defensively after the history-window cut (mirrors the AWS version).
    while history and history[0]["role"] != "user":
        history = history[1:]

    # Bedrock role "assistant" maps to Gemini role "model".
    contents = [
        types.Content(
            role="user" if turn["role"] == "user" else "model",
            parts=[types.Part.from_text(text=turn["content"])],
        )
        for turn in history
    ]
    response = gcp_clients.genai_client().models.generate_content(
        model=model_id,
        contents=contents,
        config=types.GenerateContentConfig(
            system_instruction=SYSTEM_PROMPT,
            max_output_tokens=MAX_TOKENS,
        ),
    )
    return (response.text or "").strip()
