<walkthrough-metadata>
  <meta name="title" content="PFE Basic" />
  <meta name="description" content="Hands-on Platform Engineering Basic" />
  <meta name="component_id" content="110" />
</walkthrough-metadata>

<walkthrough-disable-features toc></walkthrough-disable-features>

# Platform Engineering Handson 入門編

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
cd ~/gcp-getting-started-lab-jp/pfe-basic
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

### **割り当ての拡張**

本ラボではデフォルトでの割り当て(クオータ)が不足する可能性があります。そのため事前に不足が予想される項目を拡張を申請します。
[割り当てとシステム制限](https://console.cloud.google.com/iam-admin/quotas)に移動します。

中央のフィルタに、`Compute Engine API` と入力します。リストから、名前が`Persistent Disk SSD (GB)`、項目(ロケーションなど)が`region : asia-northeast1` となっているものを見つけます。
該当するものにチェックを入れて、上部の`割り当てを編集`をクリックします。

`新しい値`に 1000 を入力します。

リクエストの説明に、`Platform Engineering Hands-on で利用するため`と入力し、`次へ`をクリックします。

`リクエストを送信`をクリックします。

通常、数分後に承認され、登録しているアカウントのメールアドレスに結果が送信されています。
その後、5分程度経過すると、割り当てが拡張されます。


以上で事前準備は完了です。

## **Lab-01 GKE Enterprise によるマルチチームでの GKE の利用**
GKE Enterprise を有効化すると様々な高度な機能が GKE 上で利用できるようになります。
その中の一つとして、入門編では、チーム管理機能を利用します。
Platform Engineering における、Internal Developer Platform は複数のストリーンアラインドチーム(アプリ開発チーム)によって利用されることを想定しているため、このようなマルチテナントの機能を実装しておくと管理がしやすくなります。


### **Lab-01-01.GKE Enterprise の有効化**

Platform Engeering に役立つマルチチームの機能を持つ、GKE Enterprise を有効化します。

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

### **Lab-01-07. ダッシュボードの確認**

再び、GUI(ブラウザ上のコンソール)で作業します。ブラウザ上の別のタブを開き（または同タブにURLを入力して）[チーム](https://console.cloud.google.com/kubernetes/teams)へ移動します。
チームのページより、チーム名 `app-a-team` がリンクになっているためクリックします。
画面上部の`モニタリング`タブより、チームに関する情報が確認できます。
どのような情報が確認できるかみてみましょう。
(エラーがカウントされますが、アプリケーションの仕様によるもので問題ございません)

また、時間に余裕がある場合、以下も確認してみましょう。
本日の説明範囲を超えますが、セキュリティに関するダッシュボードを確認することが可能です。
[セキュリティ](https://console.cloud.google.com/kubernetes/security/dashboard)


Lab-01はここで完了となります。


## **Lab-02. Cloud Workstations による Golden Path の提供**
Platform Engineering の観点から、開発者に作成ずみの開発環境とサンプルとなるアプリケーションのテンプレートを提供します。
また、Platform 利用者に立場に立って、アプリケーションのデプロイを試してみます。

### **Lab-02-01. Artifact Resistry 作成**
Cloud Workstations イメージを保管するためにレポジトリを作成します。

```bash
gcloud artifacts repositories create ws-repo \
  --repository-format docker \
  --location asia-northeast1 \
  --description="Docker repository for Cloud workstations"
```

ここで、Lab-03 で使うアプリケーション用の レポジトリも作成しておきます。

```bash
gcloud artifacts repositories create spring-app \
  --repository-format docker \
  --location asia-northeast1 \
  --description="Docker repository for spring-app"
```

### **Lab-02-02. Cloud Workstations コンテナイメージの作成**

開発者がサンプルコードを起動するためのライブラリや Code OSS 拡張機能を事前に有効化したイメージを作成します。
今回はあらかじめ用意したサンプルコードを利用します。中身は以下で確認できます。

```bash
cat lab-02/workstations/Dockerfile
```
Cloud Build を利用して、Cloud Workstations コンテナイメージをビルドします。
(赤字でメッセージが出ることがありますが、問題ございません。)

```bash
gcloud builds submit lab-02/workstations/ \
  --tag asia-northeast1-docker.pkg.dev/${PROJECT_ID}/ws-repo/codeoss-spring:v1.0.0
```

### **Lab-02-03. Cloud Workstations イメージ Pull 用のサービスアカウントの設定**

プライベートなカスタムイメージを利用するため、Artifact Resistry から Pull できる権限を持つサービスアカウントを作成しておきます。

```bash
gcloud iam service-accounts create codeoss-customized-sa \
  --display-name "Service Account for codeoss-customized config"
```
サービスアカウントに権限を付与しておきます。今回は、Artifact Resistry から Pull できる権限で十分なため、`artifactregistry.reader`を付与します。


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

Lab-02 は完了となります。

## **Lab-03. 開発者として Platform を利用する**

### **Lab-03-01. Workstations の起動**
GUI での作業となります。
ブラウザで新しいタブを開き、[Workstations一覧](https://console.cloud.google.com/workstations/list)を開きます。
**My workstations** に表示される `ws-spring-dev`の START(開始) をクリックします。
起動には数分程度かかります。
ステータスが、稼働中になりましたら、開始をクリックします。新しいタブで Code OSS の Welcome 画面が開きます。初回は表示に少し時間がかかります。

### **Lab-03-01. サンプルアプリケーションの入手**
git よりサンプルアプリケーションを取得します。
左側の2番目のアイコンをクリック、または、Ctr + Shift +E の入力で、EXPLORER が開きます。
Clone Repository を選択します。

上部に開いた URL バーに `https://github.com/ssekimoto/gs-spring-boot.git`と入力します。
入力後、`レポジトリの URL https://github.com/ssekimoto/gs-spring-boot.git`をクリックします。
(Github から複製を選択してしまうと、Github の認証が必要となりますのでキャンセルしてやり直してください)
複製するフォルダーを選択してください、はそのまま OK を教えてください。
続いて 複製したレポジトリを開きますか？または現在のワークスペースに追加しますか？という選択には、`開く`を選択してください。

### **Lab-03-01. サンプルアプリケーションの実行**
左上の３本の線のアイコンから、Terminal > New Terminal を選択します。
画面下にターミナルが現れますので、こちらで作業を実施します。

complete ディレクトリに移動します。

```bash
cd complete
```

アプリケーションをビルドします。

```bash
mvn clean install
```

ビルドしたアプリケーションをまずは Workstations 上で実行します。

```bash
java -jar target/spring-boot-complete-0.0.1-SNAPSHOT.jar
```

実行すると 右下に Open Preview という吹き出しが現れるので、クリックします。
続いて、Open をクリックするとシンプルなアプリケーションにアクセスできます。
完了したら、ターミナルに戻り、Ctrl-C でアプリケーションを停止しておきます。

### **Lab-03-02. GKE でのアプリケーションの実行**
引き続き Cloud Workstations で作業をします。
サンプルアプリケーションと一緒に、Dockerfile も Golden Path として git から提供されています。
以前の手順と同様に Cloud Build でコンテナの作成を行います。

Workstations 上のターミナルで実行します。ディレクトリを移動しておきます。

```bash
cd /home/user/gs-spring-boot/complete
```

Workstations 上では Google Cloud にログインに別途ログインする必要があります。

```bash
gcloud auth login
```

表示される URL を Ctr+クリックで Open、もしくはコピー&ペーストで別のタブで開きます。
すると Google アカウントへのログイン画面になるため、ログインを実施します。
最後に表示される `4/0` から始まる verification code をコピーして、Cloud Workstations の ターミナルに貼り付けます。
正常にログインが完了すると
`You are now loggeid in as [アカウント]`と表示されます。

また、Cloud Shell と同じように以下設定を行います。

```bash
export PROJECT_ID=[PROJECT_ID(自身のIDに置き換えます[]は不要です)]
```

```bash
gcloud config set project ${PROJECT_ID}
```

提供されている Dockerfile を利用して、コンテナ化を行います。

```bash
gcloud builds submit . --tag asia-northeast1-docker.pkg.dev/${PROJECT_ID}/spring-app/spring-app:v1.0.0
```

続いて GKE へのデプロイを行います。
左側のファイル一覧から ` complete/k8s.yaml` を開きます。
17行目の `asia-northeast1-docker.pkg.dev/${PROJECT_ID}/spring-app/spring-app:v1.0.0` の`${PROJECT_ID}`を実際のプロジェクトID に置き換えます。(Cloud Workstations は編集すると即時反映となるため、保存は不要です。）

GKE への接続を行います

```bash
gcloud container clusters get-credentials dev-cluster --region asia-northeast1 --project ${PROJECT_ID}
```

GKE のデプロイを実施します。

```bash
kubectl apply -f k8s.yaml 
```

数分後以下でデプロイ後の確認を行います。

```bash
kubectl get all 
```

期待通り Running になっていれば、開発者として、 GKE への初期デプロイを完了することができました。

## **Configurations!**
これで、入門編のハンズオンは完了となります。引き続き実践編、セキュリティガードレール編もお楽しみ下さい。

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