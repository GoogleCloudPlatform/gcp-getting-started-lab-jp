<walkthrough-metadata>
  <meta name="title" content="GKE Multi-Cluster Inference Gateway with TPUs and DRANET" />
  <meta name="description" content="TPU、Cloud Storage FUSE、マネージド DRANET を使用して、マルチクラスタ GKE Inference Gateway を構築するハンズオン" />
  <meta name="component_id" content="103" />
</walkthrough-metadata>

<walkthrough-disable-features toc></walkthrough-disable-features>

# GKE Inference Gateway マルチクラスタ TPU 編

このハンズオンでは、TPU v6e、Cloud Storage FUSE、GKE マネージド DRANET、マルチクラスタ GKE Inference Gateway を使い、2 リージョン構成の推論基盤を構築します。

## Google Cloud プロジェクトの設定、確認

### **1. 対象の Google Cloud プロジェクトを設定**

```bash
export PROJECT_ID=$(gcloud config get-value project)
echo $PROJECT_ID
```

必要に応じて、操作対象のプロジェクトを明示します。

```bash
gcloud config set project $PROJECT_ID
```

このラボでは TPU v6e の割り当てが必要です。既定では Spot VM の `ct6e-standard-1t` TPU ノードを `europe-west4-a` に 2 台、`asia-northeast1-b` に 1 台作成します。1 Pod あたり v6e 1 チップを使い、Europe は 2 Pod、Asia は 1 Pod、全体で 3 チップを使う想定です。割り当てが別ゾーンにある場合は、`lab-01/variables.tf` の `regions` と `region_to_tpu_zone` を更新してください。リージョンごとの台数を変える場合は、同じファイルの `region_to_tpu_node_count` も更新してください。
利用モデルは `Qwen/Qwen3-8B` です。

### **2. 必要なツールと認証**

Cloud Shell で実行している場合は、通常は Qwiklabs の一時アカウントでログイン済みです。まず、現在のアカウントとプロジェクトを確認します。

```bash
gcloud auth list --filter=status:ACTIVE --format="value(account)"
export PROJECT_ID="$(gcloud config get-value project)"
echo "$PROJECT_ID"
gcloud config set project "$PROJECT_ID"
```

期待する状態は、アクティブアカウントが `student-...@qwiklabs.net`、プロジェクトが Qwiklabs から払い出された `qwiklabs-...` のプロジェクトになっていることです。個人アカウントや別プロジェクトが表示された場合は、このラボの操作対象がずれているので、先に直してください。

Cloud Shell やローカル端末で認証が切れている場合は、次の順に実行します。

```bash
gcloud auth login
```

ブラウザで認証画面が開いたら、必ず Qwiklabs の一時アカウントを選びます。認可後、Cloud Shell に戻って次を確認します。

```bash
gcloud auth list --filter=status:ACTIVE --format="value(account)"
gcloud config set project "$PROJECT_ID"
```

Terraform などが Application Default Credentials を要求する場合があります。`terraform plan` や `terraform apply` で認証エラーが出た場合は、同じ Qwiklabs アカウントで ADC も更新します。

```bash
gcloud auth application-default login
gcloud auth application-default print-access-token >/dev/null && echo "ADC OK"
```

Cloud Shell でブラウザ連携がうまく動かない場合や、ローカル端末から実行していて URL と認証コードを手動で扱いたい場合は、次の形式を使います。

```bash
gcloud auth login --no-launch-browser
gcloud auth application-default login --no-launch-browser
```

表示された URL をブラウザで開き、Qwiklabs の一時アカウントで認可し、表示されたコードをターミナルに貼り付けます。

教材のルートディレクトリを環境変数に入れます。以降の手順は、この `LAB_DIR` を使って移動します。
`gcp-getting-started-lab-jp` のルートから実行している場合は `inference-gw` ディレクトリを、`inference-gw` の中で実行している場合は現在のディレクトリを使います。

このコマンドは ボタン実行が不可のため、コピー＆ペーストで行います。
```
if [ -d "./inference-gw/lab-01" ]; then
  export LAB_DIR="$(pwd)/inference-gw"
elif [ -d "./lab-01" ]; then
  export LAB_DIR="$(pwd)"
else
  echo "inference-gw directory not found. Move to gcp-getting-started-lab-jp or inference-gw."
  exit 1
fi
echo "$LAB_DIR"
```

