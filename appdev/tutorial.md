# はじめてみよう AppDev ハンズオン

## ハンズオンの内容

フルマネージド Kubernetes サービス「Kubernetes Engine」や、フルマネージド リレーショナル データベースサービス「Cloud Spanner」 をはじめとした、GCP 開発者向けサービスを使用したマイクロサービス アプリケーションの開発について学ぶハンズオンです。

ハンズオンの流れ
1. 環境準備
2. クーポンサービスの作成
3. クーポンサービスの組み込み
4. クーポンサービスの改善
5. (Advanced) クーポンサービスの高度化
6. クリーンアップ

# 1. 環境準備
## GCP のプロジェクト ID を設定する

### プロジェクト名と ID のリストを取得する

```bash
gcloud projects list
```

### 取得した GCP プロジェクト ID を環境変数に設定する

下記コマンドの FIXME を実際の GCP プロジェクト ID に置き換えて実行する。

```bash
export GOOGLE_CLOUD_PROJECT=FIXME
```

### gcloud から利用する GCP のデフォルトプロジェクトを設定する

```bash
gcloud config set project $GOOGLE_CLOUD_PROJECT
```

## ハンズオンで利用する GCP の API を有効化する

```bash
gcloud services enable cloudbuild.googleapis.com sourcerepo.googleapis.com containerregistry.googleapis.com container.googleapis.com cloudtrace.googleapis.com cloudprofiler.googleapis.com logging.googleapis.com compute.googleapis.com spanner.googleapis.com
```

## サービスアカウントの作成、IAM ロールの割当

### ハンズオン向けのサービスアカウントを作成する

```bash
gcloud iam service-accounts create appdev-handson --display-name "AppDev HandsOn Service Account"
```

## サービスアカウントで利用する鍵を作成しダウンロードする

```bash
gcloud iam service-accounts keys create auth.json --iam-account=appdev-handson@$GOOGLE_CLOUD_PROJECT.iam.gserviceaccount.com --key-file-type=json
```

## サービスアカウントに権限（IAM ロール）を割り当てる

### Cloud Profiler Agent role

```bash
gcloud projects add-iam-policy-binding $GOOGLE_CLOUD_PROJECT  --member serviceAccount:appdev-handson@$GOOGLE_CLOUD_PROJECT.iam.gserviceaccount.com --role roles/cloudprofiler.agent
```

### Cloud Trace Agent role

```bash
gcloud projects add-iam-policy-binding $GOOGLE_CLOUD_PROJECT  --member serviceAccount:appdev-handson@$GOOGLE_CLOUD_PROJECT.iam.gserviceaccount.com --role roles/cloudtrace.agent
```

### Cloud Monitoring Metric Writer role

```bash
gcloud projects add-iam-policy-binding $GOOGLE_CLOUD_PROJECT  --member serviceAccount:appdev-handson@$GOOGLE_CLOUD_PROJECT.iam.gserviceaccount.com --role roles/monitoring.metricWriter
```

### Cloud Monitoring Metadata Writer role

```bash
gcloud projects add-iam-policy-binding $GOOGLE_CLOUD_PROJECT  --member serviceAccount:appdev-handson@$GOOGLE_CLOUD_PROJECT.iam.gserviceaccount.com --role roles/stackdriver.resourceMetadata.writer
```

### Cloud Spanner Database User role

```bash
gcloud projects add-iam-policy-binding $GOOGLE_CLOUD_PROJECT  --member serviceAccount:appdev-handson@$GOOGLE_CLOUD_PROJECT.iam.gserviceaccount.com --role roles/spanner.databaseUser
```

### （Optional）Cloud Debugger Agent role

```bash
gcloud projects add-iam-policy-binding $GOOGLE_CLOUD_PROJECT  --member serviceAccount:appdev-handson@$GOOGLE_CLOUD_PROJECT.iam.gserviceaccount.com --role roles/clouddebugger.agent
```

## GKE の準備

### クラスターを作成する

Google Cloud SDK 284.0.0

```bash
gcloud container clusters create "k8s-appdev-handson"  \
--zone "asia-northeast1-c" \
--enable-autorepair \
--username "admin" \
--machine-type "n1-standard-2" \
--image-type "COS" \
--disk-type "pd-standard" \
--disk-size "100" \
--scopes "https://www.googleapis.com/auth/cloud-platform" \
--num-nodes "3" \
--enable-stackdriver-kubernetes \
--cluster-version "1.14.10-gke.27" \
--enable-ip-alias \
--network "projects/$GOOGLE_CLOUD_PROJECT/global/networks/default" \
--subnetwork "projects/$GOOGLE_CLOUD_PROJECT/regions/asia-northeast1/subnetworks/default" \
--addons HorizontalPodAutoscaling,HttpLoadBalancing \
--workload-pool=$GOOGLE_CLOUD_PROJECT.svc.id.goog
```

