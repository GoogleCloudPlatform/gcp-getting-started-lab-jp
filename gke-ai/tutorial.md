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
        "prompt": "Translate to Japanese: Hello, how are you doing today?",
        "max_new_tokens": 50
    }'
```


```Bash
{
  "generated_text": "Translate to Japanese: Hello, how are you doing today?\nこんにちは、今日はお元気ですか？",
  "model_name": "google/gemma-3-1b-it + your-username/your-gemma3-1b-lora-adapter",
  "processing_time_ms": 1234
}
```
以上で、google/gemma-3-1b-it の GKE でのサービングは終わります。












まず、クラスタへの接続情報を取得します。
```bash
gcloud container clusters get-credentials gke-dojo-cluster --region asia-northeast1 --project ${PROJECT_ID}
```

以下のコマンドで、マニフェストの適用を行ってください。
実行時 Warning が複数出力されますが、デプロイ自体には問題ございません。

```bash
kubectl apply -f lab-01/app/
```
以下のコマンドで、現在の Pod および Node のステータスを取得を継続して行います。
Pod の作成に伴い、Node が複製され、Pod がデプロイされる様子が確認できます。
デプロイには 2,3 分程度の時間がかかります。
```bash
watch -d kubectl get pods,nodes,svc
```

数分後、Pod の Status が Running となることを確認できたら、 `Ctrl-C` でコマンドの実行を終了します。

### **2. Demo サイトの確認**
ロードバランサーの設定が完了するまで数分かかります。数分後、以下のコマンドでアプリケーションの URL を確認します。
確認した URL をコピーして Chrome などの Web ブラウザのアドレスバーに貼り付けアプリケーションを確認します。
なお、設定が完了するまでの数分間（場合によってはそれ以上）は、Connection reset by peer のエラーが出力されます。
その場合は、さらにしばらくお待ちください。

```bash
kubectl get svc | grep LoadBalancer | awk '{print "http://"$4}'
```

Lab01 はこちらで完了となります。


## **Lab02.Balloon Pod の利用による高速なスケーリング**
<walkthrough-tutorial-duration duration=10></walkthrough-tutorial-duration>


手動または HPA 経由でスケールアップすると、新しい Pod がプロビジョニングされますが、予備容量がない場合は、新しいノードがプロビジョニングされるために遅延が発生する可能性があります。
Autopilot モードで迅速にスケールアップするためには、Balloon Pod を利用します。

### **1. Priority Class と Balloon Pod の作成**
まずは、Priority の定義リソースである Priority Class と Balloon Pod を作成します。

```bash
kubectl apply -f lab-02/balloon-priority.yaml 
kubectl apply -f lab-02/balloon-deploy.yaml 
```

Balloon Pod の作成により、ノードがスケールすることを watch コマンドで動的に確認します。
完了までに数分かかります。

```bash
watch -d kubectl get pods,nodes
```
数分後、すべての Pod と Node の Status が Running となることを確認できたら、 `Ctrl-C` でコマンドの実行を終了します。

### **2. 迅速なスケールアウトの確認**

次に frontend の pod を 1 から 4 へスケールアウトします。

```bash
kubectl scale --replicas=4 deployment gke-dojo
```

Balloon Pod を先に作成していたため、目的の Pod のスケールアウトはスピーディに完了します。一方　Balloon Pod　は優先度が低いため、ノードから削除され、さらなるノードのスケールアウトが始まります。Balloon Pod は追加されたノードに配置されます。
以下のコマンドで一連の流れを確認しましょう。

```bash
watch -n 1 kubectl get pods,nodes
```

数分後、すべての Pod と Node の Status が Running となることを確認できたら、 `Ctrl-C` でコマンドの実行を終了します。

Lab02 はこちらで完了となります。

次の内容に入る前に不要なリソースを削除します。
```bash
kubectl delete -f lab-02/balloon-priority.yaml 
kubectl delete -f lab-02/balloon-deploy.yaml 
kubectl delete deployment gke-dojo
kubectl delete svc gke-dojo
```

## **Ex01.Google Cloud サービスによる CI/CD**
<walkthrough-tutorial-duration duration=30></walkthrough-tutorial-duration>

### **0. ２つ目のクラスター作成**
後続で使う 2 つ目のクラスターを作成しておきます。

```bash
gcloud container --project "$PROJECT_ID" clusters create-auto "gke-dojo-cluster-prod" \
--region "asia-northeast1" --release-channel "regular"
```
このクラスタは、本番環境向けクラスタとして扱います。
開発環境クラスタで動作を確認したアプリケーションを本番環境にデプロイするという流れを Cloud Build と Cloud Deploy で実装します。

### **1. 対象のアプリケーション確認**

ローカルにある python アプリケーションを出力して確認してください。
こちらはテキストを出力するシンプルな Flask アプリケーションです。

```bash
cat lab-ex01/main.py
```

### **2. レポジトリ作成**

以下のコマンドで Flask アプリケーションのコンテナイメージを配置するための Artifact Registry のレポジトリを作成します。
```bash
gcloud artifacts repositories create gke-dojo --repository-format=docker --location=asia-northeast1
```

### **3. Cloud Build によるコンテナイメージの作成**

Cloud Build を利用して、クラウド上でコンテナイメージのビルドを行います。
Cloud Build に含まれている Buildpacks により Dockerfile を書かなくとも、アプリケーションの構成を認識して適切なコンテナイメージを作成することができます。

以下のコマンドで、ディレクトリを移動します。

```bash
cd lab-ex01
```
移動後、ビルドを実行します。

```bash
gcloud builds submit --config cloudbuild.yaml
```
最終的に`STATUS: SUCCESS`と表示されましたら、ビルド成功です。

カレントディレクトリを戻しておきます。

```bash
cd ..
```

### **4. Cloud Deploy による デプロイ**

前の手順で用意した Flask アプリケーションを Kubernetes マニフェストを確認します。

```bash
cat lab-ex01/k8s/deployment.yaml
```

```bash
cat lab-ex01/k8s/service.yaml
```

続いて Cloud Deploy にてターゲットとなる GKE クラスタにデプロイするための定義ファイルを確認します。
```bash
cat lab-ex01/clouddeploy.yaml
```

以下のコマンドで `clouddeploy.yaml` 内の`PROJECT_ID`を実際の環境変数(プロジェクトID)へ置き換えます。
```
sed -i 's/PROJECT_ID/'"$PROJECT_ID"'/g' lab-ex01/clouddeploy.yaml
```

このファイルを利用して、アプリケーションをデプロイするためのパイプラインを用意します。
```bash
gcloud deploy apply --file=lab-ex01/clouddeploy.yaml --region asia-northeast1 --project=$PROJECT_ID
```

Cloud Deploy ではテンプレートとなる Kubernetes のマニフェストを環境に合わせてレンダリングするために、Skaffold を利用します。
ここでは、コンテナイメージを今回のアプリケーションに書き換えるのみのため、シンプルなコンフィグを作成しています。

```bash
cat lab-ex01/skaffold.yaml
```
それでは、デプロイを開始します。以下のコマンドでリリースを作成します。

```bash
cd lab-ex01/
gcloud deploy releases create release01 \
    --delivery-pipeline=gke-dojo \
    --region=asia-northeast1 \
    --skaffold-file=skaffold.yaml \
    --source=./ \
    --images=gke-dojo="asia-northeast1-docker.pkg.dev/$PROJECT_ID/gke-dojo/gke-dojo-app:v1"
