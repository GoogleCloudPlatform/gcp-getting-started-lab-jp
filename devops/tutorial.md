# はじめてみようDevOps ハンズオン

## ハンズオンの内容
GKEを使ったアプリケーション開発(コーディング、テスト、デプロイ）、Stackdriverを用いた運用(分散トレーシング、ロギング、プロファイリング)を体験するハンズオンです。

# GCPのプロジェクトIDを設定する

## プロジェクト名とIDのリストを取得する
```bash
gcloud projects list
```

## 取得したGCPプロジェクトIDを環境変数に設定する

今コマンドのFIXMEを実際のGCPプロジェクトIDに置き換えて実行する。
```bash
export GOOGLE_CLOUD_PROJECT=FIXME
```

## gcloudから利用するGCPのデフォルトプロジェクトを設定する
```bash
gcloud config set project $GOOGLE_CLOUD_PROJECT
```

# ハンズオンで利用するGCPのAPIを有効化する

```bash
gcloud services enable cloudbuild.googleapis.com sourcerepo.googleapis.com containerregistry.googleapis.com container.googleapis.com cloudtrace.googleapis.com cloudprofiler.googleapis.com logging.googleapis.com compute.googleapis.com
```

# サービスアカウントの作成、IAMロールの割当

## ハンズオン向けのサービスアカウントを作成する
```bash
gcloud iam service-accounts create dohandson --display-name "DevOps HandsOn Service Account"
```

## サービスアカウントで利用する鍵を作成しダウンロードする
```bash
gcloud iam service-accounts keys create auth.json --iam-account=dohandson@$GOOGLE_CLOUD_PROJECT.iam.gserviceaccount.com --key-file-type=json
````

## サービスアカウントに権限(IAMロール)を割り当てる

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

### (Optional)  CloudDebugger Agent role
```bash
gcloud projects add-iam-policy-binding $GOOGLE_CLOUD_PROJECT  --member serviceAccount:dohandson@$GOOGLE_CLOUD_PROJECT.iam.gserviceaccount.com --role roles/clouddebugger.agent
```

# ダウンロードしたサービスアカウントの鍵をハンズオン用のディレクトリに配置する

```bash
mv auth.json gcp-credentials/auth.json
```

# GKEの準備

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

## GKEクラスターにアクセスするための認証情報を取得する

```bash
gcloud container clusters get-credentials k8s-devops-handson --zone asia-northeast1-c
```

# コンテナの作成と動作確認

## ハンズオン用の設定ファイルを修正する

デモ用アプリケーションの設定ファイルにGCPプロジェクトIDを設定する
```bash
sed -i".org" -e "s/FIXME/$GOOGLE_CLOUD_PROJECT/g" conf/app.conf
```

Kubernetesのデプロイ用設定ファイルにGCPプロジェクトIDを設定する
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

## CloudShellの機能を利用し、起動したアプリケーションにアクセスする

画面右上にあるアイコンをクリックし、"プレビューのポート: 8080"を選択する。これにより新しい画面が表示され、Cloud Shell上で起動しているコンテナにアクセスできる。
![PreviewOnCloudShell](https://storage.googleapis.com/devops-handson-for-github/PreviewOnCloudShell.png)

![BrowserAccessToMainController](https://storage.googleapis.com/devops-handson-for-github/BrowserAccessToMainController.png)

# 作成したコンテナをKubernetesクラスターに配置する

## 作成したコンテナをコンテナレジストリ(Google Container Registry)へ登録(プッシュ)する
```bash
docker push gcr.io/$GOOGLE_CLOUD_PROJECT/devops-handson:v1
```

## 登録したコンテナをKubernetesクラスターへデプロイする
```bash
kubectl apply -f gke-config/deployment.yaml
```

## デプロイしたコンテナへアクセスし動作確認を行なう

デプロイしたコンテナに対してトラフィックを転送するIngressのIPアドレスを確認する。
```bash
kubectl get ingress/devops-handson-ingress
```

コマンドの実行結果。xx.xx.xx.xxの部分には実際のグローバルIPが入ります。
```
NAME                     HOSTS     ADDRESS        PORTS     AGE
devops-handson-ingress   *         xx.xx.xx.xx   80        1m
```

先程のコマンドで確認したIngressのグローバルIPに対してブラウザからアクセスし、画面が表示されることを確認する。Ingressを作成してからアクセスに成功するまで5-10分程度時間がかかるので、404エラーが出る場合は時間を置いてリトライを行なう。

アクセス先のURL。<INGRESS-IP>は確認したIPに置き換えて実行すること。
```
http://<INGESS-IP>/
```

![BrowserAccessToMainController](https://storage.googleapis.com/devops-handson-for-github/BrowserAccessToMainController.png)

後のステップで確認するStackdriver Profilerのサンプル数を稼ぐため、
Apache Benchを使い複数回、/bench1へのアクセスを行う。
Timeoutエラーが出た場合は -tの値を増やしてみてください。(Timeout値)

```bash
sudo apt-get install apache2-utils
```
```bash
ab -n 30 -c 5 -t 60 http://[INGRESS_IP]/bench1
```

# Stackdriverを利用したトラブルシュート

## 動作の遅い機能の確認

こちらのURLにアクセスし、描画されるまで時間がかかることを確認する。Google Chromeを利用している場合は、開発者ツールを起動しレスポンスが返ってくるまでの秒数を確認する。
```
http://<INGESS-IP>/bench1
```

![BrowserAccessToSlowBenchController](https://storage.googleapis.com/devops-handson-for-github/BrowserAccessToSlowBenchController.png)

## Stackdriverを利用した分析

### Stackdriver Traceを利用したレイテンシーの確認
1. トレース -> トレースリストを開き、リクエスト フィルタに /bench1 を入力する。
2. リクエストが遅い Span を確認する。
3. ログを表示をクリック
4. “I” と表示されるアイコンをクリックして、連携されたStackdriver loggingのログを確認する

![StackdriverTrace](https://storage.googleapis.com/devops-handson-for-github/StackdriverTrace.png)

### Stackdrier Loggingによるログの確認

Traceのページで /bench1 のトレースを表示し、Logの横に表示されている View リンクをクリックする。

![StackdriverTraceToStackdriverLogging](https://storage.googleapis.com/devops-handson-for-github/StackdriverTraceToStackdriverLogging.png)

Stackdrier Loggingのページに遷移し、関連するログが表示されていることを確認する。
![StackdriverLogging](https://storage.googleapis.com/devops-handson-for-github/StackdriverLogging.png)

### Stackdriver Profilerによるアプリケーションのプロファイリング

プロファイラ を開き、fibonacciという関数の処理にリソースが使われていることを確認する。
閲覧時は、ゾーンに “asia-northeast1-c”、バージョンに “1.0.0” を設定する。

![StackdriverProfiler](https://storage.googleapis.com/devops-handson-for-github/StackdriverProfiler.png)

# Cloud Buildによるビルド・デプロイの自動化

## Cloud Buildサービスアカウントへの権限追加

Cloud Buildを実行する際に利用されるサービスアカウントを確認する。
```bash
gcloud projects get-iam-policy $GOOGLE_CLOUD_PROJECT | grep cloudbuild.gserviceaccount.com | uniq
```

コマンド実行結果
```
- serviceAccount:1018524524339@cloudbuild.gserviceaccount.com
```

Cloud Buildを実行する際に利用されるサービスアカウントにKubernetes 管理者の権限を与える。
FIXMEの値を、上記コマンドで書く確認したサービスアカウントに置き換えてコマンドを実行する。
```bash
gcloud projects add-iam-policy-binding $GOOGLE_CLOUD_PROJECT  --member serviceAccount:FIXME --role roles/container.admin
```

## Cloud Source Repository(CSR)でGitレポジトリを作成する

Cloud ConsoleからもSource Repositoryにアクセスし、新しいレポジトリを作成します。作成時、レポジトリ名に “devops-handson” を設定する。

## Cloud Buildトリガーの設定
Cloud ConsoleからもCloud Build -> トリガーにアクセスし、トリガーの追加を行なう。トリガー追加時は以下の内容の設定を行なう。
* [ソースを選択] ソースを選択 -> Cloud Source Repositories を選択
* [リポジトリを選択] devops-handson を選択
* [トリガーを選択] ビルド設定 -> Cloud Build 構成ファイル（yaml または json）
* [トリガーを選択] ビルド設定 -> Cloud Build 構成ファイルの場所 -> /devops/cloudbuild.yaml

## Gitレポジトリに資材を登録する

GitクライアントでCSRと認証するための設定を行なう
```bash
git config --global credential.https://source.developers.google.com.helper gcloud.sh
```

CSRをGitのリモートレポジトリとして登録する。
```bash
git remote add google https://source.developers.google.com/p/$GOOGLE_CLOUD_PROJECT/r/devops-handson
```

Gitで利用するユーザー名を登録する。USERNAMEは自身のユーザ名に置き換えるて実行する。
```bash
git config --global user.name "USERNAME"
```
Gitで利用するユーザーのEメールを設定する。USERNAME@EXAMPLE.comは自身のメールアドレスに置き換えるて実行する。
```bash
$ git config --global user.email "USERNAME@EXAMPLE.com"
```

CSRに資材を転送(プッシュ)する
```bash
git push google master
```

## Cloud Buildが自動的に実行されることの確認
Cloud Build -> 履歴　を選択し、git pushコマンドを実行した時間にビルドが実行されていることを確認する。

ビルド完了後、以下コマンドを実行し、Cloud Buildで作成したコンテナがデプロイされていることを確認する。
```bash
kubectl describe deployment/devops-handson-deployment
```

コマンド実行結果の例。Cloud Build実行前はImageがgcr.io/PROJECTID/devops-handson:v1となっているが、実行後はgcr.io/PROJECTID/devops-handson:COMMITHASHになっている事が分かる。実際はPROJECTIDはGCPのプロジェクトID、COMMITHASHはGitのコミットハッシュが表示される。

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

これにてGKEを使ったアプリケーション開発(コーディング、テスト、デプロイ）、Stackdriverを用いた運用(分散トレーシング、ロギング、プロファイリング)を体験するハンズオンは完了です！

デモで使った資材が不要な方はクリーンアップを行って下さい。

## クリーンアップ

## GCPのデフォルトプロジェクト設定の削除
```bash
gcloud config unset project
```

## ハンズオンで利用した資材の削除

* GKEクラスター(k8s-devops-handson)
* IAMアカウント(dohandson@xxx)
* IAMアカウント Cloud Build(xxxxxx@cloudbuild.gserviceaccount.com)からKubernetes 管理者　の役割を削除する
* Cloud Source Repositoryのdevops-handsonレポジトリ
* Container Registryのdevops-handsonイメージ
