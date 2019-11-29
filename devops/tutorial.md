# はじめてみよう DevOps ハンズオン

## ハンズオンの内容

GKE を使ったアプリケーション開発（コーディング、テスト、デプロイ）、Stackdriver を用いた運用（分散トレーシング、ロギング、プロファイリング）を体験するハンズオンです。

# GCP のプロジェクト ID を設定する

## プロジェクト名と ID のリストを取得する

```bash
gcloud projects list
```

## 取得した GCP プロジェクト ID を環境変数に設定する

下記コマンドの FIXME を実際の GCP プロジェクト ID に置き換えて実行する。

```bash
export GOOGLE_CLOUD_PROJECT=FIXME
```

## gcloud から利用する GCP のデフォルトプロジェクトを設定する

```bash
gcloud config set project $GOOGLE_CLOUD_PROJECT
```

# ハンズオンで利用する GCP の API を有効化する

```bash
gcloud services enable cloudbuild.googleapis.com sourcerepo.googleapis.com containerregistry.googleapis.com container.googleapis.com cloudtrace.googleapis.com cloudprofiler.googleapis.com logging.googleapis.com compute.googleapis.com
```

# サービスアカウントの作成、IAM ロールの割当

## ハンズオン向けのサービスアカウントを作成する

```bash
gcloud iam service-accounts create dohandson --display-name "DevOps HandsOn Service Account"
```

## サービスアカウントで利用する鍵を作成しダウンロードする

```bash
gcloud iam service-accounts keys create auth.json --iam-account=dohandson@$GOOGLE_CLOUD_PROJECT.iam.gserviceaccount.com --key-file-type=json
```

## サービスアカウントに権限（IAM ロール）を割り当てる

### Cloud Profiler Agent role

```bash
gcloud projects add-iam-policy-binding $GOOGLE_CLOUD_PROJECT  --member serviceAccount:dohandson@$GOOGLE_CLOUD_PROJECT.iam.gserviceaccount.com --role roles/cloudprofiler.agent
```

### Cloud Trace Agent role

```bash
gcloud projects add-iam-policy-binding $GOOGLE_CLOUD_PROJECT  --member serviceAccount:dohandson@$GOOGLE_CLOUD_PROJECT.iam.gserviceaccount.com --role roles/cloudtrace.agent
```

### Cloud Monitoring Metric Writer role

```bash
gcloud projects add-iam-policy-binding $GOOGLE_CLOUD_PROJECT  --member serviceAccount:dohandson@$GOOGLE_CLOUD_PROJECT.iam.gserviceaccount.com --role roles/monitoring.metricWriter
```

### Cloud Monitoring Metadata Writer role

```bash
gcloud projects add-iam-policy-binding $GOOGLE_CLOUD_PROJECT  --member serviceAccount:dohandson@$GOOGLE_CLOUD_PROJECT.iam.gserviceaccount.com --role roles/stackdriver.resourceMetadata.writer
```

### （Optional）Cloud Debugger Agent role

```bash
gcloud projects add-iam-policy-binding $GOOGLE_CLOUD_PROJECT  --member serviceAccount:dohandson@$GOOGLE_CLOUD_PROJECT.iam.gserviceaccount.com --role roles/clouddebugger.agent
```

# ダウンロードしたサービスアカウントの鍵をハンズオン用のディレクトリに配置する

```bash
mv auth.json gcp-credentials/auth.json
```

# GKE の準備

## クラスターを作成する

```bash
gcloud container clusters create "k8s-devops-handson"  \
--zone "asia-northeast1-c" \
--enable-autorepair \
--username "admin" \
--machine-type "n1-standard-1" \
--image-type "COS" \
--disk-type "pd-standard" \
--disk-size "100" \
--scopes "https://www.googleapis.com/auth/cloud-platform" \
--num-nodes "3" \
--enable-cloud-logging --enable-cloud-monitoring \
--enable-ip-alias \
--network "projects/$GOOGLE_CLOUD_PROJECT/global/networks/default" \
--subnetwork "projects/$GOOGLE_CLOUD_PROJECT/regions/asia-northeast1/subnetworks/default" \
--addons HorizontalPodAutoscaling,HttpLoadBalancing
```

## GKE クラスターにアクセスするための認証情報を取得する

```bash
gcloud container clusters get-credentials k8s-devops-handson --zone asia-northeast1-c
```

# コンテナの作成と動作確認

## ハンズオン用の設定ファイルを修正する

デモ用アプリケーションの設定ファイルに GCP プロジェクト ID を設定する

```bash
sed -i".org" -e "s/FIXME/$GOOGLE_CLOUD_PROJECT/g" conf/app.conf
```

Kubernetesのデプロイ用設定ファイルに GCP プロジェクト ID を設定する

