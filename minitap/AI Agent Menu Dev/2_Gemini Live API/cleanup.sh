#!/bin/bash

echo "🧹 ハンズオンで作成したリソースをクリーンアップします..."

# ★ ユーザーアカウントからユニークな接尾辞を自動生成
ACCOUNT_SUFFIX=$(gcloud config get-value account | cut -d '@' -f 1)
PROJECT_ID=$(gcloud config get-value project)
REGION=us-central1

# ★ ユニークなリソース名を定義
BACKEND_SERVICE_NAME="cafe-agent-backend-${ACCOUNT_SUFFIX}"
FRONTEND_SERVICE_NAME="cafe-agent-app-${ACCOUNT_SUFFIX}"
BACKEND_SA_NAME="cafe-agent-sa-${ACCOUNT_SUFFIX}"
FRONTEND_SA_NAME="cafe-agent-app-sa-${ACCOUNT_SUFFIX}"

echo "以下のリソースを削除します:"
echo "  - Cloud Run Service (Backend): $BACKEND_SERVICE_NAME"
echo "  - Cloud Run Service (Frontend): $FRONTEND_SERVICE_NAME"
echo "  - Service Account (Backend): ${BACKEND_SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
echo "  - Service Account (Frontend): ${FRONTEND_SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
echo "注: Artifact Registryのリポジトリは共有のため、このスクリプトでは削除しません。"

# 1. Cloud Runサービスの削除
echo "--- Deleting Cloud Run services..."
gcloud run services delete $FRONTEND_SERVICE_NAME --region $REGION --quiet
gcloud run services delete $BACKEND_SERVICE_NAME --region $REGION --quiet

# 2. サービスアカウントの削除
echo "--- Deleting service accounts..."
gcloud iam service-accounts delete "${FRONTEND_SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com" --quiet
gcloud iam service-accounts delete "${BACKEND_SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com" --quiet

echo "✅ クリーンアップが完了しました。"