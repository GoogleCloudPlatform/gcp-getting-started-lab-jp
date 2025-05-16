<walkthrough-metadata>
  <meta name="title" content="GKE Dojo Basic" />
  <meta name="description" content="Hands-on Dojo GKE AI" />
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

```
export REGION="us-central1"
export ZONE="us-central1-a"
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
### **3. google cloud への認証を設定する**
Cloud Shellのセッションが切れた場合、Google Cloudへの認証も切れていることがあります。その場合は、以下のコマンドを実行して再認証してください。

```Bash
gcloud auth login
```
コマンドを実行すると、Cloud Shell上にURLが表示され、続いて以下のようなメッセージが表示されることがあります。
```
Go to the following link in your browser:

    https://accounts.google.com/o/oauth2/auth?response_type=code&client_id=...

Enable headless account? (Y/n)?
```
ここで、Y を入力して Enter キーを押してください。

その後、Cloud Shell に表示されたURLをコピーします。

重要: **コピーした URL は現在作業しているシークレットウィンドウの新しいタブに貼り付けて開いてください。**

ブラウザで URL を開くと、Google アカウントのログイン画面が表示されます。

アカウント選択の注意:
ハンズオン環境 (例: Qwiklabs) をご利用の場合、通常、student- で始まるメールアドレス (例: student-01-xxxxxxxx@qwiklabs.net) のアカウントを使用するよう指示されているはずです。必ず、その指定された student-アカウントでログインしてください。個人のGmailアカウントなどでログインしないように注意しましょう。

ログインが成功し、許可を求める画面が表示されたら、「許可」または「Allow」をクリックします。
認証が完了すると、ブラウザのタブに認証コードが表示されるか、「You are now authenticated with the Google Cloud SDK!」のようなメッセージが表示されます。その後、Cloud Shellのプロンプトに戻れば、認証は完了です。


### **4. プロジェクト ID とプロジェクト番号を設定する**

```
export PROJECT_ID=$(gcloud projects list --filter="projectId ~ '^qwiklabs-gcp-' AND projectId != 'qwiklabs-resources'" --format="value(projectId)" | head -n 1)
export PROJECT_NUMBER=$(gcloud projects describe $PROJECT_ID --format="value(projectNumber)")
echo $PROJECT_ID
echo $PROJECT_NUMBER
```

### **5. gcloud のデフォルト設定**

```bash
export REGION="us-central1"
export ZONE="us-central1-a"
gcloud config set project $PROJECT_ID
gcloud config set compute/region $REGION
gcloud config set compute/zone $ZONE
```


## **Lab00.GKE Autopilot クラスタの作成**
<walkthrough-tutorial-duration duration=20></walkthrough-tutorial-duration>

このラボでは、ハンズオンの基盤となる Google Kubernetes Engine (GKE) クラスタを作成します。
今回は、GKEの運用モードの一つである Autopilot モード を利用します。Autopilot モードでは、ノードのプロビジョニングやスケーリング、セキュリティ構成など、クラスタの運用管理の多くがGoogle によって自動化されるため、ユーザーはアプリケーションの開発とデプロイに集中できます。特に、GPU のようなアクセラレータを利用する際も、複雑なノードプールの設定が不要になるメリットがあります。

以下のコマンドを実行し、GKE Autopilot クラスタを作成します。クラスタ名は gke-dojo-cluster とします。

```bash
export GKE_CLUSTER_NAME="gke-dojo-cluster"
gcloud container --project "$PROJECT_ID" clusters create-auto "$GKE_CLUSTER_NAME" --region "$REGION" --release-channel "rapid"
```

クラスタの作成には 10分〜20分程度 の時間がかかります。コマンドの実行が完了するまで、しばらくお待ちください。
コマンドが成功すると、指定したリージョンに新しい GKE Autopilot クラスタが作成されます。Autopilot モードでは、GPU などのアクセラレータを利用する場合でも、特別なクラスタ設定は原則不要です。ワークロードが必要とするリソース（CPU, メモリ, GPUなど）をマニフェストファイルで指定すれば、Autopilot が必要なノードを自動的に準備してくれます。

## **Lab01.Gemma3 サービングアプリケーションのデプロイ**

<walkthrough-tutorial-duration duration=40></walkthrough-tutorial-duration>

GKEクラスタの準備が整いました！
このラボでは、いよいよ AI モデル「Gemma 3 (4B)」をGKEクラスタ上にデプロイし、推論リクエストを受け付けることができるサービングアプリケーションを構築します。

### **1. Gemma 3 (4B) モデルの準備**

このハンズオンでは、Hugging Face Hubで公開されている google/gemma-3-4b-it モデルを、アプリケーションが推論リクエストを受け取った際に動的にロード（ダウンロード）する方式を取ります。

まずは、モデル名とHugging Faceアクセストークンを環境変数に設定します。

HF_TOKEN の値は、ご自身の Hugging Face アクセストークンに置き換えてください。アクセストークンは Hugging Face のウェブサイトで取得できます（通常は Settings -> Access Tokens から）。講義スライドに利用方法が記載されていますので、そちらも参照してください。トークンは機密情報ですので、取り扱いには十分注意してください。

```
export HF_MODEL_NAME="google/gemma-3-4b-it"
export HF_TOKEN="[YOUR_HUGGINGFACE_ACCESS_TOKEN]" 
```


### **1. 推論用 Docker イメージの作成と Artifact Registry へのプッシュ**

GKE上でアプリケーションを動作させるためには、まずそのアプリケーションをコンテナイメージ（具体的にはDockerイメージ）としてパッケージングする必要があります。
そして、そのイメージを GKE クラスタがアクセスできる場所に保存します。ここでは、Google Cloudの プライベートコンテナレジストリサービスである Artifact Registry を使用します。

まず、イメージ名やリポジトリ名などを環境変数に設定します。

```bash
export AR_REPO_NAME="gemma3-4b-repo"
export IMAGE_NAME="gemma3-4b-server"
export IMAGE_TAG="latest"
```

次に、推論・サービング用のアプリケーションを格納するための Artifact Registry のDockerリポジトリを作成します。既に同名のリポジトリが存在する場合は、このコマンドはスキップされます。

```bash
gcloud artifacts repositories describe ${AR_REPO_NAME} --location=${REGION} > /dev/null 2>&1 || \
gcloud artifacts repositories create ${AR_REPO_NAME} \
    --repository-format=docker \
    --location=${REGION} \
    --description="Gemma 3 GKE handson repository"
