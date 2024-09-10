<walkthrough-metadata>
  <meta name="title" content="PFE Basic" />
  <meta name="description" content="Hands-on Platform Engineering Basic 2024-09" />
  <meta name="component_id" content="110" />
</walkthrough-metadata>

<walkthrough-disable-features toc></walkthrough-disable-features>

# 入門編: Google Cloud で始める Platform Engineering

## Google Cloud プロジェクトの設定、確認

### **1. 対象の Google Cloud プロジェクトを設定**

ハンズオンを行う Google Cloud プロジェクトのプロジェクト ID を環境変数に設定し、以降の手順で利用できるようにします。 **(右辺の [PROJECT_ID] を手動で置き換えてコマンドを実行します)**

```bash
export PROJECT_ID=[PROJECT_ID]
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
gcloud config set project ${PROJECT_ID}
```
承認するかどうかを聞かれるメッセージがでた場合は、`承認` ボタンをクリックします。

### **3. ハンズオンで利用する Google Cloud の API を有効化する**

Google Cloud では利用したい機能ごとに、有効化を行う必要があります。
ここでは、以降のハンズオンで利用する機能を事前に有効化しておきます。（4,5分ほどかかります）
〜finished successfully というメッセージが出たら正常に終了しています。

```bash
gcloud services enable cloudbuild.googleapis.com container.googleapis.com artifactregistry.googleapis.com clouddeploy.googleapis.com workstations.googleapis.com
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
cd ~/gcp-getting-started-lab-jp/pfe-basic-sep
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
  --no-enable-master-authorized-networks --async
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
  --no-enable-master-authorized-networks --async
```
### **Lab-00-06. WS クラスタ の作成**

後半の Lab02 で使う Cloud Workstations 用のクラスタを用意しておきます。
この作業は同一のリージョンで一度だけ必要で、作成完了まで 25 分程度かかります。

```bash
gcloud workstations clusters create cluster-handson \
  --network "projects/$PROJECT_ID/global/networks/ws-network" \
  --subnetwork "projects/$PROJECT_ID/regions/asia-northeast1/subnetworks/ws-subnet" \
  --region asia-northeast1 \
  --async
```

以上で事前準備は完了です。

## **Lab-01 GKE Enterprise によるマルチチームでの GKE の利用**
GKE Enterprise を有効化すると様々な高度な機能が GKE 上で利用できるようになります。
その中の一つとして、入門編では、チーム管理機能を利用します。
Platform Engineering における、Internal Developer Platform は複数のストリームアラインドチーム(アプリ開発チーム)によって利用されることを想定しているため、このようなマルチテナントの機能を実装しておくと管理がしやすくなります。


### **Lab-01-01.GKE Enterprise の有効化**

Platform Engineering に役立つマルチチームの機能を持つ、GKE Enterprise を有効化します。

```bash
gcloud services enable --project "$PROJECT_ID" \
   anthos.googleapis.com \
   gkehub.googleapis.com
```

### **Lab-01-02.GKE Enterprise チーム機能の有効化**

まず、チーム機能に必要なフリートを作成します。フリートは船団という意味で、GKE クラスタの論理的なグループです。

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


### **Lab-01-03.GKE Enterprise チームスコープの作成**

フリートの中にチームスコープを作成します。チームスコープは複数クラスタにまたがる開発チームが利用する範囲とメンバーなどを定義するリソースです。
```bash
gcloud container fleet scopes create app-a-team
```

### **Lab-01-04. チームスコープへのクラスタの登録**

