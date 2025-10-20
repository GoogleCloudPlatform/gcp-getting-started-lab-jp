from google.adk.agents import LlmAgent
from google.adk.tools.agent_tool import AgentTool
from google.adk.tools import google_search
from google.adk.tools.tool_context import ToolContext


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
