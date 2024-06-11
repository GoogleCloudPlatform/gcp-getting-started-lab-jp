#!/bin/bash

echo "### 1. IP アドレスの取得"
gcloud compute addresses create knowledge-drive-ip \
  --network-tier=PREMIUM \
  --ip-version=IPV4 \
  --global
echo

echo "### 2. 証明書の作成"
KNOWLEDGE_DRIVE_IP=$(gcloud compute addresses describe knowledge-drive-ip --format="get(address)" --global) \
&& gcloud compute ssl-certificates create knowledge-drive-cert \
  --domains=kd-${KNOWLEDGE_DRIVE_IP//./-}.nip.io \
  --global
echo

echo "### 3. ネットワーク エンドポイント グループの作成"
gcloud compute network-endpoint-groups create knowledge-drive-neg \
  --region=asia-northeast1 \
  --network-endpoint-type=serverless  \
  --cloud-run-service=knowledge-drive
echo

echo "### 4. バックエンドサービスの作成"
gcloud compute backend-services create knowledge-drive-bs \
  --load-balancing-scheme=EXTERNAL_MANAGED \
  --global
echo

echo "### 5. バックエンドサービスとネットワーク エンドポイント グループの紐づけ"
gcloud compute backend-services add-backend knowledge-drive-bs \
  --global \
  --network-endpoint-group=knowledge-drive-neg \
  --network-endpoint-group-region=asia-northeast1
echo

echo "### 6. URL マップの作成"
gcloud compute url-maps create knowledge-drive-urlmap \
  --default-service knowledge-drive-bs
echo

echo "### 7. ターゲット HTTPS プロキシの作成"
gcloud compute target-https-proxies create knowledge-drive-proxy \
  --ssl-certificates=knowledge-drive-cert \
  --url-map=knowledge-drive-urlmap
echo

echo "### 8. 転送ルールの作成"
gcloud compute forwarding-rules create knowledge-drive-forwardingrule \
  --load-balancing-scheme=EXTERNAL_MANAGED \
  --network-tier=PREMIUM \
  --address=knowledge-drive-ip \
  --target-https-proxy=knowledge-drive-proxy \
  --global \
  --ports=443
echo

echo "### 9. ロードバランサの作成が完了するまで待機"
export KNOWLEDGE_DRIVE_IP=$(gcloud compute addresses describe knowledge-drive-ip --format="get(address)" --global) \
export KNOWLEDGE_DRIVE_URL="https://kd-${KNOWLEDGE_DRIVE_IP//./-}.nip.io"
START_DATE=$(TZ=Asia/Tokyo date '+%H時%M分%S秒')
echo -n "待機開始($START_DATE) "
while true
do
    curl -s -o /dev/null $KNOWLEDGE_DRIVE_URL
    if [ $? -eq 0 ]; then
        echo
        END_DATE=$(TZ=Asia/Tokyo date '+%H時%M分%S秒')
        echo "作成完了($END_DATE)"
        break
    fi
    sleep 10
    echo -n "."
done
echo 

echo "### ロードバランサ経由でのアクセス URL: $KNOWLEDGE_DRIVE_URL"