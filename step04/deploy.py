import vertexai
import os
from dotenv import load_dotenv
from vertexai import agent_engines
from vertexai.preview.reasoning_engines import AdkApp
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

load_dotenv()

GOOGLE_CLOUD_PROJECT = os.getenv("GOOGLE_CLOUD_PROJECT")
LOCATION = os.getenv("LOCATION")
STAGING_BUCKET = os.getenv("STAGING_BUCKET")

vertexai.init(
    project=GOOGLE_CLOUD_PROJECT,
    location=LOCATION,
    staging_bucket=STAGING_BUCKET,
)

app = AdkApp(
    agent=root_agent,
    enable_tracing=True,
)

remote_agent = agent_engines.create(
    app,
    requirements=[
        'google-adk==1.4.1',
        'google-cloud-aiplatform==1.97.0',
        'google-genai==1.20.0'
    ],
    display_name="My Agent",
    description="Agent Engine workshop sample",
)
