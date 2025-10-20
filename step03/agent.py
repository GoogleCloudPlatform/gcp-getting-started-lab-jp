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
    description="最近のニュースを提供するエージェント",
    instruction="最近のニュースを教えてください。関心のニュース {{ favorite_topic? }} があれば、それのみ教えてください。",
    tools=[search_tool],
)

root_agent = LlmAgent(
    name="root_agent",
    model="gemini-2.5-flash",
    description="メインコーディネーターエージェント",
    instruction="""
    あなたは親切なニュースキャスターです。
    ユーザーの問い合わせに対して専門家のエージェントにタスクをアサインしてください。
    ユーザにあなたのチームがどんなお手伝いできるのかを教えてください。
    """,
    sub_agents=[news_agent, weather_agent]
)