```
リポジトリが準備できたら、いよいよ推論・サービング用アプリケーションのDockerイメージをビルドし、作成したArtifact Registryリポジトリにプッシュします。
lab-01/ ディレクトリには、アプリケーションコードと Dockerfile（イメージの設計図）が含まれています。
カレントディレクトリを変更します。
```bash
cd $HOME/gcp-getting-started-lab-jp/gke-ai/lab-01/
```

現在、lab-01にカレントディレクトリが指定されていることをプロンプトから確認して実行します。

```bash
gcloud builds submit --tag ${REGION}-docker.pkg.dev/${PROJECT_ID}/${AR_REPO_NAME}/${IMAGE_NAME}:${IMAGE_TAG} .
```
イメージのビルドとプッシュには数分かかることがあります。

### **2. GKE へのデプロイ**

DockerイメージがArtifact Registryにプッシュされたので、次はこのイメージを使ってGKEクラスタ上にアプリケーションをデプロイします。
まず、kubectl コマンド（Kubernetesを操作するためのCLIツール）がGKEクラスタを操作できるように、認証情報を取得し、現在のコンテキスト（操作対象のクラスタ）を設定します。

```bash
gcloud container clusters get-credentials gke-dojo-cluster --region us-central1 --project ${PROJECT_ID}
```
これにより、以降の kubectl コマンドは、先ほど作成した gke-dojo-cluster に対して実行されるようになります。

次に、Kubernetesのマニフェストファイル（アプリケーションのデプロイ方法や設定を記述したファイル）を準備します。
lab-01/ ディレクトリには deployment_template.yaml というテンプレートファイルがあります。このファイルには、先ほど設定した環境変数（イメージのパスやHugging Faceのトークンなど）を参照するプレースホルダーが含まれています。
envsubst コマンドを使って、これらのプレースホルダーを実際の値に置き換え、deployment.yaml という名前で新しいファイルを作成します。

```bash
envsubst < deployment_template.yaml > deployment.yaml
```

準備が整ったマニフェストファイル (deployment.yaml と service.yaml) を使って、アプリケーションをGKEにデプロイします。
- deployment.yaml: Gemma サービングアプリケーションの Pod（コンテナを実行する最小単位）をどのように作成し、管理するかを定義します。
- service.yaml: デプロイされたアプリケーションに外部からアクセスするためのネットワーク設定（ロードバランサなど）を定義します。

```bash
kubectl apply -f deployment.yaml
kubectl apply -f service.yaml
```

### **3. Podのログ確認**

デプロイしたアプリケーションが正しく起動しているか、Pod のログを見て確認しましょう。
アプリケーションの起動、特に Gemma モデルのダウンロードと初期化には時間がかかるため、デプロイから実際にリクエストを受け付けられるようになるまで 15 分程度かかる可能性があります。

まず、デプロイされたPodの名前を取得します。app=gemma3-server というラベルが付いた Pod を検索しています。

```bash
export POD_NAME_GEMMA3=$(kubectl get pods -l app=gemma3-server -o jsonpath='{.items[0].metadata.name}')
```

次に、取得したPod名を使ってログをリアルタイムで表示します (-f オプション)。

```bash
kubectl logs -f $POD_NAME_GEMMA3
```
ログにエラーメッセージが表示されず、モデルのロードやサーバー起動に関するメッセージ（例: Uvicorn running on http://0.0.0.0:80 など）が表示されれば、順調に起動している証拠です。
ログの最後に "Application startup complete" や、モデルのダウンロードとロードが完了した旨のメッセージが表示されるのを確認してください。
**エラーが頻発している場合は、環境変数の設定ミス（特にHF_TOKEN）やリソース不足などが考えられます**

問題なければ、ログ出力を Ctr+C などで停止してください。

### **4. アクセス先の確認**
アプリケーション (Pod) が起動したら、外部からアクセスするための IP アドレスを取得します。service.yaml でタイプ LoadBalancer の Service を作成したため、ロードバランサーが外部IP アドレスを割り当ててくれます。

以下のコマンドで、gemma3-server-service という名前の Service の外部IPアドレスを取得し、環境変数 EXTERNAL_IP_GEMMA3 に設定します。

```
export EXTERNAL_IP_GEMMA3=$(kubectl get service gemma3-server-service  -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo "External IP for Gemma 3 (4B) service: $EXTERNAL_IP_GEMMA3"
```

### **5. 推論リクエスト**
curl コマンドを使って、デプロイした Gemma サービングアプリケーションに推論リクエストを送信してみましょう。
リクエストボディには、使用するモデル名（Hugging Face Hubでの名前）、プロンプト（モデルへの指示や質問）、最大トークン数（生成されるテキストの最大長）を指定します。



```
curl -i -X POST "http://${EXTERNAL_IP_GEMMA3}:80/v1/completions" \
    -H "Content-Type: application/json" \
    -d '{
        "model": "google/gemma-3-4b-it",
        "prompt": "日本の首都はどこですか？",
        "max_tokens": 50
    }'
