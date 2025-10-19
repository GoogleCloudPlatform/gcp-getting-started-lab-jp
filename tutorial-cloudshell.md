---
title: "AI Agents: Weather & News"
description: "ADK を用いて金融アドバイスを提供する AI Agents を作成するチュートリアル"
duration: 60
level: Beginner
tags: [AI Agents, ADK, Python, "Weather & News", Gemini]
---

# AI Agents: Weather & News

ADK (Agent Development Kit) を用いて, シンプルな単体 Agent  を作成するチュートリアルです.

## 事前準備: Google アカウント認証とプロジェクトの設定

- Google アカウント認証
- プロジェクトの設定
- 必要な API の有効化

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

設定内容を確認

```bash
cat .env
```

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

- "GOOGLの最新情報を教えて"
- "MSFTのトレーディング戦略を提案して"

## Step 01. エージェントの仕組み

このエージェントは4つのサブエージェントで構成されています:

### 1. Data Analyst
- Google検索を使用して市場データを収集
- SEC filings、ニュース、アナリストレポートを分析
- 包括的な市場分析レポートを生成

### 2. Trading Analyst
- 市場分析に基づいてトレーディング戦略を提案
- ユーザーのリスク態度と投資期間を考慮
- 5つ以上の異なる戦略オプションを提供

### 3. Execution Analyst
- トレーディング戦略の実行計画を策定
- エントリー/エグジットのタイミング、注文タイプを提案
- ポジションサイジングとリスク管理を含む

### 4. Risk Analyst
- 提案された計画の総合的なリスク評価
- 市場リスク、流動性リスク、心理的リスクを分析
- 具体的なリスク軽減策を提案

## Step 02. カスタマイズ

### プロンプトの編集

日本語プロンプトは以下のファイルに記載されています:

```bash
cloudshell edit financial_advisor/prompt.py
```

### サブエージェントのカスタマイズ

各サブエージェントのプロンプトを編集できます:

```bash
cloudshell edit financial_advisor/sub_agents/data_analyst/prompt.py
cloudshell edit financial_advisor/sub_agents/trading_analyst/prompt.py
cloudshell edit financial_advisor/sub_agents/execution_analyst/prompt.py
cloudshell edit financial_advisor/sub_agents/risk_analyst/prompt.py
```

## Step 03. カスタマイズ

## Step 04. カスタマイズ

## おめでとうございます!

これで Financial Advisor Agent の構築が完了しました.

次のステップ:
- 異なる銘柄で試してみる
- プロンプトをカスタマイズする
- 独自のサブエージェントを追加する
