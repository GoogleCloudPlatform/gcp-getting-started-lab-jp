import os
from dotenv import load_dotenv
from google.adk.agents.callback_context import CallbackContext
from google.adk.models import LlmResponse, LlmRequest
from google.adk.agents.llm_agent import LlmAgent

import vertexai
from vertexai import agent_engines

load_dotenv()
GOOGLE_CLOUD_PROJECT = os.getenv("GOOGLE_CLOUD_PROJECT")
LOCATION = os.getenv("LOCATION")

AGENT_ID = "7776190434329493504"

vertexai.init(project=GOOGLE_CLOUD_PROJECT, location=LOCATION)
remote_agent = agent_engines.get(AGENT_ID)

async def call_remote_agent(
    callback_context: CallbackContext, llm_request: LlmRequest
) -> LlmResponse:
    session = remote_agent.create_session(user_id='default_user')
    events = remote_agent.stream_query(
                user_id='default_user',
                session_id=session['id'],
                message=str(llm_request.contents)
             )
    content = list(events)[-1]['content']
    remote_agent.delete_session(
        user_id='default_user',
        session_id=session['id'],
    )
    return LlmResponse(content=content)

root_agent = LlmAgent(
    name='remote_agent_proxy',
    model='gemini-2.5-flash', # not used
    description='Interactive agent',
    before_model_callback=call_remote_agent,
)