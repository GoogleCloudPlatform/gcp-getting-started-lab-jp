# Deep Search Agent Development Kit (ADK) クイックスタート

> **注:** このエージェントは以前 `gemini-fullstack` という名前でしたが、`deep-search` に名称変更されました。以前の `gemini-fullstack` エージェントをお探しの方も、こちらで問題ありません！機能はすべて同一です。

**Deep Search Agent Development Kit (ADK) クイックスタート**は、Gemini を活用した洗練されたフルスタック・リサーチ・エージェントを構築するための、本番環境対応（Production-Ready）のブループリントです。ADK がどのように複雑なエージェンティック（自律的）・ワークフローを構造化し、モジュール式のエージェントを構築し、そして重要なヒューマン・イン・ザ・ループ（HITL：人間参加型）のステップを組み込むかを示すために設計されています。

<table>
  <thead>
    <tr>
      <th colspan="2">主な機能</th>
    </tr>
  </thead>
  <tbody>
    <tr>
      <td>🏗️</td>
      <td><strong>フルスタック & 本番対応:</strong> 完全な React フロントエンドと ADK 駆動の FastAPI バックエンドを備え、<a href="https://cloud.google.com/run">Google Cloud Run</a> および <a href="https://cloud.google.com/vertex-ai/generative-ai/docs/agent-engine/overview">Vertex AI Agent Engine</a> へのデプロイオプションが含まれています。</td>
    </tr>
    <tr>
      <td>🧠</td>
      <td><strong>高度なエージェンティック・ワークフロー:</strong> エージェントは Gemini を使用してマルチステップの計画を<strong>策定 (Strategize)</strong> し、調査結果を<strong>振り返って (Reflect)</strong> 情報の欠落を特定し、最終的な包括的レポートを<strong>統合 (Synthesize)</strong> します。</td>
    </tr>
    <tr>
      <td>🔄</td>
      <td><strong>反復的 & HITL リサーチ:</strong> 計画の承認プロセスにユーザーを巻き込み、その後、（Gemini の関数呼び出しを介して）十分な情報が集まるまで自律的に検索と結果の精査をループします。</td>
    </tr>
  </tbody>
</table>

エージェントの動作イメージは以下の通りです：

<img src="https://github.com/GoogleCloudPlatform/agent-starter-pack/blob/main/docs/images/adk_gemini_fullstack.gif?raw=true" width="80%" alt="Gemini Fullstack ADK Preview">

このプロジェクトのフロントエンドアプリは、[Gemini FullStack LangGraph Quickstart](https://github.com/google-gemini/gemini-fullstack-langgraph-quickstart) のコンセプトを適応させています。

## 🚀 はじめに: ゼロから1分でエージェントを実行する
**前提条件:** **[Python 3.10+](https://www.python.org/downloads/)**, **[Node.js](https://nodejs.org/)**, **[uv](https://github.com/astral-sh/uv)**

セットアップ環境に合わせて、以下の2つのオプションから選択してください：

* A. **[Google AI Studio](#a-google-ai-studio)**: **Google AI Studio API キー** を使用したい場合はこちらを選択してください。この方法ではサンプルリポジトリをクローンして使用します。
* B. **[Google Cloud Vertex AI](#b-google-cloud-vertex-ai)**: 既存の **Google Cloud プロジェクト** を認証に使用したい場合はこちらを選択してください。この方法では、[agent-starter-pack](https://goo.gle/agent-starter-pack) を使用して、必要なデプロイ用スクリプトを含む本番対応の新しいプロジェクトを生成します。

---

### A. Google AI Studio

**[Google AI Studio API キー](https://aistudio.google.com/app/apikey)** が必要になります。

#### ステップ 1: リポジトリのクローン
リポジトリをクローンし、プロジェクトディレクトリへ `cd` コマンドで移動します。

```bash
git clone [https://github.com/google/adk-samples.git](https://github.com/google/adk-samples.git)
cd adk-samples/python/agents/deep-search