```

-i オプションで HTTP レスポンスヘッダも表示します。

しばらく待つと、Gemma モデルからの応答が JSON 形式で返ってきます。例えば、以下のようなレスポンスが期待できます（内容は実行ごとに多少変わることがあります）。

```
HTTP/1.1 200 OK
// ... (他のヘッダー)
content-type: application/json
{"id":"...","object":"text_completion","created":...,"model":"google/gemma-3-4b-it","choices":[{"index":0,"text":"\n日本の首都は東京です。","logprobs":null,"finish_reason":"length"}],"usage":{"prompt_tokens":0,"completion_tokens":10,"total_tokens":10}}
```
プロンプトに対する簡単な応答（例：「日本の首都は東京です。」など）が text フィールドに含まれていれば、Lab01は成功です！
GKE上でGemma 3 (4B) モデルをサービングし、実際に推論を実行することができました。

## **Lab02.GKE 上で Gemma をファインチューニングする**

### **1. 環境変数の設定**

前のラボでは既存の Gemma モデルをそのまま利用しましたが、このラボではさらに一歩進んで、GKE クラスタ上で Gemma モデルを ファインチューニング します。
ファインチューニングとは、既存の学習済みモデルに対して、特定のタスクやデータセットに合わせて追加の学習を行うことで、モデルの性能を向上させたり、特定の振る舞いをさせたりする手法です。

このラボでは、LoRA (Low-Rank Adaptation) という効率的なファインチューニング手法を用いて、Gemma からの返答の語尾が全て「ござる」になるように学習させます。

ファインチューニングは計算資源、特に GPU を大量に消費する処理です。GKEの Kubernetes Job を利用することで、学習ジョブの実行に必要な GPU リソースを動的にプロビジョニングし、学習完了後にはリソースを解放するという効率的な運用が可能です。

まず、このラボで使用する環境変数を設定します。
前のラボで設定した PROJECT_ID, REGION, GKE_CLUSTER_NAME などに加え、ファインチューニングジョブ用の Artifact Registry リポジトリ名、イメージ名、学習済みアダプタの保存先となるHugging Face リポジトリ名などを設定します。

HF_TOKEN にはHugging Faceの 書き込み権限 (write access) があるアクセストークンを設定します。ファインチューニングしたモデルアダプタを Hugging Face Hub にご自身の新しいリポジトリとしてプッシュするために必要です。
また、HF_USERNAME にはご自身の Hugging Face のユーザー名を設定してください。
これらの値をテキストエディタなどに一時的にコピーし、ご自身のアカウント情報に合わせて正確に編集してから、Cloud Shell で実行してください。
```
export REGION=$(gcloud config get compute/region)
export CLUSTER_NAME="gke-dojo-cluster"
export AR_REPO_NAME="gemma-finetune-job-repo"
export IMAGE_NAME="gemma-finetune-job"
export IMAGE_TAG="latest"
export HF_MODEL_NAME="google/gemma-3-4b-it"
export HF_TOKEN="[YOUR_HUGGINGFACE_WRITE_ACCESS_TOKEN]"
export HF_USERNAME="[YOUR_HUGGINGFACE_USERNAME]"
export LORA_ADAPTER_REPO_NAME="gemma-gozaru-adapter"
```
### **2.学習用スクリプトと Dockerfile の準備**

GKE 上でファインチューニングジョブを実行するためには、学習ロジックを記述した Python スクリプトと、そのスクリプトを実行するための環境を定義した Dockerfile が必要です。
lab-02/ ディレクトリには、これらのファイル（finetune_gozaru.py, Dockerfileなど）が既に用意されています。

- finetune_gozaru.py: Hugging Face の transformers ライブラリや peft (Parameter-Efficient Fine-Tuning) ライブラリを使用してLoRAファインチューニングを実行するスクリプトです。「ござる」データセット（スクリプト内に簡易的に定義）で学習し、学習済み LoRA アダプタを Hugging Face Hub にアップロードする機能が含まれています。
- Dockerfile: 実行するために必要な Python 環境、CUDA（GPUを利用するためのNVIDIAのプラットフォーム）、各種ライブラリ（transformers, torch, peft など）をインストールする手順が記述されています。


### **3.Docker イメージのビルドと Artifact Registry へのプッシュ**


次に、この学習用スクリプトとDockerfileを元にDockerイメージをビルドし、Artifact Registryにプッシュします。このイメージがGKEのJobによって実行されることになります。

まず、ファインチューニングジョブ用のDockerイメージを格納するArtifact Registryリポジトリを作成します。（既に存在する場合はスキップされます）

```bash
gcloud artifacts repositories describe ${AR_REPO_NAME} --repository-format=docker --location=${REGION} > /dev/null 2>&1 || \
gcloud artifacts repositories create ${AR_REPO_NAME} \
    --repository-format=docker \
    --location=${REGION} \
    --description="Gemma Fine-tuning Job Images"
