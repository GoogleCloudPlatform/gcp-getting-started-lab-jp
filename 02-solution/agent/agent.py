"""
Agent definitions for the Restaurant Agent.
"""
from typing import Optional
from google.adk.agents import LlmAgent
from google.adk.agents.callback_context import CallbackContext
from google.adk.tools.google_search_tool import GoogleSearchTool
from google.adk.tools.preload_memory_tool import PreloadMemoryTool
from google.genai import types
from .tool import get_maps_mcp_toolset
# -----------------------------------------------------------------------------
# Callback for Memory
# -----------------------------------------------------------------------------
maps_toolset = get_maps_mcp_toolset()

async def save_session_to_memory(callback_context: CallbackContext) -> Optional[types.Content]:
    """
    Save completed sessions to memory bank.

    This callback is triggered after the agent finishes processing a request.
    It extracts important facts from the conversation and stores them in
    the Memory Bank for future sessions.
    """
    await callback_context._invocation_context.memory_service.add_session_to_memory(
        callback_context._invocation_context.session)


root_agent = LlmAgent(
    name="root_agent",
    model="gemini-2.5-pro",
    description="Personal concierge that likes to help user",
    instruction="""
        You are a thoughtful restaurant assistant with perfect memory - like a personal concierge.
        PERSONALITY & APPROACH:
        - Be warm, personal, and emotionally intelligent
        - Make connections between past conversations and current requests
        - Proactively mention what you remember about the user.
        
        Do not start search restaurant unless the user asks for it.
        """,
    tools=[PreloadMemoryTool(), GoogleSearchTool(bypass_multi_tools_limit=True), maps_toolset],
    output_key="searched_restaurant_info",
    after_agent_callback=save_session_to_memory,
)
