"""
Runner for the Restaurant Agent.

The Runner is the "heart" of your agent system. It:
- Binds the Agent to a User and Session
- Executes the Event Loop
- Manages state transitions
- Connects to Session and Memory services
"""
import os
from typing import Optional

from dotenv import load_dotenv
from google.adk.agents import Agent
from google.adk.runners import Runner
from google.adk.memory import VertexAiMemoryBankService
from google.adk.sessions import VertexAiSessionService
from google.genai import types

load_dotenv()

GOOGLE_CLOUD_PROJECT = os.getenv("GOOGLE_CLOUD_PROJECT")
GOOGLE_CLOUD_LOCATION = os.getenv("GOOGLE_CLOUD_LOCATION")
AGENT_ENGINE_ID = os.getenv("AGENT_ENGINE_ID")


class RestaurantRunner:
    """Wrapper around ADK Runner with Vertex AI session and memory services."""

    def __init__(
        self,
        agent: Agent,
        user_id: str = "user",
        session_id: Optional[str] = None
    ):
        self.agent = agent
        self.user_id = user_id
        self._session_id = session_id

        # TODO: Initialize VertexAiSessionService
        # This service handles short-term memory (conversation context).
        # It should use:
        # - project=GOOGLE_CLOUD_PROJECT
        # - location=GOOGLE_CLOUD_LOCATION
        # - agent_engine_id=AGENT_ENGINE_ID
        self.session_service = None  # REPLACE THIS

        # TODO: Initialize VertexAiMemoryBankService
        # This service handles long-term memory (user preferences, facts).
        # It should use the same project, location, and agent_engine_id.
        self.memory_service = None  # REPLACE THIS

        # TODO: Create the ADK Runner
        # The Runner connects everything together:
        # - app_name: Use self.agent.name
        # - agent: The agent to run
        # - session_service: For short-term memory
        # - memory_service: For long-term memory
        self.runner = None  # REPLACE THIS

    async def get_session(self):
        """Get existing session or create a new one."""
        if self._session_id:
            try:
                session = await self.session_service.get_session(
                    app_name=self.agent.name,
                    user_id=self.user_id,
                    session_id=self._session_id,
                )
                if session:
                    self._session_id = session.id
                    return session
            except Exception as e:
                print(f"Error retrieving session {self._session_id}: {e}")

        # Create new session
        session = await self.session_service.create_session(
            app_name=self.agent.name,
            user_id=self.user_id,
        )
        self._session_id = session.id
        return session

    async def call_agent(self, query: str) -> Optional[str]:
        """Send a query to the agent and return the response."""
        session = await self.get_session()
        content = types.Content(role="user", parts=[types.Part(text=query)])

        events = self.runner.run(
            user_id=session.user_id,
            session_id=session.id,
            new_message=content,
        )

        for event in events:
            if event.is_final_response():
                response = event.content.parts[0].text
                print(f"\nAgent Response: {response}")
                return response

        return None
