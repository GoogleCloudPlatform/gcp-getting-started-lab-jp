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
GOOGLE_CLOUD_LOCATION = os.getenv("GOOGLE_CLOUD_DEPLOY_LOCATION", "global")
GOOGLE_CLOUD_DEPLOY_LOCATION = os.getenv("GOOGLE_CLOUD_DEPLOY_LOCATION", "us-central1")
AGENT_DISPLAY_NAME = "restaurant_agent_codelab"

if not GOOGLE_CLOUD_PROJECT:
    raise ValueError("GOOGLE_CLOUD_PROJECT not found in environment variables.")


def create_agent_engine():
    """
    Registers an Agent Engine resource in Vertex AI to enable Sessions and Memory Bank.
    This does NOT deploy the agent code to the cloud - it just provisions the infrastructure.
    """
    # Initialize Vertex AI
    logger.info(f"Initializing Vertex AI for project: {GOOGLE_CLOUD_PROJECT}, location: {GOOGLE_CLOUD_DEPLOY_LOCATION}")
    vertexai.init(project=GOOGLE_CLOUD_PROJECT, location=GOOGLE_CLOUD_DEPLOY_LOCATION)
    client = vertexai.Client(project=GOOGLE_CLOUD_PROJECT, location=GOOGLE_CLOUD_DEPLOY_LOCATION)

    logger.info(f"Creating/Registering Agent Engine: {AGENT_DISPLAY_NAME}")

    # Create Agent Engine with Memory Bank configuration
    agent_engine = client.agent_engines.create(
        config={
            "display_name": AGENT_DISPLAY_NAME,
            "context_spec": {
                "memory_bank_config": {
                    "generation_config": {
                        "model": f"projects/{GOOGLE_CLOUD_PROJECT}/locations/{GOOGLE_CLOUD_LOCATION}/publishers/google/models/gemini-2.5-pro"
                    },
                }
            },
        }
    )

    # Extract the ID and print instructions
    agent_engine_id = agent_engine.api_resource.name.split("/")[-1]
    logger.info("Agent Engine Created Successfully!")
    logger.info(f"Agent Engine ID: {agent_engine_id}")

if __name__ == "__main__":
    try:
        create_agent_engine()
    except Exception as e:
        logger.error(f"Failed to create Agent Engine: {e}")
