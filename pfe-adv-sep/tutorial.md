<walkthrough-metadata>
  <meta name="title" content="PFE Basic" />
  <meta name="description" content="Hands-on Platform Engineering Advanced 2024-09" />
  <meta name="component_id" content="110" />
</walkthrough-metadata>

<walkthrough-disable-features toc></walkthrough-disable-features>

# 実践編: Google Cloud で始める Platform Engineering

## Google Cloud プロジェクトの設定、確認

### **1. 対象の Google Cloud プロジェクトを設定**

ハンズオンを行う Google Cloud プロジェクトのプロジェクト ID を環境変数に設定し、以降の手順で利用できるようにします。

```bash
export PROJECT_ID=$(gcloud config get-value project)
```

`プロジェクト ID` は [ダッシュボード](https://console.cloud.google.com/home/dashboard) に進み、左上の **プロジェクト情報** から確認することも可能です。

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
gcloud config set project ${PROJECT_ID}
```
承認するかどうかを聞かれるメッセージがでた場合は、`承認` ボタンをクリックします。

### **3. ハンズオンで利用する Google Cloud の API を有効化する**

Google Cloud では利用したい機能ごとに、有効化を行う必要があります。
ここでは、以降のハンズオンで利用する機能を事前に有効化しておきます。（4,5分ほどかかります）
〜finished successfully というメッセージが出たら正常に終了しています。

```bash
gcloud services enable container.googleapis.com \
  artifactregistry.googleapis.com \
  cloudbuild.googleapis.com \
  clouddeploy.googleapis.com \
  gkehub.googleapis.com \
  containerscanning.googleapis.com \
  containersecurity.googleapis.com \
  containeranalysis.googleapis.com \
  anthos.googleapis.com
```

**GUI**: [API ライブラリ](https://console.cloud.google.com/apis/library?project={{project-id}})

## **4. gcloud コマンドラインツール設定 - リージョン、ゾーン**

コンピュートリソースを作成するデフォルトのリージョン、ゾーンとして、東京 (asia-northeast1/asia-northeast1-c）を指定します。

```bash
gcloud config set compute/region asia-northeast1 && gcloud config set compute/zone asia-northeast1-c
```

## **参考: Cloud Shell の接続が途切れてしまったときは?**

一定時間非アクティブ状態になる、またはブラウザが固まってしまったなどで `Cloud Shell` が切れてしまう、またはブラウザのリロードが必要になる場合があります。その場合は以下の対応を行い、チュートリアルを再開してください。

### **01. チュートリアル資材があるディレクトリに移動する**

```bash
cd ~/gcp-getting-started-lab-jp/pfe-adv-sep
```

### **02. チュートリアルを開く**

```bash
teachme tutorial.md
```

### **03. プロジェクト ID を設定する**

```bash
export PROJECT_ID=$(gcloud config get-value project)
```

### **4. gcloud のデフォルト設定**

```bash
gcloud config set project ${PROJECT_ID} && gcloud config set compute/region asia-northeast1 && gcloud config set compute/zone asia-northeast1-c
```

## **Lab-00.Lab 向けクラスタの準備**
<walkthrough-tutorial-duration duration=20></walkthrough-tutorial-duration>


### **Lab-00-01. VPC の作成**

今回の Lab 用 VPC を作成します。

```bash
gcloud compute networks create ws-network \
  --subnet-mode custom
```

### **Lab-00-02. サブネットの作成**

作成した VPC にサブネットを作成します。

```bash
gcloud compute networks subnets create ws-subnet \
  --network ws-network \
  --region asia-northeast1 \
  --range "192.168.1.0/24"
```

### **Lab-00-03. Cloud Router の作成**

Cloud NAT を設定するため、Cloud Router を作成しておきます。


```bash
gcloud compute routers create \
  ws-router \
  --network ws-network \
  --region asia-northeast1
```

### **Lab-00-04. Cloud NAT の作成**

GKE Cluster や Cloud Workstations は外部 IP を持たせない設定となるため、Cloud NAT を設定しておきます。

```bash
gcloud compute routers nats create ws-nat \
  --router ws-router \
  --auto-allocate-nat-external-ips \
  --nat-all-subnet-ip-ranges \
  --region asia-northeast1
```

### **Lab-00-05. GKE クラスタ の作成**

以下のコマンドを実行し、GKE クラスタを作成します。

```bash
gcloud container --project "$PROJECT_ID" clusters create "dev-cluster" \
  --region "asia-northeast1" \
  --release-channel "regular" \
  --network "ws-network" \
  --subnetwork "ws-subnet" \
  --enable-private-nodes \
  --enable-ip-alias \
  --disk-type pd-standard \
  --num-nodes 2 \
  --no-enable-master-authorized-networks \ 
  --enable-dataplane-v2 \
  --enable-cilium-clusterwide-network-policy \
  --enable-fleet \
  --security-posture=standard \
  --workload-vulnerability-scanning=enterprise \
  --async
```

クラスタの作成には10分〜20分程度の時間がかかります。
同様に Production 用のクラスタも作っておきます。

```bash
gcloud container --project "$PROJECT_ID" clusters create "prod-cluster" \
  --region "asia-northeast1" \
  --release-channel "regular" \
  --network "ws-network" \
  --subnetwork "ws-subnet" \
  --enable-private-nodes \
  --enable-ip-alias \
  --disk-type pd-standard \
  --num-nodes 2 \
  --no-enable-master-authorized-networks \ 
  --enable-dataplane-v2 \
  --enable-cilium-clusterwide-network-policy \
  --enable-fleet \
  --security-posture=standard \
  --workload-vulnerability-scanning=enterprise \
  --async
```

以上で事前準備は完了です。

## **Lab-01 Google Cloud での CI/CD**
GKE 上のワークロードに対して CI/CD を実現するための Cloud Build や Cloud Deploy の機能を試してみます。

### **Lab-01-01 アプリケーションコンテナ保管用レポジトリの作成**

Artifact Registry に CI で作成する成果物であるコンテナイメージを保管するためのレポジトリを作成しておきます。

```bash
gcloud artifacts repositories create app-repo \
  --repository-format docker \
  --location asia-northeast1 \
  --description="Docker repository for python app"
```

### **Lab-01-02 Cloud Build による CI**
Cloud Build を利用してサンプルアプリケーションのソースコードからコンテナイメージをビルドします。
サンプルアプリケーションは Flask を利用した Python のアプリケーションです。

```bash
cat lab-01/app.py
```

リクエストを受けると、ランダムに犬の品種を JSON 形式で返す API を提供しています。
また、ビルド中のステップとして、静的解析(PEP8)と簡単なユニットテストを実装しています。

```bash
cat lab-01/cloudbuild.yaml
```

Cloud Build で実行します。今回は Git レポジトリを用意していないため、ローカルのソースコードから手動トリガーとして実行します。

```bash
gcloud builds submit --config lab-01/cloudbuild.yaml .
```

各ステップが順に行われているのが、出力をみてわかります。
5分ほど正常に完了します。
その後、正しくソースコードがコンテナ化されているのか、Cloud Shell 上でコンテナを動作させて確認します。
まず、以下のコマンドで Cloud Shell に先ほど作成したイメージをダウンロードしてきます。

```bash
docker pull asia-northeast1-docker.pkg.dev/$PROJECT_ID/app-repo/pets:v1
```

続いて、以下のコマンドでCloud Shell 上でコンテナを動作させます。

```bash
 docker run -d -p 5000:5000 asia-northeast1-docker.pkg.dev/$PROJECT_ID/app-repo/pets:v1
```

正しく動作しているか、curl アクセスして確認してみます。JSON 形式でレスポンスがあれば成功です。
```bash
curl http://localhost:5000/random-pets
```

##
### **Lab-01-02 Cloud Deploy によるCD**
続いて、Cloud Deploy を活用して、複数のクラスタに順番にデプロイしていきます。
dev-cluster に対しては、トリガーと共にデプロイがされますが、
prod-cluster に対しては、UI 上でプロモートという操作をするまではデプロイが行われません。

早速そのようなパイプラインを設定していきます。
設定は以下の `lab-01/clouddeploy.yaml` に記述されています。

```bash
cat lab-01/clouddeploy.yaml
```

以下のファイルは`PROJECT_ID`がプレースホルダーになっていますので、各自の環境に合わせて置換します。

```bash
sed -i "s|\${PROJECT_ID}|$PROJECT_ID|g" lab-01/clouddeploy.yaml
```

まずは、パイプラインとターゲットを Cloud Deploy に登録します。これによりアプリケーションをデプロイするための
Cluster および、dev / prod という順序性が定義されます。

```bash
gcloud deploy apply --file lab-01/clouddeploy.yaml --region=asia-northeast1 --project=$PROJECT_ID
```

続いて、リリースを作成して、実際のデプロイを実行します。
デプロイ方法は、`skaffold.yaml`に定義されています。ここには、デプロイに利用するマニフェスト、およびデプロイに対応する成果物が定義されています。

```bash
cat lab-01/skaffold.yaml
```

続いて以下のコマンドで実際に GKE の dev-cluster にデプロイします。

```bash
gcloud deploy releases create \
    release-$(date +%Y%m%d%H%M%S) \
    --delivery-pipeline=pfe-cicd \
    --region=asia-northeast1 \
    --project=$PROJECT_ID \
    --images=pets=asia-northeast1-docker.pkg.dev/$PROJECT_ID/app-repo/pets:v1
```

デプロイ中の様子を見るため、GUI で確認していきます。
数分の経過後、[Cloud Deploy コンソール](https://console.cloud.google.com/deploy)に最初のリリースの詳細が表示され、それが最初のクラスタに正常にデプロイされたことが確認できます。

[Kubernetes Engine コンソール](https://console.cloud.google.com/kubernetes)に移動して、アプリケーションのエンドポイントを探します。
左側のメニューバーより Gateway、Service、Ingress を選択し`サービス`タブに遷移します。表示される一覧から `pets-service` という名前のサービスを見つけます。
Endpoints 列に IP アドレスが表示され、リンクとなっているため、それをクリックして、IPアドレスの最後に`/random-pets`をつけて移動します。
アプリケーションが期待どおりに動作していることを確認します。

ステージングでテストしたので、本番環境に昇格する準備が整いました。
[Cloud Deploy コンソール](https://console.cloud.google.com/deploy)に戻ります。
デリバリーパイプラインの一覧から、`pfe-cicd` をクリックします。
すると、`プロモート` という青いリンクが表示されています。リンクをクリックし、内容を確認した上で、下部の`プロモート`ボタンをクリックします。すると本番環境へのデプロイを実施されます。

数分後にデプロイが完了されましたら、この手順は完了となります。

## **Lab-01-03 Cloud Build から Cloud Deploy の実行**
ここまでで、CI と CD を別々に行うことができました。
次の手順としては、アプリケーションを更新し、ビルドを実行します。
ビルドの最後の手順として、Cloud Deploy を実行するように設定しておき、一気通貫で CI と CD が実行されるようにします。

まずはアプリケーションを更新します。今回は簡単にするために事前に用意した app.txt を app.py に置き換えることで更新を完了します。

```bash
mv lab-01/app.py lab-01/app.bak
```

```bash
mv lab-01/app.txt lab-01/app.py
```

必要に応じて更新後のソースコードをご確認ください。

続いて、`lab-01/cloudbuild.yaml` についても変更を加え、ビルドステップの最後に、Cloud Deploy を実行するように編集する必要があります。
ただし、今回は先ほどと同様に `lab-01/cloudbuild-2.yaml`というファイルで更新ずみのものを用意しておりますので、こちらを利用します。

```bash
cat lab-01/cloudbuild-2.yaml
```
確認するとステップが追加されていることがわかります。
同様に Cloud Deploy 側にも変更を加えています。今回は、プロモートのボタンを押さずに一気に prod-cluster にデプロイするため、
デプロイの自動化機能を有効化しています。

```bash
cat lab-01/clouddeploy-2.yaml
```

先ほど同様に`PROJECT_ID`および`PROJECT_NUMBER`がプレースホルダーになっていますので、各自の環境に合わせて置換します。

```bash
sed -i "s|\${PROJECT_ID}|$PROJECT_ID|g" lab-01/clouddeploy-2.yaml
sed -i "s/serviceAccount: ${PROJECT_NUMBER}-compute@developer.gserviceaccount.com/serviceAccount: ${PROJECT_ID}-compute@developer.gserviceaccount.com/g" lab-01/clouddeploy-2.yaml
```

```bash
gcloud deploy apply --file lab-01/clouddeploy.yaml --region=asia-northeast1 --project=$PROJECT_ID
```

Cloud Build から Cloud Deploy を利用するにあたっていくつか権限が必要になるため、サービスアカウントに付与します。

```bash
PROJECT_NUMBER=$(gcloud projects describe $PROJECT_ID --format="value(projectNumber)")
CLOUD_BUILD_SA="${PROJECT_NUMBER}@cloudbuild.gserviceaccount.com"
COMPUTE_SA="${PROJECT_NUMBER}-compute@developer.gserviceaccount.com"
```

```bash
gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:${PROJECT_NUMBER}@cloudbuild.gserviceaccount.com" \
    --role="roles/clouddeploy.admin"
```

```bash
gcloud iam service-accounts add-iam-policy-binding $COMPUTE_SA \
    --member="serviceAccount:${CLOUD_BUILD_SA}" \
    --role="roles/iam.serviceAccountUser" \
    --project=$PROJECT_ID
```
それでは実行します。

```bash
gcloud builds submit --config lab-01/cloudbuild-2.yaml .
```
もし、エラーが出てしまいましたら、`app.py`の最終行にある空白行を削除もしくは、改行を行いもう一度、上のコマンドを試してください。
これは PEP8 による構文解析で、空行の有無を判定しているためです。
しばらくすると先ほどの CI のステップが順に行われた後、デリバリーパイプラインでデプロイが開始されるのが確認できます。

デプロイ中の様子を見るため、GUI で確認していきます。
数分の経過後、[Cloud Deploy コンソール](https://console.cloud.google.com/deploy)に今回のリリースの詳細が表示され、それが最初のクラスタに正常にデプロイされたことが確認できます。

[Kubernetes Engine コンソール](https://console.cloud.google.com/kubernetes)に移動して、アプリケーションのエンドポイントを探します。
左側のメニューバーより Gateway、Service、Ingress を選択し`サービス`タブに遷移します。表示される一覧から `pets-service` という名前のサービスを見つけます。
Endpoints 列に IP アドレスが表示され、リンクとなっているため、それをクリックして、IPアドレスの最後に`/random-pets`をつけて移動します。
再びアプリケーションが期待どおりに動作していることを確認します。今回は先ほどとは異なる出力となるのが確認できるようになっています。

ステージングでテストしたので、本番環境に昇格する準備が整いました。
[Cloud Deploy コンソール](https://console.cloud.google.com/deploy)に戻ります。
デリバリーパイプラインの一覧から、`pfe-cicd` をクリックします。
すると、`プロモート` という青いリンクが表示されています。リンクをクリックし、内容を確認した上で、下部の`プロモート`ボタンをクリックします。すると本番環境へのデプロイを実施されます。

数分後にデプロイが完了されましたら、この手順は完了となります。

こちらで Lab-01 は完了となります。




## **Configurations!**
おめでとうございます。実践編のハンズオンは完了となります。
次回の Google Cloud のハンズオンシリーズもご参加をお待ちしております。