# はじめてみよう DevOps ハンズオン

## Google Cloud Platform（GCP）プロジェクトの選択

ハンズオンを行う GCP プロジェクトを選択し、 **Start** をクリックしてください。

<walkthrough-project-setup>
</walkthrough-project-setup>


## ハンズオンの内容

下記の内容をハンズオン形式で学習します。

- 環境準備：10 分
  - gcloud コマンドラインツール設定
  - GCP 機能（API）有効化設定
  - サービスアカウント設定

- [Kubernetes Engine（GKE）](https://cloud.google.com/kubernetes-engine/) を用いたアプリケーション開発：40 分
  - サンプルアプリケーションのコンテナ化
  - コンテナの[Google Container Registry](https://cloud.google.com/container-registry/) への登録
  - GKE クラスターの作成
  - コンテナの GKE へのデプロイ、外部公開
  - チャレンジ問題：もう一つの外部からのアクセス経路

- [Operations](https://cloud.google.com/products/operations) を用いたアプリケーションの運用：10 分
  - [Cloud Logging](https://cloud.google.com/logging/) によるログ管理
  - [Cloud Trace](https://cloud.google.com/trace/) による分散トレーシング
  - [Cloud Profiler](https://cloud.google.com/profiler/) によるプロファイリング
  - チャレンジ問題：特定のログの確認

- [Cloud Build](https://cloud.google.com/cloud-build/) によるビルド、デプロイの自動化：30 分
  - [Cloud Source Repositories](https://cloud.google.com/source-repositories/) へのリポジトリの作成
  - [Cloud Build トリガー](https://cloud.google.com/cloud-build/docs/running-builds/automate-builds) の作成
  - Git クライアントの設定
  - ソースコードの Push をトリガーにした、アプリケーションのビルド、GKE へのデプロイ
  - チャレンジ問題：処理に時間がかかっているページの改善

- クリーンアップ：10 分
  - プロジェクトごと削除
  - （オプション）個別リソースの削除


## 環境準備

<walkthrough-tutorial-duration duration=10></walkthrough-tutorial-duration>

最初に、ハンズオンを進めるための環境準備を行います。

下記の設定を進めていきます。

- gcloud コマンドラインツール設定
- GCP 機能（API）有効化設定
- サービスアカウント設定


## gcloud コマンドラインツール

GCP は、CLI、GUI から操作が可能です。ハンズオンでは主に CLI を使い作業を行いますが、GUI で確認する URL も合わせて掲載します。


### gcloud コマンドラインツールとは?

gcloud コマンドライン インターフェースは、GCP でメインとなる CLI ツールです。このツールを使用すると、コマンドラインから、またはスクリプトや他の自動化により、多くの一般的なプラットフォーム タスクを実行できます。

たとえば、gcloud CLI を使用して、以下のようなものを作成、管理できます。

- Google Compute Engine 仮想マシン
- Google Kubernetes Engine クラスタ
- Google Cloud SQL インスタンス

**ヒント**: gcloud コマンドラインツールについての詳細は[こちら](https://cloud.google.com/sdk/gcloud?hl=ja)をご参照ください。

<walkthrough-footnote>次に gcloud CLI をハンズオンで利用するための設定を行います。</walkthrough-footnote>


## gcloud コマンドラインツール設定 - プロジェクト

gcloud コマンドでは操作の対象とするプロジェクトの設定が必要です。

### GCP のプロジェクト ID を環境変数に設定

環境変数 `GOOGLE_CLOUD_PROJECT` に GCP プロジェクト ID を設定します。

```bash
export GOOGLE_CLOUD_PROJECT="{{project-id}}"
```

### CLI（gcloud コマンド） から利用する GCP のデフォルトプロジェクトを設定

操作対象のプロジェクトを設定します。

```bash
gcloud config set project $GOOGLE_CLOUD_PROJECT
```


## gcloud コマンドラインツール設定 - リージョン、ゾーン

### デフォルトリージョンを設定

コンピュートリソースを作成するデフォルトのリージョンとして、日本リージョン（asia-northeast1）を指定します。

```bash
gcloud config set compute/region asia-northeast1
```

### デフォルトゾーンを設定

コンピュートリソースを作成するデフォルトのゾーンとして、日本リージョン内の 1 ゾーン（asia-northeast1-c）を指定します。

```bash
gcloud config set compute/zone asia-northeast1-c
```

<walkthrough-footnote>CLI（gcloud）を利用する準備が整いました。次にハンズオンで利用する機能を有効化します。</walkthrough-footnote>


## GCP 環境設定

GCP では利用したい機能ごとに、有効化を行う必要があります。
ここでは、以降のハンズオンで利用する機能を事前に有効化しておきます。

### ハンズオンで利用する GCP の API を有効化する

```bash
gcloud services enable cloudbuild.googleapis.com sourcerepo.googleapis.com containerregistry.googleapis.com cloudresourcemanager.googleapis.com container.googleapis.com stackdriver.googleapis.com cloudtrace.googleapis.com cloudprofiler.googleapis.com logging.googleapis.com
```

**GUI**: [APIライブラリ](https://console.cloud.google.com/apis/library?project={{project-id}})

<walkthrough-footnote>必要な機能が使えるようになりました。次にサービスアカウントの設定を行います。</walkthrough-footnote>


## サービスアカウントの作成、権限設定

アプリケーションから他の GCP サービスを利用する場合、個々のエンドユーザーではなく、専用の Google アカウント（サービスアカウント）を作ることを強く推奨しています。

### ハンズオン向けのサービスアカウントを作成する

`dohandson` という名前で、ハンズオン専用のサービスアカウントを作成します。

```bash
gcloud iam service-accounts create dohandson --display-name "DevOps HandsOn Service Account"
```

**ヒント**: サービスアカウントについての詳細は[こちら](https://cloud.google.com/iam/docs/service-accounts)をご参照ください。

### サービスアカウントで利用する鍵を作成し、ダウンロードする

```bash
gcloud iam service-accounts keys create auth.json --iam-account=dohandson@$GOOGLE_CLOUD_PROJECT.iam.gserviceaccount.com --key-file-type=json
```

**GUI**: [サービスアカウント](https://console.cloud.google.com/iam-admin/serviceaccounts?project={{project-id}})

## サービスアカウントに権限（IAM ロール）を割り当てる

作成したサービスアカウントには GCP リソースの操作権限がついていないため、ここで必要な権限を割り当てます。

下記の権限を割り当てます。

- Cloud Profiler Agent ロール
- Cloud Trace Agent ロール
- Cloud Monitoring Metric Writer ロール
- Cloud Monitoring Metadata Writer ロール
- Cloud Debugger Agent ロール

```bash
gcloud projects add-iam-policy-binding $GOOGLE_CLOUD_PROJECT  --member serviceAccount:dohandson@$GOOGLE_CLOUD_PROJECT.iam.gserviceaccount.com --role roles/cloudprofiler.agent
gcloud projects add-iam-policy-binding $GOOGLE_CLOUD_PROJECT  --member serviceAccount:dohandson@$GOOGLE_CLOUD_PROJECT.iam.gserviceaccount.com --role roles/cloudtrace.agent
gcloud projects add-iam-policy-binding $GOOGLE_CLOUD_PROJECT  --member serviceAccount:dohandson@$GOOGLE_CLOUD_PROJECT.iam.gserviceaccount.com --role roles/monitoring.metricWriter
gcloud projects add-iam-policy-binding $GOOGLE_CLOUD_PROJECT  --member serviceAccount:dohandson@$GOOGLE_CLOUD_PROJECT.iam.gserviceaccount.com --role roles/stackdriver.resourceMetadata.writer
gcloud projects add-iam-policy-binding $GOOGLE_CLOUD_PROJECT  --member serviceAccount:dohandson@$GOOGLE_CLOUD_PROJECT.iam.gserviceaccount.com --role roles/clouddebugger.agent
```

<walkthrough-footnote>アプリケーションから利用する、サービスアカウントの設定が完了しました。次に GKE を利用したアプリケーション開発に進みます。</walkthrough-footnote>

## Google Kubernetes Engine を用いたアプリケーション開発

<walkthrough-tutorial-duration duration=40></walkthrough-tutorial-duration>

コンテナ、Kubernetes を利用したアプリケーション開発を体験します。

下記の手順で進めていきます。

- サンプルアプリケーションのコンテナ化
- コンテナの[Google Container Registry](https://cloud.google.com/container-registry/) への登録
- GKE クラスターの作成、設定
- コンテナの GKE へのデプロイ、外部公開
- チャレンジ問題：もう一つの外部からのアクセス経路


## サンプルアプリケーションのコンテナ化

### コンテナを作成する

Go言語で作成されたサンプル Web アプリケーションをコンテナ化します。
ここで作成したコンテナはローカルディスクに保存されます。

```bash
docker build -t gcr.io/$GOOGLE_CLOUD_PROJECT/devops-handson:v1 .
```

**ヒント**: `docker build` コマンドを叩くと、Dockerfile が読み込まれ、そこに記載されている手順通りにコンテナが作成されます。

### Cloud Shell 上でコンテナを起動する

上の手順で作成したコンテナを Cloud Shell 上で起動します。

```bash
docker run -d -p 8080:8080 \
--name devops-handson \
-e GOOGLE_APPLICATION_CREDENTIALS=/tmp/keys/auth.json \
-v $PWD/auth.json:/tmp/keys/auth.json:ro \
gcr.io/$GOOGLE_CLOUD_PROJECT/devops-handson:v1
```

**ヒント**: Cloud Shell 環境の 8080 ポートを、コンテナの 8080 ポートに紐付け、バックグラウンドで起動します。

<walkthrough-footnote>アプリケーションをコンテナ化し、起動することができました。次に実際にアプリケーションにアクセスしてみます。</walkthrough-footnote>


## 作成したコンテナの動作確認

### CloudShell の機能を利用し、起動したアプリケーションにアクセスする

画面右上にあるアイコン <walkthrough-web-preview-icon></walkthrough-web-preview-icon> をクリックし、"プレビューのポート: 8080"を選択します。
これによりブラウザで新しいタブが開き、Cloud Shell 上で起動しているコンテナにアクセスできます。

正しくアプリケーションにアクセスできると、下記のような画面が表示されます。

![BrowserAccessToMainController](https://storage.googleapis.com/devops-handson-for-github/BrowserAccessToMainController.png)

<walkthrough-footnote>ローカル環境（Cloud Shell 内）で動いているコンテナにアクセスできました。次に GKE で動かすための準備を進めます。</walkthrough-footnote>


## コンテナのレジストリへの登録

先程作成したコンテナはローカルに保存されているため、他の場所から参照ができません。
他の場所から利用できるようにするために、GCP 上のプライベートなコンテナ置き場（コンテナレジストリ）に登録します。

### 作成したコンテナをコンテナレジストリ（Google Container Registry）へ登録（プッシュ）する

```bash
docker push gcr.io/$GOOGLE_CLOUD_PROJECT/devops-handson:v1
```

**GUI**: [コンテナレジストリ](https://console.cloud.google.com/gcr/images/{{project-id}}?project={{project-id}})

<walkthrough-footnote>次にコンテナを動かすための基盤である GKE の準備を進めます。</walkthrough-footnote>


## GKE クラスターの作成、設定

コンテナレジストリに登録したコンテナを動かすための、GKE 環境を準備します。

### GKE クラスターを作成する

```bash
gcloud beta container clusters create "k8s-devops-handson"  \
--image-type "COS" \
--scopes "https://www.googleapis.com/auth/cloud-platform" \
--enable-stackdriver-kubernetes \
--enable-ip-alias \
--network "projects/$GOOGLE_CLOUD_PROJECT/global/networks/default" \
--subnetwork "projects/$GOOGLE_CLOUD_PROJECT/regions/asia-northeast1/subnetworks/default"
```

**参考**: クラスターの作成が完了するまでに、最大 10 分程度時間がかかることがあります。

**GUI**: [クラスター](https://console.cloud.google.com/kubernetes/list?project={{project-id}})

<walkthrough-footnote>クラスターが作成できました。次にクラスターを操作するツールの設定を行います。</walkthrough-footnote>


## GKE クラスターの作成、設定

### GKE クラスターへのアクセス設定を行う

Kubernetes には専用の [CLI ツール（kubectl）](https://kubernetes.io/docs/reference/kubectl/overview/)が用意されています。

認証情報を取得し、作成したクラスターを操作できるようにします。

```bash
gcloud container clusters get-credentials k8s-devops-handson
```

<walkthrough-footnote>これで kubectl コマンドから作成したクラスターを操作できるようになりました。次に作成済みのコンテナをクラスターにデプロイします。</walkthrough-footnote>


## コンテナの GKE へのデプロイ、外部公開 - 準備

### Kubernetes クラスターに、ダウンロード済みのサービスアカウントの鍵情報を Secret として登録する

以前の手順で作成したサービスアカウントの鍵ファイルを Kubernetes に登録します。
コンテナはこれを利用し、各種 GCP のサービスにアクセスします。

```bash
kubectl create secret generic dohandson-key --from-file=key.json=auth.json
```

**ヒント**: Secret についての詳細は[こちら](https://cloud.google.com/kubernetes-engine/docs/concepts/secret)をご参照ください。

### ハンズオン用の設定ファイルを修正する

Kubernetes のデプロイ用設定ファイルを、コンテナレジストリに登録済みのコンテナを使うように修正します。

```bash
sed -i".org" -e "s/FIXME/$GOOGLE_CLOUD_PROJECT/g" gke-config/deployment.yaml
```

<walkthrough-footnote>アプリケーションをクラスターにデプロイする準備ができました。次にデプロイを行います。</walkthrough-footnote>

## コンテナの GKE へのデプロイ、外部公開

### コンテナを Kubernetes クラスターへデプロイする

```bash
kubectl apply -f gke-config/
```

このコマンドにより、Kubernetes の 3 リソースが作成され、インターネットからアクセスできるようになります。

- [Deployment](https://cloud.google.com/kubernetes-engine/docs/concepts/deployment)
- [Service](https://kubernetes.io/ja/docs/concepts/services-networking/service/)
- [Ingress](https://kubernetes.io/ja/docs/concepts/services-networking/ingress/)

**GUI**: [Deployment](https://console.cloud.google.com/kubernetes/workload?project={{project-id}}), [Service/Ingress](https://console.cloud.google.com/kubernetes/discovery?project={{project-id}})

<walkthrough-footnote>コンテナを GKE にデプロイし、外部公開できました。次にデプロイしたアプリケーションにアクセスします。</walkthrough-footnote>


## コンテナの GKE へのデプロイ、外部公開 - 動作確認

### アクセスするグローバル IP アドレスの取得

デプロイしたコンテナへのアクセスを待ち受ける Service の IP アドレスを確認します。

```bash
kubectl get service devops-handson-loadbalancer -w
```

このコマンドは対象のリソース状態を監視（watch）します。グローバル IP アドレスが付与されたら Ctrl + C を押してキャンセルしてください。

**ヒント**: デプロイしたコンテナ自体はグローバルからアクセス可能な IP アドレスを持ちません。今回のように、外部からのアクセスを受け付けるリソース（Service）を作成し、そこを通してコンテナにアクセスする必要があります。

### コンテナへアクセス

下記のコマンドを実行し出力された URL をクリックし、アクセスします。

```bash
export SERVICE_IP=$(kubectl get service devops-handson-loadbalancer -ojsonpath='{.status.loadBalancer.ingress[0].ip}'); echo "http://${SERVICE_IP}/"
```

<walkthrough-footnote>アプリケーションにインターネット経由でアクセスすることができました。次にアクセスに時間がかかるページの調査を行います。</walkthrough-footnote>


## アクセスに時間がかかるページの確認

下記のコマンドを実行し出力された URL をクリック、アクセスし、描画されるまで時間がかかることを確認します。
Google Chrome を利用している場合は、[Chrome DevTools](https://developers.google.com/web/tools/chrome-devtools?hl=ja) を起動しレスポンスが返ってくるまでの秒数を確認します。

```bash
echo "http://${SERVICE_IP}/bench1"
```

**ヒント**: 意図的に処理に時間がかかるようにアプリケーションを作成しています。

![BrowserAccessToSlowBenchController](https://storage.googleapis.com/devops-handson-for-github/BrowserAccessToSlowBenchController.png)

### 擬似的にアクセス負荷をかける

後のステップで確認する Cloud Profiler のサンプル数を稼ぐため、 `/bench1` に 50 回アクセスを行います。

```bash
COUNT=0; while [ $COUNT -lt 50 ]; do curl -s http://${SERVICE_IP}/bench1 > /dev/null; echo $COUNT; COUNT=$(( COUNT + 1 )); done
```

<walkthrough-footnote>特定のページへのアクセスに時間がかかることを確認し、そこに負荷をかけました。次になぜこのページが重いのかをトラブルシューティングします。</walkthrough-footnote>


## チャレンジ問題：もう一つの外部からのアクセス経路

前の手順では、作成した Service に対してインターネット経由でアクセスし、アプリケーションの動作を確認しました。

しかし実は Service の作成と同時に、Ingress というリソースも作成しています。

### Service と Ingress の違い

双方ともグローバル IP アドレスを持たせ、稼働しているコンテナの前に配置でき、ロードバランサの役割を担います。
しかし大きく下記の違いがあります。

- Service: L4 で動作するため、IP アドレス、ポート番号に基づいて負荷分散を行う。
- Ingress: L7 で動作するため、HTTPの情報に基づき負荷分散ができる。具体的には、TLSの終端、URL 情報による負荷分散先のコントロールなどが可能。

昨今の Web サービスでは、TLS を利用することが基本となっており、さらにより柔軟な設定を行えるため Ingress を前段に置く形が基本的な構成となります。
詳細は、[Service](https://kubernetes.io/ja/docs/concepts/services-networking/service/)、[Ingress](https://kubernetes.io/ja/docs/concepts/services-networking/ingress/)をご参照ください。

### Ingress へのアクセス

作成済みの Ingress のグローバル IP アドレスを探し出し、ブラウザからアクセスし、Service と同じページが見えることを確認してください。

**ヒント**: CLI で調査をする場合、Service で実施した情報取得の手順を参考にしてください。
GUI で調査をする場合、以前の手順でアクセスしたページから IP アドレスを探して下さい。


## Operations を利用したアプリケーションの運用

<walkthrough-tutorial-duration duration=10></walkthrough-tutorial-duration>

Operations を利用しアプリケーションのトラブルシューティングを体験します。

下記の手順で進めていきます。

- [Cloud Trace](https://cloud.google.com/trace/) による分散トレーシング
- [Cloud Logging](https://cloud.google.com/logging/) によるログ管理
- [Cloud Profiler](https://cloud.google.com/profiler/) によるプロファイリング
- チャレンジ問題：特定のログの確認


## Cloud Trace による分散トレーシング

サンプルアプリケーションには、あらかじめトレーシングをするための情報を埋め込んでいます。
その情報を Cloud Trace から可視化することが可能です。

1. [トレースリストのページ](https://console.cloud.google.com/traces/traces?project={{project-id}})にブラウザからアクセスし、リクエスト フィルタに `/bench1` を入力
2. リクエストが遅い Span（青丸）を確認
3. ログを表示をクリック
4. “I” と表示されるアイコンをクリックして、連携された Cloud logging のログを確認

![Trace](https://storage.googleapis.com/devops-handson-for-github/StackdriverTrace.png)

**ヒント**: 今回は 1 アプリケーションの中の処理呼び出しを見ています。しかしこの分散トレーシングはユーザーの 1 リクエストが複数のサービスで構成されるような、マイクロサービスアーキテクチャで特に有用です。

<walkthrough-footnote>処理がかかっているページの処理内のトレーシング情報を元に、どの処理に時間がかかっているのかを確認しました。次にログ情報からアプリケーションに問題が無いかを確認します。</walkthrough-footnote>


## Cloud Logging によるログ管理

サンプルアプリケーションでは標準出力にログを出力しています。
それらは自動的に Cloud Logging に連携され、表示、検索などをすることが可能です。

[トレースリストのページ](https://console.cloud.google.com/traces/traces?project={{project-id}}) のページで `/bench1` のトレースを表示し、ログの横に表示されている 表示リンク をクリックします。

![TraceToLogging](https://storage.googleapis.com/devops-handson-for-github/StackdriverTraceToStackdriverLogging.png)

Logging のページに遷移し、関連するログが表示されていることを確認します。

![Logging](https://storage.googleapis.com/devops-handson-for-github/StackdriverLogging.png)

[アプリケーションログ](https://console.cloud.google.com/logs/viewer?project={{project-id}}&resource=k8s_container)も確認可能です。

<walkthrough-footnote>Cloud Logging からアプリケーション、その他のログを確認しました。次にプロファイラを使い、リソース使用量の観点からアプリケーションを確認します。</walkthrough-footnote>


## Cloud Profiler によるプロファイリング

[プロファイラ](https://console.cloud.google.com/profiler/devops-demo;zone=asia-northeast1-c;version=1.0.0/cpu?project={{project-id}}) を開き、fibonacci という関数の処理にリソースが使われていることを確認します。

![Profiler](https://storage.googleapis.com/devops-handson-for-github/StackdriverProfiler.png)

`プロファイルの種類` を切り替えることで、様々な情報を見ることができます。

- CPU 時間
- ヒープ
- 割り当てられたヒープ
- スレッド

<walkthrough-footnote>プロファイラを使うことで様々なリソースの使用量を確認しました。ここまでで簡単にアプリケーションのトラブルシュートができることを体験頂けたと思います。次にアプリケーションの作成、更新を自動化します。</walkthrough-footnote>


## チャレンジ問題：特定のログの確認

サンプルアプリケーションでは context というオブジェクトの中身をログに出力しています。

ここではそれがちゃんとログに出力されていることを確認します。

### 出力箇所の確認

まずアプリケーションのどこでそのログ出力をしているかを確認します。

1. 画面右上にあるアイコン <walkthrough-cloud-shell-editor-icon></walkthrough-cloud-shell-editor-icon> をクリックし、Cloud Shell エディタを開きます。
2. 次にエディタのエクスプローラーから `cloudshell_open/gcp-getting-started-lab-jp/devops/` とたどり、main.go ファイルを開きます。
3. 99 行目の log.XXXX という行が該当箇所です。

### 出力されたログの確認

Cloud Logging を使い、該当のログが出力されていることを確認します。

**ヒント**: このログはアプリケーションから出力されています。また Cloud Logging はログの検索機能を持っています。


## Cloud Build によるビルド、デプロイの自動化

<walkthrough-tutorial-duration duration=30></walkthrough-tutorial-duration>

Cloud Build を利用し今まで手動で行っていたアプリケーションのビルド、コンテナ化、リポジトリへの登録、GKE へのデプロイを自動化します。

下記の手順で進めていきます。

- [Cloud Source Repositories](https://cloud.google.com/source-repositories/) へのリポジトリの作成
- [Cloud Build トリガー](https://cloud.google.com/cloud-build/docs/running-builds/automate-builds) の作成
- Git クライアントの設定
- ソースコードの Push をトリガーにした、アプリケーションのビルド、GKE へのデプロイ
- チャレンジ問題：処理に時間がかかっているページの改善


## Cloud Build サービスアカウントへの権限追加

Cloud Build を実行する際に利用されるサービスアカウントを取得し、環境変数に格納します。

```bash
export CB_SA=$(gcloud projects get-iam-policy $GOOGLE_CLOUD_PROJECT | grep cloudbuild.gserviceaccount.com | uniq | cut -d ':' -f 2)
```

上で取得したサービスアカウントに Cloud Build から自動デプロイをさせるため Kubernetes 管理者の権限を与えます。

```bash
gcloud projects add-iam-policy-binding $GOOGLE_CLOUD_PROJECT  --member serviceAccount:$CB_SA --role roles/container.admin
```

<walkthrough-footnote>Cloud Build で利用するサービスアカウントに権限を付与し、Kubernetes に自動デプロイできるようにしました。次に資材を格納する Git リポジトリを作成します。</walkthrough-footnote>


## Cloud Source Repository（CSR）に Git レポジトリを作成

今回利用しているソースコードを配置するためのプライベート Git リポジトリを、Cloud Source Repository（CSR）に作成します。

```bash
gcloud source repos create devops-handson
```

**GUI**: [Source Repository](https://source.cloud.google.com/{{project-id}}/devops-handson): 作成前にアクセスすると拒否されます。

<walkthrough-footnote>資材を格納する Git リポジトリを作成しました。次にこのリポジトリに更新があったときにそれを検知し、処理を開始するトリガーを作成します。</walkthrough-footnote>


## Cloud Build トリガーを作成

Cloud Build に前の手順で作成した、プライベート Git リポジトリに push が行われたときに起動されるトリガーを作成します。

```bash
gcloud beta builds triggers create cloud-source-repositories --description="devopshandson" --repo=devops-handson --branch-pattern=".*" --build-config="devops/cloudbuild.yaml"
```

**GUI**: [ビルドトリガー](https://console.cloud.google.com/cloud-build/triggers?project={{project-id}})

<walkthrough-footnote>リポジトリの更新を検知するトリガーを作成しました。次にリポジトリを操作する Git クライアントの設定を行います。</walkthrough-footnote>


## Git クライアント設定

### 認証設定

Git クライアントで CSR と認証するための設定を行います。

```bash
git config --global credential.https://source.developers.google.com.helper gcloud.sh
```

**ヒント**: git コマンドと gcloud で利用している IAM アカウントを紐付けるための設定です。

### 利用者設定

USERNAME を自身のユーザ名に置き換えて実行し、利用者を設定します。

```bash
git config --global user.name "USERNAME"
```

### メールアドレス設定

USERNAME@EXAMPLE.com を自身のメールアドレスに置き換えて実行し、利用者のメールアドレスを設定します。

```bash
git config --global user.email "USERNAME@EXAMPLE.com"
```

<walkthrough-footnote>Git クライアントの設定を行いました。次に先程作成した CSR のリポジトリと、Cloud Shell 上にある資材を紐付けます。</walkthrough-footnote>


## Git リポジトリ設定

CSR を Git のリモートレポジトリとして登録します。
これで git コマンドを使い Cloud Shell 上にあるファイル群を管理することができます。

```bash
git remote add google https://source.developers.google.com/p/$GOOGLE_CLOUD_PROJECT/r/devops-handson
```

<walkthrough-footnote>以前の手順で作成した CSR のリポジトリと、Cloud Shell 上にある資材を紐付けました。次にその資材をプッシュします。</walkthrough-footnote>


## CSR への資材の転送（プッシュ）

以前の手順で作成した CSR は空の状態です。
git push コマンドを使い、CSR に資材を転送（プッシュ）します。

```bash
git push google master
```

**GUI**: [Source Repository](https://source.cloud.google.com/{{project-id}}/devops-handson) から資材がプッシュされたことを確認できます。

<walkthrough-footnote>Cloud Shell 上にある資材を CSR のリポジトリにプッシュしました。次に資材の更新をトリガーに処理が始まっている Cloud Build を確認します。</walkthrough-footnote>


## Cloud Build トリガーの動作確認

### Cloud Build の自動実行を確認

[Cloud Build の履歴](https://console.cloud.google.com/cloud-build/builds?project={{project-id}}) にアクセスし、git push コマンドを実行した時間にビルドが実行されていることを確認します。

### 新しいコンテナのデプロイ確認

ビルドが正常に完了後、以下コマンドを実行し、Cloud Build で作成したコンテナがデプロイされていることを確認します。

```bash
kubectl describe deployment/devops-handson-deployment | grep Image
```

`error: You must be logged in to the server (Unauthorized)` というメッセージが出た場合は、再度コマンドを実行してみてください。

コマンド実行結果の例。

```
    Image:        gcr.io/{{project-id}}/devops-handson:COMMITHASH
```

Cloud Build 実行前は Image が `gcr.io/{{project-id}}/devops-handson:v1` となっていますが、実行後は `gcr.io/{{project-id}}/devops-handson:COMMITHASH` になっている事が分かります。
実際は、COMMITHASH には Git のコミットハッシュ値が入ります。

<walkthrough-footnote>資材を更新、プッシュをトリガーとしたアプリケーションのビルド、コンテナ化、GKE へのデプロイを行うパイプラインが完成しました。次はチャレンジ問題を用意しています。</walkthrough-footnote>


## チャレンジ問題：処理に時間がかかっているページの改善

/bench1 にアクセスをするとレスポンスに時間がかかっていることを確認しました。それを修正し、Kubernetes にデプロイしてみましょう。

```bash
echo "http://${SERVICE_IP}/bench1"
```

### ソースコードの修正

main.go がアプリケーションのソースコードです。処理に時間がかかっているいくつかの行を削除し、保存します。

**ヒント**: Stress とコメントがついています。

### Git に修正をコミット、CSR にプッシュ

今行った修正を git コマンドを使い、コミット、CSR にプッシュします。

**ヒント**: 通常 `git add`、`git commit`、`git push` の 3 つのコマンドを利用します。

### Cloud Build の自動実行を確認

[Cloud Build の履歴](https://console.cloud.google.com/cloud-build/builds?project={{project-id}}) にアクセスし、git push コマンドを実行した時間にビルドが実行されていることを確認します。

### アプリケーションにアクセスし、すぐレスポンスがかえることを確認

```bash
echo "http://${SERVICE_IP}/bench1"
```


## Congraturations!

<walkthrough-conclusion-trophy></walkthrough-conclusion-trophy>

これにて GKE を使ったアプリケーション開発（コーディング、テスト、デプロイ）、Operations を用いた運用（分散トレーシング、ロギング、プロファイリング）、Cloud Build によるビルド、デプロイの自動化を体験するハンズオンは完了です！！

デモで使った資材が不要な方は、次の手順でクリーンアップを行って下さい。


## クリーンアップ（プロジェクトを削除）

作成したリソースを個別に削除する場合は、こちらのページの手順を実施せずに次のページに進んで下さい。

### GCP のデフォルトプロジェクト設定の削除

```bash
gcloud config unset project
```

### プロジェクトの削除

```bash
gcloud projects delete {{project-id}}
```


## クリーンアップ（個別リソースの削除）

### GKE クラスターの削除

```bash
gcloud container clusters delete k8s-devops-handson --quiet
```

### アプリケーション用サービスアカウントの削除

```bash
gcloud iam service-accounts delete dohandson@$GOOGLE_CLOUD_PROJECT.iam.gserviceaccount.com --quiet
```

### Cloud Build 用サービスアカウントから Kubernetes 管理者権限の削除

```bash
gcloud projects remove-iam-policy-binding $GOOGLE_CLOUD_PROJECT  --member serviceAccount:$CB_SA --role roles/container.admin
```

### Cloud Source Repository のリポジトリの削除

```bash
gcloud source repos delete devops-handson --quiet
```

### Container Registry に登録しているコンテナイメージの削除

```bash
gcloud container images list-tags gcr.io/$GOOGLE_CLOUD_PROJECT/devops-handson --format="csv[no-heading](DIGEST)" | xargs -I{} gcloud container images delete gcr.io/$GOOGLE_CLOUD_PROJECT/devops-handson@sha256:{} --force-delete-tags --quiet
```

### Cloud Build トリガーの削除

```bash
gcloud beta builds triggers list --filter="description = devopshandson" --format="value(id)" | xargs -I{} gcloud beta builds triggers delete {} --quiet
```

### ハンズオン資材の削除

```bash
cd $HOME && rm -rf cloudshell_open
```
