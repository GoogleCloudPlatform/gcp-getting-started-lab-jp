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

### Google Cloud Platform（GCP）プロジェクトの選択

ハンズオンを行う GCP プロジェクトを選択し、 **Start** をクリックしてください。

<walkthrough-project-setup>
</walkthrough-project-setup>
```

### 取得した GCP プロジェクト ID を環境変数に設定する

環境変数 `GOOGLE_CLOUD_PROJECT` に GCP プロジェクト ID を設定します。

```bash
export GOOGLE_CLOUD_PROJECT="{{project-id}}"
```

### gcloud から利用する GCP のデフォルトプロジェクトを設定する

```bash
gcloud config set project $GOOGLE_CLOUD_PROJECT
```

## gcloud コマンドラインツール設定 - リージョン、ゾーン

### デフォルトリージョンを設定

コンピュートリソースを作成するデフォルトのリージョンとして、東京リージョン（asia-northeast1）を指定します。

```bash
gcloud config set compute/region asia-northeast1
```

### デフォルトゾーンを設定

コンピュートリソースを作成するデフォルトのゾーンとして、東京リージョン内の 1 ゾーン（asia-northeast1-c）を指定します。

```bash
gcloud config set compute/zone asia-northeast1-c
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

## サービスアカウントに権限（IAM ロール）を割り当てる
作成したサービスアカウントには GCP リソースの操作権限がついていないため、ここで必要な権限を割り当てます。

下記の権限を割り当てます。

- Cloud Profiler Agent role
- Cloud Trace Agent role
- Cloud Monitoring Metric Writer role
- Cloud Monitoring Metadata Writer role
- Cloud Spanner Database User role

```bash
gcloud projects add-iam-policy-binding $GOOGLE_CLOUD_PROJECT  --member serviceAccount:appdev-handson@$GOOGLE_CLOUD_PROJECT.iam.gserviceaccount.com --role roles/cloudprofiler.agent
gcloud projects add-iam-policy-binding $GOOGLE_CLOUD_PROJECT  --member serviceAccount:appdev-handson@$GOOGLE_CLOUD_PROJECT.iam.gserviceaccount.com --role roles/cloudtrace.agent
gcloud projects add-iam-policy-binding $GOOGLE_CLOUD_PROJECT  --member serviceAccount:appdev-handson@$GOOGLE_CLOUD_PROJECT.iam.gserviceaccount.com --role roles/monitoring.metricWriter
gcloud projects add-iam-policy-binding $GOOGLE_CLOUD_PROJECT  --member serviceAccount:appdev-handson@$GOOGLE_CLOUD_PROJECT.iam.gserviceaccount.com --role roles/stackdriver.resourceMetadata.writer
gcloud projects add-iam-policy-binding $GOOGLE_CLOUD_PROJECT  --member serviceAccount:appdev-handson@$GOOGLE_CLOUD_PROJECT.iam.gserviceaccount.com --role roles/spanner.databaseUser
```

## GKE の準備

### クラスターを作成する

```bash
gcloud container clusters create "k8s-appdev-handson"  \
--image-type "COS" \
--machine-type "n1-standard-2" \
--enable-stackdriver-kubernetes \
--enable-ip-alias \
--release-channel stable \
--workload-pool $GOOGLE_CLOUD_PROJECT.svc.id.goog
```

### GKE クラスターにアクセスするための認証情報を取得する

```bash
gcloud container clusters get-credentials k8s-appdev-handson
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

```bash
gcloud spanner databases ddl update appdev-db --instance=appdev-handson-instance --project=$GOOGLE_CLOUD_PROJECT \
  --ddl='CREATE TABLE Visitors ( SessionId STRING(1024) NOT NULL, LatestCouponUsed INT64 ) PRIMARY KEY (SessionId)'
```

Coupons

```bash
gcloud spanner databases ddl update appdev-db --instance=appdev-handson-instance --project=$GOOGLE_CLOUD_PROJECT \
  --ddl='CREATE TABLE Coupons ( SessionId STRING(1024) NOT NULL, CouponId STRING(1024) NOT NULL, DiscountPercentage INT64 NOT NULL, IsUsed BOOL NOT NULL, ExpiredBy INT64 NOT NULL) PRIMARY KEY (SessionId, CouponId), INTERLEAVE IN PARENT Visitors ON DELETE CASCADE'
```

### Spanner サンプルデータ作成

```bash
export COUPON_EXPIREDBY=$(python3 -c "import time; print(int(time.time()) + 10800);")
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
    --sql='SELECT SessionId, CouponId, DiscountPercentage, IsUsed, ExpiredBy FROM Coupons WHERE SessionId="aaaaaaaa-1111-bbbb-2222-cccccccccccc"'