```

次に、Dockerイメージをビルドし、Artifact Registryにプッシュします。
その前に、Cloud ShellからArtifact Registry（${REGION}-docker.pkg.devという形式のホスト名）に対してDockerコマンドで認証できるように設定しておきます。

```bash
cd $HOME/gcp-getting-started-lab-jp/gke-ai/lab-02/
```
lab-02ディレクトリに移動していることを確認してください。

```bash
gcloud auth configure-docker ${REGION}-docker.pkg.dev
gcloud builds submit --tag ${REGION}-docker.pkg.dev/${PROJECT_ID}/${AR_REPO_NAME}/${IMAGE_NAME}:${IMAGE_TAG} .
```
このビルドプロセスは、必要なライブラリのダウンロードや設定が含まれるため、数分から十数分かかることがあります。完了までお待ちください。

### **4.GKE 上でのファインチューニングジョブの実行**

Docker イメージの準備ができたので、いよいよGKEクラスタ上でファインチューニングジョブを実行します。
Kubernetesの Job は、バッチ処理や一度きりのタスクを実行するのに適したリソースです。Jobは、指定された数のPodを正常に完了させることを保証します。
このJobのマニフェストファイル (finetune_job_template.yaml) には、使用するDockerイメージ、必要なGPUリソース（例: NVIDIA L4 GPUを1つリクエスト）、環境変数（Hugging Faceのトークンやモデル名など）が定義されています。

まず、finetune_job_template.yaml の中のプレースホルダーを環境変数の実際の値で置換し、finetune_job.yaml を作成します

```bash
envsubst < finetune_job_template.yaml > finetune_job.yaml
```

finetune_job.yaml を開いて、spec.template.spec.containers[0].image や env の値が正しく設定されているか確認してみてください。
特に nodeSelector や tolerations でGPUの種類 (cloud.google.com/gke-accelerator: nvidia-l4) を指定している部分に注目です。
Autopilot モードでは、このようなリソース要求に基づいて適切なノードが自動的にプロビジョニングされます。

作成した finetune_job.yaml をクラスタに適用して、Jobを開始します。
Jobが作成されると、Kubernetesは指定されたリソース（この場合はL4 GPUが利用可能なノード）を確保し、Podをスケジュールします。



```bash
kubectl apply -f finetune_job.yaml
```
JobのPodが起動し、学習が開始されるまでには少し時間がかかります。特に、GPUノードのプロビジョニングが必要な場合（クラスタに利用可能なL4 GPUノードがまだない場合）、数分から10分程度 かかることがあります。

以下のコマンドで、Jobに関連するPodの状態を監視できます (-wオプションで変更を監視)。

```bash
kubectl get pods -l job-name=gemma-gozaru-finetune-job -w
```
Podのステータスが Pending (保留中) から ContainerCreating (コンテナ作成中)、そして Running (実行中) に変わるのを確認してください。最終的には学習が完了すると Completed (完了) になります。

&lt;walkthrough-important>
Podが Pending から進まない場合: kubectl describe pod [POD_NAME] でPodのイベントを確認してください。
よくある原因としては、リージョンで指定したGPUタイプが一時的に利用できない、リソースクォータの不足などが考えられます。
Autopilot が適切なノードをプロビジョニングするまで待つか、エラーメッセージに応じて対処が必要です。
JobのPodが Running になったら、Podのログを追跡して学習の進捗を確認できます。

```Bash
export FINETUNE_POD_NAME=$(kubectl get pods -l job-name=gemma-gozaru-finetune-job -o jsonpath='{.items[0].metadata.name}')
kubectl logs -f $FINETUNE_POD_NAME
```
ログには、データセットのロード、ベースモデルのロード、そしてLoRAアダプタの学習エポックごとの進捗（loss の値など）が表示されるはずです。
学習が進むと、以下のようなログが期待されます（一部抜粋）。

```
INFO:root:LoRA config: PeftConfig(...)
INFO:root:Training model...
...
{'loss': ..., 'learning_rate': ..., 'epoch': ...}
...
INFO:root:ファインチューニング完了。モデルをHubにプッシュします: [YOUR_HUGGINGFACE_USERNAME]/gemma-gozaru-adapter
```

最終的に INFO:root:ファインチューニング完了。 のようなメッセージが表示され、Podのステータスが Completed になれば、学習ジョブは成功です！

所要時間: 学習自体には、使用する GPU の性能、データセットのサイズ、エポック数などによって異なりますが、このハンズオンの構成では L4 GPU でおよそ15〜30分程度かかる見込みです。

### **4.Hugging Face Hub で結果を確認する**
学習スクリプト (train.py) の中で trainer.push_to_hub() が実行されるように設定されているため、ファインチューニングが正常に完了すると、学習されたLoRAアダプタ（モデルの差分ファイル群）が自動的にHugging Face Hubにご自身の新しいリポジトリとしてプッシュされます。

以下のURLの [YOUR_HUGGINGFACE_USERNAME] と [YOUR_GOZARU_LORA_ADAPTER_REPO_NAME] (環境変数 LORA_ADAPTER_REPO_NAME で設定した名前、デフォルトは gemma-gozaru-adapter) の部分をご自身のものに置き換えて、ブラウザでアクセスしてみてください。

https://huggingface.co/[YOUR_HUGGINGFACE_USERNAME]/[YOUR_GOZARU_LORA_ADAPTER_REPO_NAME]

アクセスすると、新しいリポジトリが作成され、adapter_config.json, adapter_model.safetensors などのファイルがアップロードされているはずです。
これらが、Gemmaを「ござる」化するための LoRA アダプタです。

GKE 上で Gemma モデルのファインチューニング（LoRA学習）を行い、その結果を Hugging Face Hub に保存することができました。

## **Lab03.GKE 上でファインチューニング済み Gemma をサービングする**
### **1.環境変数を設定する**

前の Lab02 では、Gemma モデルを「ござる」語尾になるようにファインチューニングし、その LoRA アダプタを Hugging Face Hub に保存しました。この Lab03 では、その成果を実際にデプロイして体験します！

具体的には、ベースとなる Gemma モデルに、Lab02 で作成した「ござる」LoRA アダプタを適用した形で GKE クラスタ上にサービングアプリケーションをデプロイし、実際に「ござる」と返答するかどうかを確認します。
まず、このラボで使用する環境変数を設定します。
主に、デプロイするアプリケーションのコンテナイメージ名、ベースモデル名、そして最も重要な Lab02 で Hugging Face HubにプッシュしたLoRAアダプタのリポジトリIDなどを設定します。

```bash
export CLUSTER_NAME="gke-dojo-cluster"
export AR_REPO_NAME="gozaru-gemma-repo"
export IMAGE_NAME="gozaru-gemma-server"
export IMAGE_TAG="latest"
export HF_MODEL_NAME="google/gemma-3-4b-it"
export LORA_ADAPTER_NAME="[YOUR_HUGGINGFACE_USERNAME]/[YOUR_GOZARU_LORA_ADAPTER_REPO_NAME]"
export HF_TOKEN="[YOUR_HUGGINGFACE_READ_ACCESS_TOKEN]"
```
LORA_ADAPTER_NAME の [YOUR_HUGGINGFACE_USERNAME] と [YOUR_GOZARU_LORA_ADAPTER_REPO_NAME] の部分は、ご自身の Hugging Face ユーザー名と、Lab02 で LoRA アダプタをプッシュしたリポジトリ名に正しく置き換えてください。

### **2. コンテナのビルドとプッシュ**

次に、ファインチューニング済みのGemmaモデル（正確にはベースモデル＋LoRAアダプタ）をサービングするためのアプリケーションをDockerイメージとしてビルドし、Artifact Registryにプッシュします。
lab-03/ ディレクトリには、このための Dockerfile やアプリケーションコード（LoRAアダプタをロードする機能を含む）が用意されています。

まず、この Lab 用のArtifact Registryリポジトリを作成します。（既に存在する場合はスキップされます）

```bash
cd $HOME/gcp-getting-started-lab-jp/gke-ai/lab-03/
```
カレントディレクトリが lab-03 であることを確認してください。

```bash
gcloud artifacts repositories describe ${AR_REPO_NAME} --repository-format=docker --location=${REGION} > /dev/null 2>&1 || \
gcloud artifacts repositories create ${AR_REPO_NAME} \
    --repository-format=docker \
    --location=${REGION} \
    --description="Gozaru Gemma LoRA inference server"
