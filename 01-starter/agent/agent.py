"""
Agent definitions for the Restaurant Agent.

In this file, you will create a single agent with:
- Memory capabilities (PreloadMemoryTool)
- Google Search (GoogleSearchTool)
- Google Maps (MCP Toolset)
"""

from google.adk.agents import LlmAgent

from google.adk.tools.google_search_tool import GoogleSearchTool
from google.adk.tools.preload_memory_tool import PreloadMemoryTool
from .tool import get_maps_mcp_toolset
from .callback import save_session_to_memory


# -----------------------------------------------------------------------------
# Initialize Tools
# -----------------------------------------------------------------------------

# TODO: Initialize the Maps MCP toolset
maps_toolset = None  # REPLACE THIS

# -----------------------------------------------------------------------------
# Root Agent
# -----------------------------------------------------------------------------

# TODO: Create root_agent with all tools
# This is the main agent that:
# - Uses PreloadMemoryTool to load user memories at conversation start
# - Uses GoogleSearchTool for web searches
# - Uses the Maps MCP toolset for restaurant searches
# - Saves sessions to memory using after_agent_callback
root_agent = None  # REPLACE THIS WITH YOUR AGENT DEFINITION