```

上記コマンドを実行後、以下のような出力結果が得られることを確認する
```
SessionId                             CouponId                              DiscountPercentage  IsUsed  ExpiredBy
aaaaaaaa-1111-bbbb-2222-cccccccccccc  xxxxxxxx-1111-yyyy-2222-zzzzzzzzzzzz  40                  False   1604913597
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

Kubernetes にアプリケーションをデプロイする

```bash
kubectl apply -f microservices-demo-0.1.4/release/kubernetes-manifests.yaml --namespace appdev-handson-ns
```

## ハンズオン資材の修正

以下コマンドで Kubernetes にクーポンサービスをデプロイする為の定義ファイルへ GCP プロジェクト固有の情報を設定する。(FIXME という文字列を GCP プロジェクト ID に置き換える)

```bash
sed -i".org" -e "s/FIXME/$GOOGLE_CLOUD_PROJECT/g" ~/cloudshell_open/gcp-getting-started-lab-jp/appdev/microservices-demo/kubernetes-manifests/couponservice.yaml
```

```bash
sed -i".org" -e "s/FIXME/$GOOGLE_CLOUD_PROJECT/g" ~/cloudshell_open/gcp-getting-started-lab-jp/appdev/microservices-demo/kubernetes-manifests/frontend.yaml
```

### Kubernetes 上にデプロイしたデモアプリケーションの動作確認

サービスへ接続する 外部 IP アドレス ( EXTERNAL-IP ) を以下のコマンドで確認します。
EXTERNAL-IP に 値が入っていない場合、もしくは\<pending\>になっている場合は時間を置いて再度確認用のコマンドを実行してください。

```bash
kubectl get service frontend-external -n appdev-handson-ns
```

上記コマンドを実行した結果の例 ( EXTERNAL-IPに値が入っている場合 )
```
NAME                TYPE           CLUSTER-IP    EXTERNAL-IP      PORT(S)        AGE
frontend-external   LoadBalancer   10.4.10.232   35.187.195.202   80:32692/TCP   2m19s
```

サービスへ接続する 外部 IP アドレス ( EXTERNAL-IP ) を環境変数へ設定する。

```bash
export FRONTEND_IP=$(kubectl get service frontend-external -n appdev-handson-ns -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
```

以下コマンドを実行し、ブラウザからアクセスするためのURLを取得する。

```bash
echo http://$FRONTEND_IP/
```

コマンド実行例
```
http://35.187.195.202/
```