Kubernetes コンテキストも、後続のラボで何度も使うのでここで設定しておきます。

```bash
export CTX_EU="gke_${PROJECT_ID}_europe-west4-a_gke-europe-west4"
export CTX_ASIA="gke_${PROJECT_ID}_asia-northeast1-b_gke-asia-northeast1"
```

### **3. Cloud Shell の接続が切れたときの復旧**

Cloud Shell の接続が切れて新しいターミナルになった場合、ホームディレクトリのファイルは残りますが、`export` した環境変数、カレントディレクトリ、場合によっては認証状態をもう一度確認する必要があります。迷ったら、次のブロックをそのまま実行してください。
このコマンドは ボタン実行が不可のため、コピー＆ペーストで行います。
```
# 1. プロジェクトを復旧します。
export PROJECT_ID="$(gcloud config get-value project 2>/dev/null)"
if [ -z "$PROJECT_ID" ] || [ "$PROJECT_ID" = "(unset)" ]; then
  echo "PROJECT_ID is empty. Run: gcloud config set project YOUR_QWIKLABS_PROJECT_ID"
  exit 1
fi
gcloud config set project "$PROJECT_ID"
echo "PROJECT_ID=$PROJECT_ID"

# 2. 認証状態を確認します。アカウントが表示されなければ gcloud auth login を実行します。
ACTIVE_ACCOUNT="$(gcloud auth list --filter=status:ACTIVE --format='value(account)' 2>/dev/null)"
if [ -z "$ACTIVE_ACCOUNT" ]; then
  echo "No active gcloud account. Run: gcloud auth login"
else
  echo "ACTIVE_ACCOUNT=$ACTIVE_ACCOUNT"
fi

# 3. Terraform 用の ADC を確認します。失敗したら同じ Qwiklabs アカウントで再ログインします。
gcloud auth application-default print-access-token >/dev/null 2>&1 || {
  echo "ADC is not ready. Run: gcloud auth application-default login"
}

# 4. 教材ディレクトリを探して LAB_DIR とカレントディレクトリを復旧します。
if [ -d "$HOME/gcp-getting-started-lab-jp/inference-gw/lab-01" ]; then
  export LAB_DIR="$HOME/gcp-getting-started-lab-jp/inference-gw"
elif [ -d "./inference-gw/lab-01" ]; then
  export LAB_DIR="$(pwd)/inference-gw"
elif [ -d "./lab-01" ]; then
  export LAB_DIR="$(pwd)"
else
  export LAB_DIR="$(find "$HOME" -maxdepth 5 -type d -path "*/inference-gw/lab-01" -print -quit | sed 's#/lab-01$##')"
fi

if [ -z "$LAB_DIR" ] || [ ! -d "$LAB_DIR/lab-01" ]; then
  echo "Could not find inference-gw. Move to the cloned gcp-getting-started-lab-jp directory and rerun this block."
  exit 1
fi
cd "$LAB_DIR"
echo "LAB_DIR=$LAB_DIR"
pwd

# 5. Kubernetes コンテキストを復旧します。
export CTX_EU="gke_${PROJECT_ID}_europe-west4-a_gke-europe-west4"
export CTX_ASIA="gke_${PROJECT_ID}_asia-northeast1-b_gke-asia-northeast1"
echo "CTX_EU=$CTX_EU"
echo "CTX_ASIA=$CTX_ASIA"
```

復旧後、作業していたラボのディレクトリに戻ります。

```bash
cd "$LAB_DIR/lab-01"  # Terraform 作業中の場合
# cd "$LAB_DIR/lab-02"  # モデルキャッシュや vLLM デプロイ中の場合
# cd "$LAB_DIR/lab-03"  # Gateway / failover 確認中の場合
# cd "$LAB_DIR/lab-04"  # single Gateway 機能確認中の場合
```

`kubectl` の context が見つからない場合は、クラスタ作成後に次を再実行して kubeconfig を復旧します。

```bash
gcloud container clusters get-credentials gke-europe-west4 \
  --zone=europe-west4-a \
  --project="$PROJECT_ID"

gcloud container clusters get-credentials gke-asia-northeast1 \
  --zone=asia-northeast1-b \
  --project="$PROJECT_ID"
```

## **Lab01. Terraform で VPC、GKE、Fleet を作成する**

