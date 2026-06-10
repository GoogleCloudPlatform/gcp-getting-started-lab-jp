import asyncio
import logging
import os
from typing import Any, Dict

import requests
import sqlalchemy
from fastmcp import FastMCP
from google.auth import default as google_auth_default
from google.auth.transport.requests import Request
from google.cloud.sql.connector import Connector

logging.basicConfig(
    level=logging.INFO,
    format="[%(levelname)s] %(asctime)s %(message)s",
)
logger = logging.getLogger("it-support-mcp")

PROJECT_ID = os.environ["PROJECT_ID"]
REGION = os.environ["REGION"]
INSTANCE_CONNECTION_NAME = os.environ["INSTANCE_CONNECTION_NAME"]
DB_NAME = os.environ.get("DB_NAME", "company_data")
DB_USER = os.environ.get("DB_USER", "postgres")
DB_PASS = os.environ["DB_PASS"]
MODEL_ARMOR_TEMPLATE = os.environ.get("MODEL_ARMOR_TEMPLATE", "")
MODEL_ARMOR_FAIL_OPEN = os.environ.get("MODEL_ARMOR_FAIL_OPEN", "false").lower() == "true"

# ハンズオンの再現性を高めるため、Model Armor に加えて簡易 business guard も入れます。
# 実システムでは、ここを自社ポリシーに合わせて調整します。
BLOCKED_KEYWORDS = [
    "dump",
    "password",
    "passwd",
    "credential",
    "secret",
    "全テーブル",
    "パスワード",
    "認証情報",
    "秘密情報",
    "機密情報を全部",
    "ignore previous",
    "以前の指示を無視",
]

connector = Connector()

def getconn():
    return connector.connect(
        INSTANCE_CONNECTION_NAME,
        "pg8000",
        user=DB_USER,
        password=DB_PASS,
        db=DB_NAME,
    )

pool = sqlalchemy.create_engine(
    "postgresql+pg8000://",
    creator=getconn,
    pool_pre_ping=True,
    pool_size=2,
    max_overflow=2,
)

mcp = FastMCP("IT Support MCP Server")

def _get_access_token() -> str:
    credentials, _ = google_auth_default(scopes=["https://www.googleapis.com/auth/cloud-platform"])
    credentials.refresh(Request())
    return credentials.token

def _local_business_guard(text: str) -> None:
    lowered = text.lower()
    for keyword in BLOCKED_KEYWORDS:
        if keyword.lower() in lowered:
            raise PermissionError(
                f"セキュリティポリシーによりブロックしました。検出キーワード: {keyword}"
            )

def _model_armor_guard(text: str, tool_name: str) -> Dict[str, Any]:
    if not MODEL_ARMOR_TEMPLATE:
        logger.warning("MODEL_ARMOR_TEMPLATE is not set. Skipping Model Armor.")
        return {"skipped": True, "reason": "MODEL_ARMOR_TEMPLATE is empty"}

    url = (
        f"https://modelarmor.{REGION}.rep.googleapis.com/v1/"
        f"projects/{PROJECT_ID}/locations/{REGION}/templates/{MODEL_ARMOR_TEMPLATE}:sanitizeUserPrompt"
    )

    payload = {
        "userPromptData": {
            "text": f"tool={tool_name}\ninput={text}"
        }
    }

    headers = {
        "Content-Type": "application/json",
        "Authorization": f"Bearer {_get_access_token()}",
    }

    response = requests.post(url, json=payload, headers=headers, timeout=15)
    response.raise_for_status()

    body = response.json()
    result = body.get("sanitizationResult", {})
    match_state = result.get("filterMatchState", "UNKNOWN")
    invocation_result = result.get("invocationResult", "UNKNOWN")

    logger.info(
        "Model Armor result: tool=%s match_state=%s invocation_result=%s",
        tool_name,
        match_state,
        invocation_result,
    )

    if match_state == "MATCH_FOUND":
        logger.warning(
            "Model Armor detected a match, but this hands-on keeps processing. "
            "Business guard remains the hard block for prohibited operations."
        )

    return body

def enforce_input_policy(text: str, tool_name: str) -> None:
    try:
        # Hard block は業務ルールで行います。
        # Model Armor は環境やフィルタ更新により正常な日本語入力でも MATCH_FOUND になる場合があるため、
        # このハンズオンでは検知ログとして扱います。
        _local_business_guard(text)
        _model_armor_guard(text, tool_name)
    except PermissionError:
        raise
    except Exception as exc:
        logger.exception("Model Armor check failed.")
        if MODEL_ARMOR_FAIL_OPEN:
            logger.warning("MODEL_ARMOR_FAIL_OPEN=true のため処理を継続します。")
            return
        raise RuntimeError(f"Model Armor check failed: {exc}") from exc

@mcp.tool()
def get_system_status(service_name: str) -> str:
    """社内システムの現在の稼働状況を取得します。"""
    try:
        enforce_input_policy(service_name, "get_system_status")
    except Exception as exc:
        return f"❌ {exc}"

    with pool.connect() as db_conn:
        row = db_conn.execute(
            sqlalchemy.text("""
                SELECT service_name, status, updated_at
                FROM system_status
                WHERE service_name = :service_name
            """),
            {"service_name": service_name},
        ).fetchone()

    if not row:
        return f"システム '{service_name}' は見つかりません。"

    return f"{row.service_name}: {row.status} 最終更新: {row.updated_at}"

@mcp.tool()
def get_employee_info(name: str) -> str:
    """指定された従業員の部署とメールアドレスを取得します。"""
    try:
        enforce_input_policy(name, "get_employee_info")
    except Exception as exc:
        return f"❌ {exc}"

    with pool.connect() as db_conn:
        row = db_conn.execute(
            sqlalchemy.text("""
                SELECT name, department, email, updated_at
                FROM employees
                WHERE name = :name
            """),
            {"name": name},
        ).fetchone()

    if not row:
        return f"従業員 '{name}' は見つかりません。"

    return f"{row.name}: 部署={row.department}, Email={row.email}, 最終更新={row.updated_at}"

if __name__ == "__main__":
    port = int(os.environ.get("PORT", "8080"))
    logger.info("Starting IT Support MCP Server on port %s", port)

    asyncio.run(
        mcp.run_async(
            transport="streamable-http",
            host="0.0.0.0",
            port=port,
        )
    )
