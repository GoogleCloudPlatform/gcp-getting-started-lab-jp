"""
MiniTAP MCP Analytics - Source Package

このパッケージには、MCP Toolbox for Databasesとの統合に必要な
クライアントライブラリとユーティリティが含まれています。
"""

__version__ = "1.0.0"
__author__ = "MiniTAP Team"

from .mcp_client import MCPClient

__all__ = [
    "MCPClient"
]
