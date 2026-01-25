"""
Deploy Agent Engine to Vertex AI.

The Agent Engine is the managed infrastructure that:
- Stores and manages user sessions
- Provides the Memory Bank vector database
- Handles memory extraction and retrieval
- Scales automatically based on demand

Run this script once to create your Agent Engine, then add the
AGENT_ENGINE_ID to your .env file.
"""
import os
import logging
from dotenv import load_dotenv
import vertexai

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

load_dotenv()

GOOGLE_CLOUD_PROJECT = os.getenv("GOOGLE_CLOUD_PROJECT")
GOOGLE_CLOUD_LOCATION = os.getenv("GOOGLE_CLOUD_LOCATION", "us-central1")
AGENT_DISPLAY_NAME = "restaurant_agent_codelab"

if not GOOGLE_CLOUD_PROJECT:
    raise ValueError("GOOGLE_CLOUD_PROJECT not found in environment variables.")


def register_agent_engine():
    """
    Registers an Agent Engine resource in Vertex AI to enable Sessions and Memory Bank.
    This does NOT deploy the agent code to the cloud - it just provisions the infrastructure.
    """

    # TODO: Initialize Vertex AI
    # Use vertexai.init() with project and location
    # Then create a client with vertexai.Client()
    # REPLACE_INIT_VERTEXAI

    logger.info(f"Creating/Registering Agent Engine: {AGENT_DISPLAY_NAME}")

    # TODO: Create Agent Engine with Memory Bank configuration
    # The agent_engine should be created with:
    # - display_name: AGENT_DISPLAY_NAME
    # - context_spec with memory_bank_config
    # - generation_config with the Gemini model path
    #
    # Example structure:
    # agent_engine = client.agent_engines.create(
    #     config={
    #         "display_name": AGENT_DISPLAY_NAME,
    #         "context_spec": {
    #             "memory_bank_config": {
    #                 "generation_config": {
    #                     "model": f"projects/{PROJECT}/locations/{LOCATION}/publishers/google/models/gemini-2.5-flash"
    #                 },
    #             }
    #         },
    #     }
    # )
    # REPLACE_CREATE_AGENT_ENGINE

    # After creating, extract the ID and print instructions
    # agent_engine_id = agent_engine.api_resource.name.split("/")[-1]
    # logger.info("Agent Engine Registered Successfully!")
    # logger.info(f"Agent Engine ID: {agent_engine_id}")
    # logger.info("\nIMPORTANT: Add the following line to your .env file:")
    # logger.info(f"AGENT_ENGINE_ID={agent_engine_id}")

    pass  # Remove this line after implementing


if __name__ == "__main__":
    try:
        register_agent_engine()
    except Exception as e:
        logger.error(f"Failed to register Agent Engine: {e}")