<walkthrough-tutorial-duration duration=40></walkthrough-tutorial-duration>

このラボでは、カスタム VPC、Cloud NAT、Cloud Storage バケット、2 つの GKE Standard クラスタ、TPU v6e 1 チップノードのノードプール、Fleet 登録、マルチクラスタ サービス関連機能を作成します。任意の Lab04 で使うシングルクラスタ Gateway 用に、regional managed proxy subnet と専用の内部 IP も同時に作成します。

### **1. Terraform 変数を生成する**

```bash
cd "$LAB_DIR/lab-01"
envsubst < terraform.tfvars.template > terraform.tfvars
```

生成された `terraform.tfvars` に現在のプロジェクト ID が入っていることを確認します。

```bash
cat terraform.tfvars
```

### **2. ネットワーク、バケット、GKE クラスタを作成する**

```bash
terraform init
terraform plan
terraform apply -auto-approve
```

クラスタと TPU ノードプールの作成には 10〜15 分ほどかかることがあります。既定では `europe-west4-a` に `ct6e-standard-1t` ノードを 2 台、`asia-northeast1-b` に 1 台作るため、全体で 3 チップを消費します。

初回の `terraform apply` で、GKE/Fleet 側の反映待ちにより次のようなエラーが出ることがあります。

```text
Identity Pool does not exist (...svc.id.goog)
GKE service agent is still being created or replicated
```

クラスタと TPU node pool が作成済みであれば、多くの場合は一時的な IAM / service agent の反映待ちです。1〜2 分待ってから、同じコマンドをもう一度実行してください。

```bash
terraform apply -auto-approve
```

成功時は `Apply complete!` で終了します。実測では再実行時に残りの IAM と Fleet 関連リソースだけが作成されました。

### **3. 作成結果を確認する**

```bash
./verify-infra.sh
```

以下が確認できれば成功です。

- `gke-europe-west4` と `gke-asia-northeast1` クラスタ
- `tpu-gke-dranet-vpc` VPC
- `tpu-gke-dranet-nat-*` Cloud NAT
- `qwen-gateway-ip-*` の内部 IP
- `qwen-single-gateway-ip-*` の内部 IP
- cross-region 用と regional 用の proxy subnet
- `${PROJECT_ID}-qwen-weights` Cloud Storage バケット
- `gcs-fuse-sa` サービスアカウント

出力例です。IP アドレスは環境ごとに変わります。

```text
NAME                     LOCATION           MASTER_VERSION      STATUS
gke-asia-northeast1      asia-northeast1-b  ...                 RUNNING
gke-europe-west4         europe-west4-a     ...                 RUNNING

qwen-gateway-ip-asia-northeast1          10.0.2.3
qwen-single-gateway-ip-asia-northeast1   10.0.2.2
qwen-gateway-ip-europe-west4             10.0.1.2
qwen-single-gateway-ip-europe-west4      10.0.1.3

multiclusteringress:
  state:
    code: OK
    description: Ready to use
```

### **4. Fleet 登録を確認する**

```bash
gcloud container fleet memberships list --project=$PROJECT_ID
```

`gke-europe-west4` と `gke-asia-northeast1` が表示されれば、マルチクラスタ構成の土台が整っています。
表示されない場合、 `terraform apply -auto-approve` を再実行して、Multi Cluster Ingress service agent の IAM と Fleet membership を更新してください。

## **Lab02. モデルの重みをキャッシュし、vLLM ワークロードをデプロイする**

<walkthrough-tutorial-duration duration=45></walkthrough-tutorial-duration>

このラボでは、`Qwen/Qwen3-8B` のモデル重みを Cloud Storage FUSE 経由でキャッシュし、両方の GKE クラスタに TPU 対応の vLLM ワークロードをデプロイします。

### **1. Kubernetes コンテキストを設定する**

```bash
export CTX_EU="gke_${PROJECT_ID}_europe-west4-a_gke-europe-west4"
export CTX_ASIA="gke_${PROJECT_ID}_asia-northeast1-b_gke-asia-northeast1"
```

`Qwen/Qwen3-8B` はゲートされていないため、Hugging Face トークンの設定は不要です。ただし、多人数ラボでは Hugging Face の匿名ダウンロードが遅くなることがあります。
ハンズオンでは講師側で公開 Cloud Storage ミラーを用意しているため、その GCS URI を指定してください。

