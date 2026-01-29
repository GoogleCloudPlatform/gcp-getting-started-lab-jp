<walkthrough-metadata>
  <meta name="title" content="Lab 02: Building an Advanced TPU Inference Platform with GKE Inference Gateway" />
  <meta name="description" content="Comprehensive tutorial for deploying Qwen models on TPU v5e using GKE Autopilot, configuring advanced traffic management, and observability." />
</walkthrough-metadata>

<walkthrough-disable-features toc></walkthrough-disable-features>

# Lab 02: GKE Inference Gateway による TPU 推論基盤の構築

本ラボでは、Google Kubernetes Engine (GKE) 上で **本番運用を見据えた AI 推論基盤** を構築します。
単にモデルを動かすだけでなく、**GKE Inference Gateway** をフル活用し、「負荷に応じた賢い分散」や「リクエスト内容に基づくルーティング」、「可視化」までを一気通貫で実装します。

**本ラボのゴール:**
- **GKE TPU 構成:** GKE ノードで TPU を利用する
- **高度なルーティング:** Inference Gateway による負荷分散と Body-Based Routing
- **可視化:** Cloud Monitoring での推論メトリクス（KV キャッシュ等）の確認

---

## **1. プロジェクトとネットワークの準備**

GKE で利用する VPC 及びサブネットを作成していきます。また、今回は Inference Gateway (リージョン外部ロードバランサ) を利用するため、Envoy プロキシが配置されるプロキシ専用サブネットの作成が含まれます。

### **1.1 環境変数の設定**

```
export PROJECT_ID=$(gcloud projects list --filter="projectId ~ '^qwiklabs-' AND projectId != 'qwiklabs-resources'" --format="value(projectId)" | head -n 1)
gcloud config set project $PROJECT_ID
export REGION="us-west1"
export CLUSTER_NAME="inference-gateway-lab"
export NETWORK_NAME="inference-vpc"
export SUBNET_NAME="inference-subnet"
echo "Project: $PROJECT_ID / Region: $REGION"
```

### **1.2 API の有効化**

```bash
gcloud services enable \
  compute.googleapis.com \
  container.googleapis.com \
  cloudresourcemanager.googleapis.com \
  artifactregistry.googleapis.com \
  networkservices.googleapis.com \
  servicenetworking.googleapis.com \
  monitoring.googleapis.com \
  logging.googleapis.com
```

### **1.3 VPC とサブネットの作成**

GKE ノード用のサブネット及び、**プロキシ専用サブネット (Proxy-only Subnet)** を作成します。

```bash
gcloud compute networks create ${NETWORK_NAME} \
  --project=${PROJECT_ID} \
  --subnet-mode=custom \
  --bgp-routing-mode=regional
```
```bash
gcloud compute networks subnets create ${SUBNET_NAME} \
  --project=${PROJECT_ID} \
  --network=${NETWORK_NAME} \
  --region=${REGION} \
  --range=10.0.0.0/20 \
  --secondary-range=pods-range=10.4.0.0/14,services-range=10.8.0.0/20
```
```bash
gcloud compute networks subnets create proxy-only-subnet \
  --project=${PROJECT_ID} \
  --purpose=REGIONAL_MANAGED_PROXY \
  --role=ACTIVE \
  --region=${REGION} \
  --network=${NETWORK_NAME} \
  --range=10.129.0.0/23
```

## **2. GKE クラスタと機能拡張のインストール**

### **2.1 GKE Autopilot クラスタの作成**

TPU v5e を利用可能な Autopilot クラスタを作成します。

```bash
echo "Provisioning..."
gcloud container clusters create-auto ${CLUSTER_NAME} \
  --project=${PROJECT_ID} \
  --region=${REGION} \
  --network=${NETWORK_NAME} \
  --subnetwork=${SUBNET_NAME} \
  --cluster-secondary-range-name=pods-range \
  --services-secondary-range-name=services-range \
  --release-channel=rapid \
  --async
```

クラスタが `RUNNING` になるまで待機します。

```bash
echo "Provisioning..."; sleep 60; until gcloud container clusters describe ${CLUSTER_NAME} --region=${REGION} --format="value(status)" 2>/dev/null | grep -q "RUNNING"; do echo -n "."; sleep 20; done; echo "Completed"
```
作成したクラスタを操作できるようにクレデンシャルの取得をします。
```bash
gcloud container clusters get-credentials ${CLUSTER_NAME} --region=${REGION}
```

### **2.2 Gateway API Inference Extension (CRD) のインストール**

AI 推論専用の機能 (`InferencePool` 等) を有効化します。

```bash
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api-inference-extension/releases/download/v1.0.0/manifests.yaml
```

---

## **3. 推論モデル (vLLM / Qwen2.5) のデプロイ**

今回は `Qwen/Qwen2.5-14B-Instruct` を使用します。
Inference Gateway の負荷分散効果を確認するため、**2つの Pod (Replicas: 2)** で起動します。

### **3.1 モデルサーバーのデプロイ**

事前に用意されているマニフェストを表示して確認します。
```bash
cat vllm.yaml
```
* **TPU v5e (4チップ)** を指定
* **Replicas: 2** (2つのノードで分散)
* **起動コマンド** を明示的に指定 (コンテナの即時終了を防ぐため)

作成したマニフェストを適用します
```bash
kubectl apply -f vllm.yaml
```

