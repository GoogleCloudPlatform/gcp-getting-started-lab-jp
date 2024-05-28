<walkthrough-metadata>
  <meta name="title" content="PFE Jissen" />
  <meta name="description" content="Hands-on Platform Engineering Jissen" />
  <meta name="component_id" content="110" />
</walkthrough-metadata>

<walkthrough-disable-features toc></walkthrough-disable-features>

# Platform Engineering Handson 実践編

## Google Cloud プロジェクトの設定、確認

### **1. 対象の Google Cloud プロジェクトを設定**

ハンズオンを行う Google Cloud プロジェクトのプロジェクト ID を環境変数に設定し、以降の手順で利用できるようにします。 **(右辺の [PROJECT_ID] を手動で置き換えてコマンドを実行します)**

```bash
export PROJECT_ID=[PROJECT_ID]
```

`プロジェクト ID` は [ダッシュボード](https://console.cloud.google.com/home/dashboard) に進み、左上の **プロジェクト情報** から確認します。

### **2. プロジェクトの課金が有効化されていることを確認する**

```bash
gcloud beta billing projects describe ${PROJECT_ID} | grep billingEnabled
```

**Cloud Shell の承認** という確認メッセージが出た場合は **承認** をクリックします。

出力結果の `billingEnabled` が **true** になっていることを確認してください。**false** の場合は、こちらのプロジェクトではハンズオンが進められません。別途、課金を有効化したプロジェクトを用意し、本ページの #1 の手順からやり直してください。

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
gcloud services enable cloudbuild.googleapis.com container.googleapis.com artifactregistry.googleapis.com clouddeploy.googleapis.com
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
cd ~/gcp-getting-started-lab-jp/pfe-cicd
```

### **02. チュートリアルを開く**

```bash
teachme tutorial.md
```

### **03. プロジェクト ID を設定する**

```bash
export PROJECT_ID=[PROJECT_ID]
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

以下のコマンドを実行し、GKE Autopilot クラスタを作成します。

```bash
gcloud container --project "$PROJECT_ID" clusters create-auto "dev-cluster" \
  --region "asia-northeast1" \
  --release-channel "regular" \
  --network "ws-network" \
  --subnetwork "ws-subnet" \
  --enable-private-nodes \
  --no-enable-master-authorized-networks --async
```

クラスタの作成には10分〜20分程度の時間がかかります。
同様に Production 用のクラスタも作っておきます。

```bash
gcloud container --project "$PROJECT_ID" clusters create-auto "prod-cluster" \
  --region "asia-northeast1" \
  --release-channel "regular" \
  --network "ws-network" \
  --subnetwork "ws-subnet" \
  --enable-private-nodes \
  --no-enable-master-authorized-networks --async
```

事前準備はこちらで完了となります。

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
cat app.py
```

リクエストを受けると、ランダムに犬の品種を JSON 形式で返す API を提供しています。
また、ビルド中のステップとして、静的解析(PEP8)と簡単なユニットテストを実装しています。

```bash
cat cloudbuild.yaml
```

Cloud Build で実行します。今回は Git レポジトリを用意していないため、ローカルのソースコードから手動トリガーとして実行します。

```bash
gcloud builds submit --config cloudbuild.yaml .
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
 docker run -d -p 5000:5000 asia-northeast1-docker.pkg.dev/pfe-adv/app-repo/pets:v1
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
設定は以下の `clouddeploy.yaml` に記述されています。

```bash
cat clouddeploy.yaml
```

以下の3つのファイルは`PROJECT_ID`がプレースホルダーになっていますので、各自の環境に合わせて置換します。

```bash
sed -i "s|\${PROJECT_ID}|$PROJECT_ID|g" kubernetes-manifests/deployment.yaml
```

```bash
sed -i "s|\${PROJECT_ID}|$PROJECT_ID|g" skaffold.yaml
```

```bash
sed -i "s|\${PROJECT_ID}|$PROJECT_ID|g" clouddeploy.yaml
```

まずは、パイプラインとターゲットを Cloud Deploy に登録します。これによりアプリケーションをデプロイするための
Cluster および、dev / prod という順序性が定義されます。

```bash
gcloud deploy apply --file clouddeploy.yaml --region=asia-northeast1 --project=$PROJECT_ID
```

続いて、リリースを作成して、実際のデプロイを実行します。
デプロイ方法は、`skaffold.yaml`に定義されています。ここには、デプロイするのに利用するマニフェスト、およびデプロイに対応する成果物が定義されています。

```bash
cat skaffold.yaml
```

```bash
gcloud deploy releases create release-$(date +%Y%m%d%H%M%S) --delivery-pipeline=pfe-cicd --region=asia-northeast1 --source=kubernetes-manifests/ --project=$PROJECT_ID
```

## **Lab-02 GKE Enterprise による チームスコープでの Logging**
GKE Enterprise を有効化すると様々な高度な機能が GKE 上で利用できるようになります。
その一つとしてチーム単位での Logging を本ハンズオンでの対象とします。

### **Lab-02-01.GKE Enterprise の有効化**

```bash
gcloud services enable --project "$PROJECT_ID" \
   anthos.googleapis.com \
   gkehub.googleapis.com \ 
   connectgateway.googleapis.com
```

### **Lab-02-02.GKE Enterprise チーム機能の有効化**

フリートを作成します。フリートは船団という意味で、GKE クラスタの論理的なグループです。

```bash
  gcloud container fleet create \
    --project "$PROJECT_ID"
```

作成したフリートに dev-cluster を登録しておきます。

```bash
gcloud container clusters update dev-cluster --enable-fleet --location asia-northeast1
```

同様に Prod Cluster も登録します。

```bash
gcloud container clusters update prod-cluster --enable-fleet --location asia-northeast1
```
### **Lab-02-03.GKE Enterprise チームスコープの作成**

フリートの中にチームスコープを作成します。チームスコープは複数クラスタにまたがる開発チームが利用する範囲とメンバーなどを定義するリソースです。
```bash
gcloud container fleet scopes create app-a-team
```

### **Lab-02-04. チームスコープへのクラスタの登録**

ここからは GUI で操作します。
ブラウザ上の別のタブを開き（または同タブにURLを入力して）[チーム](https://console.cloud.google.com/kubernetes/teams)へ移動します。
チームのページより、チーム名 `app-a-team` がリンクになっているためクリックします。
続いて、ページ上部の` + クラスタを追加` をクリックします。
`すべて選択` にチェックを入れ `OK` を押します。
`チームスコープを更新`をクリックします。

### **Lab-02-05. 名前空間の追加**

チーム機能では、複数クラスタにまたがる名前空間を作成することが可能です。
ページ上部の` + 名前空間を追加` をクリックします。

Namespace の下に 'app-a-team-ns' を入力して、`チームスコープを更新`をクリックします。

### **Lab-02-06. チームスコープ内の名前空間へのアプリケーションのデプロイ**

再び、Cloud Shell での作業となります。
以下のコマンドでdev-cluster に対して接続します。

```bash
gcloud container clusters get-credentials dev-cluster --region asia-northeast1 --project "$PROJECT_ID"
```

以下のコマンドを実行し、サンプルアプリケーションをデプロイします。
```bash
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: fleet-example-pod
  namespace: app-a-team-ns
spec:
  containers:
  - name: count
    image: ubuntu:14.04
    args: [bash, -c,
        'for ((i = 0; ; i++)); do echo "$i: $(date)"; sleep 1; done']
EOF
```
### **Lab-01-03 Cloud Deploy による CD**


### **Lab-02-07. Fleet Logging の設定**
以下コマンドを実行し、Fleet Logging の構成ファイルを生成します。  

```bash
cat << EOF > fleet-logging.json
{
  "loggingConfig": {
      "defaultConfig": {
          "mode": "COPY"
      },
      "fleetScopeLogsConfig": {
          "mode": "MOVE"
      }
  }
}
EOF
```

生成した構成ファイルを指定し、Fleet Logging を有効化します。  
```bash
gcloud container fleet fleetobservability update \
        --logging-config=fleet-logging.json
```

以下コマンドを実行し、Fleet Logging が構成されていることを確認します。
```bash
gcloud container fleet fleetobservability describe
```

以下のように出力例 spec.fleetobservability 配下に設定内容が入力されていることを確認します。  
```text
createTime: '2022-09-30T16:05:02.222568564Z'
membershipStates:
  projects/123456/locations/us-central1/memberships/cluster-1:
    state:
      code: OK
      description: Fleet monitoring enabled.
      updateTime: '2023-04-03T20:22:51.436047872Z'
name:
projects/123456/locations/global/features/fleetobservability
resourceState:
  state: ACTIVE
spec:
  fleetobservability:
    loggingConfig:
      defaultConfig:
        mode: COPY
      fleetScopeLogsConfig:
        mode: MOVE
```

### **Lab-02-08. チームスコープログの確認**

ここからは GUI で操作します。
ブラウザ上の別のタブを開き（または同タブにURLを入力して）[チーム](https://console.cloud.google.com/kubernetes/teams)へ移動します。  
チームのページより、チーム名 `app-a-team` がリンクになっているためクリックします。  
`ログ`タブを選択し、先ほどデプロイしたアプリケーションから以下のような形式でログが出力されていることを確認します。  
```text
27834: Tue May 28 07:52:37 UTC 2024
27835: Tue May 28 07:52:38 UTC 2024
27836: Tue May 28 07:52:39 UTC 2024
27837: Tue May 28 07:52:40 UTC 2024
27838: Tue May 28 07:52:41 UTC 2024
27839: Tue May 28 07:52:42 UTC 2024
27840: Tue May 28 07:52:43 UTC 2024
27841: Tue May 28 07:52:44 UTC 2024
27842: Tue May 28 07:52:45 UTC 2024
27843: Tue May 28 07:52:46 UTC 2024
```

### **Lab-02-09. チームスコープメトリクスの確認**
チーム管理画面の`モニタリング`タブを選択し、チームスコープ単位でメトリクス情報が閲覧可能であることを確認します。

Lab-02 はこちらで完了になります。


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



## **Configurations!**
これで、実践編のハンズオンは完了となります。引き続き、セキュリティガードレール編もお楽しみ下さい。

## **クリーンアップ（プロジェクトを削除）**

ハンズオン用に利用したプロジェクトを削除し、コストがかからないようにします。

### **1. Google Cloud のデフォルトプロジェクト設定の削除**

```bash
gcloud config unset project
```

### **2. プロジェクトの削除**

```bash
gcloud projects delete ${PROJECT_ID}
```

### **3. ハンズオン資材の削除**

```bash
cd $HOME && rm -rf gcp-getting-started-lab-jp gopath
```