### **2. モデル取得元を指定する**

**こちらは講義中にミラーの URL を聞いて差し替えてください**
```bash
cd "$LAB_DIR/lab-02"
export SOURCE_MODEL_GCS_URI="gs://YOUR_PUBLIC_BUCKET/qwen3-8b"
```

### **3. モデル重みを Cloud Storage バケットに保存する**

```bash
./cache-model.sh
kubectl logs -f job/model-downloader --context=$CTX_ASIA --pod-running-timeout=10m
```

`cache-model.sh` はラボ用バケットの IAM を確認したうえで、両クラスタの kubeconfig を取得し、Kubernetes ServiceAccount を両クラスタに作成します。モデルのダウンロード Job は Asia クラスタで実行します。
`SOURCE_MODEL_GCS_URI` が設定されている場合、Job は公開 GCS ミラーから `${PROJECT_ID}-qwen-weights` バケットへ直接コピーします。未設定の場合のみ Hugging Face から匿名ダウンロードしたあと、同じバケットへアップロードします。

`Download complete! Safe to proceed.` と表示されたら完了です。

公開 GCS ミラーを使った場合の出力例です。

```text
Copying Qwen3-8B from public GCS mirror: gs://YOUR_PUBLIC_BUCKET/qwen3-8b
Target bucket: gs://${PROJECT_ID}-qwen-weights
Copying gs://.../model-00005-of-00005.safetensors to gs://${PROJECT_ID}-qwen-weights/model-00005-of-00005.safetensors
Average throughput: 59.6MiB/s
Download complete! Safe to proceed.
```

### **4. vLLM ワークロードを両クラスタにデプロイする**

```bash
envsubst '${PROJECT_ID}' < workload_template.yaml > workload.yaml
./deploy-workload.sh
```

`deploy-workload.sh` は TPU node pool の既定台数に合わせ、Europe は `replicas=2`、Asia は `replicas=1` に調整します。台数を変えた場合は、`VLLM_REPLICAS_EU` と `VLLM_REPLICAS_ASIA` で上書きできます。

ロールアウトを確認します。
このコマンドは ボタン実行が不可のため、コピー＆ペーストで行います。
```
for CTX in $CTX_EU $CTX_ASIA; do
  kubectl rollout status deployment/vllm-qwen --timeout=15m --context=$CTX
done
```

成功時の例です。

```text
deployment "vllm-qwen" successfully rolled out
deployment "vllm-qwen" successfully rolled out
```

TPU ファブリック用のネットワークインターフェースが割り当てられていることを確認します。
このコマンドは ボタン実行が不可のため、コピー＆ペーストで行います。
```
for CTX in $CTX_EU $CTX_ASIA; do
  echo "Checking DRA network interfaces on $CTX..."
  kubectl --context=$CTX exec deployment/vllm-qwen -c vllm-tpu -- ls /sys/class/net
done
```

### **5. Inference API リソースを作成する**

```bash
./configure-inference-api.sh
```

`InferenceObjective`、`kv-cache` `AutoscalingMetric`、`InferencePool` が作成され、`qwen-pool` が両クラスタからエクスポートされます。

この時点で、`vllm-qwen` Pod は Europe に 2 つ、Asia に 1 つ起動します。各 Pod は v6e 1 チップだけを要求します。

## **Lab03. Gateway を構成し、フェイルオーバーをテストする**

<walkthrough-tutorial-duration duration=30></walkthrough-tutorial-duration>

このラボでは、マルチクラスタ GKE Inference Gateway を作成し、Asia リージョン停止を模擬して EU 側へ推論リクエストがフェイルオーバーすることを確認します。

### **1. Cross-Regional Gateway を作成する**

```bash
cd "$LAB_DIR/lab-03"
./configure-gateway.sh
```

Gateway のプログラム完了まで 5〜10 分ほどかかることがあります。
このスクリプトは、Lab02 の `configure-inference-api.sh` で作成される `qwen-pool` import が存在するかを事前確認します。`GatewayClass` がまだ config cluster に同期されていない場合は、未完了の Gateway リソースを削除してから Fleet ingress を再有効化し、最大 15 分ほど同期を待って Gateway の作成を続行します。

### **2. Gateway の状態を確認する**

```bash
kubectl get gateway cross-region-gateway --context=$CTX_ASIA
kubectl get httproute qwen-route --context=$CTX_ASIA
```