モデルのダウンロードとコンパイルには数分かかります。その間にゲートウェイの設定を進めます。

### **3.2 InferencePool の作成**

`Service` の代わりに `InferencePool` を作成します。これにより、サイドカー (Endpoint Picker) が注入され、各 Pod の負荷状況（KV キャッシュ等）に基づいたルーティングが可能になります。

```bash
helm install qwen-pool \
  --set inferencePool.modelServers.matchLabels.app=vllm-qwen \
  --set inferencePool.selector.matchLabels.app=vllm-qwen \
  --set inferencePool.targetPort=8000 \
  --set provider.name=gke \
  --set provider.gke.autopilot=true \
  --version v1.0.1 \
  oci://registry.k8s.io/gateway-api-inference-extension/charts/inferencepool
```

### **3.3 Gateway と HTTPRoute の作成**

推論サーバーへのルーティングを提供するロードバランサー＝ゲートウェイを作成します。
まずはマニフェストを確認します。
```bash
cat gateway.yaml
```
マニフェストを適用します。
```bash
kubectl apply -f gateway.yaml
```

---

## **4. 動作確認と推論テスト**

### **4.1 起動確認**

Gateway の IP アドレスが払い出され、Pod が `Running` になるまで待ちます。

```bash
echo "Provisioning..."
GATEWAY_IP=""
while [ -z "$GATEWAY_IP" ]; do
  GATEWAY_IP=$(kubectl get gateway inference-gateway -o jsonpath='{.status.addresses[0].value}')
  if [ -z "$GATEWAY_IP" ]; then
    echo -n "."
    sleep 5
  fi
done
echo -e "Gateway IP: $GATEWAY_IP"
```
以下のコマンドにより Pod が Ready になるまで待ちます。

```bash
kubectl wait --for=condition=Ready pod -l app=vllm-qwen --timeout=900s
```

### **4.2 推論テスト**

リクエストで疎通を確認します。

```bash
curl -i -X POST http://${GATEWAY_IP}/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "Qwen/Qwen2.5-14B-Instruct",
    "messages": [{"role": "user", "content": "GKE Inference Gatewayについて一言で"}],
    "max_tokens": 100
  }'
```

次に、**負荷分散の確認** です。10 回連続でリクエストを投げ、ログを確認します。

```bash
for i in {1..10}; do
  curl -s -o /dev/null -w "Request $i: HTTP %{http_code}\n" \
  -X POST http://${GATEWAY_IP}/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model": "Qwen/Qwen2.5-14B-Instruct", "messages": [{"role": "user", "content": "Hello"}], "max_tokens": 10}' &
done
```
少し待ってログを確認します
```bash
sleep 5
echo "--- Access Logs ---"
kubectl logs -l app=vllm-qwen --tail=10
```

---

## **5. 高度な機能: 可視化とボディベースルーティング**


### **5.1 メトリクスを確認する**

Inference Gateway は各 Pod から **KV Cache Utilization (メモリ使用率)** や **Queue Size (待ち行列数)** を収集し、それに基づいて一番空いている Pod にリクエストを送ります。

**確認手順:**
1.  Google Cloud Console で **[モニタリング] > [Metrics Explorer]** を開きます。
2.  **[指標を選択]** をクリックし、`inference_pool_average_kv_cache_utilization` または `inference_pool_average_queue_size` を検索します。
3.  グラフが表示されれば、Gateway が Pod の推論によるリソース負荷状況をリアルタイムで把握している証拠です。

### **5.2 HTTP アクセスログの有効化**

Gateway がどのバックエンドを選んだかを詳細に追跡するため、ログを有効化します。
マニフェストを確認します。
```bash
cat backendpolicy.yaml
```
続いてマニフェストを適用します。
```bash
kubectl apply -f  backendpolicy.yaml
```

### **5.3 本文ベースルーティング (Body-Based Routing)**

通常のロードバランサは URL パスしか見ませんが、Inference Gateway は **JSON ボディ内のモデル名** (`"model": "..."`) を見てルーティングできます。

**1. 拡張機能のインストール:**
```bash
helm install body-based-router oci://registry.k8s.io/gateway-api-inference-extension/charts/body-based-routing \
    --set provider.name=gke \
    --set inferenceGateway.name=inference-gateway \
    --version v1.0.0
```

**2. ルート定義の更新:**
「モデル名が `Qwen/Qwen2.5-14B-Instruct` の時だけ通す」設定に変更します。
マニフェストを確認します。
```bash
cat body-routing.yaml
```
マニフェストを適用します。
```bash
kubectl apply -f body-routing.yaml
```

**3. 検証:**
正しいモデル名で検証します。
```bash
curl -i -X POST http://${GATEWAY_IP}/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model": "Qwen/Qwen2.5-14B-Instruct", "messages": [{"role": "user", "content": "Correct"}]}'
```
続いて誤ったモデル名で検証します。
```bash
curl -i -X POST http://${GATEWAY_IP}/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model": "Owen/Owen2.5-14B-Instruct", "messages": [{"role": "user", "content": "Wrong"}]}'
```

これにより、Gateway がリクエストの中身（L7）を理解して制御していることが証明されます。

---
## **Congratulations!**

おめでとうございます。これで Lab 02 は完了です。
TPU 上での推論、そして Inference Gateway による高度なトラフィック制御までを実践しました。