### GKE クラスターにアクセスするための認証情報を取得する

```bash
gcloud container clusters get-credentials k8s-appdev-handson --zone asia-northeast1-c
```

### GCP の IAM 情報と Kubernetes のサービスアカウントを紐付ける (Workload Identity)

ネームスペースの作成
```bash
kubectl create namespace appdev-handson-ns
```

Kubernetes のサービスアカウント作成
```bash
kubectl create serviceaccount --namespace appdev-handson-ns appdev-handson-k8s
```

GCP の IAM で GCP のサービスアカウントと Kubernetes のサービスアカウントを紐付ける
```bash
gcloud iam service-accounts add-iam-policy-binding \
  --role roles/iam.workloadIdentityUser \
  --member "serviceAccount:$GOOGLE_CLOUD_PROJECT.svc.id.goog[appdev-handson-ns/appdev-handson-k8s]" \
  appdev-handson@$GOOGLE_CLOUD_PROJECT.iam.gserviceaccount.com
```

Kubernetes のサービスアカウントに WorkloadIdentity を利用するためのアノテーションを追加する
```bash
kubectl annotate serviceaccount \
  --namespace appdev-handson-ns \
  appdev-handson-k8s \
  iam.gke.io/gcp-service-account=appdev-handson@$GOOGLE_CLOUD_PROJECT.iam.gserviceaccount.com
```

## Spanner データベースの準備

### Spanner インスタンスの作成　

```bash
gcloud spanner instances create appdev-handson-instance --config=regional-asia-northeast1 --description="AppDev HandsOn Instance" --nodes=1 --project=$GOOGLE_CLOUD_PROJECT
```

### Spanner デフォルトインスタンスの設定
```bash
gcloud config set spanner/instance appdev-handson-instance
```

### Spanner データベースの作成

```bash
gcloud spanner databases create appdev-db --instance=appdev-handson-instance --project=$GOOGLE_CLOUD_PROJECT
```

### Spanner テーブルの作成

Visitors
```
gcloud spanner databases ddl update appdev-db --instance=appdev-handson-instance --project=$GOOGLE_CLOUD_PROJECT\
  --ddl='CREATE TABLE Visitors ( SessionId STRING(1024) NOT NULL, LatestCouponUsed INT64 ) PRIMARY KEY (SessionId)'
```

Coupons
```
gcloud spanner databases ddl update appdev-db --instance=appdev-handson-instance --project=$GOOGLE_CLOUD_PROJECT\
  --ddl='CREATE TABLE Coupons ( SessionId STRING(1024) NOT NULL, CouponId STRING(1024) NOT NULL, DiscountPercentage INT64 NOT NULL, IsUsed BOOL NOT NULL, ExpiredBy INT64 NOT NULL) PRIMARY KEY (SessionId, CouponId), INTERLEAVE IN PARENT Visitors ON DELETE CASCADE'
```

### Spanner サンプルデータ作成

```
export COUPON_EXPIREDBY=`date +%s -d "+3 hours"`
```

サンプルデータの挿入
```bash
gcloud spanner rows insert --database=appdev-db \
      --table=Visitors \
      --data=SessionId=aaaaaaaa-1111-bbbb-2222-cccccccccccc
```

```bash
gcloud spanner rows insert --database=appdev-db \
      --table=Coupons \
      --data=SessionId=aaaaaaaa-1111-bbbb-2222-cccccccccccc,CouponId=xxxxxxxx-1111-yyyy-2222-zzzzzzzzzzzz,DiscountPercentage=40,IsUsed=false,ExpiredBy=$COUPON_EXPIREDBY
```

結果の確認
```bash
gcloud spanner databases execute-sql appdev-db \
    --sql='SELECT SessionId, CouponId, DiscountPercentage, IsUsed, ExpiredBy  FROM Coupons WHERE SessionId="aaaaaaaa-1111-bbbb-2222-cccccccccccc"'
```

## デモアプリケーションの準備

### Kubernetes へのデモアプリケーションデプロイ

