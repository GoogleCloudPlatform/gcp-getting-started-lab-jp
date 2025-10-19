---
title: "AI Agents: Weather & News"
description: "ADK を用いて金融アドバイスを提供する AI Agents を作成するチュートリアル"
duration: 60
level: Beginner
tags: [AI Agents, ADK, Python, "Weather & News", Gemini]
---

# AI Agents: Weather & News

ADK (Agent Development Kit) を用いて, シンプル Multi Agent を作成するチュートリアルです.

## 事前準備: Google アカウント認証とプロジェクトの設定

- Google アカウント認証
- プロジェクトの設定
- 必要な API の有効化
- Python の仮装環境を準備
- 環境変数の設定

### Google アカウント認証

認証しているかどうかアカウントの確認です

```bash
gcloud auth list
```

認証済みアカウントが正しくコンフィグに設定されているか確認します

```bash
gcloud config get-value account
```

もし

```
Credentialed Accounts

ACTIVE: *
ACCOUNT: hogehoge@example.com
```

のようにログイン済みのアカウントがうまく出ていない場合は,

```bash
gcloud auth application-default login --no-launch-browser
```

を実行してログインを行います (ログイン URL が出てくるので, URL をクリック, verification code を入力しましょう).

### プロジェクトの設定

### プロジェクト ID の設定

```bash
gcloud config set project PLEASE_SPECIFY_YOUR_PROJECT_ID
```

### 正しく設定されているか確認

```bash
gcloud config get-value project
```

後ほど使用するので project id を環境変数に設定

```bash
export GOOGLE_CLOUD_PROJECT=$(gcloud config get-value project)
```

ついでにデフォの location も後ほど使用するので設定

```bash
export GOOGLE_CLOUD_LOCATION=us-central1
```

### 必要な API の有効化

今回利用する API の一覧です

```bash
gcloud services enable aiplatform.googleapis.com
```

### Python の仮装環境を準備

```bash
uv sync
source .venv/bin/activate
```

### 環境変数の設定

`.env` ファイルにプロジェクト情報を設定します。

```bash
cat > .env <<EOF
GOOGLE_GENAI_USE_VERTEXAI=1
GOOGLE_CLOUD_PROJECT=${GOOGLE_CLOUD_PROJECT}
GOOGLE_CLOUD_LOCATION=${GOOGLE_CLOUD_LOCATION}
EOF
```
<walkthrough-editor-open-file filePath="./.env">ここをクリック</walkthrough-editor-open-file>して、フィアルを確認してみてください。

## Step 00. Hello World Agent - 初めての Agent

### Agent とは？

AI Agent は、ユーザーの指示を理解し、自律的にタスクを実行する AI システムです。ADK (Agent Development Kit) を使用すると、簡単に Agent を作成できます。

### コードを見てみよう

<walkthrough-editor-open-file filePath="./step00/agent.py">step00/agent.py</walkthrough-editor-open-file> を開いて、最初の Agent の構造を確認しましょう：

```python
from google.adk.agents.llm_agent import LlmAgent

root_agent = LlmAgent(
    name="hello_world",
    model="gemini-2.5-flash",
    description="ユーザに挨拶するエージェント",
    instruction="ユーザーに丁寧に挨拶してください"
)
```

### ローカル環境で Agent を動かしてみる

```bash
adk web . --port 8080
```

Cloud Shell の Web Preview 機能を使ってアクセスします:
1. 上部メニューの「ウェブでプレビュー」をクリック
2. ポート 8080 を選択
3. ブラウザで UI が開きます
4. Agent 一覧で **step00** を選んでください

### プロンプトの入力例

以下のような質問をしてみてください:

- "こんにちは！"
- "おはようございます"
- "はじめまして、太郎です"

### 🎯 このステップで学んだこと
- LlmAgent の基本構造（name, model, description, instruction）
- ADK Web インターフェースの使い方
- シンプルな Agent の動作確認

---

## Step 01. 単体 Agentを作ってみよう！

### ツール（関数）を持つ Agent の作成

Agent に特定の機能を持たせるには、Python 関数を「ツール」として追加します。天気情報を提供する Agent を作ってみましょう。

### コードの確認

<walkthrough-editor-open-file filePath="./step01/agent.py">step01/agent.py</walkthrough-editor-open-file> を開いて確認しましょう：

```python
# 天気情報取得関数（ツール）
def get_weather(city: str) -> dict:
    """指定された都市の現在の天気予報を取得します。"""
    mock_weather_db = {
        "ニューヨーク": {"status": "success", "report": "ニューヨークの天気は晴れ、気温は25℃です。"},
        "ロンドン": {"status": "success", "report": "ロンドンは曇り、気温は15℃です。"},
        "東京": {"status": "success", "report": "東京は小雨、気温は18℃です。"},
    }
    # ...

root_agent = LlmAgent(
    name="weather_agent_v1",
    model="gemini-2.5-flash",
    description="特定の都市の天気情報を提供するエージェント",
    instruction="あなたは親切な天気アシスタントです。気象キャスターのように回答してください",
    tools=[get_weather],  # ← ツールを追加！
)
```

