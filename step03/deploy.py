import vertexai
import os
from dotenv import load_dotenv
from vertexai import agent_engines
from vertexai.preview.reasoning_engines import AdkApp
from agent import root_agent as agent

load_dotenv()

GOOGLE_CLOUD_PROJECT = os.getenv("GOOGLE_CLOUD_PROJECT")
LOCATION = os.getenv("LOCATION")
STAGING_BUCKET = os.getenv("STAGING_BUCKET")

vertexai.init(
    project=GOOGLE_CLOUD_PROJECT,
    location=LOCATION,
    staging_bucket=STAGING_BUCKET,
)

app = AdkApp(
    agent=agent,
    enable_tracing=True,
)

remote_agent = agent_engines.create(
    app,
    requirements=[
        'google-adk==1.4.1',
        'google-cloud-aiplatform==1.97.0',
        'google-genai==1.20.0'
    ],
    display_name="My Agent",
    description="Agent Engine workshop sample",
)
