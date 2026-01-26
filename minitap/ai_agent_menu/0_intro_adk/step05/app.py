"""
Vertex AI Agent Engine チャットアプリケーション
Streamlitを使用したインタラクティブなチャットインターフェース
"""

import streamlit as st
import vertexai
from vertexai import reasoning_engines
import os
from dotenv import load_dotenv
import uuid
from datetime import datetime
import logging

# ============================================================================
# 初期設定 / Initial Configuration
# ============================================================================

# ADKからの非同期APIモード警告を抑制
# Suppress async API mode warnings from ADK
logging.getLogger('root').setLevel(logging.ERROR)

# 環境変数の読み込み / Load environment variables
load_dotenv()

# Google Cloud設定 / Google Cloud Configuration
PROJECT_ID = os.getenv("GOOGLE_CLOUD_PROJECT")
LOCATION = os.getenv("GOOGLE_CLOUD_LOCATION", "us-central1")
AGENT_RESOURCE_NAME = os.getenv("AGENT_RESOURCE_NAME")

# Streamlitページ設定 / Streamlit Page Configuration
st.set_page_config(
    page_title="Agent Chat",
    page_icon="🤖",
    layout="wide"
)

# エージェントリソース名の確認 / Check agent resource name
if not AGENT_RESOURCE_NAME:
    st.error("⚠️ 環境変数にAGENT_RESOURCE_NAMEを設定してください。/ Please set AGENT_RESOURCE_NAME in your .env file.")
    st.stop()

# ============================================================================
# Vertex AI クライアント初期化 / Initialize Vertex AI Client
# ============================================================================

# Vertex AIクライアントの作成 / Create Vertex AI client
client = vertexai.Client(
    project=PROJECT_ID,
    location=LOCATION,
)

# エージェント接続の初期化 / Initialize agent connection
if "agent" not in st.session_state:
    try:
        # エージェントエンジンを取得 / Get agent engine
        st.session_state.agent = client.agent_engines.get(name=AGENT_RESOURCE_NAME)
    except Exception as e:
        st.error(f"❌ エージェントへの接続に失敗しました / Failed to connect to agent: {e}")
        st.stop()

# ============================================================================
# セッション管理関数 / Session Management Functions
# ============================================================================

def create_new_session(user_id="streamlit_user"):
    """
    新しいセッションを作成
    Create a new session in the agent engine
    """
    try:
        session = st.session_state.agent.create_session(user_id=user_id)
        session_id = session.id if hasattr(session, 'id') else session.get('id', str(uuid.uuid4()))
        return session_id
    except Exception as e:
        st.warning(f"セッション作成エラー / Session creation error: {e}")
        return str(uuid.uuid4())


def sync_existing_sessions(user_id="streamlit_user"):
    """
    既存のセッションを同期
    Sync existing sessions from the agent engine
    """
    try:
        response = st.session_state.agent.list_sessions(user_id=user_id)
        sessions = response.sessions if hasattr(response, 'sessions') else response.get('sessions', [])
        return sessions
    except Exception as e:
        st.warning(f"セッション同期エラー / Session sync error: {e}")
        return []


def delete_session(session_id, user_id="streamlit_user"):
    """
    セッションを削除
    Delete a session from the agent engine
    """
    try:
        st.session_state.agent.delete_session(
            user_id=user_id,
            session_id=session_id
        )
        return True
    except Exception as e:
        st.warning(f"セッション削除エラー / Session deletion error: {e}")
        return False


# ============================================================================
# チャットセッション初期化 / Initialize Chat Sessions
# ============================================================================

# チャットセッションストレージの初期化 / Initialize chat sessions storage
if "chats" not in st.session_state:
    st.session_state.chats = {}