取得したURLへアクセスし、アプリケーションにアクセスできることを確認する。
![BaseApp](https://github.com/GoogleCloudPlatform/gcp-getting-started-lab-jp/blob/master/appdev/tutorial-assets/BaseApp.png?raw=true)


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

## couponservice コンテナイメージの作成 ( Cloud Build にてビルド)

couponservice を Cloud Build を使ってコンテナをビルドし、couponservice:v1 というタグをつけて Container Registry にコンテナを登録する

```bash
cd ~/cloudshell_open/gcp-getting-started-lab-jp/appdev/microservices-demo/src/couponservice && gcloud builds submit --tag gcr.io/$GOOGLE_CLOUD_PROJECT/couponservice:v1
```

## Kubernetes マニフェストファイルの確認

先ほどビルドしたコンテナ ( couponservice:v1 ) を Kubernetes クラスターにデプロイするための修正がマニフェストファイルに反映されている事を確認する

```bash
cat ~/cloudshell_open/gcp-getting-started-lab-jp/appdev/microservices-demo/kubernetes-manifests/couponservice.yaml | grep "couponservice:v1"
```

出力画面の例
```
image: gcr.io/{{project-id}}/couponservice:v1
```

## couponservice のデプロイ

以下コマンドを実行し、マニュフェストファイルを使って、先程 Container Registry に登録したクーポンサービスのコンテナ ( couponservice:v1 ) を Kubernetes ( GKE ) のクラスター上にデプロイする

```bash
kubectl apply -f ~/cloudshell_open/gcp-getting-started-lab-jp/appdev/microservices-demo/kubernetes-manifests/couponservice.yaml --namespace appdev-handson-ns
```

以下コマンドを実行し、デプロイされたコンテナの情報を確認します。Container Registryに登録したクーポンサービスのコンテナがデプロイされていることを確認します。

```bash
kubectl describe deployment couponservice --namespace appdev-handson-ns
```

Imageのパスが、gcr.io/{{project-id}}/couponservice:v1 となっていることを確認します。

結果出力の例
```
...
server:
    Image:      gcr.io/{{project-id}}/couponservice:v1
...
```

# 3. クーポンサービスの組み込み

コンテナのデプロイは完了したため、クーポンサービスは Kubernetes 上で動いているが、他のマイクロサービスから呼び出されていない。そのため他のマイクロサービスから呼び出されるように変更を行う必要があります。本ハンズオンでは frontend サービスと couponservice を接続します。

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

## frontend コンテナイメージの作成 ( Cloud Build にてビルド)

frontend を Cloud Build を使ってコンテナをビルドし、frontend:v1 というタグをつけて Container Registry にコンテナを登録します

```bash
cd ~/cloudshell_open/gcp-getting-started-lab-jp/appdev/microservices-demo/src/frontend && gcloud builds submit --tag gcr.io/$GOOGLE_CLOUD_PROJECT/frontend:v1
```

## Kubernetes マニフェストファイルの確認

先ほどビルドしたコンテナ ( frontend:v1 ) を Kubernetes クラスターにデプロイするための修正がマニュフェストファイルに反映されている事を確認する

```bash
cat ~/cloudshell_open/gcp-getting-started-lab-jp/appdev/microservices-demo/kubernetes-manifests/frontend.yaml | grep "frontend:v1"
```

出力画面の例 ( xxxxx は 実際のGCPプロジェクトIDが入るため、実行する環境によって異なります )
```
image: gcr.io/xxxxx/frontend:v1
```

## frontend のデプロイ

以下コマンドを実行し、マニュフェストファイルを使って、先程 Container Registry に登録したクーポンサービスのコンテナ ( frontend:v1 ) を Kuberentes ( GKE ) のクラスター上にデプロイする

```bash
kubectl apply -f ~/cloudshell_open/gcp-getting-started-lab-jp/appdev/microservices-demo/kubernetes-manifests/frontend.yaml --namespace appdev-handson-ns
```

以下コマンドを実行し、デプロイされたコンテナの情報を確認します。Container Registryに登録したクーポンサービスのコンテナがデプロイされていることを確認します。

```bash
kubectl describe deployment frontend --namespace appdev-handson-ns
```

Imageのパスが、gcr.io/xxxxx/frontend:v1 となっていることを確認します。

結果出力の例 ( xxxxx は 実際のGCPプロジェクトIDが入るため、実行する環境によって異なります )
```
...
server:
    Image:      gcr.io/xxxxx/frontend:v1
...
```

## 動作確認

ブラウザからアプリケーションにアクセスし、クーポン ( Special Coupon: xx% OFF ... ) が表示される事を確認する。

```bash
echo http://$FRONTEND_IP/
```

![V1App](https://github.com/GoogleCloudPlatform/gcp-getting-started-lab-jp/blob/master/appdev/tutorial-assets/V1App.png?raw=true)

# 4. クーポンサービスの改善

Spanner を使ってクーポンの払い出しに関するデータを永続化する。

## ソースコードの修正

appdev/microservices-demo/src/couponservice/src/main/java/hipstershop/CouponService.java

- `Collection<Coupon> coupons = service.getCouponsBySessionId(req.getSessionId());`をコメントアウトする。
- `Collection<Coupon> coupons = service.getCouponsBySessionIdWithSpanner(req.getSessionId());`をコメントインする。

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

<walkthrough-editor-open-file filePath="cloudshell_open/gcp-getting-started-lab-jp/appdev/microservices-demo/src/couponservice/src/main/java/hipstershop/CouponService.java">
ファイルを Cloud Shell Editor で開く
</walkthrough-editor-open-file>

## コンテナイメージの作成 ( CloudBuild にてビルド )

修正後の couponservice を Cloud Build を使ってコンテナをビルドし、couponservice:v2 というタグをつけて Container Registry にコンテナを登録する

```bash
cd ~/cloudshell_open/gcp-getting-started-lab-jp/appdev/microservices-demo/src/couponservice && gcloud builds submit --tag gcr.io/$GOOGLE_CLOUD_PROJECT/couponservice:v2
```

## Spanner へのクーポンデータ追加

### クーポン期限の設定 ( 3 時間後のエポック秒 )

```bash
export COUPON_EXPIREDBY=$(python3 -c "import time; print(int(time.time()) + 10800);")
```

### セッション ID の設定

ブラウザでアプリケーションにアクセスし、画面下部にある SessionId をメモする。

```bash
echo http://$FRONTEND_IP/
```

```
例
session-id: 42d37f1b-21cc-4bf8-bd63-1775545e870a
```

![CheckSession](https://github.com/GoogleCloudPlatform/gcp-getting-started-lab-jp/blob/master/appdev/tutorial-assets/CheckSession.png?raw=true)


以下コマンドを実行し、環境変数に調べたセッション ID を設定する

```bash
export USER_SESSION_ID=42d37f1b-21cc-4bf8-bd63-1775545e870a
```

以下コマンドを実行し、Spanner にいま開いているセッションに対してのみクーポンを表示するためのデータを追加(Insert)します。

```bash
gcloud spanner rows insert --database=appdev-db \
      --table=Visitors \
      --data=SessionId=$USER_SESSION_ID
```

```bash
gcloud spanner rows insert --database=appdev-db \
      --table=Coupons \
      --data=SessionId=$USER_SESSION_ID,CouponId=xxxxxxxx-1111-yyyy-2222-zzzzzzzzzzzz,DiscountPercentage=40,IsUsed=false,ExpiredBy=$COUPON_EXPIREDBY
```

## Kubernetes に修正したクーポンサービスをデプロイする

### Kubernetes のマニュフェストファイルを修正する

appdev/microservices-demo/kubernetes-manifests/couponservice.yaml を以下の通り修正する。
xxxxx はプロジェクト ID に読み替えて実行する。

```
修正前
image: gcr.io/xxxxx/couponservice:v1

修正後
image: gcr.io/xxxxx/couponservice:v2
```

<walkthrough-editor-open-file filePath="cloudshell_open/gcp-getting-started-lab-jp/appdev/microservices-demo/kubernetes-manifests/couponservice.yaml">
ファイルを Cloud Shell Editor で開く
</walkthrough-editor-open-file>

### 新しいアプリケーションをデプロイする

以下コマンドを実行し、マニュフェストファイルを使って、先程 Container Registry に登録したクーポンサービスのコンテナ ( couponservice:v2 ) を Kuberentes ( GKE ) のクラスター上にデプロイします

```bash
kubectl apply -f ~/cloudshell_open/gcp-getting-started-lab-jp/appdev/microservices-demo/kubernetes-manifests/couponservice.yaml --namespace appdev-handson-ns
```

以下コマンドを実行し、デプロイされたコンテナの情報を確認します。Container Registryに登録したクーポンサービスのコンテナがデプロイされていることを確認します。

```bash
kubectl describe deployment couponservice --namespace appdev-handson-ns
```

Imageのパスが、gcr.io/{{project-id}}/couponservice:v2 となっていることを確認します。

結果出力の例
```
...
server:
    Image:      gcr.io/{{project-id}}/couponservice:v2
...
```

## 動作確認

ブラウザでアプリケーションにアクセスし、Spanner に保存したクーポンが表示される事を確認する。

```bash
echo http://$FRONTEND_IP/
```

![V2App](https://github.com/GoogleCloudPlatform/gcp-getting-started-lab-jp/blob/master/appdev/tutorial-assets/V2App.png?raw=true)


# 5. (Advanced) クーポンサービスの高度化

### 有効な期限内のクーポンだけを返却する機能を追加

CouponService に 有効なクーポンだけを返却する機能を追加する。CouponService に新しい RPC (getValidCoupons) として実装すること。CouponService に機能実装した後は FrontendService から新しい RPC を呼び出し、有効なクーポンだけを表示する。検証時は Spanner に無効なクーポンを追加し、これらが表示されない事を確認すること。

# おめでとうございます！

<walkthrough-conclusion-trophy></walkthrough-conclusion-trophy>

フルマネージド Kubernetes サービス「Kubernetes Engine」や、フルマネージド リレーショナル データベースサービス「Cloud Spanner」 をはじめとした、GCP 開発者向けサービスを使用したマイクロサービス アプリケーションの開発について学ぶハンズオンは完了です。

必要な方はデモで使った資材が不要な方はクリーンアップを行って下さい。

# クリーンアップ

## プロジェクトごと削除

作成した資材を個別に削除する場合は、こちらのページの手順を実施せずに次のページに進んで下さい。

### プロジェクトの削除

```bash
gcloud projects delete $GOOGLE_CLOUD_PROJECT
```

### GCP のデフォルトプロジェクト設定の削除

```bash
gcloud config unset project
```

## ハンズオンで利用した資材の個別削除

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

```bash
gcloud spanner databases delete appdev-db --instance=appdev-handson-instance --project=$GOOGLE_CLOUD_PROJECT
```

### Spanner インスタンス削除

```bash
gcloud spanner instances delete appdev-handson-instance --project=$GOOGLE_CLOUD_PROJECT
```

## GCP のデフォルトプロジェクト設定の削除

```bash
gcloud config unset project
```