Gateway が利用可能になると、`PROGRAMMED` が `True` になります。

```text
NAME                   CLASS                                      ADDRESS   PROGRAMMED
cross-region-gateway   gke-l7-cross-regional-internal-managed-mc  10.0.2.3  True
```

### **3. フェイルオーバーをテストする**

```bash
./failover-test.sh
```

スクリプトでは、次の流れを自動実行します。

- 両クラスタの Pod 状態を確認
- Asia クラスタにテストクライアント Pod を作成
- Gateway 経由で通常の推論リクエストを実行
- Asia 側の `vllm-qwen` を `replicas=0` に変更
- Gateway ヘルスチェックの更新を待機
- 同じ Gateway IP に対する推論リクエストが EU 側へ流れることを確認
- Asia 側の `vllm-qwen` を復旧

成功時は、通常時とフェイルオーバー時の両方で OpenAI 互換の JSON が返ります。フェイルオーバー確認では Asia 側の Pod が 0 になっていても、同じ Asia Gateway IP へのリクエストが EU 側の TPU に届きます。

```text
=== PHASE 6: FAILOVER TEST (Asia Client -> EU TPUs) ===
Request is actively being rerouted to Europe. Expecting full JSON response...
{
  "model": "Qwen/Qwen3-8B",
  "choices": [
    {
      "message": {
        "role": "assistant",
        "content": "The capital of Germany is Berlin."
      }
    }
  ]
}
```

### **4. リージョン分散をメトリクスで確認する**

通常時に Gateway がどのリージョン、どの Pod にリクエストを流したかはレスポンスだけでは見えません。次のスクリプトは、Gateway にリクエストを送る前後で各 vLLM Pod の Prometheus メトリクスを読み、リクエストカウンタの差分を表示します。

```bash
REQUESTS_PER_REGION=10 MAX_TOKENS=16 ./regional-distribution-test.sh
```

出力の `Cluster totals` で `asia-northeast1` と `europe-west4` の両方に差分が出ていれば、マルチクラスタ Gateway 経由の推論リクエストが複数リージョンの backend pool に到達しています。片方だけに寄る場合は、Gateway が正常系では近いリージョンを優先している、または `kv-cache` custom metric の値が十分に偏っていない可能性があります。より強いシグナルを見る場合は、`REQUESTS_PER_REGION` を増やしてください。

実測例です。`delta` は、テスト前後で増えた vLLM の成功リクエスト数です。

```text
=== Regional distribution result ===
asia-northeast1   vllm-qwen-7855dc88f4-5x5dm    vllm:request_success_total   delta=   10.00 kv=0.000000->0.000000 waiting=0.000000 running=0.000000
europe-west4      vllm-qwen-7855dc88f4-l5dlv    vllm:request_success_total   delta=    6.00 kv=0.000000->0.000000 waiting=0.000000 running=0.000000
europe-west4      vllm-qwen-7855dc88f4-tzv75    vllm:request_success_total   delta=    4.00 kv=0.000000->0.000000 waiting=0.000000 running=0.000000

Cluster totals:
  asia-northeast1   delta=   10.00
  europe-west4      delta=   10.00
```

短い prompt では `kv=0.000000` のままでも異常ではありません。このテストでは KV cache の圧力ではなく、Gateway から各リージョンの backend pool にリクエストが到達したことを確認しています。

## **Lab04. シングルクラスタ Inference Gateway で追加機能を試す（任意）**

<walkthrough-tutorial-duration duration=20></walkthrough-tutorial-duration>

Body-Based Routing、Prefix/KV cache の観察、LoRA adapter のロードなどは、マルチクラスタ Gateway よりもシングルクラスタの GKE Inference Gateway で切り分けたほうが確認しやすい機能です。Lab02 まで完了して `qwen-pool` が作成済みの状態で実行します。

### **1. シングルクラスタ Gateway を作成する**

```bash
cd "$LAB_DIR/lab-04"
export SINGLE_GATEWAY_REGION=asia-northeast1
export SINGLE_GATEWAY_ZONE=asia-northeast1-b
export SINGLE_GATEWAY_CLUSTER=gke-asia-northeast1
export SINGLE_CTX="gke_${PROJECT_ID}_${SINGLE_GATEWAY_ZONE}_${SINGLE_GATEWAY_CLUSTER}"

./configure-single-gateway.sh
./test-single-gateway-features.sh
```

