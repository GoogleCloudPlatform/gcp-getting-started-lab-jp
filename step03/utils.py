# 天気情報取得関数
from google.adk.agents import LlmAgent
from google.adk.tools import google_search
from google.adk.tools.agent_tool import AgentTool


def get_weather(city: str) -> dict:
    """指定された都市の現在の天気予報を取得します。

    Args:
        city (str): 都市名（例：new_york, london, tokyo）。

    Returns:
        dict: 天気情報を含む辞書。
              'status' キー（'success' または 'error'）を含みます。
              'success' の場合、天気の詳細情報を持つ 'report' キーを含みます。
              'error' の場合、'error_message' キーを含みます。
    """

    mock_weather_db = {
        "new_york": {"status": "success", "report": "ニューヨークの天気は晴れ、気温は25℃です。"},
        "london": {"status": "success", "report": "ロンドンは曇り、気温は15℃です。"},
        "tokyo": {"status": "success", "report": "東京は小雨、気温は18℃です。"},
    }

    if city in mock_weather_db:
        return mock_weather_db[city]
    else:
        return {"status": "error", "error_message": f"申し訳ありませんが、「{city}」の天気情報はありません。"}


search_agent = LlmAgent(
    name="search_agent",
    model="gemini-2.5-flash",
    description="""
    検索エージェント
    """,
    instruction="""
    問い合わせのトピックに関して　Google 検索を使って教えてください。
    """,
    tools=[google_search]
)

search_tool = AgentTool(agent=search_agent)
