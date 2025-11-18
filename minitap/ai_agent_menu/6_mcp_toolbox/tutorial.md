# 🚀 MCP Toolbox for Databases を活用したAgentic Data Analytics MiniTAP

![Static Badge](https://img.shields.io/badge/Version-1.0-blue)
[![Static Badge](https://img.shields.io/badge/MCP-Toolbox%20for%20databases-yellow)](https://googleapis.github.io/genai-toolbox/getting-started/introduction/)
[![Static Badge](https://img.shields.io/badge/Gemini-Data%20Analytics-green?logo=googlegemini&logoColor=f5f5f5)](https://cloud.google.com/)

## 📊 MiniTAP 概要

この MiniTAP は、**MCP (Model Context Protocol) Toolbox for Databases** を活用して、Google Trends データの高度な分析を行うハンズオン学習環境です。ローカルエージェントと Agent Engine の両方で MCP Toolbox を活用し、AI エージェントによるデータ分析の最新手法を体験できます。

### 🎯 主な特徴

- ✅ **ADK (Agent Development Kit) 統合**: ローカル・リモート両対応
- ✅ **MCP Toolbox for Databases 統合**: YAML 設定ベースの柔軟なツール管理
- ✅ **Google Cloud Run デプロイ**: スケーラブルな本番環境対応
- ✅ **BigQuery パブリックデータセット**: Google Trends 国際データの活用
- ✅ **リアルタイム分析**: 最新のトレンドデータによる洞察生成

### 1. 環境セットアップ
```bash
# Google Cloud認証
gcloud auth application-default login
gcloud config set project YOUR_PROJECT_ID
```

### 2. 自動プロジェクトセットアップ

```bash
# プロジェクトIDの自動検出と設定
python setup/setup_project.py

# BigQuery環境の準備
python setup/bigquery_setup.py
```

### 3. MCP Toolbox デプロイ

```bash
# MCP Toolbox for DatabasesをCloud Runにデプロイ
python setup/deploy_toolbox.py
```

<walkthrough-editor-open-file filePath="./MiniTAP_Data_Analytics_Hands_On.ipynb">ここをクリック</walkthrough-editor-open-file>して、ハンズオンを開始してください。