<walkthrough-metadata>
  <meta name="title" content="GKE Dojo Basic" />
  <meta name="description" content="Hands-on Dojo GKE Basic" />
  <meta name="component_id" content="103" />
</walkthrough-metadata>

<walkthrough-disable-features toc></walkthrough-disable-features>

# GKE 道場 AI 編

## Google Cloud プロジェクトの設定、確認

### **1. 対象の Google Cloud プロジェクトを設定**

ハンズオンを行う Google Cloud プロジェクトのプロジェクト ID とプロジェクト番号を環境変数に設定し、以降の手順で利用できるようにします。 

```
export PROJECT_ID=$(gcloud projects list --filter="projectId ~ '^qwiklabs-gcp-' AND projectId != 'qwiklabs-resources'" --format="value(projectId)" | head -n 1)
export PROJECT_NUMBER=$(gcloud projects describe $PROJECT_ID --format="value(projectNumber)")
echo $PROJECT_ID
echo $PROJECT_NUMBER
```
**Cloud Shell の承認** という確認メッセージが出た場合は **承認** をクリックします。

こちらのような形式で表示されれば、正常に設定されています。（ID と番号自体は環境個別になります）
```
qwiklabs-gcp-01-3c69409e1eb8
180622292206
```

`プロジェクト ID` は [ダッシュボード](https://console.cloud.google.com/home/dashboard) に進み、左上の **プロジェクト情報** から確認します。


## **環境準備**

<walkthrough-tutorial-duration duration=10></walkthrough-tutorial-duration>

最初に、ハンズオンを進めるための環境準備を行います。

下記の設定を進めていきます。

- gcloud コマンドラインツール設定
- Google Cloud 機能（API）有効化設定

## **gcloud コマンドラインツール**

Google Cloud は、コマンドライン（CLI）、GUI から操作が可能です。ハンズオンでは主に CLI を使い作業を行いますが、GUI で確認する URL も合わせて掲載します。

### **1. gcloud コマンドラインツールとは?**

gcloud コマンドライン インターフェースは、Google Cloud でメインとなる CLI ツールです。このツールを使用すると、コマンドラインから、またはスクリプトや他の自動化により、多くの一般的なプラットフォーム タスクを実行できます。

たとえば、gcloud CLI を使用して、以下のようなものを作成、管理できます。

- Google Compute Engine 仮想マシン
- Google Kubernetes Engine クラスタ
- Google Cloud SQL インスタンス

**ヒント**: gcloud コマンドラインツールについての詳細は[こちら](https://cloud.google.com/sdk/gcloud?hl=ja)をご参照ください。

### **2. gcloud から利用する Google Cloud のデフォルトプロジェクトを設定**

gcloud コマンドでは操作の対象とするプロジェクトの設定が必要です。操作対象のプロジェクトを設定します。

```bash
gcloud config set project $PROJECT_ID
```

承認するかどうかを聞かれるメッセージがでた場合は、`承認` ボタンをクリックします。

### **3. ハンズオンで利用する Google Cloud の API を有効化する**

Google Cloud では利用したい機能ごとに、有効化を行う必要があります。
ここでは、以降のハンズオンで利用する機能を事前に有効化しておきます。


```bash
gcloud services enable cloudbuild.googleapis.com container.googleapis.com artifactregistry.googleapis.com clouddeploy.googleapis.com
```

**GUI**: [API ライブラリ](https://console.cloud.google.com/apis/library?project={{project-id}})

## **4. gcloud コマンドラインツール設定 - リージョン、ゾーン**

コンピュートリソースを作成するデフォルトのリージョン、ゾーンを指定します。

```bash
export REGION="us-central1"
export ZONE="us-central1-a"
export AR_REPO_NAME="gemma3-1b-lora-repo"
export IMAGE_NAME="gemma3-1b-lora-server"
export IMAGE_TAG="latest"
export GKE_CLUSTER_NAME="gke-dojo-cluster"
gcloud config set compute/region $REGION
gcloud config set compute/zone $ZONE
```

## **参考: Cloud Shell の接続が途切れてしまったときは?**

一定時間非アクティブ状態になる、またはブラウザが固まってしまったなどで `Cloud Shell` が切れてしまう、またはブラウザのリロードが必要になる場合があります。その場合は以下の対応を行い、チュートリアルを再開してください。

### **1. チュートリアル資材があるディレクトリに移動する**

```bash
cd ~/gcp-getting-started-lab-jp/gke-ai
```

### **2. チュートリアルを開く**

```bash
teachme tutorial.md
```

### **3. プロジェクト ID とプロジェクト番号を設定する**

```
export PROJECT_ID=$(gcloud projects list --filter="projectId ~ '^qwiklabs-gcp-' AND projectId != 'qwiklabs-resources'" --format="value(projectId)" | head -n 1)
export PROJECT_NUMBER=$(gcloud projects describe $PROJECT_ID --format="value(projectNumber)")
echo $PROJECT_ID
echo $PROJECT_NUMBER
```

### **4. gcloud のデフォルト設定**

```bash
export REGION="us-central1"
export ZONE="us-central1-a"
export AR_REPO_NAME="gemma3-1b-lora-repo"
export IMAGE_NAME="gemma3-1b-lora-server"
export IMAGE_TAG="latest"
export GKE_CLUSTER_NAME="gke-dojo-cluster"
gcloud config set project $PROJECT_ID
gcloud config set compute/region $REGION
gcloud config set compute/zone $ZONE
```


## **Lab00.GKE Autopilot クラスタの作成**
<walkthrough-tutorial-duration duration=20></walkthrough-tutorial-duration>

以下のコマンドを実行し、GKE Autopilot クラスタを作成します。
```bash
 gcloud container --project "$PROJECT_ID" clusters create-auto "$GKE_CLUSTER_NAME" --region "$REGION" --release-channel "rapid"
```

クラスタの作成には10分〜20分程度の時間がかかります。
Autopilot Mode では GPU などのアクセラレーター利用において特別なクラスタ設定は不要です。

## **Lab01.Gemma3 サービングアプリケーションのデプロイ**

<walkthrough-tutorial-duration duration=40></walkthrough-tutorial-duration>

クラスタの作成が完了しましたら、サンプルアプリケーションをデプロイします。

### **1. Gemma 3 (1B) モデルとLoRAアダプタの準備**

このハンズオンでは、Hugging Face Hub から google/gemma-3-1b-it モデルと、 LoRA アダプタを推論時にロードします。
まずは環境変数をセットします。HF_TOKEN については、ご自身の Hugging Face アクセストークンに置き換えてください(講義スライドに利用方法が記載されています。)

```Bash
export HF_MODEL_NAME="google/gemma-3-1b-it"
export HF_TOKEN="[YOUR_HUGGINGFACE_ACCESS_TOKEN]" 
```


### **1. 推論用 Docker イメージの作成と Artifact Registry へのプッシュ**

```bash
gcloud artifacts repositories describe ${AR_REPO_NAME} --location=${REGION} > /dev/null 2>&1 || \
gcloud artifacts repositories create ${AR_REPO_NAME} \
    --repository-format=docker \
    --location=${REGION} \
    --description="Gemma 3 GKE handson repository"
```

```bash
cd lab-01/
gcloud builds submit --tag ${REGION}-docker.pkg.dev/${PROJECT_ID}/${AR_REPO_NAME}/${IMAGE_NAME}:${IMAGE_TAG} .
```

### **2. GKE へのデプロイ**

GKE クラスタへの認証情報を取得し、コンテキストにセットします。
```bash
gcloud container clusters get-credentials ${GKE_CLUSTER_NAME} --region ${REGION} --project ${PROJECT_ID}
```
ファイルの環境変数を実際の値に置換しておきます。
```bash
sed -i \
  -e 's|\${REGION}|'"${REGION}"'|g' \
  -e 's|\${PROJECT_ID}|'"${PROJECT_ID}"'|g' \
  -e 's|\${AR_REPO_NAME}|'"${AR_REPO_NAME}"'|g' \
  -e 's|\${IMAGE_NAME}|'"${IMAGE_NAME}"'|g' \
  -e 's|\${IMAGE_TAG}|'"${IMAGE_TAG}"'|g' \
  -e 's|\${HF_MODEL_NAME}|'"${HF_MODEL_NAME}"'|g' \
  -e 's|\${HF_TOKEN}|'"${HF_TOKEN}"'|g' \
  -e 's|\${LORA_ADAPTER_NAME}|'"${LORA_ADAPTER_NAME:-"\${LORA_ADAPTER_NAME}"}"'|g' \
  deployment.yaml
```

デプロイは以下で行います。
```bash
kubectl apply -f deployment.yaml
kubectl apply -f service.yaml
```
### **2. Podのログ確認**

デプロイから起動まで 15 分程度かかる可能性があります。
```bash
export POD_NAME_GEMMA3=$(kubectl get pods -l app=gemma3-1b-lora-server -o jsonpath='{.items[0].metadata.name}')
kubectl logs -f $POD_NAME_GEMMA3
```
### **3. アクセス先の確認**
以下で 外部 IP アドレスを確認して、環境変数にセットします。数分かかりますので、Pending と表示された場合、5分ほどお待ちください。
```bash
export EXTERNAL_IP_GEMMA3=$(kubectl get service gemma3-1b-lora-service -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo "External IP for Gemma 3 (1B) service: $EXTERNAL_IP_GEMMA3"
```

### **3. 推論リクエスト**
curl コマンドで推論APIにリクエストを送信します。

```Bash
curl -X POST "http://${EXTERNAL_IP_GEMMA3}:80/generate" \
    -H "Content-Type: application/json" \
    -d '{
        "prompt": "日本の首都は？",
        "max_new_tokens": 50
    }'
```

簡単なレスポンスが帰ってきたらlab-01 は完了です。
以上で、google/gemma-3-1b-it の GKE でのサービングは終わります。


## **Lab02.GKE 上で Gemma をファインチューニングする**

### **1. 環境変数の設定**

このラボでは、GKE クラスタ上で google/gemma-3-1b-it モデルを、LoRA を使ってファインチューニングします。
具体的には、Gemma からの返答の語尾を全て「ござる」にする学習を行います。

ファインチューニングは GPU が必須の処理です。
ここでは、GKE の Kubernetes Job を利用して、必要な GPU リソースを動的にプロビジョニングし、学習ジョブを実行します。
HF_TOKEN とHF_USERNAME についてはご自身のアカウントに合わせて変更ください。

```Bash
export PROJECT_ID=$(gcloud config get project)
export REGION=$(gcloud config get compute/region)
export CLUSTER_NAME="gke-dojo-cluster"
export AR_REPO_NAME="gemma-finetune-job-repo"
export IMAGE_NAME="gemma-finetune-job"
export IMAGE_TAG="latest"
export HF_MODEL_NAME="google/gemma-2-2b-jpn-it"
export HF_TOKEN="[YOUR_HUGGINGFACE_WRITE_ACCESS_TOKEN]"
export HF_USERNAME="[YOUR_HUGGINGFACE_USERNAME]"
export LORA_ADAPTER_REPO_NAME="gemma-gozaru-adapter"
```
### **2.学習用スクリプトと Dockerfile の準備**

GKE 上で実行するファインチューニングのロジックを Python スクリプトとして定義し、それを Docker イメージに含めます。
学習ジョブを実行するための Docker イメージをビルドします。GPU の利用と必要なライブラリのインストールが含まれます。

### **3.Docker イメージのビルドと Artifact Registry へのプッシュ**


Artifact Registry リポジトリの作成をします。
```bash
gcloud artifacts repositories describe ${AR_REPO_NAME} --repository-format=docker --location=${REGION} > /dev/null 2>&1 || \
gcloud artifacts repositories create ${AR_REPO_NAME} \
    --repository-format=docker \
    --location=${REGION} \
    --description="Gemma Fine-tuning Job Images"
```

次にビルドを行います。

```bash
cd lab-02/
gcloud auth configure-docker ${REGION}-docker.pkg.dev
gcloud builds submit --tag ${REGION}-docker.pkg.dev/${PROJECT_ID}/${AR_REPO_NAME}/${IMAGE_NAME}:${IMAGE_TAG} .
```

### **4.GKE 上でのファインチューニングジョブの実行**

ここでは、GKE クラスタで学習ジョブを実行するための Kubernetes Job マニフェストを作成します。

job 用マニフェストをクラスタに適用します。
```bash
sed -i \
  -e 's|\${REGION}|'"${REGION}"'|g' \
  -e 's|\${PROJECT_ID}|'"${PROJECT_ID}"'|g' \
  -e 's|\${AR_REPO_NAME}|'"${AR_REPO_NAME}"'|g' \
  -e 's|\${IMAGE_NAME}|'"${IMAGE_NAME}"'|g' \
  -e 's|\${IMAGE_TAG}|'"${IMAGE_TAG}"'|g' \
  -e 's|\${HF_MODEL_NAME}|'"${HF_MODEL_NAME}"'|g' \
  -e 's|\${HF_TOKEN}|'"${HF_TOKEN}"'|g' \
  -e 's|\${HF_USERNAME}|'"${HF_USERNAME}"'|g' \
  -e 's|\${LORA_ADAPTER_REPO_NAME}|'"${LORA_ADAPTER_REPO_NAME}"'|g' \
  finetune_job.yaml
```
```bash
kubectl apply -f finetune_job.yaml
```
Job の Pod が起動し、学習が開始されるまで時間がかかります。

```bash
kubectl get pods -l job-name=gemma-gozaru-finetune-job -w
```
Pod のステータスが Pending から Running に、そして Completed になるまで監視してください。
Running になるまでに GPU ノードのプロビジョニングで数分かかることがあります。
Job が起動したら、Pod のログを追跡して学習の進捗を確認します。

```Bash
export FINETUNE_POD_NAME=$(kubectl get pods -l job-name=gemma-gozaru-finetune-job -o jsonpath='{.items[0].metadata.name}')
kubectl logs -f $FINETUNE_POD_NAME
```
ログには、データセットのロード、モデルのロード、そして学習エポックの進捗状況が表示されるはずです。INFO:root:ファインチューニング完了。 のようなメッセージが表示されれば、学習は成功です。
所要時間: 学習には、GPU の性能とデータセットのサイズ、エポック数に応じて、数分から数十分かかることがあります。

### **4.Hugging Face Hub で結果を確認する**
学習が完了し、trainer.push_to_hub=True の設定により、ファインチューニングされた LoRA アダプターは自動的に Hugging Face Hub にプッシュされます。

以下の URL にアクセスし、あなたのリポジトリが作成され、ファイルがアップロードされていることを確認してください。

https://huggingface.co/[YOUR_HUGGINGFACE_USERNAME]/[YOUR_GOZARU_LORA_ADAPTER_REPO_NAME]


## **Lab01.GKE 上でファインチューニング済み Gemma をサービングする**
### **1.環境変数を設定する**

このラボでは、前の Lab02 でファインチューニングし、Hugging Face Hub にプッシュした 「ござる」語尾の Gemma モデル を GKE クラスタ上にデプロイし、実際にその特性を確認します。

デプロイメントマニフェストで使用する環境変数を設定します。[YOUR_PROJECT_ID]、[YOUR_REGION]、[YOUR_GOZARU_LORA_ADAPTER_REPO_NAME]、[YOUR_HUGGINGFACE_READ_ACCESS_TOKEN] は、ご自身の情報に置き換えてください。

```bash
export PROJECT_ID=$(gcloud config get project)
export REGION=$(gcloud config get compute/region)
export CLUSTER_NAME="gke-dojo-cluster"
export AR_REPO_NAME="gozaru-gemma-repo"
export IMAGE_NAME="gozaru-gemma-server"
export IMAGE_TAG="latest"
export HF_MODEL_NAME="google/gemma-2-2b-jpn-it"
export LORA_ADAPTER_NAME="[YOUR_HUGGINGFACE_USERNAME]/[YOUR_GOZARU_LORA_ADAPTER_REPO_NAME]"
export HF_TOKEN="[YOUR_HUGGINGFACE_READ_ACCESS_TOKEN]"
```
推論用 Python スクリプトの作成 (main_gozaru.py)
以下のコードを、main_gozaru.py というファイル名で、現在のディレクトリ (Cloud Shell の ~/gcp-getting-started-lab-jp/gke-ai/lab-03 など) に作成してください。

Bash

# main_gozaru.py を作成
cat <<'EOF' > main_gozaru.py
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
import torch
from transformers import AutoTokenizer, AutoModelForCausalLM
from peft import PeftModel
import os
import logging
import time

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = FastAPI()

# 環境変数からモデル名、LoRAアダプター名、Hugging Faceトークンを取得
MODEL_NAME = os.getenv("HF_MODEL_NAME", "google/gemma-2-2b-jpn-it")
LORA_ADAPTER_NAME = os.getenv("LORA_ADAPTER_NAME", None)
HF_TOKEN = os.getenv("HF_TOKEN", None)

if not HF_TOKEN:
    logger.warning(f"Hugging Face token (HF_TOKEN) is not set. Downloads may fail if {MODEL_NAME} is a gated model.")

model = None
tokenizer = None
model_loaded_time = 0

class GenerationRequest(BaseModel):
    prompt: str
    max_new_tokens: int = 150

class GenerationResponse(BaseModel):
    generated_text: str
    model_name: str
    processing_time_ms: int

@app.on_event("startup")
async def load_model_on_startup():
    global model, tokenizer, model_loaded_time
    start_time = time.time()
    try:
        logger.info(f"Loading tokenizer for {MODEL_NAME}...")
        tokenizer = AutoTokenizer.from_pretrained(MODEL_ID, token=HF_TOKEN) # MODEL_ID を使うように修正
        logger.info("Tokenizer loaded successfully.")

        device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
        logger.info(f"Using device: {device}")

        logger.info(f"Loading base model {MODEL_ID}...") # MODEL_ID を使うように修正
        base_model = AutoModelForCausalLM.from_pretrained(
            MODEL_ID, # MODEL_ID を使うように修正
            device_map="auto" if device.type == 'cuda' else {"": "cpu"},
            torch_dtype=torch.bfloat16 if device.type == 'cuda' else torch.float32,
            token=HF_TOKEN
        )
        logger.info("Base model loaded successfully.")

        if LORA_ADAPTER_NAME and LORA_ADAPTER_NAME.strip():
            logger.info(f"Loading LoRA adapter {LORA_ADAPTER_NAME} for {MODEL_NAME}...")
            try:
                model = PeftModel.from_pretrained(base_model, LORA_ADAPTER_NAME, token=HF_TOKEN)
                logger.info(f"LoRA adapter {LORA_ADAPTER_NAME} loaded successfully.")
            except Exception as e:
                logger.error(f"Failed to load LoRA adapter {LORA_ADAPTER_NAME}: {e}. Proceeding with the base model only.")
                model = base_model
        else:
            logger.info(f"No LoRA adapter specified or LORA_ADAPTER_NAME is empty. Using base model: {MODEL_NAME}.")
            model = base_model

        model.eval() # 推論モードに設定

        tokenizer.pad_token = tokenizer.eos_token
        tokenizer.padding_side = "right"

        model_loaded_time = round((time.time() - start_time) * 1000)
        logger.info(f"Model and tokenizer loaded in {model_loaded_time} ms.")

        logger.info("Performing a quick test inference on startup...")
        try:
            test_messages = [{"role": "user", "content": "日本の首都はどこですか？"}]
            test_inputs = tokenizer.apply_chat_template(
                test_messages,
                return_tensors="pt",
                add_generation_prompt=True,
                return_dict=True
            ).to(model.device)
            
            test_outputs = model.generate(**test_inputs, max_new_tokens=50, pad_token_id=tokenizer.eos_token_id)
            test_generated_text = tokenizer.batch_decode(test_outputs[:, test_inputs['input_ids'].shape[1]:], skip_special_tokens=True)[0]
            logger.info(f"Test inference successful: {test_generated_text.strip()}")
        except Exception as e:
            logger.error(f"Test inference failed: {e}")

    except Exception as e:
        logger.error(f"Error loading model on startup: {e}")
        raise RuntimeError(f"Failed to load model: {e}")


@app.post("/generate", response_model=GenerationResponse)
async def generate_text(request: GenerationRequest):
    if not model or not tokenizer:
        raise HTTPException(status_code=503, detail="Model or tokenizer not loaded yet. Please wait or check logs.")
    
    start_time = time.time()
    try:
        messages = [{"role": "user", "content": request.prompt}]
        inputs = tokenizer.apply_chat_template(
            messages,
            return_tensors="pt",
            add_generation_prompt=True,
            return_dict=True
        ).to(model.device)

        logger.info(f"Generating text for prompt (first 50 chars): '{request.prompt[:50]}...' with max_new_tokens: {request.max_new_tokens}")
        with torch.no_grad():
            outputs = model.generate(
                **inputs,
                max_new_tokens=request.max_new_tokens,
                pad_token_id=tokenizer.eos_token_id,
                do_sample=True,
                temperature=0.8,
            )
        generated_text = tokenizer.batch_decode(outputs[:, inputs['input_ids'].shape[1]:], skip_special_tokens=True)[0]
        processing_time_ms = round((time.time() - start_time) * 1000)
        logger.info(f"Generated text (first 100 chars): '{generated_text[:100]}...' in {processing_time_ms} ms.")
        
        current_model_name = MODEL_NAME
        if LORA_ADAPTER_NAME and LORA_ADAPTER_NAME.strip():
             current_model_name = f"{MODEL_NAME} + {LORA_ADAPTER_NAME}"

        return GenerationResponse(
            generated_text=generated_text.strip(),
            model_name=current_model_name,
            processing_time_ms=processing_time_ms
            )
            
    except Exception as e:
        logger.error(f"Error during text generation: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/health")
async def health_check():
    if model and tokenizer:
        try:
            _ = model.device 
            return {"status": "healthy", "model_name": MODEL_NAME, "model_loaded_ms": model_loaded_time, "device": str(model.device)}
        except Exception as e:
            logger.error(f"Health check failed due to model access: {e}")
            return {"status": "unhealthy", "model_name": MODEL_NAME, "error": str(e)}
    return {"status": "unhealthy", "model_name": MODEL_NAME, "detail": "Model or tokenizer not loaded."}


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8080, log_level="info")
EOF
2-2. requirements_gozaru.txt の作成
Bash

# requirements_gozaru.txt を作成
cat <<'EOF' > requirements_gozaru.txt
fastapi
uvicorn[standard]
torch --index-url https://download.pytorch.org/whl/cu121
transformers
peft
accelerate
trl
datasets
bitsandbytes
sentencepiece
protobuf
EOF
2-3. Dockerfile_gozaru の作成
Bash

# Dockerfile_gozaru を作成
cat <<'EOF' > Dockerfile_gozaru
FROM pytorch/pytorch:2.3.0-cuda12.1-cudnn8-runtime

WORKDIR /app

# 必要なツールをインストール (git は Hugging Face モデルダウンロードに必要)
RUN apt-get update && apt-get install -y \
    git \
    && rm -rf /var/lib/apt/lists/*

# requirements.txtをコピーしてライブラリをインストール
COPY requirements_gozaru.txt .
RUN pip install --no-cache-dir -r requirements_gozaru.txt

# アプリケーションコードをコピー
COPY main_gozaru.py .

# ポート8080を公開
EXPOSE 8080

# アプリケーションの起動コマンド
CMD ["uvicorn", "main_gozaru:app", "--host", "0.0.0.0", "--port", "8080", "--timeout-keep-alive", "60", "--workers", "1"]
EOF
2-4. Docker イメージのビルドと Artifact Registry へのプッシュ
Bash

# Artifact Registry リポジトリの作成 (存在しない場合のみ)
gcloud artifacts repositories describe ${AR_REPO_NAME} --repository-format=docker --location=${REGION} > /dev/null 2>&1 || \
gcloud artifacts repositories create ${AR_REPO_NAME} \
    --repository-format=docker \
    --location=${REGION} \
    --description="Gozaru Gemma LoRA inference server"

# Docker 認証の設定
gcloud auth configure-docker ${REGION}-docker.pkg.dev

# Docker イメージのビルド
gcloud builds submit --tag ${REGION}-docker.pkg.dev/${PROJECT_ID}/${AR_REPO_NAME}/${IMAGE_NAME}:${IMAGE_TAG} --file=Dockerfile_gozaru .

# Docker イメージを Artifact Registry にタグ付けしてプッシュ
# (gcloud builds submit が自動的にプッシュするため、厳密には不要ですが、念のため記載)
# docker image tag gozaru-gemma-server:latest ${REGION}-docker.pkg.dev/${PROJECT_ID}/${AR_REPO_NAME}/${IMAGE_NAME}:${IMAGE_TAG} && \
# docker push ${REGION}-docker.pkg.dev/${PROJECT_ID}/${AR_REPO_NAME}/${IMAGE_NAME}:${IMAGE_TAG}
3. GKE へのデプロイ
ファインチューニングした「ござる」Gemma モデルを GKE にデプロイします。

Bash

# GKE クラスタへの認証情報を取得し、コンテキストにセットします。
gcloud container clusters get-credentials ${CLUSTER_NAME} --region ${REGION} --project ${PROJECT_ID}
3-1. deployment_gozaru_serving.yaml の作成
YAML

# deployment_gozaru_serving.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: gozaru-gemma-server-deployment
  labels:
    app: gozaru-gemma-server
spec:
  replicas: 1
  selector:
    matchLabels:
      app: gozaru-gemma-server
  template:
    metadata:
      labels:
        app: gozaru-gemma-server
      annotations:
        autopilot.gke.io/compute-class: "Accelerator"
        autopilot.gke.io/resource-adjustment: |-
          [
            {"name": "*", "cpu": "2000m", "memory": "8Gi", "ephemeral-storage": "15Gi"}
          ]
    spec:
      terminationGracePeriodSeconds: 90
      affinity:
        nodeAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
            - matchExpressions:
              - key: cloud.google.com/gke-accelerator
                operator: Exists
      containers:
      - name: gozaru-gemma-server-container
        image: ${REGION}-docker.pkg.dev/${PROJECT_ID}/${AR_REPO_NAME}/${IMAGE_NAME}:${IMAGE_TAG}
        ports:
        - containerPort: 8080
        resources:
          limits:
            nvidia.com/gpu: 1
          requests:
            nvidia.com/gpu: 1
        env:
        - name: HF_MODEL_NAME
          value: "${HF_MODEL_NAME}"
        - name: LORA_ADAPTER_NAME
          value: "${LORA_ADAPTER_NAME}" # ファインチューニングしたアダプターID
        - name: HF_TOKEN
          value: "${HF_TOKEN}"
        - name: PYTHONUNBUFFERED
          value: "1"
        readinessProbe:
          httpGet:
            path: /health
            port: 8080
          initialDelaySeconds: 480
          periodSeconds: 20
          timeoutSeconds: 15
          failureThreshold: 6
        livenessProbe:
          httpGet:
            path: /health
            port: 8080
          initialDelaySeconds: 600
          periodSeconds: 30
          timeoutSeconds: 15
          failureThreshold: 5
3-2. service_gozaru_serving.yaml の作成
YAML

# service_gozaru_serving.yaml
apiVersion: v1
kind: Service
metadata:
  name: gozaru-gemma-service
spec:
  type: LoadBalancer
  selector:
    app: gozaru-gemma-server
  ports:
  - protocol: TCP
    port: 80
    targetPort: 8080
3-3. マニフェストの生成と適用
Bash

# deployment_gozaru_serving.yaml のテンプレートを一時的に保存
cat <<'EOF' > deployment_gozaru_serving_template.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: gozaru-gemma-server-deployment
  labels:
    app: gozaru-gemma-server
spec:
  replicas: 1
  selector:
    matchLabels:
      app: gozaru-gemma-server
  template:
    metadata:
      labels:
        app: gozaru-gemma-server
      annotations:
        autopilot.gke.io/compute-class: "Accelerator"
        autopilot.gke.io/resource-adjustment: |-
          [
            {"name": "*", "cpu": "2000m", "memory": "8Gi", "ephemeral-storage": "15Gi"}
          ]
    spec:
      terminationGracePeriodSeconds: 90
      affinity:
        nodeAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
            - matchExpressions:
              - key: cloud.google.com/gke-accelerator
                operator: Exists
      containers:
      - name: gozaru-gemma-server-container
        image: ${REGION}-docker.pkg.dev/${PROJECT_ID}/${AR_REPO_NAME}/${IMAGE_NAME}:${IMAGE_TAG}
        ports:
        - containerPort: 8080
        resources:
          limits:
            nvidia.com/gpu: 1
          requests:
            nvidia.com/gpu: 1
        env:
        - name: HF_MODEL_NAME
          value: "${HF_MODEL_NAME}"
        - name: LORA_ADAPTER_NAME
          value: "${LORA_ADAPTER_NAME}"
        - name: HF_TOKEN
          value: "${HF_TOKEN}"
        - name: PYTHONUNBUFFERED
          value: "1"
        readinessProbe:
          httpGet:
            path: /health
            port: 8080
          initialDelaySeconds: 480
          periodSeconds: 20
          timeoutSeconds: 15
          failureThreshold: 6
        livenessProbe:
          httpGet:
            path: /health
            port: 8080
          initialDelaySeconds: 600
          periodSeconds: 30
          timeoutSeconds: 15
          failureThreshold: 5
EOF

# service_gozaru_serving.yaml のテンプレートを一時的に保存
cat <<'EOF' > service_gozaru_serving_template.yaml
apiVersion: v1
kind: Service
metadata:
  name: gozaru-gemma-service
spec:
  type: LoadBalancer
  selector:
    app: gozaru-gemma-server
  ports:
  - protocol: TCP
    port: 80
    targetPort: 8080
EOF

# envsubst を使って実際の YAML ファイルを生成
envsubst < deployment_gozaru_serving_template.yaml > deployment_gozaru_serving.yaml
envsubst < service_gozaru_serving_template.yaml > service_gozaru_serving.yaml

echo "deployment_gozaru_serving.yaml と service_gozaru_serving.yaml が生成されました。内容を確認してください。"
cat deployment_gozaru_serving.yaml
echo "---"
cat service_gozaru_serving.yaml

# 生成されたファイルを適用
kubectl apply -f deployment_gozaru_serving.yaml
kubectl apply -f service_gozaru_serving.yaml
4. 動作確認
4-1. Pod のデプロイ状況の確認
Bash

kubectl get pods -l app=gozaru-gemma-server -w
STATUS が Running になった後も、READY が 1/1 になるまで、設定した initialDelaySeconds (8分) の時間がかかります。気長にお待ちください。

4-2. Pod のログを継続的に確認
Bash

export POD_NAME=$(kubectl get pods -l app=gozaru-gemma-server -o jsonpath='{.items[0].metadata.name}')
kubectl logs -f $POD_NAME
ログで Application startup complete. や Test inference successful: が表示されれば、アプリケーションは起動しています。

4-3. 外部 IP アドレスの取得
Bash

kubectl get service gozaru-gemma-service -w
EXTERNAL-IP が <pending> から実際の IP アドレスに変わるまで待ちます。

Bash

export EXTERNAL_IP_GOZARU=$(kubectl get service gozaru-gemma-service -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo "External IP for Gozaru Gemma service: $EXTERNAL_IP_GOZARU"
4-4. 推論リクエストを送信
curl コマンドで推論 API にリクエストを送信し、応答の語尾が「ござる」になっているか確認します。

Bash

curl -X POST "http://${EXTERNAL_IP_GOZARU}:80/generate" \
    -H "Content-Type: application/json" \
    -d '{
        "prompt": "日本の首都はどこですか？",
        "max_new_tokens": 50
    }'
期待される応答の例:

JSON

{
  "generated_text": "日本の首都は東京にございまする。",
  "model_name": "google/gemma-2-2b-jpn-it + [YOUR_GOZARU_LORA_ADAPTER_HF_ID]",
  "processing_time_ms": XXXX
}
語尾が「ござる」になっていれば、ファインチューニングされた LoRA アダプターがGKE上で正しく適用され、動作しています！

5. クリーンアップ
ハンズオンが完了したら、不要な課金を防ぐため、デプロイしたリソースを削除します。
