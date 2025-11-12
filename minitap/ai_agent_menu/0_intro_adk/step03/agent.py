from google.adk.agents.llm_agent import LlmAgent

from step03.utils import get_weather, search_tool

weather_agent = LlmAgent(
    name="weather_agent",
    model="gemini-2.5-flash",
    description="特定の都市の天気情報を提供するエージェント",
    instruction="ユーザの問い合わせの都市の天気を教えてください",
    tools=[get_weather],
)


news_agent = LlmAgent(
    name="news_agent",
    model="gemini-2.5-flash",
    description="ニュースを提供するエージェント",
    instruction="問い合わせのトピックのニュースを３００文字程度で教えてください",
    tools=[search_tool],
)

root_agent = LlmAgent(
    name="root_agent",
    model="gemini-2.5-pro",
    description="メインコーディネーターエージェント",
    instruction="""
    あなたは代表エージェントです。
    ユーザーの問い合わせに対して専門家のエージェントにタスクをアサインしてください。
    ユーザにあなたのチームがどんなお手伝いできるのかを教えてください。
    """,
    sub_agents=[news_agent, weather_agent]
)