```bash
sed -i".org" -e "s/FIXME/$GOOGLE_CLOUD_PROJECT/g" gke-config/deployment.yaml
```

## コンテナを作成する

```bash
docker build -t gcr.io/$GOOGLE_CLOUD_PROJECT/devops-handson:v1 .
```

## コンテナを起動する

```bash
docker run -d -p 8080:8080 --name devops-handson gcr.io/$GOOGLE_CLOUD_PROJECT/devops-handson:v1
```

## CloudShell の機能を利用し、起動したアプリケーションにアクセスする

画面右上にあるアイコンをクリックし、"プレビューのポート: 8080"を選択する。これにより新しい画面が表示され、Cloud Shell 上で起動しているコンテナにアクセスできる。

![PreviewOnCloudShell](https://storage.googleapis.com/devops-handson-for-github/PreviewOnCloudShell.png)

![BrowserAccessToMainController](https://storage.googleapis.com/devops-handson-for-github/BrowserAccessToMainController.png)

# 作成したコンテナを Kubernetes クラスターに配置する

## 作成したコンテナをコンテナレジストリ（Google Container Registry）へ登録（プッシュ）する

```bash
docker push gcr.io/$GOOGLE_CLOUD_PROJECT/devops-handson:v1
```

## 登録したコンテナを Kubernetes クラスターへデプロイする

```bash
kubectl apply -f gke-config/deployment.yaml
```

## デプロイしたコンテナへアクセスし動作確認を行なう

デプロイしたコンテナに対してトラフィックを転送する Ingress の IP アドレスを確認する。

```bash
kubectl get ingress/devops-handson-ingress
```

コマンドの実行結果。xx.xx.xx.xxの部分には実際のグローバル IP が入ります。

```
NAME                     HOSTS     ADDRESS        PORTS     AGE
devops-handson-ingress   *         xx.xx.xx.xx   80        1m
```

先程のコマンドで確認した Ingress のグローバル IP に対してブラウザからアクセスし、画面が表示されることを確認する。Ingress を作成してからアクセスに成功するまで 5-10 分程度時間がかかるので、404 エラーが出る場合は時間を置いてリトライを行なう。

アクセス先の URL である INGRESS-IP は確認した IP に置き換えてアクセスすること。

```
http://<INGRESS-IP>/
```

![BrowserAccessToMainController](https://storage.googleapis.com/devops-handson-for-github/BrowserAccessToMainController.png)

Ingress 以外にも、Loadbalancer を作成して動作確認することができる。※ Ingress の作成に時間を要している場合は試してみましょう。

```bash
kubectl apply -f gke-config/loadbalancer.yaml
```

以下のコマンドで Loadbalancer のグローバル IP を確認し、アクセス。

```bash
kubectl get service/devops-handson-loadbalancer
```
```
NAME                          TYPE           CLUSTER-IP    EXTERNAL-IP    PORT(S)        AGE
devops-handson-loadbalancer   LoadBalancer   10.0.29.159   34.84.252.73   80:30392/TCP   16m
```



## Apache Bench で /bench1 へ複数回アクセスをする
後のステップで確認する Stackdriver Profiler のサンプル数を稼ぐため、Apache Bench を使い複数回、/bench1 へのアクセスを行う。
Timeout エラーが出た場合は -t の値を増やしてみてください。（Timeout値）

```bash
sudo apt-get install apache2-utils
```

```bash
ab -n 30 -c 5 -t 60 http://[INGRESS_IP]/bench1
```

# Stackdriver を利用したトラブルシュート

## 動作の遅い機能の確認

こちらの URL にアクセスし、描画されるまで時間がかかることを確認する。Google Chrome を利用している場合は、開発者ツールを起動しレスポンスが返ってくるまでの秒数を確認する。

```
http://<INGRESS-IP>/bench1
```

![BrowserAccessToSlowBenchController](https://storage.googleapis.com/devops-handson-for-github/BrowserAccessToSlowBenchController.png)

## Stackdriver を利用した分析

### Stackdriver Trace を利用したレイテンシーの確認

1. トレース -> トレースリストを開き、リクエスト フィルタに /bench1 を入力する。
2. リクエストが遅い Span を確認する。
3. ログを表示をクリック
4. “I” と表示されるアイコンをクリックして、連携された Stackdriver logging のログを確認する

![StackdriverTrace](https://storage.googleapis.com/devops-handson-for-github/StackdriverTrace.png)

### Stackdrier Logging によるログの確認

Trace のページで /bench1 のトレースを表示し、Log の横に表示されている View リンクをクリックする。

![StackdriverTraceToStackdriverLogging](https://storage.googleapis.com/devops-handson-for-github/StackdriverTraceToStackdriverLogging.png)

Stackdrier Logging のページに遷移し、関連するログが表示されていることを確認する。

![StackdriverLogging](https://storage.googleapis.com/devops-handson-for-github/StackdriverLogging.png)

### Stackdriver Profiler によるアプリケーションのプロファイリング

プロファイラ を開き、fibonacci という関数の処理にリソースが使われていることを確認する。
閲覧時は、ゾーンに “asia-northeast1-c”、バージョンに “1.0.0” を設定する。

![StackdriverProfiler](https://storage.googleapis.com/devops-handson-for-github/StackdriverProfiler.png)

# Cloud Build によるビルド・デプロイの自動化

## Cloud Build サービスアカウントへの権限追加

Cloud Build を実行する際に利用されるサービスアカウントを確認する。

```bash
gcloud projects get-iam-policy $GOOGLE_CLOUD_PROJECT | grep cloudbuild.gserviceaccount.com | uniq
```

コマンド実行結果

```
- serviceAccount:1018524524339@cloudbuild.gserviceaccount.com
```

Cloud Build を実行する際に利用されるサービスアカウントに Kubernetes 管理者の権限を与える。
FIXME の値を、上記コマンドで書く確認したサービスアカウントに置き換えてコマンドを実行する。

```bash
gcloud projects add-iam-policy-binding $GOOGLE_CLOUD_PROJECT  --member serviceAccount:FIXME --role roles/container.admin
```

## Cloud Source Repository（CSR）で Git レポジトリを作成する

Cloud Console からも Source Repository にアクセスし、新しいレポジトリを作成します。作成時、レポジトリ名に “devops-handson” を設定する。

## Cloud Build トリガーの設定

Cloud Console からも Cloud Build -> トリガーにアクセスし、トリガーの追加を行なう。トリガー追加時は以下の内容の設定を行なう。

* [ソースを選択] ソースを選択 -> Cloud Source Repositories を選択
* [リポジトリを選択] devops-handson を選択
* [トリガーを選択] ビルド設定 -> Cloud Build 構成ファイル（yaml または json）
* [トリガーを選択] ビルド設定 -> Cloud Build 構成ファイルの場所 -> /devops/cloudbuild.yaml

## Git レポジトリに資材を登録する

Git クライアントで CSR と認証するための設定を行なう

```bash
git config --global credential.https://source.developers.google.com.helper gcloud.sh
```

CSR を Git のリモートレポジトリとして登録する。

```bash
git remote add google https://source.developers.google.com/p/$GOOGLE_CLOUD_PROJECT/r/devops-handson
```

Git で利用するユーザー名を登録する。USERNAME は自身のユーザ名に置き換えて実行する。

```bash
git config --global user.name "USERNAME"
```

Git で利用するユーザーのメールアドレスを設定する。USERNAME@EXAMPLE.com は自身のメールアドレスに置き換えて実行する。

```bash
git config --global user.email "USERNAME@EXAMPLE.com"
```

CSR に資材を転送（プッシュ）する

```bash
git push google master
```

## Cloud Build が自動的に実行されることの確認

Cloud Build -> 履歴 を選択し、git push コマンドを実行した時間にビルドが実行されていることを確認する。
ビルド完了後、以下コマンドを実行し、Cloud Build で作成したコンテナがデプロイされていることを確認する。

```bash
kubectl describe deployment/devops-handson-deployment
```

コマンド実行結果の例。Cloud Build 実行前は Image が gcr.io/PROJECTID/devops-handson:v1 となっているが、実行後は gcr.io/PROJECTID/devops-handson:COMMITHASH になっている事が分かる。実際は PROJECTID は GCP のプロジェクト ID 、COMMITHASH は Git のコミットハッシュが表示される。

```
...
Pod Template:
  Labels:  app=devops-handson
  Containers:
   myapp:
    Image:        gcr.io/PROJECTID/devops-handson:COMMITHASH
...
```

# Congraturations!

<walkthrough-conclusion-trophy></walkthrough-conclusion-trophy>

これにて GKE を使ったアプリケーション開発（コーディング、テスト、デプロイ）、Stackdriver を用いた運用（分散トレーシング、ロギング、プロファイリング）を体験するハンズオンは完了です！

デモで使った資材が不要な方はクリーンアップを行って下さい。

## クリーンアップ

## GCP のデフォルトプロジェクト設定の削除

```bash
gcloud config unset project
```

## ハンズオンで利用した資材の削除

* GKE クラスター（k8s-devops-handson）
* IAM アカウント（dohandson@xxx）
* IAM アカウント Cloud Build（xxxxxx@cloudbuild.gserviceaccount.com）から Kubernetes 管理者 の役割を削除する
* Cloud Source Repository の devops-handson レポジトリ
* Container Registry の devops-handson イメージ
