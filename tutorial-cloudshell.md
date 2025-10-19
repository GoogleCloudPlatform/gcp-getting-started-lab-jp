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

## Step 00. Hello World Agent

### ローカル環境で Agent を動かしてみる

```bash
adk web
```

Cloud Shell の Web Preview 機能を使ってアクセスします:
1. 上部メニューの「ウェブでプレビュー」をクリック
2. ポート 8000 を選択
3. ブラウザで UI が開きます.
4. Agent 一覧で step 00 を選んでください。

### プロンプトの入力例

以下のような質問をしてみてください:

- "こんにちは！"
- "東京の天気は？"

## Step 01. 単体 Agentを作ってみよう！


## Step 02. Agentチームを作ってみよう！

### プロンプトの編集
<walkthrough-editor-select-line filePath="./step02/agent.py" startLine=70 endLine=71 startCharacterOffset=4 endCharacterOffset=41>step02/agent.py</walkthrough-editor-select-line> の`root_agent`に`news_agent`を追加してください。

Hint: 

```shell
root_agent = LlmAgent(
    name="root_agent",
    model="gemini-2.5-flash",
    description="メインコーディネーターエージェント",
    instruction="""
    あなたは親切なニュースキャスターです。
    ユーザーの問い合わせに対して専門家のエージェントにタスクをアサインしてください。
    ユーザにあなたのチームがどんなお手伝いできるのかを教えてください。
    """,
    sub_agents=[news_agent, weather_agent]
)
```

## Step 03. Agent に記憶を持たせる

## Step 04. AgentEngine に Deploy

### 作業、動作確認手順

デプロイした AI エージェントにリクエストを投げて、ちゃんと動いていることを確認します。

1. [エディタ] 右下のターミナル選択画面から、先程 Agent Engine にデプロイをしていたセッション (bash と書かれているはずです) をクリックし、セッションを移ります

2. [エディタ] ログの最終行に以下のようなメッセージが表示されていれば、デプロイが完了しています

Cleaning up the temp folder: /tmp/agent_engine〜

3. [エディタ] 以下のコマンドを実行し、デプロイした AI エージェントに問い合わせします (例、あなたは何ができますか？)
```shell
uv run python query.py "あなたは何ができますか？"content_copy
```
4. [エディタ] 以下のコマンドを実行し、メッセージに URL を与えてポッドキャスト台本の生成を依頼します。(URL 部分は好きなものに変更してください)
```shell
uv run python query.py "今日の株式市場を教えてください"content_copy
```

## おめでとうございます!
これで Tutorial が完了しました.

次のステップ:
- プロンプトをカスタマイズする
- 独自のサブエージェントを追加する
