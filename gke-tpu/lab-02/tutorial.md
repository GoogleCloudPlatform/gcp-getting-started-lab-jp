<walkthrough-metadata>
  <meta name="title" content="Lab 02: Building an Advanced TPU Inference Platform with GKE Inference Gateway" />
  <meta name="description" content="Comprehensive tutorial for deploying Qwen models on TPU v5e using GKE Autopilot, configuring advanced traffic management, and observability." />
</walkthrough-metadata>

<walkthrough-disable-features toc></walkthrough-disable-features>

# Lab 02: GKE Inference Gateway による TPU 推論基盤の構築

本ラボでは、Google Kubernetes Engine (GKE) 上で **本番運用を見据えた TPU 推論基盤** を構築します。
単にモデルを動かすだけでなく、**GKE Inference Gateway** をフル活用し、「負荷に応じた賢い分散」や「リクエスト内容に基づくルーティング」、「可視化」までを一気通貫で実装します。

**本ラボのゴール:**
1.  **堅牢なネットワーク:** 推論専用 VPC とプロキシ専用サブネットの構築
2.  **マルチ TPU 構成:** 複数の TPU ノード (v5e) へのスケールアウト
3.  **高度なルーティング:** Inference Gateway による負荷分散と Body-Based Routing
4.  **可視化:** Cloud Monitoring での推論メトリクス（KV キャッシュ等）の確認

---

## **1. プロジェクトとネットワークの準備**

今回は、Inference Gateway (リージョン外部ロードバランサ) を利用するため、Envoy プロキシが配置される **「プロキシ専用サブネット」** が必須です。まずはネットワークと各種サブネットから作成します。

### **1.1 環境変数の設定**

```bash
export PROJECT_ID=$(gcloud projects list --filter="projectId ~ '^qwiklabs-gcp-' AND projectId != 'qwiklabs-resources'" --format="value(projectId)" | head -n 1)

gcloud config set project $PROJECT_ID
export REGION="us-central1"
export CLUSTER_NAME="inference-gateway-lab"
export NETWORK_NAME="inference-vpc"
export SUBNET_NAME="inference-subnet"

echo "Project: $PROJECT_ID / Region: $REGION"
```

### **1.2 API の有効化**

```bash
gcloud services enable \
  container.googleapis.com \
  cloudresourcemanager.googleapis.com \
  artifactregistry.googleapis.com \
  networkservices.googleapis.com \
  servicenetworking.googleapis.com \
  monitoring.googleapis.com \
  logging.googleapis.com
```

### **1.3 VPC とサブネットの作成**

GKE ノード用のサブネットに加え、**プロキシ専用サブネット (Proxy-only Subnet)** を作成します。

```bash
# VPC 作成
gcloud compute networks create ${NETWORK_NAME} \
  --project=${PROJECT_ID} \
  --subnet-mode=custom \
  --bgp-routing-mode=regional

# GKE用サブネット
gcloud compute networks subnets create ${SUBNET_NAME} \
  --project=${PROJECT_ID} \
  --network=${NETWORK_NAME} \
  --region=${REGION} \
  --range=10.0.0.0/20 \
  --secondary-range=pods-range=10.4.0.0/14,services-range=10.8.0.0/20

# プロキシ専用サブネット
gcloud compute networks subnets create proxy-only-subnet \
  --project=${PROJECT_ID} \
  --purpose=REGIONAL_MANAGED_PROXY \
  --role=ACTIVE \
  --region=${REGION} \
  --network=${NETWORK_NAME} \
  --range=10.129.0.0/23
```

---

## **2. GKE クラスタと機能拡張のインストール**

### **2.1 GKE Autopilot クラスタの作成**

TPU v5e を利用可能な Autopilot クラスタを作成します。

```bash
echo "クラスタ作成中... (約 5〜10 分かかります)"
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
echo "待機中..."
sleep 60
until gcloud container clusters describe ${CLUSTER_NAME} --region=${REGION} --format="value(status)" 2>/dev/null | grep -q "RUNNING"; do
  echo -n "."
  sleep 20
done
echo "クラスタ準備完了"

# クレデンシャルの取得
gcloud container clusters get-credentials ${CLUSTER_NAME} --region=${REGION}
```