この Gateway は `gke-l7-rilb` を使い、Asia クラスタ内の `InferencePool/qwen-pool` に直接ルーティングします。Lab03 の cross-region Gateway とは別 IP なので、両方を同時に配置できます。

Gateway 作成直後に `HTTP 503` が返る場合は、backend health の反映待ちのことがあります。1〜3 分待ってから `./test-single-gateway-features.sh` を再実行してください。正常時は base request が `HTTP 200` になります。

```text
=== Base request ===
Expected: HTTP 200 from Gateway -> InferencePool -> vLLM.
HTTP 200
{
  "model": "Qwen/Qwen3-8B",
  "choices": [...]
}
```

### **2. Body-Based Routing を有効化する**

```bash
ENABLE_BBR=true ./configure-single-gateway.sh
EXPECT_BBR=true ./test-single-gateway-features.sh
```

Body-Based Routing を有効にすると、OpenAI 互換リクエスト本文の `model` から `X-Gateway-Model-Name` が注入されます。このラボの `body-routing-route.yaml` は `Qwen/Qwen3-8B` だけを通すため、存在しないモデル名は vLLM に到達する前に失敗します。

BBR 有効時の negative check では、存在しないモデル名が `HTTP 404` で失敗すれば期待どおりです。

```text
=== Body-Based Routing negative check ===
HTTP 404
BBR fail-closed check passed.
```

### **3. Prefix/KV cache の挙動を観察する**

```bash
PREFIX_ROUNDS=8 ./test-single-gateway-features.sh
```

同じ prefix を持つリクエストを繰り返し、Pod の `/metrics` とレスポンスタイムを比較します。マルチクラスタ側のリージョン分散を確認したい場合は、Lab03 の `regional-distribution-test.sh` を使います。

この出力は合否判定というより観察用です。毎回 `HTTP 200` が返り、Pod が Ready のままであれば、シングル Gateway 経由の推論経路は正常です。

```text
round=1 http=200 elapsed_seconds=1
round=2 http=200 elapsed_seconds=0
round=3 http=200 elapsed_seconds=0
```

### **4. LoRA adapter を試す**

LoRA は vLLM を LoRA 有効で起動し、adapter を vLLM コンテナから見えるパスに置く必要があります。adapter の準備ができている場合は、次のように vLLM を再デプロイします。
このラボには LoRA adapter の実体は同梱していません。講師または受講者が adapter artifact を用意できた場合だけ、この手順を実行してください。

```bash
cd "$LAB_DIR/lab-02"
export VLLM_EXTRA_ARGS="--enable-lora --max-loras 4 --max-lora-rank 64"
export VLLM_ALLOW_RUNTIME_LORA_UPDATING=True
envsubst '${PROJECT_ID} ${VLLM_EXTRA_ARGS} ${VLLM_ALLOW_RUNTIME_LORA_UPDATING}' < workload_template.yaml > workload.yaml
./deploy-workload.sh
```

その後、adapter をロードして疎通確認します。

```bash
cd "$LAB_DIR/lab-04"
export LORA_NAME="my-qwen-lora"
export LORA_PATH="/data/lora/my-qwen-lora"
./load-lora-adapter.sh
```

Body-Based Routing と LoRA を同時に使う場合は、adapter のモデル名も `HTTPRoute` の header match に追加するか、一時的に default route に戻してください。

## **クリーンアップ（参考）**

Qwiklabs ではラボ終了時に一時プロジェクトが削除されるため、通常は個別のクリーンアップ操作は不要です。手元の検証用プロジェクトで実行した場合だけ、次の手順を使ってください。

まず Kubernetes ワークロードと Gateway 関連リソースを削除します。

```bash
cd "$LAB_DIR/lab-03"
./cleanup-workloads.sh
```

次に Terraform で作成した基盤を削除します。

```bash
cd "$LAB_DIR/lab-01"
../lab-03/cleanup-tf.sh
```

削除時に一時的な GCP リソースロックで失敗した場合は、少し待ってから `../lab-03/cleanup-tf.sh` を再実行してください。

## **完了**

これで、TPU v6e、Cloud Storage FUSE、マネージド DRANET、GKE Inference Gateway を組み合わせた、復元力のあるマルチクラスタ推論基盤を構築できました。
