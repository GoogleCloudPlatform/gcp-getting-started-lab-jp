"""
Starlight Cafe 音声対話システム - バックエンド

このファイルはGemini Live APIを使用したリアルタイム音声対話システムのバックエンドです。

主な機能:
1. Gemini Live APIとの連携
2. WebSocketを通じたフロントエンドとの通信  
3. リアルタイム音声ストリーミング
4. AIエージェント（Patrick）の設定とメッセージ処理

【🎯 ハンズオン・カスタマイズについて】
ハンズオン時にカスタマイズする設定項目は system_instruction.py に分離されています：
- SYSTEM_INSTRUCTION: AIエージェントの役割・性格・知識
- VOICE_NAME: 音声の種類
- LANGUAGE: 対応言語  
- AI_TEMPERATURE: 応答の創造性レベル
- AI_TOP_P: 応答の多様性

main.py を直接編集せず、system_instruction.py のみを変更してください。
これにより、誤って重要な処理部分を変更してしまうリスクを避けられます。
"""

import asyncio
import base64
import json
import logging
import os
import threading
import time
import uuid
import google.auth
from dotenv import load_dotenv
from system_instruction import SYSTEM_INSTRUCTION, SYSTEM_INSTRUCTION_TOOL_EXTENSION, AI_TEMPERATURE, AI_TOP_P, VOICE_NAME, LANGUAGE

from google import genai
from google.genai.types import (
    Part,
    Content,
    Blob,
    SpeechConfig,
    VoiceConfig,
    PrebuiltVoiceConfig,
    AudioTranscriptionConfig,
    RealtimeInputConfig,
    AutomaticActivityDetection,
    StartSensitivity,
    EndSensitivity,
    ActivityHandling,
    ProactivityConfig,
    GenerateContentConfig,
    HttpOptions
)
from google.adk.agents import LlmAgent
from google.adk.runners import Runner
from google.adk.agents import LiveRequestQueue
from google.adk.agents.run_config import RunConfig, StreamingMode
from google.adk.sessions.in_memory_session_service import InMemorySessionService

from fastapi import FastAPI, WebSocket
from fastapi.websockets import WebSocketState

# ===== ログ設定 =====
logger = logging.getLogger(__name__)
logging.basicConfig(level=logging.INFO)

# ===== 環境変数の読み込み =====
load_dotenv()

# ===== Google Cloud認証設定 =====
# プロジェクトIDを環境変数から取得
PROJECT_ID = os.environ.get('GOOGLE_CLOUD_PROJECT')
if not PROJECT_ID:
    try:
        _, PROJECT_ID = google.auth.default()
    except google.auth.exceptions.DefaultCredentialsError:
        print("❌ Google Cloud認証エラー")
        print("🔧 解決方法:")
        print("1. gcloud auth application-default login")
        print("2. または GOOGLE_CLOUD_PROJECT と GOOGLE_APPLICATION_CREDENTIALS を.envに設定")
        exit(1)

# Environment setup
LOCATION = os.getenv('GOOGLE_CLOUD_LOCATION', 'us-central1')
os.environ['GOOGLE_CLOUD_LOCATION'] = LOCATION
# ★環境変数でToolの使用を切り替えるフラグ
USE_TOOL = os.getenv('USE_ORDER_TOOL', 'False').lower() in ('true', '1', 't')

# ===== 音声設定（環境変数 or system_instruction.py からの設定） =====
# 環境変数が設定されている場合はそれを優先、なければ system_instruction.py のデフォルト値を使用
VOICE_NAME = os.environ.get('VOICE_NAME', VOICE_NAME)
LANGUAGE = os.environ.get('LANGUAGE', LANGUAGE)

# 言語コードマッピング
LANG_CODE_MAP = {
    'English': 'en-US',
    'Japanese': 'ja-JP',
    'Korean': 'ko-KR',
}
logger.info(f'LANGUAGE: {LANGUAGE}, VOICE_NAME: {VOICE_NAME}')

os.environ['GOOGLE_GENAI_USE_VERTEXAI'] = 'True'
os.environ['GOOGLE_CLOUD_PROJECT'] = PROJECT_ID