### Docstring について

関数の docstring はツールの説明として LLM に送信されます。そのため、適切に記述された包括的な docstring は、LLM がツールを効果的に理解し使用するために重要です。関数の目的、パラメータの意味、期待される戻り値を明確に説明してください。

### ベストプラクティス

関数を定義する際には柔軟性がありますが、シンプルさが LLM にとっての使いやすさを向上させることを忘れないでください。以下のガイドラインを考慮してください：

- **パラメータは少ない方が良い**: パラメータ数を最小限にして複雑さを減らす
- **シンプルなデータ型**: 可能な限りカスタムクラスよりも `str` や `int` などのプリミティブ型を優先
- **意味のある名前**: 関数名とパラメータ名は LLM がツールを解釈し活用する方法に大きく影響します。関数の目的と入力の意味を明確に反映する名前を選んでください。`do_stuff()` や `beAgent()` のような汎用的な名前は避けてください
- **並列実行のための設計**: 複数のツールが実行される際のパフォーマンスを向上させるため、非同期操作に対応した設計を行ってください

### 動作確認

ADK Web インターフェース (http://localhost:8000) で **step01** を選択して、以下を試してください：

#### 成功パターン：
- "東京の天気を教えて"
- "ニューヨークは今どんな天気？"
- "ロンドンの気温は？"

#### エラーパターン（わざと試してみよう）：
- "パリの天気は？" （データベースにない都市）
- "大阪の天気を教えて" （未登録の都市）

### 🎯 このステップで学んだこと
- Agent にツール（関数）を追加する方法
- 関数の戻り値を使った Agent の応答生成
- エラーハンドリングの重要性

---

## Step 02. Agentチームを作ってみよう！

### Multi-Agent アーキテクチャの理解

複数の Agent を連携させることで、より複雑なタスクを処理できます。このステップでは、ニュース Agent と天気 Agent を統括するコーディネーター Agent を作成します。

```
┌─────────────────┐
│  Root Agent     │ ← ユーザーと対話、タスクを振り分け
│ (Coordinator)   │
└────────┬────────┘
         │
    ┌────┴────┐
    │         │
┌───▼───┐ ┌──▼────┐
│ News   │ │Weather│ ← 専門タスクを実行
│ Agent  │ │ Agent │
└────────┘ └───────┘
```

### コードの構造を理解しよう

<walkthrough-editor-open-file filePath="./step02/agent.py">step02/agent.py</walkthrough-editor-open-file> を開いて、以下の重要な部分を確認しましょう：

1. **AgentTool の使用**：
```python
from google.adk.tools.agent_tool import AgentTool

# search_agent を他の Agent のツールとして使えるようにラップ
news_tool = AgentTool(agent=search_agent)
```

2. **Sub-agents の設定**：
```python
root_agent = LlmAgent(
    name="root_agent",
    sub_agents=[news_agent, weather_agent]  # ← サブエージェントを指定
)
```

### 実習：news_agent を追加しよう

<walkthrough-editor-select-line filePath="./step02/agent.py" startLine=70 endLine=71 startCharacterOffset=4 endCharacterOffset=41>step02/agent.py の 71行目</walkthrough-editor-select-line> を以下のように修正してください：

**修正前：**
```python
sub_agents=[weather_agent]
```

**修正後：**
```python
sub_agents=[news_agent, weather_agent]
```

### 動作確認

ADK Web インターフェースで **step02** を選択して、以下を試してください：

#### 複合的な質問：
- "今日の東京の天気とニュースを教えて"
- "最新のAIニュースは？"
- "ニューヨークの天気と、テクノロジーのニュースをお願い"

#### Agent の役割分担を確認：
- "何ができるの？" （Root Agent がチームの能力を説明）
- "天気だけ教えて" （Weather Agent が対応）
- "ニュースだけ見せて" （News Agent が対応）

### 🎯 このステップで学んだこと
- Multi-Agent アーキテクチャの基本
- AgentTool を使った Agent の階層化
- sub_agents による Agent チームの構築
- タスクの自動振り分けメカニズム

---

## Step 03. Agent に記憶を持たせる

### 状態管理でよりスマートな Agent へ

このステップでは、Agent にユーザーの好みや情報を記憶させ、パーソナライズされた応答を可能にします。

### 状態管理の仕組み

<walkthrough-editor-open-file filePath="./step03/agent.py">step03/agent.py</walkthrough-editor-open-file> を開いて、以下の重要な機能を確認しましょう：

1. **状態保存関数**：
```python
from google.adk.tools.tool_context import ToolContext

def append_to_state(
        tool_context: ToolContext, field: str, response: str
) -> dict[str, str]:
    """ユーザー情報を状態に保存"""
    existing_state = tool_context.state.get(field, [])
    tool_context.state[field] = existing_state + [response]
    return {"status": "success"}
```

2. **テンプレート変数の使用**：
```python
instruction="最近のニュースを教えてください。関心のニュース {{ favorite_topic? }} があれば、それのみ教えてください。"
```
`{{ favorite_topic? }}` は、保存された状態から値を参照します。

3. **Root Agent の設定**：
```python
root_agent = LlmAgent(
    name="root_agent",
    instruction="""
    ユーザにどんなニュースに興味あるか聞いてみてください。
    ユーザの興味あるニュースは favorite_topic の field に保存してください。
    ユーザの現在いる街は current_city の field に保存してください
    """,
    tools=[append_to_state]  # ← 状態保存ツールを追加
)
```

### 動作確認

ADK Web インターフェースで **step03** を選択して、以下の会話を試してください：

#### セッション 1（情報を記憶させる）：
1. "こんにちは"
2. "私は東京に住んでいて、AIのニュースに興味があります"
3. "今日のニュースを教えて"（AIニュースが優先的に表示される）

#### セッション 2（記憶の活用）：
1. "天気を教えて"（東京の天気が表示される）
2. "他の都市の天気は？"
3. "最新ニュースは？"（AIニュースが表示される）

### 🎯 このステップで学んだこと
- ToolContext を使った状態管理
- append_to_state によるユーザー情報の保存
- テンプレート変数 {{ }} による動的な instruction
- パーソナライズされた Agent 体験の実装

---

## Step 04. AgentEngine に Deploy

### プロダクション環境へのデプロイ

これまでローカルで開発した Agent を、Google Cloud の Agent Engine にデプロイして、本番環境で利用できるようにします。

### デプロイの準備

1. **環境変数の追加設定**：
```bash
# LOCATION とSTAGING_BUCKET を .env に追加
cat >> .env <<EOF
LOCATION=${GOOGLE_CLOUD_LOCATION}
STAGING_BUCKET=gs://${GOOGLE_CLOUD_PROJECT}-agent-staging
EOF
```

2. **ステージングバケットの作成**（必要な場合）：
```bash
gsutil mb -p ${GOOGLE_CLOUD_PROJECT} -l ${GOOGLE_CLOUD_LOCATION} gs://${GOOGLE_CLOUD_PROJECT}-agent-staging
```

### Agent のデプロイ

<walkthrough-editor-open-file filePath="./step03/deploy.py">step03/deploy.py</walkthrough-editor-open-file> を確認して、デプロイスクリプトの構造を理解しましょう。

**デプロイを実行**：
```bash
cd step03
uv run python deploy.py
```

デプロイには約 5-10 分かかります。完了すると以下のようなメッセージが表示されます：
```
Creating agent engine...
Agent created with ID: 7776190434329493504
Cleaning up the temp folder: /tmp/agent_engine〜
```

### デプロイした Agent への接続

<walkthrough-editor-open-file filePath="./step04/agent.py">step04/agent.py</walkthrough-editor-open-file> を開いて、デプロイした Agent ID を更新します：

```python
AGENT_ID = "YOUR_DEPLOYED_AGENT_ID"  # ← デプロイ時に表示された ID に変更
```

### デプロイした Agent のテスト

1. **基本的な問い合わせ**：
```bash
uv run python query.py "あなたは何ができますか？"
```

2. **天気の問い合わせ**：
```bash
uv run python query.py "東京の天気を教えて"
```

3. **ニュースの取得**：
```bash
uv run python query.py "最新のAIニュースを教えて"
```

4. **複合的な質問**：
```bash
uv run python query.py "今日の東京の天気と最新のテクノロジーニュースを教えて"
```

### Remote Agent Proxy パターン

Step04 の agent.py は「Remote Agent Proxy」パターンを実装しています：

```python
async def call_remote_agent(
    callback_context: CallbackContext, llm_request: LlmRequest
) -> LlmResponse:
    """デプロイされた Agent を呼び出すプロキシ関数"""
    session = remote_agent.create_session(user_id='default_user')
    events = remote_agent.stream_query(
        user_id='default_user',
        session_id=session['id'],
        message=str(llm_request.contents)
    )
    # ...
```

これにより、ローカルの ADK Web インターフェースから、クラウドにデプロイした Agent を利用できます。

### トラブルシューティング

#### デプロイが失敗する場合：
- API が有効化されているか確認: `gcloud services list --enabled`
- 権限を確認: `gcloud projects get-iam-policy ${GOOGLE_CLOUD_PROJECT}`
- クォータを確認: Console → IAM & Admin → Quotas

#### Agent が応答しない場合：
- Agent ID が正しいか確認
- .env ファイルの設定を確認
- Agent Engine のログを確認:
```bash
gcloud logging read "resource.type=aiplatform.googleapis.com/Agent" --limit 50
```

### 🎯 このステップで学んだこと
- Agent Engine へのデプロイプロセス
- AdkApp を使った本番環境の構築
- Remote Agent Proxy パターンの実装
- デプロイした Agent のテストとデバッグ

## おめでとうございます!
これで Tutorial が完了しました.

次のステップ:
- プロンプトをカスタマイズする
- 独自のサブエージェントを追加する