```
数分の経過後、[Cloud Deploy コンソール](https://console.cloud.google.com/deploy)に最初のリリースの詳細が表示され、それが最初のクラスタに正常にデプロイされたことが確認できます。

[Kubernetes Engine コンソール](https://console.cloud.google.com/kubernetes)に移動して、アプリケーションのエンドポイントを探します。
左側のメニューバーより Services & Ingress を選択し、gke-dojo-service という名前のサービスを見つけます。
Endpoints 列に IP アドレスが表示され、リンクとなっているため、それをクリックして、アプリケーションが期待どおりに動作していることを確認します。

ステージングでテストしたので、本番環境に昇格する準備が整いました。
[Cloud Deploy コンソール](https://console.cloud.google.com/deploy)に戻ります。
デリバリーパイプラインの一覧から、`gke-dojo` をクリックします。
すると、`プロモート` という青いリンクが表示されています。リンクをクリックし、内容を確認した上で、下部の`プロモート`ボタンをクリックします。すると本番環境へのデプロイを実施されます。

先ほどの手順と同様に本番環境のアプリケーションの動作を確認できましたら、本ハンズオンは終了です。

## **Configurations!**
これで、GKE での基本的なアプリケーションのデプロイと操作、Autopilot Mode におけるスケールの方法、CI/CD の操作を学ぶことができました。引き続き応用編もお楽しみ下さい。