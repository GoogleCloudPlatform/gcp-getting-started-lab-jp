import os
from pathlib import Path

import vertexai
from vertexai import types

PROJECT_ID = os.environ["PROJECT_ID"]
REGION = os.environ["REGION"]
BUCKET_NAME = os.environ["BUCKET_NAME"]
SERVICE_URL = os.environ["SERVICE_URL"]
RUN_INVOKER_SA = os.environ["RUN_INVOKER_SA"]

MCP_URL = SERVICE_URL.rstrip("/") + "/mcp"

class ItSupportMcpAgent:
    """Agent Runtime 上で動く、最小の MCP client agent。

    Cloud Run の認証には ID token が必要です。
    Agent Runtime では metadata server の identity endpoint が使えない場合があるため、
    google.oauth2.id_token.fetch_id_token() は使いません。

    代わりに、Agent Identity に Token Creator を許可した専用サービスアカウントを
    IAM Credentials API で impersonate し、Cloud Run 用 ID token を発行します。
    """

    def __init__(self, mcp_url: str, audience: str, invoker_sa: str):
        self.mcp_url = mcp_url
        self.audience = audience
        self.invoker_sa = invoker_sa

    def _get_cloud_run_id_token(self) -> str:
        from google.cloud import iam_credentials_v1

        # Agent Identity の認証情報は Google Cloud クライアントライブラリ経由で使用します。
        # raw requests で IAMCredentials API を叩くと、Agent Identity の認証コンテキストが
        # 正しく扱われず 401 Unauthorized になる場合があります。
        client = iam_credentials_v1.IAMCredentialsClient()
        response = client.generate_id_token(
            name=f"projects/-/serviceAccounts/{self.invoker_sa}",
            audience=self.audience,
            include_email=True,
        )
        return response.token

    async def _call_mcp_async(self, tool_name: str, args: dict):
        from mcp.client.session import ClientSession
        from mcp.client.streamable_http import streamablehttp_client

        token = self._get_cloud_run_id_token()
        headers = {"Authorization": f"Bearer {token}"}

        async with streamablehttp_client(self.mcp_url, headers=headers) as streams:
            read_stream, write_stream, _ = streams

            async with ClientSession(read_stream, write_stream) as session:
                await session.initialize()
                result = await session.call_tool(tool_name, arguments=args)

                texts = []
                for content in result.content:
                    text = getattr(content, "text", None)
                    if text is not None:
                        texts.append(text)
                    else:
                        texts.append(str(content))

                return texts

    def _call_mcp(self, tool_name: str, args: dict):
        """Agent Runtime の既存 event loop と衝突しないよう、別スレッドで async MCP client を実行する。"""
        import asyncio
        from concurrent.futures import ThreadPoolExecutor

        def runner():
            return asyncio.run(self._call_mcp_async(tool_name, args))

        with ThreadPoolExecutor(max_workers=1) as executor:
            future = executor.submit(runner)
            return future.result()

    def query(self, input=None, **kwargs):
        payload = input if isinstance(input, dict) else kwargs

        tool_name = payload.get("tool_name")
        args = payload.get("args", {})

        if not tool_name:
            return {
                "ok": False,
                "error": "tool_name is required",
                "example": {
                    "tool_name": "get_system_status",
                    "args": {"service_name": "経費精算システム"},
                },
            }

        try:
            result = self._call_mcp(tool_name, args)
            return {
                "ok": True,
                "tool_name": tool_name,
                "args": args,
                "result": result,
            }
        except Exception as exc:
            return {
                "ok": False,
                "tool_name": tool_name,
                "args": args,
                "error": str(exc),
            }

client = vertexai.Client(
    project=PROJECT_ID,
    location=REGION,
    http_options={"api_version": "v1beta1"},
)

print("Agent Runtime に Agent Identity 付き agent をデプロイします。")
print(f"MCP_URL={MCP_URL}")
print(f"RUN_INVOKER_SA={RUN_INVOKER_SA}")

remote_app = client.agent_engines.create(
    agent=ItSupportMcpAgent(
        mcp_url=MCP_URL,
        audience=SERVICE_URL,
        invoker_sa=RUN_INVOKER_SA,
    ),
    config={
        "display_name": "it-support-agent-with-identity",
        "identity_type": types.IdentityType.AGENT_IDENTITY,
        "requirements": [
            "google-cloud-aiplatform",
            "mcp",
            "google-auth",
            "google-cloud-iam",
            "requests",
            "httpx",
            "cloudpickle",
            "pydantic",
        ],
        "staging_bucket": f"gs://{BUCKET_NAME}",
        "env_vars": {
            "GOOGLE_CLOUD_AGENT_ENGINE_ENABLE_TELEMETRY": "true"
        },
    },
)

engine_name = remote_app.api_resource.name
engine_id = engine_name.split("/")[-1]
effective_identity = remote_app.api_resource.spec.effective_identity

Path("agent_engine_id.txt").write_text(engine_id)
Path("agent_engine_name.txt").write_text(engine_name)
Path("agent_principal.txt").write_text(effective_identity)

print("\nAgent Runtime created.")
print(f"ENGINE_NAME={engine_name}")
print(f"ENGINE_ID={engine_id}")
print(f"AGENT_PRINCIPAL={effective_identity}")
print("\n次のラボで、この AGENT_PRINCIPAL に Token Creator を付与します。")
