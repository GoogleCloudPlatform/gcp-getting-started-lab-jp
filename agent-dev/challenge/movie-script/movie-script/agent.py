import os
from dotenv import load_dotenv

from google.adk import Agent
from google.adk.agents.llm_agent import LlmAgent
from google.adk.agents import SequentialAgent, LoopAgent, ParallelAgent
from google.adk.tools.tool_context import ToolContext
from google.adk.tools.langchain_tool import LangchainTool  # import
from google.adk.tools.crewai_tool import CrewaiTool
from google.genai import types

from langchain_community.tools import WikipediaQueryRun
from langchain_community.utilities import WikipediaAPIWrapper
from crewai_tools import FileWriterTool

load_dotenv()

model_name = os.getenv("MODEL")

def append_to_state(
        tool_context: ToolContext, field: str, response: str
) -> dict[str, str]:
    """Append new output to an existing state key.

    Args:
        field (str): a field name to append to
        response (str): a string to append to the field

    Returns:
        dict[str, str]: {"status": "success"}
    """
    existing_state = tool_context.state.get(field, [])
    tool_context.state[field] = existing_state + [response]
    return {"status": "success"}


# Agents
screenwriter = Agent(
    name="screenwriter",
    model=model_name,
    description="As a screenwriter, write a logline and plot outline for a biopic about a historical character.",
    instruction="""

    """,
    generate_content_config=types.GenerateContentConfig(
        temperature=0,
    ),
    tools=[append_to_state],
)

researcher = Agent(
    name="researcher",
    model=model_name,
    description="Answer research questions using Wikipedia.",
    instruction="""
    """,
    generate_content_config=types.GenerateContentConfig(
        temperature=0,
    ),
    tools=[
        LangchainTool(tool=WikipediaQueryRun(api_wrapper=WikipediaAPIWrapper())),
        append_to_state,
    ],
)

critic = Agent(
    name="critic",
    model=model_name,
    description="Reviews the outline so that it can be improved.",
    instruction="""

    """,
    tools=[append_to_state],
)

writers_room = LoopAgent(
    name="writers_room",
    description="Iterates through research and writing to improve a movie plot outline.",
    sub_agents=[
        researcher,
        screenwriter,
        critic
    ],
    max_iterations=3,
)

file_writer = Agent(
    name="file_writer",
    model=model_name,
    description="Creates marketing details and saves a pitch document.",
    instruction="""

    """,
    generate_content_config=types.GenerateContentConfig(
        temperature=0,
    ),
    tools=[
        CrewaiTool(
            name="file_writer_tool",
            description=("Writes a file to disk"),
            tool=FileWriterTool(),
        )
    ],
)


film_concept_team = SequentialAgent(
    name="film_concept_team",
    description="Write a film plot outline and save it as a text file.",
    sub_agents=[
        writers_room,
        file_writer
    ],
)

root_agent = LlmAgent(
    name="greeter",
    model=model_name,
    description="Guides the user in crafting a movie plot.",
    instruction="""
   
   """,
    global_instruction= "Respond in Japanese",
    generate_content_config=types.GenerateContentConfig(
        temperature=0,
    ),
    tools=[append_to_state],
    sub_agents=[film_concept_team],
)