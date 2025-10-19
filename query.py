# -*- coding: utf-8 -*-
"""
Vertex AI Agent Engine にデプロイされた単一のエージェントに問い合わせを行い、
ストリーム形式でレスポンスを出力するスクリプト。
"""
import sys
import argparse

from vertexai import agent_engines

# --- 定数定義 ---
USER_ID = "test_user01"


# --- カスタム例外定義 ---
class AgentEngineError(Exception):
    """このスクリプトにおけるAgent Engine関連エラーの基底クラス。"""
    pass


class AgentNotFoundError(AgentEngineError):
    """デプロイされたAgent Engineが見つからない場合のエラー。"""
    pass


class MultipleAgentsFoundError(AgentEngineError):
    """複数のAgent Engineが見つかった場合のエラー。"""
    pass


def find_unique_agent_engine() -> agent_engines.AgentEngine:
    """
    デプロイされている単一のAgent Engineを検索して返す。

    Raises:
        AgentNotFoundError: Agent Engineが見つからない場合。
        MultipleAgentsFoundError: Agent Engineが複数見つかった場合。

    Returns:
        デプロイされているAgent Engineのインスタンス。
    """
    print("デプロイ済みのAgent Engineを検索中...")
    agent_engine_list = agent_engines.AgentEngine.list()

    if not agent_engine_list:
        raise AgentNotFoundError("Agent Engineにデプロイされたエージェントが見つかりませんでした。")
    if len(agent_engine_list) > 1:
        names = [agent.resource_name for agent in agent_engine_list]
        raise MultipleAgentsFoundError(
            f"Agent Engineにデプロイされたエージェントが複数見つかりました: {names}"
        )

    unique_agent_resource_name = agent_engine_list[0].resource_name
    print(f"エージェント '{unique_agent_resource_name}' を使用します。")
    return agent_engines.get(unique_agent_resource_name)


def stream_agent_query(agent: agent_engines.AgentEngine, message: str) -> None:
    """
    Agent Engineにクエリを投げ、結果をストリームで標準出力に表示する。

    Args:
        agent: 使用するAgent Engineのインスタンス。
        message: エージェントに送信するメッセージ。
    """
    response_stream = agent.stream_query(
        user_id=USER_ID,
        message=message,
    )

    print("\n--- エージェントからのレスポンス ---\n")
    for event in response_stream:
        try:
            text = event["content"]["parts"][0]["text"]
            if not text:
                continue

            print(text, end="", flush=True)

        except (KeyError, IndexError, TypeError, AttributeError):
            # 予期せぬ構造のイベントはスキップする
            continue
    print("\n\n--- レスポンス終了 ---")


def main():
    """
    スクリプトのメイン処理。
    """
    parser = argparse.ArgumentParser(
        description="Vertex AI Agent Engine にクエリを送信します。"
    )
    parser.add_argument("message", help="エージェントに問い合わせたいメッセージ", type=str)
    args = parser.parse_args()

    agent = find_unique_agent_engine()
    stream_agent_query(agent, args.message)


if __name__ == "__main__":
    try:
        main()
        sys.exit(0)
    except AgentEngineError as e:
        print(f"\nエラー: {e}", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print(f"\n予期せぬエラーが発生しました: {e}", file=sys.stderr)
        sys.exit(1)
