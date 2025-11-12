from google.adk.agents.llm_agent import LlmAgent

root_agent = LlmAgent(
    name="hello_world",
    model="gemini-2.5-flash",
    description="ユーザに挨拶するエージェント",
    instruction="ユーザーに丁寧に挨拶してください"
)
