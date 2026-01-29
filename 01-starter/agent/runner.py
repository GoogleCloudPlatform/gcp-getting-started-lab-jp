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
GOOGLE_CLOUD_DEPLOY_LOCATION = os.getenv("GOOGLE_CLOUD_DEPLOY_LOCATION")
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

        # Initialize Vertex AI Session Service
        # This handles short-term memory (conversation context)
        self.session_service = VertexAiSessionService(
            project=GOOGLE_CLOUD_PROJECT,
            location=GOOGLE_CLOUD_DEPLOY_LOCATION,
            agent_engine_id=AGENT_ENGINE_ID,
        )

        # Initialize Vertex AI Memory Bank Service
        # This handles long-term memory (user preferences, facts)
        self.memory_service = VertexAiMemoryBankService(
            project=GOOGLE_CLOUD_PROJECT,
            location=GOOGLE_CLOUD_DEPLOY_LOCATION,
            agent_engine_id=AGENT_ENGINE_ID,
        )

        # Create the ADK Runner
        # The Runner connects the agent to session and memory services
        self.runner = Runner(
            app_name=self.agent.name,
            agent=self.agent,
            session_service=self.session_service,
            memory_service=self.memory_service,
        )

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
