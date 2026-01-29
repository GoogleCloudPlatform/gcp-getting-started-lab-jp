from typing import Optional
from google.adk.agents.callback_context import CallbackContext
from google.genai import types

# -----------------------------------------------------------------------------
# Callback for Memory
# -----------------------------------------------------------------------------

async def save_session_to_memory(callback_context: CallbackContext) -> Optional[types.Content]:
    """
    Save completed sessions to memory bank.

    This callback is triggered after the agent finishes processing a request.
    It extracts important facts from the conversation and stores them in
    the Memory Bank for future sessions.
    """
    await callback_context._invocation_context.memory_service.add_session_to_memory(
        callback_context._invocation_context.session)
