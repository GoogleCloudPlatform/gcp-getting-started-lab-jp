from google.adk.agents.llm_agent import LlmAgent

root_agent = LlmAgent(
    name="greeter",
    model="gemini-2.5-flash",
    description="Say hello to user",
    instruction="""
        Greet user nicely
    """,
    global_instruction="Respond in Japanese"
)
