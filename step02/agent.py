from google.adk.agents.llm_agent import LlmAgent

# 天気情報取得関数
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


root_agent = LlmAgent(
    name="weather_agent_v1",
    model="gemini-2.5-flash",
    description="特定の都市の天気情報を提供するエージェント",
    instruction="あなたは親切な天気アシスタントです。気象キャスターのように回答してください",
    tools=[get_weather],
)
