# MCP Toolbox for Databases カスタムtools.yaml本番設定
# Google Trends BigQuery専用ツール
# 自動生成: 2025-11-18 08:51:52

MCP_CONFIG = {
    "server_url": "https://mcp-trends-custom-pi6nynzn3a-uc.a.run.app",
    "project_id": "qwiklabs-gcp-02-a9e6c031e09c",
    "region": "us-central1",
    "service_name": "mcp-trends-custom",
    "service_account": "mcp-toolbox-sa@qwiklabs-gcp-02-a9e6c031e09c.iam.gserviceaccount.com",
    "toolbox_type": "mcp-toolbox-for-databases-custom",
    "configuration": "custom-google-trends-tools",
    "secret_name": "mcp-toolbox-tools-yaml",
    "status": "custom_production_ready",
    "deployed_at": "2025-11-18 08:51:52",
    "tools": {
        "execute_sql_tool": "BigQueryクエリ実行",
        "bigquery_get_dataset_info": "BigQueryデータセット情報取得",
        "bigquery_get_table_info": "BigQueryテーブル情報取得",
        "get_japan_trends": "日本のトレンド取得"
    },
    "toolsets": {
        "google-trends-analysis": "Google Trends分析ツールセット"
    }
}

print("✅ MCP Toolbox for Databases カスタムツール本番環境準備完了")
print(f"🌐 サーバーURL: {MCP_CONFIG['server_url']}")
print(f"🏗️ サービス: {MCP_CONFIG['service_name']}")
print(f"📊 設定: {MCP_CONFIG['configuration']}")
print(f"🔧 カスタムツール数: {len(MCP_CONFIG['tools'])}")