class VoicecallBackend:
    """
    音声通話バックエンドクラス
    
    Gemini Live APIとWebSocketクライアント間の橋渡しを行います。
    主な責務:
    1. Gemini Live APIセッションの管理
    2. 音声データの双方向ストリーミング
    3. エラーハンドリング
    """
    
    def __init__(self, client_websocket):
        """
        初期化
        
        Args:
            client_websocket: フロントエンドとのWebSocket接続
        """
        self.client_ws = client_websocket
        self.live_events = None
        self.live_request_queue = None
        self.text_message_queue = []


    def generate_response(self, system_instruction, contents, response_schema,
                          model='gemini-2.5-flash-lite'):
        client = genai.Client(vertexai=True,
                              project=PROJECT_ID, location=LOCATION,
                              http_options=HttpOptions(api_version='v1'))
        response = client.models.generate_content(
            model=model,
            contents=contents,
            config=GenerateContentConfig(
                system_instruction=system_instruction,
                temperature=0.1,
                top_p=0.5,
                response_mime_type='application/json',
                response_schema=response_schema,
            )
        )
        return '\n'.join(
            [p.text for p in response.candidates[0].content.parts if p.text]
        )


    def get_tech_support_tools(self):
        """
        テクニカルサポート用のFunction Callingツールを返す
        """
        async def search_knowledge_base(query: str) -> str:
            """
            Search internal knowledge base for technical documents.
            Use this tool when the user asks about specific procedures, error codes, or internal systems (VPN, Wi-Fi, etc.).
            
            Args:
                query: Search keywords (e.g., "VPN error", "Wi-Fi password")
            
            Returns:
                Relevant document content or "No information found."
            """
            logger.info(f"🔍 ナレッジベース検索: {query}")
            kb_dir = os.path.join(os.path.dirname(__file__), 'knowledge_base')
            
            results = []
            try:
                if not os.path.exists(kb_dir):
                    return "Knowledge base directory not found."

                for filename in os.listdir(kb_dir):
                    if filename.endswith(".md") or filename.endswith(".txt"):
                        filepath = os.path.join(kb_dir, filename)
                        with open(filepath, 'r', encoding='utf-8') as f:
                            content = f.read()
                            # Keyword matching (AND condition)
                            keywords = query.lower().split()
                            target_text = (filename + " " + content).lower()
                            
                            if all(keyword in target_text for keyword in keywords):
                                results.append(f"--- Document: {filename} ---\n{content}\n")
                
                if not results:
                    return "No relevant documents found in the knowledge base."
                
                return "\n".join(results)[:5000] # Limit content length
            except Exception as e:
                logger.error(f"Search error: {e}")
                return f"Error searching knowledge base: {str(e)}"

        async def create_support_ticket(title: str, issue_summary: str, priority: str = "Normal") -> str:
            """
            Create a support ticket for the user.
            Use this tool when the issue cannot be resolved immediately or the user requests a ticket.
            
            Args:
                title: Ticket title.
                issue_summary: Brief description of the issue.
                priority: Priority level ("Low", "Normal", "High", "Urgent").
            
            Returns:
                Ticket creation confirmation with Ticket ID.
            """
            ticket_id = f"TKT-{uuid.uuid4().hex[:6].upper()}"
            logger.info(f"🎫 チケット作成: ID={ticket_id}, Title={title}, Summary={issue_summary}, Priority={priority}")
            
            # フロントエンドにチケット作成イベントを送信
            try:
                if self.client_ws:
                    import json
                    message = {
                        "type": "ticket_created",
                        "data": {
                            "ticket_id": ticket_id,
                            "title": title,
                            "summary": issue_summary,
                            "priority": priority
                        }
                    }
                    await self.client_ws.send_text(json.dumps(message))
            except Exception as e:
                logger.error(f"❌ チケット作成イベント送信エラー: {e}")
            
            # In a real app, this would save to a database or call an API (Jira, ServiceNow, etc.)
            
            return f"Ticket created successfully. Ticket ID: {ticket_id}. A support representative will contact you shortly."
        
        return [search_knowledge_base, create_support_ticket]

    async def create_runner(self):
        """
        Gemini Live APIランナーの作成と設定
        
        Returns:
            tuple: (live_events, live_request_queue)
        """
        logger.info("🚀 Gemini Live APIランナーを作成中...")
        
        # セッション管理サービスの初期化
        session_service = InMemorySessionService()
        
        # ===== 【ハンズオン・カスタマイズ可能】AI応答設定 =====
        generate_content_config = GenerateContentConfig(
            temperature=AI_TEMPERATURE,  # 応答の創造性
            top_p=AI_TOP_P,             # 応答の多様性
        )
        
        # ★USE_TOOLフラグに応じて、プロンプトとToolを切り替える
        # 今回は常にツールを有効にする（ハンズオン簡略化のため）
        logger.info("✅ Function Callingツールを有効にしてエージェントを作成します。")
        instruction = SYSTEM_INSTRUCTION + SYSTEM_INSTRUCTION_TOOL_EXTENSION
        tools = self.get_tech_support_tools()

        # ===== AIエージェントの作成 =====
        voicecall_agent = LlmAgent(
            name='tech_support_agent',
            model='gemini-live-2.5-flash-preview-native-audio-09-2025',
            description='テクニカルサポートのAlexとして、お客様と親切で丁寧な音声対話を行うエージェント',
            instruction=instruction,  # システムプロンプトを適用
            generate_content_config=generate_content_config,
            tools=tools,  # Function Callingツールを追加
        )

        # ランナーの作成
        runner = Runner(
            app_name='starlight_cafe_app',
            agent=voicecall_agent,
            session_service=session_service
        )

        # セッションの作成
        session = await session_service.create_session(
            app_name='starlight_cafe_app',
            user_id='default_user',
        )

        # ===== 【ハンズオン・カスタマイズ可能】音声設定 =====
        run_config = RunConfig(
            streaming_mode=StreamingMode.BIDI,  # 双方向ストリーミング
            response_modalities=['AUDIO'],      # 音声応答
            speech_config=SpeechConfig(
                voice_config=VoiceConfig(
                    prebuilt_voice_config=PrebuiltVoiceConfig(
                        voice_name=VOICE_NAME  # 音声の種類
                    )
                ),
                language_code=LANG_CODE_MAP[LANGUAGE],  # 言語設定
            ),
            output_audio_transcription=AudioTranscriptionConfig(),  # 出力音声の文字起こし
            input_audio_transcription=AudioTranscriptionConfig(),   # 入力音声の文字起こし
        )

        # Live APIセッションの開始
        live_request_queue = LiveRequestQueue()
        live_events = runner.run_live(
            user_id='default_user',
            session_id=session.id,
            live_request_queue=live_request_queue,
            run_config=run_config,
        )

        logger.info("✅ Gemini Live APIランナーの作成完了")
        return live_events, live_request_queue

    async def agent_to_client_messaging(self):
        """
        AIエージェント → フロントエンド への音声データ転送
        """
        logger.info("🔊 エージェント→クライアント メッセージング開始")
        
        async for event in self.live_events:
            # イベントにコンテンツとパーツが含まれているかチェック
            if not (event.content and event.content.parts):
                continue
                
            for part in event.content.parts:
                # 音声データが含まれているかチェック
                if hasattr(part, 'inline_data') and part.inline_data:
                    audio_data = part.inline_data.data
                    mime_type = part.inline_data.mime_type
                    
                    # PCM音声データの場合のみ処理
                    if audio_data and mime_type.startswith('audio/pcm'):
                        message = {
                            'type': 'audio',
                            'data': base64.b64encode(audio_data).decode('ascii')
                        }
                        # フロントエンドに音声データを送信
                        await self.client_ws.send_text(json.dumps(message))

                # テキストデータ（出力トランスクリプション）のチェック
                elif hasattr(part, 'text') and part.text:
                    if event.partial: # Skip partial text
                        continue
                    role = event.content.role
                    self.text_message_queue.append((role, part.text))


    async def client_to_agent_messaging(self):
        """
        フロントエンド → AIエージェント への音声データ転送
        """
        logger.info("🎤 クライアント→エージェント メッセージング開始")
        
        async for message in self.client_ws.iter_text():
            try:
                message = json.loads(message)
                
                # 音声メッセージの場合
                if message['type'] == 'audio':
                    # PCM形式の音声データかチェック
                    if not('mime_type' in message.keys() and
                            message['mime_type'] == 'audio/pcm'): 
                        continue
                    
                    # Base64デコードしてGemini Live APIに送信
                    decoded_data = base64.b64decode(message['data'])
                    self.live_request_queue.send_realtime(
                        Blob(data=decoded_data,
                             mime_type=f'audio/pcm;rate=16000')
                    )
                    # logger.debug("🎤 クライアントから音声データを受信")

                # 画像メッセージの場合
                elif message['type'] == 'image':
                    logger.info("🖼️ 画像データを受信")
                    if 'data' in message:
                        image_data = base64.b64decode(message['data'])
                        mime_type = message.get('mime_type', 'image/jpeg')
                        self.live_request_queue.send_realtime(
                            Blob(data=image_data, mime_type=mime_type)
                        )

                # 動画メッセージの場合
                elif message['type'] == 'video':
                    logger.info("🎥 動画データを受信")
                    if 'data' in message:
                        video_data = base64.b64decode(message['data'])
                        mime_type = message.get('mime_type', 'video/mp4')
                        self.live_request_queue.send_realtime(
                            Blob(data=video_data, mime_type=mime_type)
                        )
                    
            except Exception as e:
                logger.error(f"❌ メッセージ処理エラー: {e}")


    def correct_text_message(self, past_messages, text):
        system_instruction = f'''
You are given the following data:
- Conversation text between AI and the user.
- New message from the user.

The new message is generated by audio transcription, so some words may be incorrectly recorded.
If the new message is apparently strange, modify a few words so that it matches the context.
Remove unnecessary white spaces.
Output in {LANGUAGE}.
        '''

        response_schema = {
            "type": "object",
            "properties": {
                "message": {
                    "description": "Crrected message",
                    "type": "string"
                }
            },
            "required": ["message"]
        }

        parts = [Part(text=f'''
## conversation text
{past_messages}

## new message
{text}
''')]
        contents = Content(parts=parts, role='user')
        result = self.generate_response(
                system_instruction, contents, response_schema
        )
        return json.loads(result)['message']


    async def send_text_message_task(self):
        past_messages = ''
        while True:
            if len(self.text_message_queue) == 0:
                await asyncio.sleep(1)
                continue
            role, text = self.text_message_queue.pop(0)
            if role == 'model':
                logger.info(f"📝 AI 出力テキスト: {text}")
                message = {
                    'type': 'output_transcription',
                    'text': text,
                    'speaker': 'AI'
                }
                past_messages += f'\n[AI]: {text}\n'
                await self.client_ws.send_text(json.dumps(message))
            else:
                logger.info(f"📝 User 出力テキスト: {text}")
                loop = asyncio.get_running_loop()
                # Run in another thread so that Gemini API call doesn't block asyncio.
                text = await loop.run_in_executor(
                    None, self.correct_text_message, past_messages, text
                )
                logger.info(f"📝 User 出力テキスト（修正後）: {text}")
                message = {
                    'type': 'input_transcription',
                    'text': text,
                    'speaker': 'User'
                }
                past_messages += f'\n[User]: {text}\n'
                await self.client_ws.send_text(json.dumps(message))


    async def run(self):
        """
        メイン実行ループ
        
        以下の処理を並行して実行:
        1. Gemini Live APIランナーの作成
        2. 会話開始トリガーの送信
        3. 双方向音声ストリーミングの開始
        """
        logger.info('🎬 音声対話セッション開始')
        
        # Gemini Live APIランナーの作成
        self.live_events, self.live_request_queue = await self.create_runner() 

        # 会話開始のトリガー送信
        await asyncio.sleep(2)
        logger.info("📞 会話開始トリガーを送信")
        content = Content(role='user', parts=[Part(text='電話がかかってきました。')])
        self.live_request_queue.send_content(content=content)

        try:
            # 双方向音声ストリーミングの開始
            agent_to_client_task = asyncio.create_task(
                self.agent_to_client_messaging()
            )
            # voice client to agent
            client_to_agent_task = asyncio.create_task(
                self.client_to_agent_messaging()
            )
            send_text_message_task = asyncio.create_task(
                self.send_text_message_task()
            )
            tasks = [
                agent_to_client_task, client_to_agent_task, send_text_message_task
            ]
            done, pending = await asyncio.wait(
                tasks, return_when=asyncio.FIRST_COMPLETED
            )
            
        except Exception as e:
            logger.info(f'exception: {e}')

        logger.info('end conversation')


app = FastAPI()


# Cloud Run health-check
@app.get('/')
async def read_root():
    return {'status': 'ok'}


@app.websocket('/ws')
async def handler(websocket: WebSocket):
    await websocket.accept()
    
    try:
        # VoicecallBackendインスタンスを作成して実行
        backend = VoicecallBackend(websocket)
        await backend.run()
        
    except Exception as e:
        logger.error(f"❌ WebSocketセッションエラー: {e}")
    
    finally:
        logger.info("🔌 WebSocket接続が終了しました")

# ===== 開発用サーバー起動 =====
if __name__ == '__main__':
    import uvicorn
    logger.info("🚀 開発サーバーを起動中...")
    
    uvicorn.run(
        'main:app', 
        host='localhost', 
        port=8081,
        reload=True, 
        log_level='info'
    )