# 初回起動時のセッション同期 / Sync sessions on first launch
if "current_chat_id" not in st.session_state:
    # 既存セッションの確認と同期 / Check and sync existing sessions
    existing_sessions = sync_existing_sessions()

    if existing_sessions:
        # 既存セッションを使用 / Use existing sessions
        for idx, session in enumerate(existing_sessions, 1):
            session_id = session.id if hasattr(session, 'id') else session.get('id')
            if session_id:
                chat_id = str(uuid.uuid4())
                st.session_state.chats[chat_id] = {
                    "session_id": session_id,
                    "messages": [],
                    "name": f"セッション {idx}",
                    "created_at": datetime.now()
                }
                # 最初のセッションを現在のチャットに設定 / Set first session as current
                if idx == 1:
                    st.session_state.current_chat_id = chat_id
    else:
        # 新規セッションを作成 / Create new session
        first_chat_id = str(uuid.uuid4())
        session_id = create_new_session()

        st.session_state.chats[first_chat_id] = {
            "session_id": session_id,
            "messages": [],
            "name": "チャット 1",
            "created_at": datetime.now()
        }
        st.session_state.current_chat_id = first_chat_id

# ============================================================================
# サイドバー：チャット管理 / Sidebar: Chat Management
# ============================================================================

with st.sidebar:
    st.title("💬 チャットセッション / Chat Sessions")

    # 新規チャット作成ボタン / New chat button
    if st.button("➕ 新規チャット / New Chat", use_container_width=True):
        new_chat_id = str(uuid.uuid4())
        chat_number = len(st.session_state.chats) + 1
        session_id = create_new_session()

        st.session_state.chats[new_chat_id] = {
            "session_id": session_id,
            "messages": [],
            "name": f"チャット {chat_number}",
            "created_at": datetime.now()
        }
        st.session_state.current_chat_id = new_chat_id
        st.rerun()

    st.divider()

    # セッション同期ボタン / Session sync button
    if st.button("🔄 セッション同期 / Sync Sessions", use_container_width=True):
        existing_sessions = sync_existing_sessions()
        new_sessions_count = 0

        for session in existing_sessions:
            session_id = session.id if hasattr(session, 'id') else session.get('id')

            # 既存セッションかチェック / Check if session already exists
            session_exists = any(
                chat['session_id'] == session_id
                for chat in st.session_state.chats.values()
            )

            if not session_exists and session_id:
                # 新規セッションを追加 / Add new session
                new_chat_id = str(uuid.uuid4())
                st.session_state.chats[new_chat_id] = {
                    "session_id": session_id,
                    "messages": [],
                    "name": f"同期セッション {session_id[:8]}...",
                    "created_at": datetime.now()
                }
                new_sessions_count += 1

        if new_sessions_count > 0:
            st.success(f"✅ {new_sessions_count}個のセッションを同期しました / Synced {new_sessions_count} sessions")
            st.rerun()
        else:
            st.info("ℹ️ 新規セッションはありません / No new sessions to sync")

    st.divider()

    # チャットリスト表示 / Display chat list
    st.subheader("📋 チャットリスト / Chat List")

    for chat_id, chat_data in st.session_state.chats.items():
        is_current = chat_id == st.session_state.current_chat_id

        # チャット選択UI / Chat selection UI
        col1, col2, col3 = st.columns([3, 1, 1])

        with col1:
            # チャット選択ボタン / Chat selection button
            button_label = f"{'▶ ' if is_current else '  '}{chat_data['name']}"
            if st.button(button_label, key=f"chat_{chat_id}", use_container_width=True):
                st.session_state.current_chat_id = chat_id
                st.rerun()

        with col2:
            # セッション情報ボタン / Session info button
            session_info = f"ID: {chat_data.get('session_id', 'N/A')[:8]}..."
            if st.button("ℹ️", key=f"info_{chat_id}", help=session_info):
                st.info(f"セッションID / Session ID:\n{chat_data.get('session_id', 'N/A')}")

        with col3:
            # 削除ボタン / Delete button
            if st.button("🗑️", key=f"delete_{chat_id}"):
                if len(st.session_state.chats) > 1:
                    # エージェントエンジンからセッションを削除 / Delete from agent engine
                    delete_session(chat_data["session_id"])

                    # ローカル状態から削除 / Delete from local state
                    del st.session_state.chats[chat_id]

                    # 現在のチャットが削除された場合は切り替え / Switch if current chat deleted
                    if st.session_state.current_chat_id == chat_id:
                        st.session_state.current_chat_id = list(st.session_state.chats.keys())[0]

                    st.rerun()
                else:
                    st.warning("⚠️ 最後のチャットは削除できません / Cannot delete the last chat!")