### **2.2 Gateway API Inference Extension (CRD) のインストール**

AI 推論専用の機能 (`InferencePool` 等) を有効化します。

```bash
kubectl apply -f [https://github.com/kubernetes-sigs/gateway-api-inference-extension/releases/download/v1.0.0/manifests.yaml](https://github.com/kubernetes-sigs/gateway-api-inference-extension/releases/download/v1.0.0/manifests.yaml)
```

---

## **3. 推論モデル (vLLM / Qwen2.5) のデプロイ**

今回はモデルとして `Qwen/Qwen2.5-14B-Instruct` を使用します。
Inference Gateway の負荷分散効果を確認するため、 2つの Pod を起動します。

### **3.1 モデルサーバーのデプロイ**

以下のマニフェストを適用します。
* **TPU v5e (4チップ)** を指定
* **Replicas: 2** (2つのノードで分散)
* **起動コマンド** を明示的に指定 (コンテナの即時終了を防ぐため)

```bash
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: vllm-qwen
  labels:
    app: vllm-qwen
spec:
  replicas: 2
  selector:
    matchLabels:
      app: vllm-qwen
  template:
    metadata:
      labels:
        app: vllm-qwen
    spec:
      containers:
      - name: inference-server
        image: vllm/vllm-tpu:latest
        command: ["python3", "-m", "vllm.entrypoints.openai.api_server"]
        args:
        - "--model=Qwen/Qwen2.5-14B-Instruct"
        - "--tensor-parallel-size=4"
        - "--max-model-len=4096"
        - "--gpu-memory-utilization=0.95"
        - "--trust-remote-code"
        - "--disable-log-stats"
        - "--port=8000"
        resources:
          requests:
            cpu: "8"
            memory: "30Gi"
            ephemeral-storage: "50Gi"
            [google.com/tpu](https://google.com/tpu): 4
          limits:
            [google.com/tpu](https://google.com/tpu): 4
        ports:
        - containerPort: 8000
        env:
        - name: PJRT_DEVICE
          value: "TPU"
        readinessProbe:
          httpGet:
            path: /health
            port: 8000
          initialDelaySeconds: 60
          periodSeconds: 10
        volumeMounts:
        - name: dshm
          mountPath: /dev/shm
      nodeSelector:
        [cloud.google.com/gke-tpu-accelerator](https://cloud.google.com/gke-tpu-accelerator): tpu-v5-lite-podslice
        [cloud.google.com/gke-tpu-topology](https://cloud.google.com/gke-tpu-topology): 2x2
      volumes:
      - name: dshm
        emptyDir:
          medium: Memory
EOF
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

```bash
cat <<EOF | kubectl apply -f -
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: inference-gateway
spec:
  gatewayClassName: gke-l7-regional-external-managed
  listeners:
  - name: http
    protocol: HTTP
    port: 80
    allowedRoutes:
      namespaces:
        from: Same
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: qwen-route
spec:
  parentRefs:
  - name: inference-gateway
  rules:
  - matches:
    - path:
        type: PathPrefix
        value: /v1
    backendRefs:
    - name: qwen-pool
      group: inference.networking.k8s.io
      kind: InferencePool
      port: 8000
EOF
```

---

## **4. 動作確認と負荷分散テスト**

### **4.1 起動確認**

Gateway の IP アドレスが払い出され、Pod が 2 つとも `Running` になるまで待ちます。

```bash
# Gateway IPの取得待ち
echo "Gateway IPの払い出しを待機中..."
GATEWAY_IP=""
while [ -z "$GATEWAY_IP" ]; do
  GATEWAY_IP=$(kubectl get gateway inference-gateway -o jsonpath='{.status.addresses[0].value}')
  if [ -z "$GATEWAY_IP" ]; then
    echo -n "."
    sleep 5
  fi
done
echo -e "\nGateway IP: $GATEWAY_IP"

# Podの起動待ち (2/2)
echo "Podの起動を待機中 (モデルDLとコンパイルに数分かかります)..."
kubectl wait --for=condition=Ready pod -l app=vllm-qwen --timeout=900s
```

### **4.2 推論テストと負荷分散**

まずは単発のリクエストで疎通を確認します。

```bash
curl -i -X POST http://${GATEWAY_IP}/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "Qwen/Qwen2.5-14B-Instruct",
    "messages": [{"role": "user", "content": "GKE Inference Gatewayについて一言で"}],
    "max_tokens": 100
  }'
