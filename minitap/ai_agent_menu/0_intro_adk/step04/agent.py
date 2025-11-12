from google.adk.agents.llm_agent import LlmAgent
from .utils import get_weather, search_tool, append_to_state

weather_agent = LlmAgent(
    name="weather_agent",
    model="gemini-2.5-flash",
    description="特定の都市の天気情報を提供するエージェント",
    instruction="ユーザの問い合わせの都市の天気または現在住んでいる都市の情報 {{ current_city? }}　の情報があれば教えてください",
    tools=[get_weather],
)

news_agent = LlmAgent(
    name="news_agent",
    model="gemini-2.5-flash",
    description="ニュースを提供するエージェント",
    instruction="問い合わせのトピックのニュースを３００文字程度で教えてください。関心のトピック {{ favorite_topic? }} があれば、それを教えてください。",
    tools=[search_tool],
)

root_agent = LlmAgent(
    name="root_agent",
    model="gemini-2.5-flash",
    description="メインコーディネーターエージェント",
    instruction="""
    あなたは代表エージェントです。

    ユーザの興味あるニュースは favorite_topic の field に保存してください。
    ユーザの現在いる街は current_city の field に保存してください
    
    ユーザにあなたのチームがどんなお手伝いできるのかを教えてください。
    ユーザーの問い合わせに対して専門家のエージェントにタスクをアサインしてください。
    """,
    sub_agents=[news_agent, weather_agent],
    tools=[append_to_state]
)
