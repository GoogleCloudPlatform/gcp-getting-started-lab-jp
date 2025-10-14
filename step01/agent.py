import json
from google.adk.agents import LlmAgent
from google.adk.tools import google_search

root_agent = LlmAgent(
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

# ==========================================
# 1. モックデータベースとヘルパーデータ
# ==========================================

# 都道府県を地方にマッピング（デモ用の簡易版）
# 実際の入力（「東京都」や「東京」）に対応できるように正規化ロジックを関数内に入れます。
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


# ==========================================
# 2. ツール定義 (Function Calling用)
# ==========================================

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
        "rule" : rule
    }

    return json.dumps(result, ensure_ascii=False)


# ==========================================
# 3. エージェント定義
# ==========================================


# root_agent = LlmAgent(
#     name="shipping_specialist",
#     model="gemini-2.5-flash",
#     description="出品・配送関連の問い合わせ対応エージェント",
#     instruction="""
#     あなたはYahoo!フリマの出品・配送関連エキスパートです。
#     ヤフー！フリマに出品したい方をサポートします。
#     """,
#     # 定義した関数をtoolsリストに直接渡します
#     tools=[calculate_shipping_fee]
# )