```

イメージをビルドしてプッシュします。ビルドには数分かかることがあります。

```bash
gcloud auth configure-docker ${REGION}-docker.pkg.dev
gcloud builds submit --tag ${REGION}-docker.pkg.dev/${PROJECT_ID}/${AR_REPO_NAME}/${IMAGE_NAME}:${IMAGE_TAG} .
```

### **3. GKE クラスタへのデプロイ**

Dockerイメージの準備ができたので、ファインチューニング済みの「ござる」GemmaモデルをGKEにデプロイしましょう。
手順はLab01とほぼ同様です。

まず、kubectl がGKEクラスタを操作できるように認証情報を取得します（既に設定済みのはずですが、念のためとなります）。

```bash
gcloud container clusters get-credentials ${CLUSTER_NAME} --region ${REGION} --project ${PROJECT_ID}
```
次に、マニフェストのテンプレートファイル (deployment_template.yaml) のプレースホルダーを環境変数の値で置き換えて、deployment.yaml を生成します。このテンプレートには、ベースモデル名、LoRA　アダプタ名、HF　トークンなどが渡されるように設定されています。

```bash
envsubst < deployment_template.yaml > deployment.yaml
```
deployment.yaml を確認し、HF_MODEL_NAME, LORA_ADAPTER_NAME, HF_TOKEN が正しく設定されているか見てみましょう。これらの情報を使って、Pod起動時にアプリケーションがHugging Face HubからモデルとLoRAアダプタをダウンロードします。

```bash
cat deployment.yaml
```

もし、プレースホルダー(環境変数名)のままの場合、環境変数を設定してから envsubst コマンドをもう一度実施ください。
生成されたマニフェストファイル (deployment.yaml と service.yaml) を使って、GKEにデプロイします。
service.yaml は、この「ござる」Gemmaサーバーに外部からアクセスするためのものです。

```bash
kubectl apply -f deployment.yaml
kubectl apply -f service.yaml
```
デプロイされたPodの状態を監視します。app=gozaru-gemma-server というラベルを持つPodです。

```bash
kubectl get pods -l app=gozaru-gemma-server -w
```
Podのステータスが Running になり、READY列が 1/1 になるまで待ちます。
モデルとLoRAアダプタのダウンロード、そしてそれらのロードには時間がかかるため、Running になった後もREADYが 1/1 になるまで10〜20分程度かかることがあります。

Podのログを確認して、起動状況を詳しく見てみましょう。


```bash
export POD_NAME=$(kubectl get pods -l app=gozaru-gemma-server -o jsonpath='{.items[0].metadata.name}')
kubectl logs -f $POD_NAME
```
ログの中で、ベースモデルとLoRAアダプタのダウンロード・ロードに関するメッセージや、Application startup complete. や Test inference successful: といったメッセージが表示されれば、アプリケーションの起動はほぼ完了です。

次に、外部からアクセスするためのIPアドレスを取得します。

```bash
kubectl get service gozaru-gemma-service -w
```

IPアドレスが割り当てられたら、環境変数にセットします。

```bash
export EXTERNAL_IP_GOZARU=$(kubectl get service gozaru-gemma-service -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo "External IP for Gozaru Gemma service: $EXTERNAL_IP_GOZARU"
```
いよいよ、ファインチューニングの成果を確認する時が来ました！
curl コマンドで、デプロイした「ござる」Gemmaサーバーに推論リクエストを送信し、応答の語尾が「ござる」になっているか確認します。
Lab01 とはエンドポイントのパスが /generate になっている点に注意してください (使用しているサンプルアプリの仕様です)。

```bash
curl -X POST "http://${EXTERNAL_IP_GOZARU}:80/generate" \
    -H "Content-Type: application/json" \
    -d '{
        "prompt": "日本の首都はどこですか？",
        "max_new_tokens": 50
    }'
```
期待される応答の例は以下の通りです。generated_text の語尾に注目してください
```json
{
  "generated_text": "日本の首都は東京でござる。",
  "model_name": "google/gemma-2-2b-jpn-it + [YOUR_GOZARU_LORA_ADAPTER_HF_ID]",
  "processing_time_ms": XXXX
}
```
応答の語尾が「ござる」風になっていれば大成功です！
これで、ファインチューニングされたLoRAアダプタがGKE上で正しくベースモデルに適用され、期待通りに動作していることが確認できました。

## **Configurations!**
これでGKE道場 AI編の全てのラボが完了です。Gemma モデルのサービングからファインチューニング、そしてファインチューニング済みモデルのサービングまで、GKE を活用した一連の AI/ML ワークフローを体験できました。この経験が、皆さんの今後に役立つことを願っています！