```

次に、**負荷分散の確認** です。10 回連続でリクエストを投げ、ログを確認します。Inference Gateway は、空いている TPU を優先して選びます。

```bash
# 10回連続送信
for i in {1..10}; do
  curl -s -o /dev/null -w "Request $i: HTTP %{http_code}\n" \
  -X POST http://${GATEWAY_IP}/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model": "Qwen/Qwen2.5-14B-Instruct", "messages": [{"role": "user", "content": "Hello"}], "max_tokens": 10}' &
done

# 少し待ってログ確認（両方のPodからログが出るか確認）
sleep 5
echo "--- Access Logs ---"
kubectl logs -l app=vllm-qwen --tail=10
```

---

## **5. 高度な機能: 可視化とボディベースルーティング**

ここからは Inference Gateway の高度な機能をご紹介します。

### **5.1 メトリクスを確認する**

Inference Gateway は各 Pod から **KV Cache Utilization (メモリ使用率)** や **Queue Size (待ち行列数)** を収集し、それに基づいて一番空いている Pod にリクエストを送ります。

**確認手順:**
1.  Google Cloud Console で **[モニタリング] > [Metrics Explorer]** を開きます。
2.  **[指標を選択]** をクリックし、`inference_pool_average_kv_cache_utilization` または `inference_pool_average_queue_size` を検索します。
3.  グラフが表示されれば、Gateway が「どの Pod が忙しいか」をリアルタイムで把握している証拠です。

### **5.2 HTTP アクセスログの有効化**

Gateway がどのバックエンドを選んだかを詳細に追跡するため、ログを有効化します。

```bash
cat <<EOF | kubectl apply -f -
apiVersion: networking.gke.io/v1
kind: GCPBackendPolicy
metadata:
  name: logging-backend-policy
  namespace: default
spec:
  default:
    logging:
      enabled: true
      sampleRate: 1.0 # 検証用のため全件記録
  targetRef:
    group: inference.networking.k8s.io
    kind: InferencePool
    name: qwen-pool
EOF
```

### **5.3 本文ベースルーティング (Body-Based Routing)**

通常のロードバランサは URL パスしか見ませんが、Inference Gateway は **JSON ボディ内のモデル名** (`"model": "..."`) を見てルーティングできます。

**1. 拡張機能のインストール:**
```bash
helm install body-based-router oci://registry.k8s.io/gateway-api-inference-extension/charts/body-based-routing \
    --set provider.name=gke \
    --set inferenceGateway.name=inference-gateway \
    --version 0.1.0
```

**2. ルート定義の更新:**
「モデル名が `Qwen/Qwen2.5-14B-Instruct` の時だけ通す」設定に変更します。

```bash
cat <<EOF | kubectl apply -f -
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: qwen-route
spec:
  parentRefs:
  - name: inference-gateway
  rules:
  - matches:
    # 拡張機能がボディからモデル名を抽出し、このヘッダーにセットする
    - headers:
      - type: Exact
        name: X-Gateway-Model-Name
        value: "Qwen/Qwen2.5-14B-Instruct"
      path:
        type: PathPrefix
        value: /v1
    backendRefs:
    - name: qwen-pool
      group: inference.networking.k8s.io
      kind: InferencePool
      port: 8000
EOF
```

**3. 検証:**
```bash
# A: 正しいモデル名 -> 成功 (200 OK)
curl -i -X POST http://${GATEWAY_IP}/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model": "Qwen/Qwen2.5-14B-Instruct", "messages": [{"role": "user", "content": "Correct"}]}'

# B: 間違ったモデル名 -> 失敗 (404 Not Found)
curl -i -X POST http://${GATEWAY_IP}/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model": "Wrong-Model", "messages": [{"role": "user", "content": "Wrong"}]}'
```

これにより、Gateway がリクエストの中身（L7）を理解して制御していることが証明されます。

---

## **Congratulations!**

これで Lab 02 は完了です。
TPU 上での推論、そして Inference Gateway による高度なトラフィック制御までを実践しました。
この基盤は、大規模な LLM サービスを安定して運用するための強力な武器となります。