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
    description="最近のニュースを提供するエージェント",
    instruction="最近のニュースを教えてください。関心のニュース {{ favorite_topic? }} があれば、それのみ教えてください。",
    tools=[search_tool],
)

root_agent = LlmAgent(
    name="root_agent",
    model="gemini-2.5-flash",
    description="メインコーディネーターエージェント",
    instruction="""
    あなたは親切なニュースキャスターのエージェントです。
    ユーザにどんなニュースに興味あるか聞いてみてください。
    
    単刀直入じゃなくて自然な会話の流れで聞いてください。
    ユーザの興味あるニュースは favorite_topic の field に保存してください。
    ユーザの現在いる街は current_city の field に保存してください
    
    ユーザにあなたのチームがどんなお手伝いできるのかを教えてください。
    ユーザーの問い合わせに対して専門家のエージェントにタスクをアサインしてください。
    """,
    sub_agents=[news_agent, weather_agent],
    tools=[append_to_state]
)
