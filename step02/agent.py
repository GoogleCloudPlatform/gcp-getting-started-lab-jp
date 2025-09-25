from google.adk.agents.llm_agent import LlmAgent
from google.adk.tools import google_search
from google.adk.tools.agent_tool import AgentTool


# 天気情報取得関数
def get_weather(city: str) -> dict:
    """指定された都市の現在の天気予報を取得します。

    Args:
        city (str): 都市名（例：「ニューヨーク」、「ロンドン」、「東京」）。

    Returns:
        dict: 天気情報を含む辞書。
              'status' キー（'success' または 'error'）を含みます。
              'success' の場合、天気の詳細情報を持つ 'report' キーを含みます。
              'error' の場合、'error_message' キーを含みます。
    """

    mock_weather_db = {
        "ニューヨーク": {"status": "success", "report": "ニューヨークの天気は晴れ、気温は25℃です。"},
        "ロンドン": {"status": "success", "report": "ロンドンは曇り、気温は15℃です。"},
        "東京": {"status": "success", "report": "東京は小雨、気温は18℃です。"},
    }

    if city in mock_weather_db:
        return mock_weather_db[city]
    else:
        return {"status": "error", "error_message": f"申し訳ありませんが、「{city}」の天気情報はありません。"}


weather_agent = LlmAgent(
    name="weather_agent",
    model="gemini-2.5-flash",
    description="特定の都市の天気情報を提供するエージェント",
    instruction="ユーザの問い合わせの都市の天気を教えてください",
    tools=[get_weather],
)

search_agent = LlmAgent(
    name="search_agent",
    model="gemini-2.5-flash",
    description="""
    検索エージェント
    """,
    instruction="""
    Google 検索を使って問い合わせのトピックに関してのニュースを教えてください。
    """,
    tools=[google_search]
)

news_tool = AgentTool(agent=search_agent)

news_agent = LlmAgent(
    name="news_agent",
    model="gemini-2.5-flash",
    description="最近のニュースを提供するエージェント",
    instruction="最近のニュースを教えてください。関心のニュース {{ favorite_topic? }} があれば、それのみ教えてください。",
    tools=[news_tool],
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