ここからは GUI で操作します。
ブラウザ上の別のタブを開き（または同タブにURLを入力して）[チーム](https://console.cloud.google.com/kubernetes/teams)へ移動します。
チームのページより、チーム名 `app-a-team` がリンクになっているためクリックします。
続いて、ページ上部の` + クラスタを追加` をクリックします。
`すべて選択` にチェックを入れ `OK` を押します。
`チームスコープを更新`をクリックします。

### **Lab-01-05. 名前空間の追加**

チーム機能では、複数クラスタにまたがる名前空間を作成することが可能です。
ページ上部の` + 名前空間を追加` をクリックします。

Namespace の下に 'ec-site' を入力して、`チームスコープを更新`をクリックします。

### **Lab-01-06. チームスコープ内の名前空間へのアプリケーションのデプロイ**

クラスタの作成が完了しましたら、サンプルアプリケーションをデプロイします。 [Online Boutique microservices demo](https://github.com/GoogleCloudPlatform/microservices-demo)アプリケーションは、EC サイトをモチーフにしたマイクロサービスアプリケーションとなっています。kuberenetes のマニフェストについては、`lab-01/sampleapp.yaml` をご確認ください。

再び、Cloud Shell での作業となります。
以下のコマンドでdev-cluster に対して接続します。

```bash
gcloud container clusters get-credentials dev-cluster --region asia-northeast1 --project "$PROJECT_ID"
```

以下のコマンドで名前空間を確認します。チームスコープで作成した`ec-site`名前空間が作成されていることを確認します。

```bash
kubectl get ns
```

`ec-site`名前空間にサンプルアプリケーションをデプロイします。

```bash
kubectl apply -f lab-01/sampleapp.yaml -n ec-site
```

以下のコマンドで、現在の Pod および Node のステータスを取得を継続して行います。
Pod の作成に伴い、Node が複製され、Pod がデプロイされる様子が確認できます。
デプロイには3-5分程度の時間がかかります。

```bash
watch -d kubectl get pods,nodes,svc -n  ec-site
```

数分後、すべての Pod の Status が Running となることを確認できたら、 `Ctrl-C` でコマンドの実行を終了します。

### **Lab-01-06. Demo サイトの確認**
ロードバランサーの設定が完了するまで数分かかります。数分後、以下のコマンドでアプリケーションの URL を確認します。
確認した URL をコピーして Chrome などの Web ブラウザのアドレスバーに貼り付けアプリケーションを確認します。
なお、設定が完了するまでの数分間（場合によってはそれ以上）は、Connection reset by peer のエラーが出力されます。
その場合は、さらにしばらくお待ちください。

```bash
kubectl get svc -n ec-site | grep LoadBalancer | awk '{print "http://"$4}'
```

### **Lab-01-07. Fleet Logging の設定**
チームスコープ単位でログを有効化します。この機能により、開発チームごとにログバケットを用意し、各チームに関連するログのみを表示できます。
以下コマンドを実行し、Fleet Logging の構成ファイルを生成します。  
**こちらはコピー&ペーストで実行ください**

```text
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

生成した構成ファイルを指定して、Fleet Logging を有効化します。  
```bash
gcloud container fleet fleetobservability update \
        --logging-config=fleet-logging.json
```

以下コマンドを実行し、Fleet Logging が構成されていることを確認します。
```bash
gcloud container fleet fleetobservability describe
```

出力例のように、 spec.fleetobservability 配下に設定内容が入力されていることを確認します。  
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

### **Lab-01-08. Advanced Vulnerability Insights の有効化**

GKE Enterprise の一つの機能である高度な脆弱性検査を有効にします。
クラスタ運用者は、Secutiry Posture ダッシュボードで複数のクラスタ常に存在するコンテナに対しての脆弱性を俯瞰的にみることができ、
対策を講じることが可能です。

```bash
gcloud container clusters update dev-cluster \
    --location=asia-northeast1 \
    --workload-vulnerability-scanning=enterprise --async
```
```bash
gcloud container clusters update prod-cluster \
    --location=asia-northeast1 \
    --workload-vulnerability-scanning=enterprise --async
```


### **Lab-01-09. チームスコープログの確認**

再度 GUI で操作します。
ブラウザ上の別のタブを開き（または同タブにURLを入力して）[チーム](https://console.cloud.google.com/kubernetes/teams)へ移動します。  表示されない場合は、ブラウザのリロードをお試しください。
チームのページより、チーム名 `app-a-team` がリンクになっているためクリックします。  
`ログ`タブを選択し、先ほどデプロイしたアプリケーションからログが出力されていることを確認します。  
**有効から 2,30 分程度、場合によってはそれ以上の時間がかかる場合があるため、先に後続の手順を進め、後ほど確認してみてください**
これで、チームスコープ単位でのログが確認できました。

また、[ログストレージ](https://console.cloud.google.com/logs/storage)に移動して、チームごとにバケットが作られているのを確認します。


### **Lab-01-10. ダッシュボードの確認**

画面上部の`モニタリング`タブより、チームに関する情報が確認できます。
どのような情報が確認できるかみてみましょう。
(エラーがカウントされますが、アプリケーションの仕様によるもので問題ございません)

### **Lab-01-11. セキュリティダッシュボードの確認**

また、時間に余裕がある場合、以下も確認してみましょう。
先ほど有効化した脆弱性の結果を含むセキュリティに関するダッシュボードを確認することが可能です。
表示されない場合は、ブラウザのリロードをお試しください。
[セキュリティ](https://console.cloud.google.com/kubernetes/security/dashboard)
**最大でAdvanced Vulnerability Insights の有効化から 15 分程度かかる場合があります。見れない場合は先に後続の手順を進め、後ほど確認してみてください**

Lab-01はここで完了となります。

## **Lab-02. Cloud Workstations による Golden Path の提供**
Platform Engineering の観点から、開発者に作成ずみの開発環境とサンプルとなるアプリケーションのテンプレートを提供します。
また、Platform 利用者に立場に立って、アプリケーションのデプロイを試してみます。

### **Lab-02-01. Artifact Registry 作成**
Cloud Workstations イメージを保管するためにレポジトリを作成します。

```bash
gcloud artifacts repositories create ws-repo \
  --repository-format docker \
  --location asia-northeast1 \
  --description="Docker repository for Cloud workstations"
```

### **Lab-02-02. Cloud Workstations コンテナイメージの作成**

開発者がサンプルコードを起動するためのライブラリや Code OSS 拡張機能を事前に有効化したイメージを作成します。
今回はあらかじめ用意したサンプルコードを利用します。中身は以下で確認できます。

```bash
cat lab-02/workstations/Dockerfile
```
Cloud Build のサービスアカウントへ権限を付与します。

```bash
PROJECT_NUMBER=$(gcloud projects describe $PROJECT_ID --format="value(projectNumber)")
gcloud projects add-iam-policy-binding ${PROJECT_ID} \
  --member=serviceAccount:${PROJECT_NUMBER=}-compute@developer.gserviceaccount.com \
  --condition=None \
  --role=roles/cloudbuild.builds.builder
gcloud projects add-iam-policy-binding ${PROJECT_ID} \
  --member=serviceAccount:${PROJECT_NUMBER=}-compute@developer.gserviceaccount.com \
  --condition=None \
  --role=roles/logging.logWriter
gcloud projects add-iam-policy-binding ${PROJECT_ID} \
  --member=serviceAccount:${PROJECT_NUMBER=}-compute@developer.gserviceaccount.com \
  --condition=None \
  --role=roles/iam.serviceAccountUser
gcloud projects add-iam-policy-binding ${PROJECT_ID} \
  --member=serviceAccount:${PROJECT_NUMBER=}-compute@developer.gserviceaccount.com \
  --condition=None \
  --role=roles/storage.objectUser
```

Cloud Build を利用して、Cloud Workstations コンテナイメージをビルドします。
(赤字でメッセージが出ることがありますが、問題ございません。)

```bash
gcloud builds submit \
lab-02/workstations/  --tag asia-northeast1-docker.pkg.dev/${PROJECT_ID}/ws-repo/codeoss-spring:v1.0.0
```

### **Lab-02-03. Cloud Workstations イメージ Pull 用のサービスアカウントの設定**

プライベートなカスタムイメージを利用するため、Artifact Registry から Pull できる権限を持つサービスアカウントを作成しておきます。

```bash
gcloud iam service-accounts create codeoss-customized-sa \
  --display-name "Service Account for codeoss-customized config"
```
サービスアカウントに権限を付与しておきます。今回は、Artifact Registry から Pull できる権限で十分なため、`artifactregistry.reader`を付与します。


```bash
gcloud artifacts repositories add-iam-policy-binding ws-repo \
  --location asia-northeast1 \
  --member serviceAccount:codeoss-customized-sa@${PROJECT_ID}.iam.gserviceaccount.com \
  --role=roles/artifactregistry.reader
```

### **Lab-02-04. Cloud Workstations 構成の作成**

開発者むけにカスタマイズしたコンテナイメージを利用して Cloud Workstations の構成を作成します。

```bash
gcloud workstations configs create codeoss-spring \
  --machine-type e2-standard-4 \
  --pd-disk-size 200 \
  --pd-disk-type pd-standard \
  --region asia-northeast1 \
  --cluster cluster-handson \
  --disable-public-ip-addresses \
  --shielded-integrity-monitoring \
  --shielded-secure-boot \
  --shielded-vtpm \
  --service-account codeoss-customized-sa@${PROJECT_ID}.iam.gserviceaccount.com \
  --container-custom-image asia-northeast1-docker.pkg.dev/${PROJECT_ID}/ws-repo/codeoss-spring:v1.0.0
```

### **Lab-02-05. Workstations の作成**

開発者むけに一台、Workstations を作成します。この作業は、通常、開発者ごとに行うことになります。

```bash
gcloud workstations create ws-spring-dev \
  --region asia-northeast1 \
  --cluster cluster-handson \
  --config codeoss-spring
```
### **Lab-02-06. CI/CD パイプラインの準備**

Platform Engineering の要素の一つとして、デプロイの自動化があります。
プラットフォームの管理者として開発者が簡単にデプロイできるように Cloud Build/Cloud Deploy を使ってパイプラインを構築しておきます。
今回はハンズオンのために準備したファイルを活用してパイプラインを準備します。
各ファイルの中身を確認しておきます。Cloud Build のファイルについては、実際は開発者が Workstation で使うため、ここでは確認のみです。同じファイルが開発者側のレポジトリにも保存されています。

```bash
cat lab-02/cloudbuild.yaml
```

```bash
cat lab-02/clouddeploy.yaml
```

このファイルは`PROJECT_ID`がプレースホルダーになっていますので、各自の環境に合わせて置換します。

```bash
sed -i "s|\${PROJECT_ID}|$PROJECT_ID|g" lab-02/clouddeploy.yaml
```

正しく反映されているか確認します。
```bash
cat lab-02/clouddeploy.yaml
```

まずは、パイプラインとターゲットを Cloud Deploy に登録します。これによりアプリケーションをデプロイするための
Cluster および、dev / prod という順序性が定義されます。

```bash
gcloud deploy apply --file lab-02/clouddeploy.yaml --region=asia-northeast1 --project=$PROJECT_ID
```

デプロイ方法は、`skaffold.yaml`に定義されています。ここには、デプロイに利用するマニフェスト、およびデプロイに対応する成果物が定義されています。

```bash
cat lab-02/skaffold.yaml
```

Artifact Registry に CI で作成する成果物であるコンテナイメージを保管するためのレポジトリを作成しておきます。

```bash
gcloud artifacts repositories create app-repo \
  --repository-format docker \
  --location asia-northeast1 \
  --description="Docker repository for Platform users"
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

以上で、プラットフォーム管理者としての作業は終わりました。
続いて実際にプラットフォームを利用する開発者としての体験をしてみます。

### **Lab-02-07. Workstations の起動**
開発者はまず、自分の Workstations を起動することになります。
GUI での作業となります。
ブラウザで新しいタブを開き、[Workstations一覧](https://console.cloud.google.com/workstations/list)を開きます。
**My workstations** に表示される `ws-spring-dev`の 起動 をクリックします。
起動には数分程度かかります。
ステータスが、稼働中になりましたら、開始をクリックします。新しいタブで Code OSS の Welcome 画面が開きます。初回は表示に少し時間がかかります。

### **Lab-02-08. サンプルアプリケーションの入手**
git よりサンプルアプリケーションを取得します。
左側の2番目のアイコンをクリック、または、Ctrl + Shift + E の入力で、EXPLORER が開きます。
Clone Repository を選択します。

上部に開いた URL バーに `https://github.com/ssekimoto/gs-spring-boot.git`と入力します。
入力後、`レポジトリの URL https://github.com/ssekimoto/gs-spring-boot.git`をクリックします。
(Github から複製を選択してしまうと、Github の認証が必要となりますのでキャンセルしてやり直してください)
複製するフォルダーを選択してください、はそのまま OK をクリックしてください。
続いて 複製したレポジトリを開きますか？または現在のワークスペースに追加しますか？という選択には、`開く(Open)`を選択してください。

### **Lab-02-09. サンプルアプリケーションの実行**
まずは、手元のローカル（Cloud Workstations 自体の中）でアプリケーションをテスト実行してみます。
左上の３本の線のアイコンから、Terminal > New Terminal を選択します。
画面下にターミナルが現れますので、こちらで作業を実施します。

complete ディレクトリに移動します。

```bash
cd complete
```

アプリケーションをビルドします。

```bash
mvn clean install -DskipTests
```

ビルドしたアプリケーションをまずは Workstations 上で実行します。

```bash
java -jar target/spring-boot-complete-0.0.1-SNAPSHOT.jar
```

実行すると 右下に Open Preview という吹き出しが現れるので、クリックします。
続いて、Open をクリックするとシンプルなアプリケーションにアクセスできます。
完了したら、ターミナルに戻り、Ctrl-C でアプリケーションを停止しておきます。

### **Lab-02-10. GKE でのアプリケーションの実行**
引き続き Cloud Workstations で作業をします。
サンプルアプリケーションと一緒に、Dockerfile と先ほどの CI/CD パイプライン用のファイル も Golden Path として git から提供されています。
ここでは、プラットフォーム管理者が作成したパイプラインを利用して、アプリケーションのコンテナ化から、GKE へのデプロイまでを自動化する体験をします。
Workstations 上のターミナルで実行します。もしディレクトリを移動している場合、`complete` へ移動しておきます。

```bash
cd /home/user/gs-spring-boot/complete
```

Workstations 上では Google Cloud にログインに別途ログインする必要があります。

```bash
gcloud auth login
```

表示される URL を Ctrl + クリックで Open、もしくはコピー&ペーストで別のタブで開きます。
すると Google アカウントへのログイン画面になるため、ログインを実施します。
ログインするアカウントは lab 向けに払い出されている student- から始まるものであることに注意してください。
最後に表示される `4/0` から始まる verification code をコピーして、Cloud Workstations の ターミナルに貼り付けます。
正常にログインが完了すると
`You are now logged in as [アカウント]`と表示されます。

また、Cloud Shell と同じように以下設定を行います。

```bash
export PROJECT_ID=[PROJECT_ID(自身のIDに置き換えます[]は不要です)]
```

```bash
gcloud config set project ${PROJECT_ID}
```

CI/CD パイプラインを利用して、コンテナのビルドおよび GKE の dev-cluster へのデプロイを実施します。

```bash
gcloud builds submit --config cloudbuild.yaml .
```

### **Lab-02-11. Cloud Deploy での実行確認と本番環境へのプロモート**

デプロイ中の様子を見るため、GUI で確認していきます。
数分の経過後、[Cloud Deploy コンソール](https://console.cloud.google.com/deploy)に最初のリリースの詳細が表示され、それが最初のクラスタに正常にデプロイされたことが確認できます。

[Kubernetes Engine コンソール](https://console.cloud.google.com/kubernetes)に移動して、アプリケーションのエンドポイントを探します。
左側のメニューバーより Gateway、Service、Ingress を選択し`サービス`タブに遷移します。表示される一覧から `spring-app-service` という名前のサービスを見つけます。
Endpoints 列に IP アドレスが表示され、リンクとなっているため、それをクリックして移動します。
アプリケーションが期待どおりに動作していることを確認します。

ステージングでテストしたので、本番環境に昇格する準備が整いました。
[Cloud Deploy コンソール](https://console.cloud.google.com/deploy)に戻ります。
デリバリーパイプラインの一覧から、`pfe-pipeline` をクリックします。
すると、`プロモート` という青いリンクが表示されています。リンクをクリックし、内容を確認した上で、下部の`プロモート`ボタンをクリックします。すると本番環境へのデプロイを実施されます。

数分後にデプロイが完了されましたら、この手順は完了となります。

## **Lab-03. Platform 管理者のためのオブザーバビリティ**

## **Configurations!**
これで、入門編のハンズオンは完了となります。引き続き実践編もお楽しみ下さい。