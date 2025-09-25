#!/usr/bin/env python3
"""
MCP Toolbox for Databases 最終クライアントライブラリ
Google Trends BigQuery データアクセス用
"""

import asyncio
import json
from mcp_config import MCP_CONFIG
from toolbox_core import ToolboxClient
import nest_asyncio

# Jupyter環境での非同期実行を有効化
nest_asyncio.apply()

class MCPClient:
    """
    MCP Toolboxサーバーに接続し、ツールを実行するための汎用クライアント。
    ADKのツールセットとして機能し、各メソッドがMCPサーバーのツールを呼び出す。
    """
    
    def __init__(self, server_url: str = None):
        """
        クライアントを初期化します。
        
        Args:
            server_url: 接続先のMCPサーバーURL。Noneの場合は設定ファイルから読み込みます。
        """
        self.server_url = server_url or MCP_CONFIG["server_url"]
        self._toolbox = ToolboxClient(self.server_url)
        self._tools = {}  # ツールを名前で管理するための辞書
        
        # ADKがこのクライアントをツールとして使うために、
        # __aenter__が完了している必要があるため、同期的に読み込みます。
        # (Jupyter環境なので nest_asyncio.apply() が必須)
        try:
            asyncio.run(self._load_tools())
        except Exception as e:
            print(f"❌ Failed to initialize MCPClient tools: {e}")
            raise

    async def _load_tools(self):
        """非同期でツールを読み込み、self._toolsに格納します。"""
        async with self._toolbox as toolbox:
            loaded_tools = await toolbox.load_toolset("google-trends-analysis")
            self._tools = {getattr(tool, '_name', ''): tool for tool in loaded_tools}
            print(f"✅ MCP Client connected to {self.server_url}")
            print(f"   Tools loaded: {list(self._tools.keys())}")

    async def __aenter__(self):
        """非同期コンテキストマネージャー（主にデモ用）"""
        # ツールは__init__でロード済み
        return self

    async def __aexit__(self, exc_type, exc_val, exc_tb):
        """非同期コンテキストマネージャーを終了します。"""
        # 接続管理はToolboxClientに任せる
        pass

    # --- ここからが ADK に認識されるツールメソッド ---

    async def execute_sql(self, sql: str) -> any:
        """
        【ADKツール】MCPサーバー経由で'execute_sql_tool'ツールを実行します。
        
        Args:
            sql: 実行するSQLクエリ文字列。
            
        Returns:
            クエリの実行結果。
        """
        # tools.yamlで定義されたツール名（例: 'execute_sql_tool'）を指定
        sql_tool = self._tools.get('execute_sql_tool') 
        if not sql_tool:
            raise RuntimeError("'execute_sql_tool' tool not found on the MCP server.")
            
        try:
            print(f"Executing SQL via MCP: {sql[:100]}...")
            result = await sql_tool(sql=sql)
            return result
        except Exception as e:
            print(f"❌ Error executing SQL via MCP: {e}")
            raise

    async def get_japan_trends(self, days: int = 7, limit: int = 10) -> any:
        """
        【カスタムツール】MCPサーバー経由で'get_japan_trends'ツールを実行し、日本のトレンドを取得します。
        
        Args:
            days: 遡る日数 (デフォルト: 7)
            limit: 取得する最大件数 (デフォルト: 20)
            
        Returns:
            クエリの実行結果。
        """
        # tools.yamlで定義されたツール名 'get_japan_trends' を指定
        trends_tool = self._tools.get('get_japan_trends')
        if not trends_tool:
            raise RuntimeError("'get_japan_trends' tool not found on the MCP server.")
            
        try:
            print(f"Executing get_japan_trends via MCP with days={days}, limit={limit}...")
            result = await trends_tool(days=days, limit=limit)
            return result
        except Exception as e:
            print(f"❌ Error executing get_japan_trends via MCP: {e}")
            raise
    
    async def bigquery_get_dataset_info(self, dataset_id: str) -> any:
        """
        【ADKツール】MCPサーバー経由で'bigquery_get_dataset_info'ツールを実行します。
        
        Args:
            dataset_id: 情報を取得するBigQueryデータセットID。
            
        Returns:
            データセット情報。
        """
        tool = self._tools.get('bigquery_get_dataset_info')
        if not tool:
            raise RuntimeError("'bigquery_get_dataset_info' tool not found on the MCP server.")
            
        try:
            print(f"Executing bigquery_get_dataset_info via MCP for dataset: {dataset_id}...")
            result = await tool(dataset_id=dataset_id)
            return result
        except Exception as e:
            print(f"❌ Error executing bigquery_get_dataset_info via MCP: {e}")
            raise

    async def bigquery_get_table_info(self, table_id: str) -> any:
        """
        【ADKツール】MCPサーバー経由で'bigquery_get_table_info'ツールを実行します。
        
        Args:
            table_id: 情報を取得するBigQueryテーブルID。
            
        Returns:
            テーブル情報（スキーマなど）。
        """
        tool = self._tools.get('bigquery_get_table_info')
        if not tool:
            raise RuntimeError("'bigquery_get_table_info' tool not found on the MCP server.")
            
        try:
            print(f"Executing bigquery_get_table_info via MCP for table: {table_id}...")
            result = await tool(table_id=table_id)
            return result
        except Exception as e:
            print(f"❌ Error executing bigquery_get_table_info via MCP: {e}")
            raise

    # ----------------------------------------------------
    # 動作確認用のデモ関数 (ファイル単体実行時に使用)
    # ----------------------------------------------------
    async def demo_mcp_client():  # <<< この関数の定義を if ブロックの外に出す
        """
        MCPClientの動作を確認するためのデモ関数です。
        """
        print("🚀 MCP Client Demo Start")
        try:
            # __init__でツールがロードされる
            client = MCPClient()
            
            # 1. execute_sql のデモ
            query = "SELECT term, rank FROM `bigquery-public-data.google_trends.international_top_terms` WHERE country_code = 'JP' ORDER BY week DESC, rank ASC LIMIT 3"
            result_sql = await client.execute_sql(sql=query)
            print("\n✅ Demo Query Result (execute_sql):")
            print(json.dumps(result_sql, indent=2, ensure_ascii=False))

            # 2. get_country_trends のデモ
            result_trends = await client.get_country_trends(days=1, limit=2)
            print("\n✅ Demo Query Result (get_country_trends):")
            print(json.dumps(result_trends, indent=2, ensure_ascii=False))

        except Exception as e:
            print(f"\n❌ Demo failed: {e}")

    if __name__ == "__main__":
    # このファイルを直接実行した場合はデモを実行
        asyncio.run(demo_mcp_client())