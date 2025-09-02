#!/bin/bash

# export USE_ORDER_TOOL=True

echo "🚀 ハンズオン環境の自動セットアップを開始します..."

# --- 古いプロセスが残っていたら自動的に停止する ---
echo "🧹 古いサーバープロセスをクリーンアップします..."
pkill -f "python main.py"
pkill -f "next dev --hostname localhost --port 3001"
sleep 2 # プロセスが完全に停止するのを待つ

# --- バックエンドのセットアップ ---
echo "⚙️  バックエンドを準備中..."
cd backend
pip install -r requirements.txt > /dev/null 2>&1
echo "🧠 バックエンドサーバーをバックグラウンドで起動します..."
python main.py &
cd ..
sleep 5

# --- フロントエンドのセットアップ ---
echo "🎨 フロントエンドを準備中..."
cd frontend

echo "🌐 Cloud Shell APIにホスト名を問い合わせています..."
WEB_HOST=$(curl -s -H "Authorization: Bearer $(gcloud auth print-access-token)" https://cloudshell.googleapis.com/v1/users/me/environments/default | jq -r '.webHost')
BACKEND_URL="wss://8081-${WEB_HOST}/ws"
echo "✅ バックエンドURLを自動設定しました: ${BACKEND_URL}"

# .env.localファイルにURLを書き込む
echo "NEXT_PUBLIC_BACKEND_URL=${BACKEND_URL}" > .env.local

npm install > /dev/null 2>&1

# ポート番号を3001に変更
sed -i 's/--port 3000/--port 3001/' package.json

# --- 完了メッセージ ---
echo ""
echo "🎉 セットアップが完了しました！"
echo "右上の「ウェブでプレビュー」ボタンから「ポート3001でプレビュー」を選択して、アプリにアクセスしてください。"
echo "演習でプロンプトを修正した後は、このターミナルで Ctrl+C を押して停止し、再度 ./start_handson.sh を実行してください。"
echo ""

# フロントエンドサーバーをフォアグラウンドで起動
npm run dev
