"""
Agent definitions for the Restaurant Agent.

In this file, you will create a single agent with:
- Memory capabilities (PreloadMemoryTool)
- Google Search (GoogleSearchTool)
- Google Maps (MCP Toolset)
"""
from typing import Optional

from google.adk.agents import LlmAgent
from google.adk.agents.callback_context import CallbackContext
from google.adk.tools.google_search_tool import GoogleSearchTool
from google.adk.tools.preload_memory_tool import PreloadMemoryTool
from google.genai import types

from .tool import get_maps_mcp_toolset


# -----------------------------------------------------------------------------
# Initialize Tools
# -----------------------------------------------------------------------------

# TODO: Initialize the Maps MCP toolset
# Call get_maps_mcp_toolset() to get the toolset instance
# REPLACE_MAPS_TOOLSET
maps_toolset = None  # REPLACE THIS


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
    # TODO: Implement the memory saving logic
    # Access the invocation context and call add_session_to_memory
    #
    # Example:
    # await callback_context._invocation_context.memory_service.add_session_to_memory(
    #     callback_context._invocation_context.session)
    # REPLACE_MEMORY_CALLBACK
    pass


# -----------------------------------------------------------------------------
# Root Agent
# -----------------------------------------------------------------------------

# TODO: Create root_agent with all tools
# This is the main agent that:
# - Uses PreloadMemoryTool to load user memories at conversation start
# - Uses GoogleSearchTool for web searches
# - Uses the Maps MCP toolset for restaurant searches
# - Saves sessions to memory using after_agent_callback
#
# It should:
# - Have name="root_agent"
# - Use model="gemini-2.5-pro"
# - Have a description like "Personal concierge that likes to help user"
# - Have instruction about being a thoughtful restaurant assistant
# - Include tools=[PreloadMemoryTool(), GoogleSearchTool(bypass_multi_tools_limit=True), maps_toolset]
# - Set output_key="searched_restaurant_info"
# - Set after_agent_callback=save_session_to_memory
#
# Example instruction:
# """
# You are a thoughtful restaurant assistant with perfect memory - like a personal concierge.
# PERSONALITY & APPROACH:
# - Be warm, personal, and emotionally intelligent
# - Make connections between past conversations and current requests
# - Proactively mention what you remember about the user.
#
# Do not start search restaurant unless the user asks for it.
# """

root_agent = None  # REPLACE THIS WITH YOUR AGENT DEFINITION
