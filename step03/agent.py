import json
from google.adk.agents import LlmAgent
from google.adk.tools import VertexAiSearchTool, google_search, ToolContext
from google.adk.tools.agent_tool import AgentTool

DATASTORE_ID = "projects/development-459201/locations/global/collections/default_collection/dataStores/yahoo-flea_1760456616324"


# ==========================================
# ツール定義 (Function Calling用)
# ==========================================

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


PREFECTURE_MAP = {
    "東京": "関東", "神奈川": "関東", "千葉": "関東", "埼玉": "関東",
    "大阪": "関西", "京都": "関西", "兵庫": "関西",
    "福岡": "九州",
    "北海道": "北海道",
    "沖縄": "沖縄"
}

# モックの料金表（サイズ一律、地域間距離に基づく想定）
MOCK_PRICING = {
    "same_region": 750,  # 同一地方内
    "different_region": 950,  # 異なる地方
    "remote": 1500  # 北海道・沖縄発着
}


def calculate_shipping_fee(
        origin_prefecture: str,
        destination_prefecture: str
) -> str:
    """
    発送元と配送先の都道府県に基づいて、Yahoo!フリマの推定送料を計算します。
    商品のサイズに関わらず、地域間の距離に基づいた料金を返します。

    Args:
        origin_prefecture: 発送元の都道府県名（例：'東京', '大阪'）「都」「府」「県」などを削除する必要ある。
        destination_prefecture: 配送先の都道府県名（例：'東京', '大阪'）「都」「府」「県」などを削除する必要ある。

    Returns:
        計算された送料(円）、適用ルールを含むJSON文字列。
    """
    # 2. 地方の取得（マッピングにない場合は 'other' とする）
    org_region = PREFECTURE_MAP.get(origin_prefecture, "other")
    dest_region = PREFECTURE_MAP.get(destination_prefecture, "other")

    fee = 0
    rule = ""

    # 3. 計算ロジック
    # 北海道または沖縄が含まれる場合
    if org_region in ["北海道", "沖縄"] or dest_region in ["北海道", "沖縄"]:
        fee = MOCK_PRICING["remote"]
        rule = "遠隔地料金（北海道・沖縄発着）"
    # 同一地方の場合
    elif org_region == dest_region and org_region != "other":
        fee = MOCK_PRICING["same_region"]
        rule = "同一地方料金"
    # それ以外の異なる地方
    else:
        fee = MOCK_PRICING["different_region"]
        rule = "地域間料金"

    # 4. 結果をJSON文字列として返す
    result = {
        "input": {
            "origin": origin_prefecture,
            "destination": destination_prefecture
        },
        "price": fee,
        "rule": rule
    }

    return json.dumps(result, ensure_ascii=False)


# ==========================================
# エージェント定義
# ==========================================


shipping_support_agent = LlmAgent(
    name="shipping_specialist",
    model="gemini-2.5-flash",
    description="配送関連の問い合わせ対応エージェント",
    instruction="""
    あなたはYahoo!フリマの配送関連エキスパートです。
    ヤフー！フリマに出品したい方をサポートします。
    """,
    # 定義した関数をtoolsリストに直接渡します
    tools=[calculate_shipping_fee]
)

seller_agent = LlmAgent(
    name="product_research_agent",
    model="gemini-2.5-flash",
    description="""
      Google検索を活用して、商品の適正価格（相場）の調査を支援するエージェント。
      """,
    instruction="""
          あなたは、Yahoo!フリマの出品者をサポートするAIエージェントです。
          Google検索を活用して商品情報をリサーチし、出品者の販売活動を支援してください。
          具体的には、Yahoo!フリマ内で類似商品がいくらで取引されているか（相場価格）を検索します。
          出品者は、商品画像をアップロードする場合もあれば、具体的な商品名をテキストで伝えてくる場合もあります。
          回答する際は、必ず参考にした情報源（リソースURL）もあわせて提示してください。
      """,
    tools=[google_search]
)

helper_agent = LlmAgent(
    name="vertex_search_agent",
    model="gemini-2.5-flash",
    instruction="""
    あなたはYahoo!フリマのヘルプデスクエージェントです。

    Yahoo!フリマのルール、手数料、使い方に関する質問には、**必ず**提供された Vertex AI Search ツールを使用して内部ドキュメントから回答を検索してください。

    **厳守事項:**
    1. 検索結果に基づき回答を作成し、必ず情報源（ソース）を引用してください。
    2. Yahoo!フリマに関連しない質問には回答しないでください。
    """,
    description="Vertex AI Searchを用いて公式ヘルプページを検索し回答するアシスタント",
    tools=[VertexAiSearchTool(data_store_id=DATASTORE_ID)]
)

research_tool = AgentTool(agent=seller_agent)
doc_qa_tool = AgentTool(agent=helper_agent)

# ========== Root Coordinator Agent ==========
root_agent = LlmAgent(
    name="root_agent",
    model="gemini-2.5-flash",
    instruction="""
    あなたはYahoo!フリマの総合案内AIエージェントです。購入者と出品者のサポートを行います。
    ユーザの売りたい商品は product_name の field に保存してください。
    ユーザーが現時点で売りたい値段または価格調査の結果を price の field に保存してください。
    配送料の結果は shipping_fee の field に保存してください。

    最終的に利益は {{ price? }}　 - {{ shipping_fee? }}　 の計算式で行ってくださ。
    """,
    global_instruction="""
    すべての回答は、自然で丁寧な日本語で行ってください。
    **重要:** お客様に対して、内部的に他のAIエージェントやツールが存在することは明かさず、あなた一人が対応しているように振る舞ってください（例：「リサーチ担当に聞きます」ではなく「お調べします」と言う）。
    """,
    tools=[research_tool, doc_qa_tool, append_to_state],
    sub_agents=[shipping_support_agent]
)