[サンプルサプリケーション(microservices-demo)](https://github.com/GoogleCloudPlatform/microservices-demo)をダウンロードする
```bash
curl -L https://github.com/GoogleCloudPlatform/microservices-demo/archive/v0.1.4.tar.gz --output microservices-demo-0.1.4.tar.gz
```

```bash
tar zxvf microservices-demo-0.1.4.tar.gz
```

Kubertesnにアプリケーションをデプロイする
```bash
kubectl apply -f microservices-demo-0.1.4/release/kubernetes-manifests.yaml --namespace appdev-handson-ns
```

## ハンズオン資材の修正

以下コマンドでKubernetesにクーポンサービスをデプロイする為の定義ファイルへGCPプロジェクト固有の情報を設定する。(FIXMEという文字列をGCPプロジェクトIDに置き換える)

```bash
sed -i".org" -e "s/FIXME/$GOOGLE_CLOUD_PROJECT/g" ~/cloudshell_open/gcp-getting-started-lab-jp/appdev/microservices-demo/kubernetes-manifests/couponservice.yaml
```

```bash
sed -i".org" -e "s/FIXME/$GOOGLE_CLOUD_PROJECT/g" ~/cloudshell_open/gcp-getting-started-lab-jp/appdev/microservices-demo/kubernetes-manifests/frontend.yaml
```

### Kubernetes 上にデプロイしたデモアプリケーションの動作確認

接続可能なIPアドレスを調べる
```bash
kubectl describe services frontend-external --namespace appdev-handson-ns | grep "LoadBalancer Ingress"
```

ブラウザで調べたIPアドレスにアクセスし、アプリケーションにアクセスできることを確認する

# 2. クーポンサービスの作成

```
appdev/microservices-demo
.
├── kubernetes-manifests            : Kubernetesにクーポンサービスをデプロイする為の定義ファイル
└── src
    └── couponservice
        ├── src
        │   └── main
        │       ├── java
        │       │   └── hipstershop : クーポンサービスのソースコード
        │       ├── proto           : ProtocolBuffer の定義ファイル
        │       └── resources
        ├── build.gradle            : Gradle のビルド定義ファイル
        └── Dockerfile              : コンテナのビルド定義ファイル
```

## couponservice コンテナイメージの作成 (CloudBuild にてビルド)

v1 というタグをつけてコンテナをビルドする。
```bash
cd ~/cloudshell_open/gcp-getting-started-lab-jp/appdev/microservices-demo/src/couponservice && gcloud builds submit --tag gcr.io/$GOOGLE_CLOUD_PROJECT/couponservice:v1
```

## couponservice のデプロイ
```bash
kubectl apply -f ~/cloudshell_open/gcp-getting-started-lab-jp/appdev/microservices-demo/kubernetes-manifests/couponservice.yaml --namespace appdev-handson-ns
```

# 3. クーポンサービスの組み込み
クーポンサービスは Kubernetes 上で動いているが、他のマイクロサービスから呼び出されていない。そのため他のマイクロサービスから呼び出されるように変更を行う。本ハンズオンでは frontend サービスと couponservice を接続する。

```
.
├── kubernetes-manifests
│   └── frontend.yaml               : Kubernetes に新しいバージョンの frontend サービスをデプロイする為の定義ファイル
└── src
    └── frontend
        ├── Dockerfile              : コンテナのビルド定義ファイル
        ├── genproto                : ProtocolBuffer の定義ファイル
        ├── main.go                 : frontend サービスのソースコード
        ├── handlers.go
        ├── rpc.go
        └── templates
            ├── coupon.html         : クーポン表示バナーの HTML テンプレート
            └── home.html           : トップページの HTML テンプレート
```

## frontend コンテナイメージの作成 (CloudBuild にてビルド)

v1 というタグをつけてコンテナをビルドする。
```bash
cd ~/cloudshell_open/gcp-getting-started-lab-jp/appdev/microservices-demo/src/frontend && gcloud builds submit --tag gcr.io/$GOOGLE_CLOUD_PROJECT/frontend:v1
```

## frontend のデプロイ
```bash
kubectl apply -f ~/cloudshell_open/gcp-getting-started-lab-jp/appdev/microservices-demo/kubernetes-manifests/frontend.yaml --namespace appdev-handson-ns
```

## 動作確認
ブラウザでアプリケーションにアクセスし、クーポンが表示される事を確認する。

# 4. クーポンサービスの改善
Spannerを使ってクーポンの払い出しに関するデータを永続化する。

## ソースコードの修正

appdev/microservices-demo/src/couponservice/src/main/java/hipstershop/CouponService.java

* `Collection<Coupon> coupons = service.getCouponsBySessionId(req.getSessionId());`をコメントアウトする。
* `Collection<Coupon> coupons = service.getCouponsBySessionIdWithSpanner(req.getSessionId());`をコメントアウトする。

```java
修正前
126 /* @TODO comment out below line at section 3. */
127 Collection<Coupon> coupons = service.getCouponsBySessionId(req.getSessionId());
128 /* @TODO comment in below line at section 3.
129 Collection<Coupon> coupons = service.getCouponsBySessionIdWithSpanner(req.getSessionId());
130 */

修正後
126 /* @TODO comment out below line at section 3. */
127 //Collection<Coupon> coupons = service.getCouponsBySessionId(req.getSessionId());
128 /* @TODO comment in below line at section 3. */
129 Collection<Coupon> coupons = service.getCouponsBySessionIdWithSpanner(req.getSessionId());
130
```

## コンテナイメージの作成 (CloudBuild にてビルド)

v2というタグをつけてコンテナをビルドする。
```bash
cd ~/cloudshell_open/gcp-getting-started-lab-jp/appdev/microservices-demo/src/couponservice && gcloud builds submit --tag gcr.io/$GOOGLE_CLOUD_PROJECT/couponservice:v2
```

## Spanner へのクーポンデータ追加

### クーポン期限の設定

```
export COUPON_EXPIREDBY=`date +%s -d "+3 hours"`
```

### セッションIDの設定

ブラウザでアプリケーションにアクセスし、画面下部にあるSessionIdをメモする。
```
例
session-id: 42d37f1b-21cc-4bf8-bd63-1775545e870a
```

環境変数に調べたセッションIDを設定する
```bash
export USER_SESSION_ID=42d37f1b-21cc-4bf8-bd63-1775545e870a
```

サンプルデータの挿入
```
gcloud spanner rows insert --database=appdev-db \
      --table=Visitors \
      --data=SessionId=$USER_SESSION_ID
```

```
gcloud spanner rows insert --database=appdev-db \
      --table=Coupons \
      --data=SessionId=$USER_SESSION_ID,CouponId=xxxxxxxx-1111-yyyy-2222-zzzzzzzzzzzz,DiscountPercentage=40,IsUsed=false,ExpiredBy=$COUPON_EXPIREDBY
```

## Kubernetes に修正したクーポンサービスをデプロイする

### Kubernetes のアプリケーション定義ファイルを修正する
appdev/microservices-demo/kuubernetes-manifests/couponservice.yaml を以下の通り修正する。
xxxxxはプロジェクトIDに読み替えて実行する。
```
修正前
image: gcr.io/xxxxx/couponservice:v1

修正後
image: gcr.io/xxxxx/couponservice:v2
```

### 新しいアプリケーションをデプロイする
```bash
kubectl apply -f ~/cloudshell_open/gcp-getting-started-lab-jp/appdev/microservices-demo/kubernetes-manifests/couponservice.yaml --namespace appdev-handson-ns
```

## 動作確認
ブラウザでアプリケーションにアクセスし、Spannerに保存したクーポンが表示される事を確認する。

# 5. (Advanced) クーポンサービスの高度化

### 有効な期限内のクーポンだけを返却する機能を追加
CouponService に 有効なクーポンだけを返却する機能を追加する。CouponService に新しい RPC (getValidCoupons) として実装すること。CouponService に機能実装した後は FrontendService から新しい RPC を呼び出し、有効なクーポンだけを表示する。検証時は Spanner に無効なクーポンを追加し、これらが表示されない事を確認すること。

# おめでとうございます！

<walkthrough-conclusion-trophy></walkthrough-conclusion-trophy>

フルマネージド Kubernetes サービス「Kubernetes Engine」や、フルマネージド リレーショナル データベースサービス「Cloud Spanner」 をはじめとした、GCP 開発者向けサービスを使用したマイクロサービス アプリケーションの開発について学ぶハンズオンは完了です。

必要な方はデモで使った資材が不要な方はクリーンアップを行って下さい。

# クリーンアップ

## ハンズオンで利用した資材の削除

### GKE クラスター（k8s-appdev-handson）削除
```bash
gcloud container clusters delete k8s-appdev-handson --zone asia-northeast1-c
```

### IAM アカウント（appdev-handson@xxx）削除

```bash
gcloud iam service-accounts delete appdev-handson@$GOOGLE_CLOUD_PROJECT.iam.gserviceaccount.com 
```

### Container Registry のコンテナイメージ削除
```bash
gcloud container images delete gcr.io/$GOOGLE_CLOUD_PROJECT/couponservice:v1 --force-delete-tags
```

```bash
gcloud container images delete gcr.io/$GOOGLE_CLOUD_PROJECT/couponservice:v2 --force-delete-tags
```


```bash
gcloud container images delete gcr.io/$GOOGLE_CLOUD_PROJECT/frontend:v1 --force-delete-tags
```

### Spanner データベース削除
```
gcloud spanner databases delete appdev-db --instance=appdev-handson-instance --project=$GOOGLE_CLOUD_PROJECT
```

### Spanner インスタンス削除
```
gcloud spanner instances delete appdev-handson-instance --project=$GOOGLE_CLOUD_PROJECT
```

## GCP のデフォルトプロジェクト設定の削除

```bash
gcloud config unset project
```