"""
Agent definitions for the Restaurant Agent.
"""

from google.adk.agents import LlmAgent

from google.adk.tools.google_search_tool import GoogleSearchTool
from google.adk.tools.preload_memory_tool import PreloadMemoryTool
from .tool import get_maps_mcp_toolset
from .callback import save_session_to_memory

# -----------------------------------------------------------------------------
# Callback for Memory
# -----------------------------------------------------------------------------
maps_toolset = get_maps_mcp_toolset()

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
        """,
    tools=[PreloadMemoryTool(), GoogleSearchTool(bypass_multi_tools_limit=True), maps_toolset],
    output_key="searched_restaurant_info",
    after_agent_callback=save_session_to_memory,
)
