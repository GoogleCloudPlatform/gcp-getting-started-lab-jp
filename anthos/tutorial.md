# Anthos ワークショップ

## Google Cloud Platform（GCP）プロジェクトの選択

ハンズオンを行う GCP プロジェクトを選択し、 **Start** をクリックしてください。

<walkthrough-project-setup>
</walkthrough-project-setup>

## 環境準備

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

<walkthrough-footnote>次にハンズオンで利用する機能を有効化します。</walkthrough-footnote>

## GCP 環境設定

GCP では利用したい機能ごとに、有効化を行う必要があります。
ここでは、以降のハンズオンで利用する機能を事前に有効化しておきます。

### ハンズオンで利用する GCP の API を有効化する

```bash
gcloud services enable servicemanagement.googleapis.com compute.googleapis.com
```

`Operation 〜 finished successfully.` と表示が出ることを確認します。

**GUI**: [API ライブラリ](https://console.cloud.google.com/apis/library?project={{project-id}})

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

<walkthrough-footnote>必要な機能が使えるようになりました。次にワークショップ環境を確認します</walkthrough-footnote>


## ワークショップ環境の確認

本ワークショップを実行するための、プロジェクト環境が整っているかを確認します。

```bash
curl -sL https://github.com/GoogleCloudPlatform/anthos-sample-deployment/releases/latest/download/asd-prereq-checker.sh | sh -
```

問題がない場合は、下記のように出力されます。各項目が `PASS` となっていることを確認してください。

```
Your active configuration is: [cloudshell-4100]
Checking project my-project-id, region us-central1, zone us-central1-c

PASS: User has permission to create service account with the required IAM policies.
PASS: Org Policy will allow this deployment.
PASS: Service Management API is enabled.
PASS: Anthos Sample Deployment does not already exist.
PASS: Project ID is valid, does not contain colon.
PASS: Project has sufficient quota to support this deployment.
```

## Anthos Service Deployment のデプロイ

Anthos Service Deployment は Marketplace からデプロイします。

### Marketplace へのアクセス

Marketplace の該当ページを開きます。

[Anthos Service Deployment](https://console.cloud.google.com/marketplace/details/click-to-deploy-images/anthos-sample-deployment?_ga=2.170683168.162888297.1597114669-1679921833.1550801382&project={{project-id}})

### 事前設定の適用

`運用開始` をクリックし、事前設定を適用します。完了に数分かかります。ここではいくつか必要な API を有効化しています。

### デプロイするゾーンの選択

`Deployment Zone` から台湾リージョンのうちの 1 ゾーン `asia-east1-b` を選択します。

### 事前設定の確認

`Confirm that all prerequisites have been met.` のチェックボックスにチェックを入れます。

### デプロイの開始

ページ最下部の `デプロイ` ボタンをクリックします。デプロイの完了には最大 15 分程度かかります。

## Anthos の UI へアクセス

Anthos の UI にアクセスします。

[Anthos](https://console.cloud.google.com/anthos?project={{project-id}})

Anthos の専用 UI からは、下記のような各種コンポーネントが確認できます。

- サービスメッシュ（Anthos Service Mesh）
- 構成管理（Anthos Config Management）
- クラスタ (Anthos に登録しているクラスタ)
- コンテナへの移行（Migrate for Anthos）

## Anthos Service Mesh（ASM） からサービスの確認

### ASM の UI にアクセス

Anthos Service Mesh の UI にアクセスします。

[サービス メッシュ](https://console.cloud.google.com/anthos/services?project={{project-id}})

合計 8 のサービスが稼働していることを確認します。

### 各種サービスのトポロジグラフを表示

8 のサービスが連携し、サンプル銀行サイトを作り上げています。右上の `トポロジ` をクリックし、トポロジグラフを表示します。

### トポロジグラフの詳細を確認する

トポロジグラフでは下記のような様々な情報が確認できます。

- 各種サービスがどのように連携しているか
- サービス間のリクエスト数（QPS）
- サービスの状態（Healthy かどうか）
- Kubernetes リソースの情報（Pod, Replica Set, Deployment Service など）

UI の色々なところをクリックし、サービスの各種情報を確認してみてください。

## SLO の設定

### ledgerwriter の UI へアクセス

[ledgerwriter](https://console.cloud.google.com/anthos/services/service/boa/ledgerwriter/overview?project={{project-id}})

### SLO の作成を開始

`SLO を作成`ボタンをクリックします。

### サービスレベル指標（SLI）の設定

1. **指標の選択** で `レイテンシ`をチェックします。
2. **リクエスト ベースまたは Windows ベースの選択** で `リクエスト ベース`をチェックします。
3. `続行` のボタンをクリックします。

### SLI の詳細を定義する

1. **パフォーマンス指標** の `レイテンシのしきい値` に `10` を入力します。(10 ミリ秒)
2. `続行` のボタンをクリックします。

### サービスレベル指標（SLO）の設定

1. **コンプライアンス期間** の `期間の種類` を `連続` にします。
2. **期間の長さ** に `1` を入力します。(1 日)
3. **パフォーマンス目標** の `目標` に `90` を入力します。(90%)
4. `続行` のボタンをクリックします。

### 確認と保存

1. **SLO の詳細** の `表示名` が `90% - レイテンシ - 連続日` になっていることを確認します。
2. `SLO を作成` をクリックします。

## ステータスの確認

### エラーステータスの確認

しきい値を現在のレイテンシより低く設定したため、`ステータス` が `エラーバジェット外` になっていることを確認します。

### トポロジグラフでのエラーステータスの確認

前の手順で表示したトポロジグラフを表示し、エラーステータスが表示されていることを確認します。

### アラートポリシーを設定する（オプション）

SLO には、アラートポリシーを設定することができます。そうすることで、指定の条件が満たされたときにアラートをトリガーすることが可能です。

## Cloud Shell の環境設定

ここからは CLI を中心に設定を行います。そのための環境を整えます。

### 初期化スクリプトをダウンロードする

```bash
curl -sLO https://github.com/GoogleCloudPlatform/anthos-sample-deployment/releases/latest/download/init-anthos-sample-deployment.env
```

### 初期化スクリプトを実行する

```bash
source init-anthos-sample-deployment.env
```

### Git の設定

Git コマンドで利用するメールアドレス、ユーザー名を設定します。

```bash
git config --global user.email "you@example.com"
```

```bash
git config --global user.name "Your Name"
```

メールアドレス、名前は何でも構いません。（上のコマンドそのままでも大丈夫です）

### 作業ディレクトリ（Anthos Config Management の管理ディレクトリ）に移動する

```bash
cd anthos-sample-deployment-config-repo
```

## サンプルサイト（Bank of Anthos）の確認

### アクセスするための IP アドレスを取得

```bash
export BOA_IP=$(kubectl get svc istio-ingressgateway -n istio-system -ojsonpath='{.status.loadBalancer.ingress[0].ip}')
```

### ブラウザからサイトにアクセスし、ページを確認

```bash
echo "http://${BOA_IP}/"
```

## サンプルアプリの入れ替え - Bank of Anthos の削除 -

現在動いているサンプルアプリ Bank of Anthos を Online Boutique に切り替えます。`kubectl` からではなく、Anthos Config Management の GitOps を活用し手順を進めます。

### 現在動いているアプリを削除

```bash
rm -r namespaces/boa
```

### 削除をコミットし、クラスタへの反映を確認

```bash
git add . && git commit -m "delete Bank of Anthos" && git push origin master && watch -n 1 nomos status
```

Sync Status が `PENDING` から `SYNCED` になったら、Ctrl+C で watch コマンドを終了します。

**GUI**: [こちら](https://console.cloud.google.com/anthos/services?project={{project-id}})からもサービスが消えていることが確認できます

## サンプルアプリの入れ替え - Online Boutique のデプロイ -

### Online Boutique 用フォルダの作成

ob という名前空間を使います。

```bash
mkdir namespaces/ob
```

### マニフェストのコピー

```bash
cp ../k8s-manifest/kubernetes-manifests.yaml namespaces/ob/ && cp ../k8s-manifest/istio-manifests.yaml namespaces/ob/ && cp ../k8s-manifest/namespace-ob.yaml namespaces/ob/
```

### Online Boutique のデプロイ

```bash
git add . && git commit -m "deploy online boutique" && git push origin master && watch -n 1 nomos status
```

Sync Status が `PENDING` から `SYNCED` になったら、Ctrl+C で watch コマンドを終了します。

### 動作確認

```bash
export OB_IP=$(kubectl get svc istio-ingressgateway -n istio-system -ojsonpath='{.status.loadBalancer.ingress[0].ip}') && echo "http://${OB_IP}/"
```

ブラウザからアクセスして、Online Boutique（EC サイト）が見えることを確認します。 今後、この URL を使いトラフィック管理の動作確認を行います。

## ASM を活用したトラフィック管理

ASM（Istio）には下記のような、様々なトラフィック管理機能があります。

- リクエストルーティング
- フォールトインジェクション
- サーキットブレーカー
- タイムアウト
- リトライ

ここから ASM を使い、リクエストルーティング、フォールトインジェクションを試します。

## リクエストルーティング

リクエストルーティングとは、アプリケーションのコードを触らずに ASM の設定でアクセス先をコントロールすることを言います。
この機能を使うことでカナリアリリース、ブルーグリーンデプロイメントなどが実現できます。

ここでは frontend サービスを対象に本機能を試します。

### 現状の frontend の確認

現在、frontend は下記のリソースで構成されています。(すべて ob 名前空間内)

- Deployment

  - frontend(1 Pod)

- Service

  - frontend
  - frontend-external

- VirtualService

  - frontend
  - frontend-ingress

frontend の Deployment にバージョン情報がついていないことを確認します。

```bash
kubectl get deploy frontend -n ob -oyaml | grep -A2 -i label
```

## 新しい frontend-v1, v2 を作成

v1, v2 はそれぞれ下記のような挙動をします。

- v1

  - 環境が Google Cloud と表示される
  - Replica 数は 1

- v2

  - 環境が AWS と表示される
  - Replica 数は 1

### v1, v2 のマニフェストをコピー

```bash
cp ../k8s-manifest/frontend-v[0-9]*.yaml namespaces/ob/
```

参考: `frontend-v1.yaml`

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: frontend-v1
spec:
  replicas: 1
  selector:
    matchLabels:
      app: frontend
      version: v1
〜
          - name: ENV_PLATFORM
            value: "gcp"
〜
```

参考: `frontend-v2.yaml`

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: frontend-v2
spec:
  replicas: 1
  selector:
    matchLabels:
      app: frontend
      version: v2
〜
          - name: ENV_PLATFORM
            value: "aws"
〜
```

## 新しい v1, v2 をデプロイ

### v1, v2 のマニフェストを反映し、Deployment を作成

```bash
git add . && git commit -m "create frontend-v1, v2" && git push origin master && watch -n 1 nomos status
```

Sync Status が `PENDING` から `SYNCED` になったら、Ctrl+C で watch コマンドを終了します。

## （オプション）全サービスを正常な状態に復旧

先程デプロイした Online Boutique の全サービスが正しく稼働しているかを確認し、問題があれば対応を行います

### Deployment の確認（CLI）

```bash
kubectl get deployment -n ob
```

### Deployment の確認（GUI）

[こちら](https://console.cloud.google.com/kubernetes/workload?project={{project-id}})からステータスを確認します。

### （ちゃんと稼働していないサービスがあった場合）復旧

リソース不足（すべてのコンテナを動かすための VM のリソース）のため `Pending` 状態のサービスがある場合、クラスタのノードを増やし対応します。

```bash
gcloud container clusters resize anthos-sample-cluster1 --size 4 --zone asia-east1-b
```

コマンドが完了後、少し待ち `Pending` になっていたサービスが `OK` ステータスになっていることを確認します。

## 負荷分散状況の確認

frontend に 40 回アクセスし、どちらが何回表示されるかを確認します。

```bash
for i in {{1..40}}; do curl -s http://${OB_IP}/ | grep -A1 'platform-flag' | grep -e 'AWS' -e 'Google Cloud'; done | sort | uniq -c
```

何度試してみても、`Google Cloud` の方が多く表示されるはずです。なぜそのような結果になるか考えてみましょう。

次のページで、答えを記載します。

## ASM を利用したリクエストルーティング

### 回答

前のページの状態は、v1, v2 を追加しただけで、バージョンを使ったルーティングをしていませんでした。
つまり、Kubernetes のデフォルトの挙動 ＝ Pod の数に基づいた負荷分散が行われていました。

Pod の数は以下です。

- `Google Cloud` × 2 (バージョン無し、v1 の Pod)
- `AWS` × 1 (v2 の Pod)

そのため、大体 2 : 1 の割合でアクセスが分かれていました。

### ポイント

Kubernetes でもカナリアリリースのようなリクエストルーティングが可能ですが、柔軟性に欠け、下記のようなケースの対応が困難です。

- 10 % のアクセスを新しいバージョンに割り振りたいが、新バージョンは負荷が読めないため自動でスケールするようにしたい
- 3 つ以上のバージョンを取り扱いたい

<walkthrough-footnote>次に ASM(Istio) の機能を活用し、Pod 数に関わらず、1 : 1 にアクセスが割り振られるように設定します</walkthrough-footnote>

## バージョンに基づいたリクエストルーティング

### バージョンが含まれる DestinationRule のコピー

```bash
cp ../k8s-manifest/frontend-dr.yaml namespaces/ob/
```

参考: `frontend-dr.yaml`

```yaml
apiVersion: networking.istio.io/v1alpha3
kind: DestinationRule
metadata:
  name: frontend-dr
spec:
  host: frontend
  subsets:
    - name: v1
      labels:
        version: v1
    - name: v2
      labels:
        version: v2
```

### frontend の VirtualService を バージョンを識別するように修正

```bash
patch namespaces/ob/istio-manifests.yaml ../k8s-manifest/istio-manifests.yaml.patch
```

参考: 修正後の `istio-manifests.yaml`

```yaml
apiVersion: networking.istio.io/v1alpha3
kind: VirtualService
metadata:
  name: frontend-ingress
spec:
  hosts:
    - "*"
  gateways:
    - frontend-gateway
  http:
    - route:
        - destination:
            host: frontend
            subset: v1
            port:
              number: 80
          weight: 50
        - destination:
            host: frontend
            subset: v2
            port:
              number: 80
          weight: 50
```

## 新しい VirtualService, DestinationRule をデプロイ

```bash
git add . && git commit -m "apply new VirtualService and DestinationRule" && git push origin master && watch -n 1 nomos status
```

Sync Status が `PENDING` から `SYNCED` になったら、Ctrl+C で watch コマンドを終了します。

### 負荷分散状況の再確認

frontend に 40 回アクセスし、どちらが何回表示されるかを確認します。

```bash
for i in {{1..40}}; do curl -s http://${OB_IP}/ | grep -A1 'platform-flag' | grep -e 'AWS' -e 'Google Cloud'; done | sort | uniq -c
```

うまく設定が反映されている場合、大体同じ数値になるはずです。

<walkthrough-footnote>ASM を利用し、リクエストルーティングを行いました。Kubernetes での負荷分散と違い、Pod の数と関係なくリクエストを制御できました</walkthrough-footnote>

## フォールトインジェクション

フォールトインジェクションとは、特定のサービスに対して下記のような挙動を挿入することを言います。

- ディレイ（遅延）
- 失敗

アプリケーションのコードを変更せずに、下記のようなことが可能になります。

- 20 % の確率でサービス A は 5 秒レスポンスが遅延する
- 50 % の確率でサービス B が 500 エラーを返す

## cartservice へのフォールト（失敗）の挿入

cartservice が 20 % の確率で 500 エラーを返すように設定します。

### フォールトを挿入する VirtualService のコピー

```bash
cp ../k8s-manifest/cartservice-fault.yaml namespaces/ob/
```

参考: `cartservice-fault.yaml`

```yaml
apiVersion: networking.istio.io/v1alpha3
kind: VirtualService
metadata:
  name: cartservice
spec:
  hosts:
    - cartservice
  http:
    - fault:
        abort:
          httpStatus: 500
          percentage:
            value: 20
      route:
        - destination:
            host: cartservice
```

## フォールトを挿入する VirtualService をデプロイ

### 新しい VirtualService のマニフェストを反映

```bash
git add . && git commit -m "add new VirtualService for cartservice" && git push origin master && watch -n 1 nomos status
```

Sync Status が `PENDING` から `SYNCED` になったら、Ctrl+C で watch コマンドを終了します。

### 失敗状況の確認

frontend に 40 回アクセスし、どの程度アクセスが失敗するかを確認します。

```bash
for i in {{1..40}}; do curl -sI http://${OB_IP}/ | grep HTTP; done | sort | uniq -c
```

うまく設定が反映されている場合、20 % の割合 = 大体 8 回程度 500 エラーが返ってくるはずです。

<walkthrough-footnote>ASM を利用し、フォールトインジェクションを行いました。アプリケーションに手を入れずに、特定のマイクロサービスの挙動を変えることができました</walkthrough-footnote>

## チャレンジ問題

### ディレイ（遅延）の挿入

currencyservice に固定で 1 秒の遅延を挿入してみましょう。

またそのときにどのような挙動になるかを想定し、実際の挙動を比べてみてください。そして想定と違った場合、なぜ異なっていたかを調べてみてください。

**ヒント**:[フォールトインジェクション](https://istio.io/latest/docs/tasks/traffic-management/fault-injection/) を参考にしてみてください。

## 環境の初期化

ここまで一つのクラスタ上で作業を行ってきました。

ここからは新しいクラスタを追加で 1 つ用意し、分散サービスを構築していきます。

## 新しいクラスタの作成

冗長性を確保するため、新しいクラスタを別のリージョンに作成します。

**注**: tutorial.md がおいてあるフォルダに移動すること

```bash
bash scripts/01_create_clusters.sh
```

新しいクラスタは Los Angels に作成します。

**参考**: クラスタの作成が完了するまでに、最大 10 分程度時間がかかることがあります。

**GUI**: [クラスタ](https://console.cloud.google.com/kubernetes/list?project={{project-id}})

## 作成したクラスタのコンテキスト設定

作成したクラスタを `anthos-sample-cluster2` というコンテキスト名で操作できるように設定を行います。

```bash
bash scripts/02_get_credentials.sh
```

### コンテキストの確認

2 つのコンテキストが正しく設定されたかを確認します。

```bash
kubectl config get-contexts -o name
```

出力例:

```
〜
anthos-sample-cluster2
〜
```

## クラスタ権限設定

今回利用しているサービスアカウントが、クラスタの操作を行えるように権限を付与します。

```bash
bash scripts/03_create_rolebindings.sh
```

出力例:

```
clusterrolebinding.rbac.authorization.k8s.io/cluster-admin-binding created
```

## クラスタの Anthos 管理下への登録

作成したクラスタを Anthos の管理下に登録します。

```bash
bash scripts/04_register_clusters_to_hub.sh
```

この手順を行うことで、Anthos の機能が利用できるようになります。またこの登録を行ったクラスタに対して Anthos のライセンスコストが掛かることになります。

### 登録状況の確認

正しくクラスタが登録できたかを確認します。

```bash
gcloud container hub memberships list
```

[Anthos UI](https://console.cloud.google.com/anthos?project={{project-id}})からも確認が可能です。

## zoneprinter サービスのデプロイ

それぞれのクラスタに同じアプリケーションを導入します。

### 名前空間の作成

アプリケーション用の名前空間 `zoneprinter` を作成します。

```bash
kubectl apply -f k8s-manifest/zonens.yaml --context anthos-sample-cluster1
```

```bash
kubectl apply -f k8s-manifest/zonens.yaml --context anthos-sample-cluster2
```

参考: `zonens.yaml`

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: zoneprinter
```

## zoneprinter Deployment のデプロイ

`zoneprinter` というアプリケーションをそれぞれのクラスタにデプロイします。

```bash
kubectl apply -f k8s-manifest/zonedeploy.yaml --context anthos-sample-cluster1
```

```bash
kubectl apply -f k8s-manifest/zonedeploy.yaml --context anthos-sample-cluster2
```

参考: `zonedeploy.yaml`

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: zone-ingress
  namespace: zoneprinter
  labels:
    app: zoneprinter
spec:
  selector:
    matchLabels:
      app: zoneprinter
  template:
    metadata:
      labels:
        app: zoneprinter
    spec:
      containers:
        - name: frontend
          image: gcr.io/google-samples/zone-printer:0.2
          ports:
            - containerPort: 8080
```

### Pod の確認

アプリケーションがちゃんと起動しているかを確認します。

```bash
kubectl get pod -n zoneprinter --context anthos-sample-cluster1
```

```bash
kubectl get pod -n zoneprinter --context anthos-sample-cluster2
```

## Ingress for Anthos の導入

Ingress for Anthos は異なるリージョンのクラスタに配置されているサービスを、インテリジェントに負荷分散する機能です。下記のような特徴があります。

- 1 IP アドレスでの公開
- 利用者の近いクラスタに自動的にアクセスを振り分け
- サービスのヘルスチェック

### Ingress for Anthos の有効化

```bash
gcloud services enable multiclusteringress.googleapis.com
```

### Config Cluster の設定

Config Cluster とは Ingress for Anthos の設定を担当するクラスタで、1 つのみ設定が可能です。

```bash
gcloud alpha container hub ingress enable --config-membership=projects/{{project-id}}/locations/global/memberships/anthos-sample-cluster1
```

ここでは Anthos Sample Deployment により作成されたクラスタを対象にします。

## Ingress for Anthos 関連リソースの作成

Ingress for Anthos では複数のリージョンに置かれているサービスをまとめるため、専用のリソースが用意されています。

- MultiClusterService
- MultiClusterIngress

**ポイント**: これらのリソースは設定を担当する `Config Cluster` のみに作成することに注意してください。

### MultiClusterService の作成

```bash
kubectl apply -f k8s-manifest/mcs.yaml --context anthos-sample-cluster1
```

参考: `mcs.yaml`

```yaml
apiVersion: networking.gke.io/v1
kind: MultiClusterService
metadata:
  name: zone-mcs
  namespace: zoneprinter
spec:
  template:
    spec:
      selector:
        app: zoneprinter
      ports:
        - name: web
          protocol: TCP
          port: 8080
          targetPort: 8080
```

## MultiClusterIngress の作成

```bash
kubectl apply -f k8s-manifest/mci.yaml --context anthos-sample-cluster1
```

参考: `mci.yaml`

```yaml
apiVersion: networking.gke.io/v1
kind: MultiClusterIngress
metadata:
  name: zone-ingress
  namespace: zoneprinter
spec:
  template:
    spec:
      backend:
        serviceName: zone-mcs
        servicePort: 8080
```

## Ingress for Anthos の動作確認

### MultiClusterIngress の確認

MultiClusterIngress のステータスを確認します。

```bash
watch -n 5 kubectl describe mci zone-ingress -n zoneprinter --context anthos-sample-cluster1
```

出力の下部に `VIP` が出ていない場合、少しお待ち下さい。

### ブラウザからのアクセス確認

VIP に記載されていた IP アドレスにブラウザからアクセスをします。

正しく稼働している場合、アクセス先の場所情報が表示されます。

**注意**: アクセスが可能になるまで最大 10 分程度かかる場合があります。

## フェイルオーバー

みなさんがアクセスをしているリージョンの Deployment を削除し、正しくフェイルオーバーされるかを確認してみましょう。

### 台湾リージョンの Deployment を削除する場合

```bash
kubectl delete -f k8s-manifest/zonedeploy.yaml --context anthos-sample-cluster1
```

### US リージョンの Deployment を削除する場合

```bash
kubectl delete -f k8s-manifest/zonedeploy.yaml --context anthos-sample-cluster2
```

## チャレンジ問題

### ワークロードが復旧した場合の挙動確認

先程削除した Deployment を再稼働させアクセスがどのようになるか確認してみてください。

### アクセス元による挙動の確認

先程作成した VIP に様々なロケーションからアクセスをしてみてください。
アクセス方法はどのような形でも構いません。

例:

- Compute Engine を使い、アクセス
- GKE のコンテナからアクセス
- 外部サービスを使ってアクセス

同じ IP アドレスへのアクセスでも、アクセス元の場所によりルーティングされる先が変わります。

## Congraturations!

<walkthrough-conclusion-trophy></walkthrough-conclusion-trophy>

これにて Anthos の各種コンポーネントを利用したワークショップは完了です！！

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

### ハンズオン資材の削除

```bash
cd $HOME && rm -rf cloudshell_open
```
