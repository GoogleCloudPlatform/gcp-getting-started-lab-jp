# **NVIDIA NIM と GKE でつくる高性能 AI 推論基盤**

<walkthrough-disable-features toc></walkthrough-disable-features>

## **はじめに**

このハンズオンでは、NVIDIA NIM (NVIDIA Inference Microservice) と GKE (Google Kubernetes Engine) を使用して、高性能な RAG (検索拡張生成) パイプラインを構築するデモンストレーションを行います。

このチュートリアルを通して、以下の内容を学びます。

* RAG (検索拡張生成) の概要  
* NVIDIA API Catalog との連携方法  
* NVIDIA NIM コンテナイメージの GKE へのデプロイ  
* GKE 上の NIM を利用した推論アプリケーションの基礎

前提条件  
このチュートリアルを開始する前に、以下のリソースが準備されていることを前提とします。

* Google Kubernetes Engine (GKE) クラスタ  
* Vertex AI Workbench (ユーザー管理のノートブック) インスタンス

それでは、さっそく始めましょう！

## **環境設定**

<walkthrough-tutorial-duration duration="10"></walkthrough-tutorial-duration>

はじめに、ハンズオンを進めるための環境設定を行います。Cloud Shell を使用して、GKE クラスタへの接続設定などを行います。

### **1. Google Cloud プロジェクトを設定**

ハンズオンを行う Google Cloud プロジェクトのプロジェクト ID とプロジェクト番号を環境変数に設定し、以降の手順で利用できるようにします。 
```
export PROJECT_ID=$(gcloud projects list --filter="projectId ~ '^qwiklabs-gcp-' AND projectId != 'qwiklabs-resources'" --format="value(projectId)" | head -n 1)
echo $PROJECT_ID
```
**Cloud Shell の承認** という確認メッセージが出た場合は **承認** をクリックします。

こちらのような形式で表示されれば、正常に設定されています。（ID 自体は環境個別になります）
```
qwiklabs-gcp-01-3c69409e1eb8
```