# ============================================================================
# メインチャットエリア / Main Chat Area
# ============================================================================

# 現在のチャットを取得 / Get current chat
current_chat = st.session_state.chats[st.session_state.current_chat_id]

# チャットタイトル / Chat title
st.title(f"🤖 {current_chat['name']}")

# メッセージ履歴を表示 / Display message history
for message in current_chat["messages"]:
    with st.chat_message(message["role"]):
        st.markdown(message["content"])

# ============================================================================
# チャット入力処理 / Chat Input Processing
# ============================================================================

# ユーザー入力を処理 / Process user input
if prompt := st.chat_input("メッセージを入力 / Enter your message"):

    # ユーザーメッセージを履歴に追加 / Add user message to history
    current_chat["messages"].append({"role": "user", "content": prompt})

    # ユーザーメッセージを表示 / Display user message
    with st.chat_message("user"):
        st.markdown(prompt)

    # アシスタントの応答を表示 / Display assistant response
    with st.chat_message("assistant"):
        message_placeholder = st.empty()
        full_response = ""

        try:
            # ストリーミングクエリを実行 / Execute streaming query
            for event in st.session_state.agent.stream_query(
                user_id="streamlit_user",
                session_id=current_chat["session_id"],
                message=prompt
            ):
                # ストリーミングイベントを処理 / Process streaming events
                content = None

                # コンテンツを抽出 / Extract content
                if hasattr(event, 'content'):
                    content = event.content
                elif isinstance(event, dict) and 'content' in event:
                    content = event['content']
                else:
                    continue

                # パーツからテキストを抽出 / Extract text from parts
                parts = []
                if hasattr(content, 'parts'):
                    parts = content.parts
                elif isinstance(content, dict) and 'parts' in content:
                    parts = content['parts']
                else:
                    continue

                # 各パーツを処理 / Process each part
                for part in parts:
                    text = None

                    if hasattr(part, 'text'):
                        text = part.text
                    elif isinstance(part, dict) and 'text' in part:
                        text = part['text']

                    if text:
                        full_response += text
                        # カーソル付きで表示 / Display with cursor
                        message_placeholder.markdown(full_response + "▌")

            # 最終表示（カーソルなし） / Final display without cursor
            message_placeholder.markdown(full_response)

            # 履歴に追加 / Add to history
            current_chat["messages"].append({
                "role": "assistant",
                "content": full_response
            })

        except AttributeError:
            # stream_queryが利用できない場合のフォールバック / Fallback if stream_query not available
            try:
                response = st.session_state.agent.query(
                    user_id="streamlit_user",
                    session_id=current_chat["session_id"],
                    message=prompt
                )

                # レスポンス処理 / Process response
                response_text = ""

                if hasattr(response, 'output'):
                    response_text = response.output
                elif isinstance(response, dict) and 'output' in response:
                    response_text = response['output']
                elif hasattr(response, 'text'):
                    response_text = response.text
                elif isinstance(response, dict) and 'text' in response:
                    response_text = response['text']
                elif isinstance(response, str):
                    response_text = response
                else:
                    response_text = str(response)

                message_placeholder.markdown(response_text)

                # 履歴に追加 / Add to history
                current_chat["messages"].append({
                    "role": "assistant",
                    "content": response_text
                })

            except Exception as e:
                st.error(f"❌ クエリエラー / Query error: {e}")

        except Exception as e:
            st.error(f"❌ ストリーミングエラー / Streaming error: {e}")