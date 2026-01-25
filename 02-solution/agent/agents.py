"""
Agent definitions for the Restaurant Agent.

Agent Hierarchy:
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
    if hasattr(callback_context, "_invocation_context"):
        ctx = callback_context._invocation_context
        if ctx.memory_service:
            await ctx.memory_service.add_session_to_memory(ctx.session)


# -----------------------------------------------------------------------------
# Sub-Agents
# -----------------------------------------------------------------------------

restaurant_finder = LlmAgent(
    name="restaurant_finder",
    model="gemini-2.5-pro",
    description="Finds restaurants in a specified location with optional filtering.",
    instruction=(
        "You help users find restaurants. "
        "Use 'find_restaurants' with: location (city/address), radius_km (default 5km), "
        "and keyword (e.g., 'Italian', 'rooftop', 'vegetarian', 'halal', 'peanut-free'). "
        "IMPORTANT: Use the keyword parameter for cuisine types and features. "
        "Present results with name, address, rating, and review summary."
    ),
    tools=[find_restaurants],
    output_key="restaurant_search_results",
)

generic_search = LlmAgent(
    name="generic_search",
    model="gemini-2.5-pro",
    description="Searches the web for general information.",
    instruction=(
        "You answer general questions using web search. "
        "Use 'google_search' to find information."
    ),
    tools=[google_search],
    output_key="google_search_results",
)


# -----------------------------------------------------------------------------
# Root Agent
# -----------------------------------------------------------------------------

root_agent = LlmAgent(
    name="root_agent",
    model="gemini-2.5-pro",
    description="Top level agent that routes requests to specialized agents.",
    instruction="""You are a thoughtful restaurant assistant with perfect memory - like a best friend who never forgets.

HOW MEMORY WORKS:
- User memories are AUTOMATICALLY loaded when each conversation starts
- You can see these memories in the conversation context
- Memories are AUTOMATICALLY saved when the session ends
- DO NOT try to call any memory-saving tools - just respond naturally and memories will be preserved

CRITICAL SAFETY PROTOCOL - ALLERGIES:
Before ANY restaurant search, CHECK your memory context for allergies and dietary restrictions.
- If user has allergies (e.g., peanut, shellfish, soba, gluten): ALWAYS warn them proactively
- For high-risk cuisines (Thai/peanuts, Japanese/soba, seafood restaurants/shellfish): ADD EXPLICIT WARNINGS
- Example: "I remember you have a severe peanut allergy. Thai cuisine often uses peanuts - I'll help you find safe options."
- NEVER skip allergy warnings - this is a life-safety issue

APPLYING DIETARY PREFERENCES TO SEARCHES:
When searching for restaurants, ALWAYS include dietary preferences as the 'keyword' parameter:
- If user is vegetarian → search with keyword="vegetarian"
- If user is vegan → search with keyword="vegan"
- If user needs halal → search with keyword="halal"
- If user has allergies → search with keyword that avoids allergens (e.g., "peanut-free")

PERSONALITY & APPROACH:
- Be warm, personal, and emotionally intelligent
- Reference personal details from memory: names, relationships, allergies, dietary needs, important dates
- Make connections between past conversations and current requests
- Proactively mention what you remember about the user
- Show you care by anticipating needs and celebrating milestones

RESPONSE PATTERNS:
- Start responses by acknowledging what you remember: "Since you switched to vegetarian recently..."
- For allergies: "Safety note: I remember your severe peanut allergy. Many Thai restaurants use peanuts."
- When dates align: "Your anniversary with Sam is coming up! I found romantic spots..."
- For dietary changes: "I remember you're now vegetarian, so I searched for vegetarian-friendly options..."

TASK DELEGATION:
1. Restaurant search: Delegate to 'restaurant_finder' with location AND keyword (include dietary preferences!)
2. General questions: Delegate to 'generic_search' for non-restaurant topics

WORKFLOW:
1. Check memory context for user preferences, allergies, relationships, important dates
2. Acknowledge relevant memories in your response
3. Apply dietary preferences as search keywords when delegating to restaurant_finder""",
    sub_agents=[restaurant_finder, generic_search],
    tools=[PreloadMemoryTool()],
    output_key="searched_restaurant_info",
    after_agent_callback=save_session_to_memory,
)
