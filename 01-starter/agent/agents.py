"""
Agent definitions for the Restaurant Agent.

In this file, you will create the agent hierarchy:
- root_agent (orchestrator with memory)
  ├── restaurant_finder (finds restaurants)
  └── generic_search (web search)
"""
import logging
from typing import Optional

from google.adk.agents import LlmAgent
from google.adk.agents.callback_context import CallbackContext
from google.adk.tools import google_search
from google.adk.tools.preload_memory_tool import PreloadMemoryTool
from google.genai import types

from agent.tools.maptools import find_restaurants

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)


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
    # REPLACE_MEMORY_CALLBACK
    pass


# -----------------------------------------------------------------------------
# Sub-Agents
# -----------------------------------------------------------------------------

# TODO: Create restaurant_finder agent
# This agent helps users find restaurants using the find_restaurants tool.
# It should:
# - Have name="restaurant_finder"
# - Use model="gemini-2.5-pro"
# - Have a description explaining its purpose
# - Have instruction on how to use the find_restaurants tool
# - Include the find_restaurants tool
# - Set output_key="restaurant_search_results"

restaurant_finder = None  # REPLACE THIS WITH YOUR AGENT DEFINITION


# TODO: Create generic_search agent
# This agent handles general web searches using google_search tool.
# It should:
# - Have name="generic_search"
# - Use model="gemini-2.5-pro"
# - Have a description explaining its purpose
# - Have instruction on how to use google_search
# - Include the google_search tool
# - Set output_key="google_search_results"

generic_search = None  # REPLACE THIS WITH YOUR AGENT DEFINITION


# -----------------------------------------------------------------------------
# Root Agent
# -----------------------------------------------------------------------------

# TODO: Create root_agent that orchestrates sub-agents
# This is the main agent that:
# - Routes requests to specialized sub-agents
# - Uses PreloadMemoryTool to load user memories
# - Saves sessions to memory using after_agent_callback
#
# It should:
# - Have name="root_agent"
# - Use model="gemini-2.5-pro"
# - Have a detailed instruction about memory usage and safety protocols
# - Include sub_agents=[restaurant_finder, generic_search]
# - Include tools=[PreloadMemoryTool()]
# - Set after_agent_callback=save_session_to_memory

root_agent = None  # REPLACE THIS WITH YOUR AGENT DEFINITION