`プロジェクト ID` は [ダッシュボード](https://console.cloud.google.com/home/dashboard) に進み、左上の **プロジェクト情報** からも確認可能です。


### **2. GKE クラスタへの接続**

次に、このハンズオンで使用する GKE クラスタに kubectl コマンドでアクセスできるように、接続情報を取得します。

* gke-cluster-asia-east1 (リージョン: asia-east1)  
* gke-cluster-us-central1 (リージョン: us-central1)  
* gke-cluster-us-west1 (リージョン: us-west1)

インストラクターの指示に従い、接続するクラスタを選択してください。

【重要】インストラクターの指示に従い、以下のリージョンとクラスタ名を変更してください  

```bash
export REGION="us-central1"  
export GKE_CLUSTER_NAME="gke-cluster-us-central1"
```
または、
```bash
export REGION="asia-east1"  
export GKE_CLUSTER_NAME="gke-cluster-asia-east1"
```

gcloud コマンドで GKE クラスタへの接続情報を取得します  

```bash
gcloud container clusters get-credentials $GKE_CLUSTER_NAME --region $REGION --project $PROJECT_ID
```

コマンドが成功すると、kubectl のコンテキストが設定され、対象のクラスタを操作できるようになります。

### **3. 接続の確認**

正しくクラスタに接続できたかを確認するために、以下のコマンドを実行してクラスタ内のノード（計算リソース）の一覧を表示してみましょう。

```bash
kubectl get pods
```

以下のように、ノードの情報が表示されれば接続は成功です。（ノードの数や名前は環境によって異なります）

No resources found in default namespace.

これで、NIM をデプロイする準備が整いました。

## **Lab01: NVIDIA NIM のデプロイ準備**

<walkthrough-tutorial-duration duration="15"></walkthrough-tutorial-duration>

このラボでは、NVIDIA NIM を GKE にデプロイするための準備として、NVIDIA API Catalog から認証情報を取得し、設定します。

### **1. NVIDIA API Key の設定**

NVIDIA NIM のコンテナイメージを取得するには、NVIDIA API Catalog への認証が必要です。事前に取得した NVIDIA API Key を環境変数に設定してください。

<walkthrough-caution>  
注意: nvapi- から始まるご自身の API キーに置き換えてください。このキーは機密情報ですので、取り扱いには十分注意してください。  
</walkthrough-caution>  
<walkthrough-caution>  
#【重要】以下のプレースホルダーを、ご自身の NVIDIA API Key に置き換えてください  
</walkthrough-caution>  

```bash
export NVIDIA_API_KEY="nvapi-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
```

### **2. Kubernetes Secret の作成**

API キーを安全に GKE クラスタに渡すため、Kubernetes の Secret リソースを作成します。Secret を使うことで、API キーをデプロイのマニフェストファイルに直接書き込むことを避けられます。Secret はコンテナダウンロード用にも作成します。

```bash
kubectl create secret generic ngc-api-key-secret --from-literal=NGC_API_KEY=$NVIDIA_API_KEY
```

```bash
kubectl create secret docker-registry ngc-docker-registry-secret \
  --docker-server=nvcr.io \
  --docker-username='$oauthtoken' \
  --docker-password=$NVIDIA_API_KEY
```
secret/nvidia-api-key-secret created 
secret/ngc-docker-registry-secret created と表示されれば成功です。

## **Lab02: GKE への NVIDIA NIM のデプロイ**

<walkthrough-tutorial-duration duration="20"></walkthrough-tutorial-duration>

いよいよ GKE クラスタに NVIDIA NIM をデプロイします。

### **1. デプロイ用マニフェストの適用**


以下のコマンドで、マニフェストをクラスタに適用し、NIM をデプロイします。

```bash
kubectl apply -f https://raw.githubusercontent.com/acc-mu3n/NIM-Bootcamp/refs/heads/work-gcp-collaboration/workspace-nim-with-rag/k8s-manifest/swallow.yaml
kubectl apply -f https://raw.githubusercontent.com/acc-mu3n/NIM-Bootcamp/refs/heads/work-gcp-collaboration/workspace-nim-with-rag/k8s-manifest/embed.yaml
```

### **2. デプロイ状況の確認**

デプロイが完了するまでには、NIM コンテナイメージのダウンロードや GPU ノードの準備のため、**10分〜20分** ほどかかる場合があります。

以下のコマンドで、Pod の状態を監視しましょう。

```bash
kubectl get pods -w
```

Pod の STATUS が ContainerCreating を経て Running になり、READY が 0/1 から 1/1 になればデプロイは完了です。

### **3. サービスの確認**

NIM に外部からアクセスするためのロードバランササービスも同時に作成されています。以下のコマンドで、外部 IP アドレスを確認します。

```bash
kubectl get service nim-swallow-autopilot-service
```

EXTERNAL-IP 列に IP アドレスが表示されるまで、数分待ちます。表示された IP アドレスは、次のステップで使用します。

## **Lab03: NIM を利用した推論の実行**

<walkthrough-tutorial-duration duration="10"></walkthrough-tutorial-duration>

最後に、デプロイした NIM に推論リクエストを送信し、モデルが正常に動作していることを確認します。

### **1. エンドポイントの準備**

まず、前のステップで確認した外部 IP アドレスを環境変数に設定します。

#【重要】<EXTERNAL_IP> の部分を、`kubectl get service nim-swallow-autopilot-service` で確認した実際のIPアドレスに置き換えてください  

```bash
export EXTERNAL_IP=<EXTERNAL_IP>
```

### **2. 推論リクエストの実行**

curl コマンドを使用して、NIM の推論エンドポイントにリクエストを送信します。このコマンドは Cloud Shell で実行ボタンがうまくいかない可能性があるので、
ご自身でコピー＆ペーストしてください。

```
curl -X "POST" "http://${EXTERNAL_IP}:8000/v1/chat/completions"   
     -H 'Content-Type: application/json'   
     -d $'{  
  "model": "meta/llama3-8b-instruct",  
  "messages": [  
    {  
      "role": "user",  
      "content": "日本の首都について、小学生にも分かるように短い言葉で教えて。"  
    }  
  ],  
  "temperature": 0.7,  
  "top_p": 1,  
  "max_tokens": 1024  
}'
```

モデルからの応答が JSON 形式で返ってくれば成功です！

```
{  
  "id": "cmpl-xxxxxxxx",  
  "object": "chat.completion",  
  "created": ...,  
  "model": "meta/llama3-8b-instruct",  
  "choices": [  
    {  
      "index": 0,  
      "message": {  
        "role": "assistant",  
        "content": "日本の首都は、東京だよ！"  
      },  
      "finish_reason": "stop"  
    }  
  ],  
  "usage": {  
    "prompt_tokens": ...,  
    "total_tokens": ...,  
    "completion_tokens": ...  
  }  
}
```
<walkthrough-congratulated>  
おめでとうございます。NIM の推論コンテナを正しく GKE にデプロイできました。
ここからは Vertex AI Workbench を使用して、Jupyter notebook を利用して操作します。
</walkthrough-congratulated>