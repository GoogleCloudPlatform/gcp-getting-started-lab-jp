from google.adk.agents.llm_agent import LlmAgent
from google.adk.tools.tool_context import ToolContext

def get_weather_stateful(city: str, tool_context: ToolContext) -> dict:
    """指定された都市の現在の天気予報を取得します、セッションの状態に基づいて温度の単位を変換します。

    Args:
        city (str): 日本語での都市名（例：「ニューヨーク」、「ロンドン」、「東京」）。
        tool_context (ToolContext): ツール呼び出しのコンテキストを提供し、呼び出しコンテキスト、関数呼び出しID、イベントアクション、認証レスポンスへのアクセスを含みます。

    Returns:
        dict: 天気情報を含む辞書。
              'status' キー（'success' または 'error'）を含みます。
              'success' の場合、天気の詳細情報を持つ 'report' キーを含みます。
              'error' の場合、'error_message' キーを含みます。
    """

    print(f"--- ツール: get_weather_stateful が {city} のために呼び出されました ---")

    # --- 状態から設定を読み込み ---
    preferred_unit = tool_context.state.get("user_preference_temperature_unit", "Celsius")
    print(f"--- ツール: 状態 'user_preference_temperature_unit' を読み込み中: {preferred_unit} ---")


    # モックの天気データ（内部では常に摂氏で保存）
    mock_weather_db = {
        "ニューヨーク": {"temp_c": 25, "condition": "晴れ"},
        "ロンドン": {"temp_c": 15, "condition": "曇り"},
        "東京": {"temp_c": 18, "condition": "雨"},
    }

    if city in mock_weather_db:
        data = mock_weather_db[city]
        temp_c = data["temp_c"]
        condition = data["condition"]

        if preferred_unit == "Fahrenheit":
            temp_value = (temp_c * 9/5) + 32
            temp_unit = "°F"
        else:
            temp_value = temp_c
            temp_unit = "°C"

        report = f"{city.capitalize()}の天気は{condition}で、気温は{temp_value:.0f}{temp_unit}です。"
        result = {"status": "success", "report": report}
        print(f"--- ツール: {preferred_unit}でレポートを生成しました。結果: {result} ---")
        return result
    else:
        # 都市が見つからない場合の処理
        error_msg = f"申し訳ありませんが、'{city}'の天気情報はありません。"
        print(f"--- ツール: 都市 '{city}' が見つかりませんでした。 ---")
        return {"status": "error", "error_message": error_msg}

def set_temperature_preference(unit: str, tool_context: ToolContext) -> dict:
    """Sets the user's preferred temperature unit (Celsius or Fahrenheit).

    Args:
        unit (str): The preferred temperature unit ("Celsius" or "Fahrenheit").
        tool_context (ToolContext): The ADK tool context providing access to session state.

    Returns:
        dict: A dictionary confirming the action or reporting an error.
    """
    print(f"--- Tool: set_temperature_preference called with unit: {unit} ---")
    normalized_unit = unit.strip().capitalize()

    if normalized_unit in ["Celsius", "Fahrenheit"]:
        tool_context.state["user_preference_temperature_unit"] = normalized_unit
        print(f"--- Tool: Updated state 'user_preference_temperature_unit': {normalized_unit} ---")
        return {"status": "success", "message": f"Temperature preference set to {normalized_unit}."}
    else:
        error_msg = f"Invalid temperature unit '{unit}'. Please specify 'Celsius' or 'Fahrenheit'."
        print(f"--- Tool: Invalid unit provided: {unit} ---")
        return {"status": "error", "error_message": error_msg}

# ルートエージェントを作成する前に前提条件を確認
root_agent_stateful = LlmAgent(
    name="weather_agent_v3_stateful", # 新しいバージョン名
    model="gemini-2.5-flash",
    description="メインエージェント: 天気情報を提供し（状態認識ユニット）、挨拶/別れを委任し、レポートを状態に保存します。",
    instruction="あなたはメインの天気エージェントです。あなたの仕事は 'get_weather_stateful' を使って天気情報を提供することです。"
                "このツールは、状態に保存されているユーザーの好みに基づいて温度の形式を設定します。"
                "簡単な挨拶は 'greeting_agent' に、別れの挨拶は 'farewell_agent' に委任してください。"
                "天気に関するリクエスト、挨拶、別れの挨拶のみを処理してください。",
    tools=[get_weather_stateful,set_temperature_preference],
    output_key="last_weather_report" # <<< エージェントの最終的な天気応答を自動保存
)