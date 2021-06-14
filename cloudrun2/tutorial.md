# Cloud Run ハンズオン

## Google Cloud Platform（Google Cloud）プロジェクトの選択

ハンズオンを行う Google Cloud プロジェクトを作成し、 Google Cloud プロジェクトを選択して **Start/開始** をクリックしてください。

<walkthrough-project-setup></walkthrough-project-setup>

<walkthrough-watcher-constant key="region" value="asia-northeast1"></walkthrough-watcher-constant>
<walkthrough-watcher-constant key="db-instance-name" value="handson-db"></walkthrough-watcher-constant>
<walkthrough-watcher-constant key="db-name" value="handson"></walkthrough-watcher-constant>
<walkthrough-watcher-constant key="repo-name" value="handson"></walkthrough-watcher-constant>
<walkthrough-watcher-constant key="topic-id" value="eats_events_topic"></walkthrough-watcher-constant>
<walkthrough-watcher-constant key="sub-id" value="eats_events_sub"></walkthrough-watcher-constant>
<walkthrough-watcher-constant key="schema-name" value="eats_events_schema"></walkthrough-watcher-constant>

<!-- Step 1 -->
## はじめに

### **内容と目的**

本ハンズオンでは、Cloud Run を中心にいくつかの Google Cloud サービスを利用して 宅配ピザの注文APIと通知サービスを模擬したサンプルアプリケーションを構築して頂きます。
本ハンズオンを通じて、 Cloud Run の基本的な使い方に加え、 Cloud Run と他 Google Cloud サービスをどのように組み合わせて本格的なアプリケーションを構成するのか学んで頂くことが目的です。

### **前提条件**

本ハンズオンは、はじめて Cloud Run に触れる方を想定しており、 事前知識がなくとも本ハンズオンの進行には影響ありません。
ハンズオン中で使用する Google Cloud サービスについてより詳しく知りたい方は、Coursera の教材や公式ドキュメントを使い学んでいただくことをお勧めします。

### **本ハンズオンで利用するサービス**

- [Cloud Run](https://cloud.google.com/run?hl=ja)
- [Cloud SQL](https://cloud.google.com/sql/?hl=ja)
- [Cloud Pub/Sub](https://cloud.google.com/pubsub/?hl=ja)
- [Artifact Registry](https://cloud.google.com/artifact-registry?hl=ja)
- [Cloud Build](https://cloud.google.com/build?hl=ja)

### **本ハンズオンで利用している主なテクノロジー**

- [Go 言語](https://golang.org/)
- [Restful API](https://e-words.jp/w/RESTful_API.html)
- [gRPC](https://grpc.io/) (Server-side streaming)
- [MySQL](https://www.mysql.com/jp/)
- [メッセージングキュー](https://e-words.jp/w/%E3%83%A1%E3%83%83%E3%82%BB%E3%83%BC%E3%82%B8%E3%82%AD%E3%83%A5%E3%83%BC%E3%82%A4%E3%83%B3%E3%82%B0.html) (Pub/Sub モデル)　
- [コンテナ](https://github.com/opencontainers/image-spec) (a.k.a Docker)

### **本ハンズオンのサンプルアプリケーション概要**
#### **アーキテクチャ図** ####
![architecture](https://storage.googleapis.com/handson-images/eats-architecture-overview.png)

#### **DBスキーマ** ####
![db_schema](https://storage.googleapis.com/handson-images/eats-db-schema.png)

<!-- Step 2 -->
## ハンズオンの内容

下記の通りハンズオンを進めます。

### **ステップ**
- 環境準備 : 10 分
    - gcloud コマンドラインツール設定
    - 利用する Google Cloud サービスの API 有効化
    - サービスアカウント設定


-  Eats サービス (注文API) の構築 : 30 分
    - Cloud SQL インスタンスの新規作成
    - Eats サービスのソースコードからコンテナイメージをビルド
    - ビルドしたコンテナイメージを Artifact Registry へプッシュ
    - Cloud Run へ Eats サービスのコンテナイメージをデプロイ
    - 動作確認
        - Eats サービスへの CRUD 
        - Cloud Run のオートスケール機能を確認

    
- Notification サービス (プッシュ通知) の構築 : 30 分
    - Cloud Pub/Sub のトピック・サブスクリプションの新規作成
    - Eats サービスのコード修正 (v2)
    - 以下のコンテナイメージをビルド、Artifact Registry へプッシュ
      - Eats サービス v2
      - Notification サーバー
      - Notification クライアント
    - Cloud Run へ各コンテナイメージをデプロイ
    - 動作確認
        - Eats サービスのイベントに合わせて通知がクライアントに飛んでくることの確認
        - Cloud Run の段階的ロールアウト・ロールバック機能を確認
    
    
- クリーンアップ : 10 分
    - プロジェクトごと削除
    - （オプション）個別リソースの削除
        - Cloud Run の削除
        - Cloud SQL の削除
        - Cloud Pub/Sub の削除
        - Artifact Registry に登録したコンテナイメージの削除
        - サービスアカウント handson-sa の削除


<!-- Step 3 -->
## 環境準備

<walkthrough-tutorial-duration duration=10></walkthrough-tutorial-duration>

最初に、ハンズオンを進めるための環境準備を行います。

下記の設定を進めていきます。

- gcloud コマンドラインツール設定
- 利用する Google Cloud サービスの API 有効化
- サービスアカウント設定


<!-- Step 4 -->
## gcloud コマンドラインツール

Google Cloud は、CLI、GUI、Rest API から操作が可能です。ハンズオンでは主に CLI を使い作業を行いますが、GUI で確認する URL も併せて掲載します。


### gcloud コマンドラインツールとは?

gcloud コマンドライン インターフェースは、Google Cloud でメインとなる CLI ツールです。このツールを使用すると、コマンドラインから、またはスクリプトや他の自動化により、多くの一般的なプラットフォーム タスクを実行できます。

たとえば、gcloud CLI を使用して、以下のようなものを作成、管理できます。

- Google Compute Engine 仮想マシン
- Google Kubernetes Engine クラスタ
- Google Cloud SQL インスタンス

**ヒント**: gcloud コマンドラインツールについての詳細は[こちら](https://cloud.google.com/sdk/gcloud?hl=ja)をご参照ください。

<walkthrough-footnote>次に gcloud CLI をハンズオンで利用するための設定を行います。</walkthrough-footnote>


<!-- Step 5 -->
## gcloud コマンドラインツール設定

gcloud コマンドでは操作の対象とするプロジェクトの設定が必要です。

### Google Cloud のプロジェクト ID を環境変数に設定

環境変数 `PROJECT_ID` に Google Cloud のプロジェクト ID を設定します。

```bash
export PROJECT_ID={{project-id}}
```

### CLI（gcloud コマンド） から利用する Google Cloud のデフォルトプロジェクトを設定

操作対象のプロジェクトを設定します。
権限を与えるための確認画面が出たら承認して進めます。

```bash
gcloud config set project $PROJECT_ID
```

<walkthrough-footnote>CLI（gcloud）を利用する準備が整いました。次にハンズオンで利用する機能を有効化します。</walkthrough-footnote>


<!-- Step 6 -->
## Google Cloud サービスの API 

Google Cloud では利用したい機能ごとに、API を有効化する必要があります。
ここでは、以降のハンズオンで利用する機能を事前に有効化しておきます。


### ハンズオンで利用する Google Cloud サービスの API を有効化する

以下の機能を有効にします。

<walkthrough-enable-apis></walkthrough-enable-apis>

- Cloud Run API
- Cloud SQL API
- Cloud Pub/Sub API
- Artifact Registry API
- Cloud Build API

```bash
gcloud services enable \
  run.googleapis.com \
  sql-component.googleapis.com \
  sqladmin.googleapis.com \
  compute.googleapis.com \
  pubsub.googleapis.com \
  artifactregistry.googleapis.com \
  cloudbuild.googleapis.com
```

**GUI**: [APIライブラリ](https://console.cloud.google.com/apis/library?project={{project-id}})または、クラウドコンソールの各サービスのページを開くと有効化ボタンが表示されます。

<!-- Step 7 -->
## サービスアカウント

サービスアカウントとは、アプリケーションやVMインスタンスが使用するアカウントです。

### サービスアカウントの作成

サンプルアプリケーションが使用するサービスアカウントを作成します。

```bash
gcloud iam service-accounts create handson-sa
```

作成したサービスアカウントに権限を付与します。 **今回のハンズオンは編集者権限を付与していますが、実際の開発の現場では必要最小限の権限を付与しましょう！**

```bash
gcloud projects add-iam-policy-binding {{project-id}} --member "serviceAccount:handson-sa@{{project-id}}.iam.gserviceaccount.com" --role "roles/editor"
```

**GUI**: [サービスアカウント](https://console.cloud.google.com/iam-admin/serviceaccounts?project={{project-id}})

<!-- Step 8 -->
## (Optional) Cloud Shell 復旧手順

もしハンズオン中に Cloud Shell を閉じてしまったり、リロードしたり、チュートリアルを閉じてしまった場合、以下のコマンドを再実行してから作業を再開してください。  
(Step 1 から順番に進めている場合はこのページはスキップいただいて結構です)

- 環境変数 `PROJECT_ID` に Google Cloud プロジェクト ID を設定
```bash
export PROJECT_ID={{project-id}}
```

- CLI（gcloud コマンド） から利用する Google Cloud のデフォルトプロジェクトを設定
```bash
gcloud config set project $PROJECT_ID
```

- 作業用のディレクトリへ移動
```bash
cd ~/cloudshell_open/gcp-getting-started-lab-jp/cloudrun2
```

- チュートリアルの起動
```bash
cd ~/cloudshell_open/gcp-getting-started-lab-jp/cloudrun2 && teachme tutorial.md
```


<!-- Step 9 -->
## Eats サービス (注文API) の構築

<walkthrough-tutorial-duration duration=30></walkthrough-tutorial-duration>

ここではサンプルアプリケーションのうち、宅配ピザの注文を API 経由で受け付ける Eats サービス を構築します。
下記の手順で進めます。

 - Cloud SQL インスタンスの新規作成
 - Eats サービスのソースコードからコンテナイメージをビルド
 - ビルドしたコンテナイメージを Artifact Registry へのプッシュ
 - Cloud Run へ Eats サービスのコンテナイメージをデプロイ
 - 動作確認
   - Eats サービスへの CRUD 
   - Cloud Run のオートスケール機能を確認


<!-- Step 10 -->
## Cloud SQL インスタンスの新規作成

### CLoud SQL の インスタンス (MySQL) を作成します。
今回作成するインスタンスの名前は **handson-db** です。リージョンは **asia-northeast1(東京)** を選択します。

```bash
gcloud sql instances create {{db-instance-name}} --tier=db-custom-1-3840 --region={{region}}
```

### 作成したインスタンスの確認を行います。
**MySQL_5_7** のインスタンスが作成され、STATUS が **RUNNABLE** になっていることを確認します。
```bash
gcloud sql instances list
```

### 作成したインスタンスにログインするため、root ユーザーのパスワードを設定します。
```text
gcloud sql users set-password root \
--host="%" \
--instance={{db-instance-name}} \
--prompt-for-password
```

### 作成したインスタンスに接続します。
数分かかることがあります。ログインの際、インスタンス作成時に指定したパスワードを聞かれるので入力してください。
```bash
gcloud sql connect {{db-instance-name}} --user=root
```

### Eats サービスが利用するデーターベースを作成します。
データベースの名前は **handson** です。この名前を違うものにすると、後ほどの工程でアプリケーションからの接続に失敗するので間違えないよう注意してください。
```sql
CREATE DATABASE {{db-name}};
```

作成直後の **handson** データベースにテーブルがないことを確認します。
```sql
USE {{db-name}};
```
```sql
SHOW TABLES;
```
Eats サービスではピザのメニュー情報がマスターデータとして予めデータベースに登録されている必要がありますが、
Eats サービスのアプリケーションに実装済みのマイグレーションツールにより、
アプリケーションの初回立ち上げ時に自動的にピザのメニュー情報が本 **handson** データベースに登録されます。
```sql
QUIT;
```

### コネクション名を確認します。
コネクション名は Cloud Run 上にデプロイしたアプリケーションから Cloud SQL のインスタンスに接続するため、このあとのステップで必要となります。
```bash
gcloud sql instances describe handson-db --format json | jq .connectionName
```

以上で Cloud SQL の準備は終了です。


<!-- Step 11 -->
## Eats サービスのソースコードからコンテナイメージをビルド

### Artifact Registry にレポジトリを作成
ビルドしたコンテナイメージを保管するレポジトリを事前に作成しておきます。
```bash
gcloud artifacts repositories create {{repo-name}} --repository-format=docker --location={{region}}
```

### Docker コマンドの認証設定
Docker コマンドを使って Artifact Registry にコンテナイメージをアップロードできるようします。
```bash
gcloud auth configure-docker {{region}}-docker.pkg.dev
```

### Docker コマンドを使って Eats サービスのコンテナイメージをビルド
`-t` オプションはタグの指定を行っています。 少々冗長と感じるかもしれませんが、
Artifact Registry にこのあとアップロードするため、以下の情報を識別できるタグとしています。
- Artifact Registry のどのリージョン、どのGoogle Cloud プロジェクト、どのレポジトリに保管するのか、
- アプリケーションのバージョン (末尾)
```bash
cd ./eats && docker build -t {{region}}-docker.pkg.dev/{{project-id}}/{{repo-name}}/eats:v1 .
```
ビルドが無事終わっているかの確認します。
```bash
docker images | grep eats
```

### コンテナイメージを Artifact Registry にアップロード
```bash
docker push {{region}}-docker.pkg.dev/{{project-id}}/{{repo-name}}/eats:v1 
```
<!-- Step 12 -->
## Cloud Run へ Eats サービスのコンテナイメージをデプロイ

### 前準備
Cloud Run の利用するリージョン、プラットフォームのデフォルト値を設定します。(毎度設定すると面倒なので)
```bash
gcloud config set run/region {{region}}
gcloud config set run/platform managed
```
### 環境変数の確認
Eats サービスを動かすため、アプリケーションにいくつか環境変数で設定値を渡してあげる必要があります。今後何度か使うので環境変数に設定しておきましょう。

データーベースのユーザー名とパスワード
```bash
export DB_USER=root
```
```text
export DB_PWD=[先程設定したパスワード]
```
Cloud Run から接続する Cloud SQL インスタンスを識別するための設定
```bash
export DB_INSTANCE=$(gcloud sql instances describe handson-db --format json | jq -r .connectionName)
```
前のものとほぼ同じ内容ですが、こちらは Eats サービスのアプリケーション自体から Cloud SQL に接続するために必要です。
```bash
export DB_CONNECTION="/cloudsql/"$(gcloud sql instances describe handson-db --format json | jq -r .connectionName)
```

### Cloud Run に デプロイ
```bash
gcloud run deploy eats \
--image={{region}}-docker.pkg.dev/{{project-id}}/{{repo-name}}/eats:v1 \
--allow-unauthenticated \
--set-env-vars=DB_PWD=${DB_PWD},DB_USER=${DB_USER},DB_CONNECTION=${DB_CONNECTION} \
--set-cloudsql-instances=${DB_INSTANCE}
```

<walkthrough-footnote>Eats サービスのコンテナイメージをビルドし、Cloud Run にデプロイすることができました。
次は Eats サービスにアクセスし動作確認をしていきます。</walkthrough-footnote>


<!-- Step 13 -->
## Eats サービスの動作確認

### ルートパスへのアクセス
eats サービスの URL は何度も使うので環境変数に設定しておきましょう。
curl コマンドを使って Eats サービスのルートパスにまずはアクセスしてみてください。
```bash
export EATS_URL=$(gcloud run services describe eats --format json | jq -r '.status.address.url')
```
```bash
curl -X GET ${EATS_URL}/
```

次のように返ってくれば、正しく Eats サービスが動作しています。

```terminal
{"version":"v1","message":"This is Eats service API"}
```

### Eats サービスの CRUD を試してみる
#### メニューの確認 (READ)
/items に GET でアクセスしてみましょう。
```bash
curl -X GET ${EATS_URL}/items
```
次のように返ってくれば、OKです。
わかりやすくするため改行を入れていますが、実際の出力は改行されません。
3 つの種類のピザがメニューとして予め登録されています。
```terminal
[
    {
        "ID":1,
        "CreatedAt":"2021-06-11T16:48:44.379Z",
        "UpdatedAt":"2021-06-11T16:48:44.379Z",
        "DeletedAt":null,
        "name":"Simple Pizza",
        "price":1000,
        "currency":"JPY"
    },
    {
        "ID":2,
        "CreatedAt":"2021-06-11T16:48:44.385Z",
        "UpdatedAt":"2021-06-11T16:48:44.385Z",
        "DeletedAt":null,
        "name":"Normal Pizza",
        "price":2000,
        "currency":"JPY"
    },
    {
        "ID":3,
        "CreatedAt":"2021-06-11T16:48:44.393Z",
        "UpdatedAt":"2021-06-11T16:48:44.393Z",
        "DeletedAt":null,
        "name":"Luxury Pizza",
        "price":3000,
        "currency":"JPY"
    }
]
```

#### 注文の作成 (CREATE)
まず注文が今のところ 1 件もないことを確認します。
/orders に GET でアクセスしてみます。
```bash
curl -X GET ${EATS_URL}/orders
```

次に注文を行います。
注文を行う場合は、POST メソッドを使い、`-d` オプションで注文内容を json フォーマットで渡してあげます。
`purchaser` と `item_id` はお好きなものを選択してください。
```bash
curl -X POST -d '{"purchaser":"Taro Yamada","item_id":1}' ${EATS_URL}/orders
```
次のように返ってくれば、OKです。
```terminal
{
    "ID":1,
    "CreatedAt":"2021-06-13T16:34:30.286Z",
    "UpdatedAt":"2021-06-13T16:34:30.286Z",
    "DeletedAt":null,"item_id":1,
    "purchaser":"Taro Yamada",
    "item_completed":false,
    "delivery_completed":false,
    "delivery_completed_at":null
}
```
#### 注文の更新 (UPDATE)
先程作成した注文の更新を行いましょう。例えばピザの調理が完了したことを示す、`item_completed` を `false` から `true` に変更してみます。
更新は PUT メソッドを使うので注意してください。また URL の末尾で、先程作成した注文の ID を指定します。
```bash
curl -X PUT -d '{"purchaser":"Taro Yamada","item_id":1,"item_completed":true}' ${EATS_URL}/orders/1
```
`item_completed` が `true` になって返ってくれば、OK です。
```terminal
{
    "ID":1,
    "CreatedAt":"2021-06-13T16:34:30.286Z",
    "UpdatedAt":"2021-06-13T17:10:53.908Z",
    "DeletedAt":null,
    "item_id":1,
    "purchaser":"Taro Yamada",
    "item_completed":true,
    "delivery_completed":false,
    "delivery_completed_at":null
}
```

#### 注文の削除 (DELETE)
先程作成した注文を削除しましょう。
削除は DELETE メソッドを使います。
```bash
curl -X DELETE ${EATS_URL}/orders/1
```
次のように返ってくれば、OKです。
```terminal
{"id":"1","message":"deleted"}
```

### Cloud Run のオートスケール機能を試してみる
Cloud Run は強力なオートスケール機能を備えています。
ここでは Eats サービスが盛況を迎えたことを妄想しながら、Eats サービスに負荷を掛けたときにどのような挙動になるのか見てみましょう。

#### 現在の コンテナ インスタンス数の確認
[Cloud Console](https://console.cloud.google.com/run/detail/asia-northeast1/eats/metrics?project={{project-id}}) から現在のコンテナインスタンス数を確認しましょう。
おそらくほとんどのケースで 1 もしくは 0 になっているかと思います。

- Active : 実際のリクエストを処理しているコンテナ インスタンス
- Idle   : アイドル状態のコンテナ インスタンス

#### Hey による負荷掛け
[Hey](https://github.com/rakyll/hey) を使って Eats サービスに負荷を掛けます。Hey は Cloud Shell にデフォルトでインストールされているため、新たにインストールする必要はありません。
Eats サービスのルートパスへの GET リクエストを 合計 10000 回、 100 並列 で実行します。
```bash
hey -n 10000 -c 100 $EATS_URL
```
負荷をかけたら、もう一度 Cloud Console でコンテナ インスタンス数を確認してみましょう。  
グラフ表示は5分程度のタイムラグがありますが、コンテナ インスタンスが自動的にスケールしてレスポンスを返したことが分かるはずです。

<walkthrough-footnote>Cloud Run 上に構築した Eats サービスが期待通り動作することを確認出来ました。次は Notification サービスを構築します。</walkthrough-footnote>


<!-- Step 15 -->
## Notification サービス (プッシュ通知) の構築

<walkthrough-tutorial-duration duration=30></walkthrough-tutorial-duration>

ここではサンプルアプリケーションのうち、Eats サービス 側のイベント (e.g. ピザの注文を受付) をクライアントにプッシュ通知する Notification サービスを構築します。  
下記の手順で進めます。

 - Cloud Pub/Sub のトピック・サブスクリプションの新規作成
 - Eats サービスのコード修正 (v2)
 - 以下のコンテナイメージをビルド、Artifact Registry へプッシュ
     - Eats サービス v2
     - Notification サーバー
     - Notification クライアント
 - Cloud Run へ各コンテナイメージをデプロイ
 - 動作確認
     - Eats サービスのイベントに合わせて通知がクライアントに飛んでくることの確認
     - Cloud Run の段階的ロールアウト・ロールバック機能を確認
    
<!-- Step 16 -->
## Cloud Pub/Sub のトピック・サブスクリプションの新規作成

### スキーマの作成
Cloud Pub/Sub では [Protocol Buffers](https://developers.google.com/protocol-buffers) もしくは [Avro](https://avro.apache.org/) を使ってメッセージのスキーマを定義することが可能です。
スキーマ設定機能は 2021.06 現在、Preview 機能となります。

スキーマを作成します。
イベント名 (e.g. 注文受付)、注文者名、注文 ID、アイテム ID を扱うスキーマです。
```bash
gcloud beta pubsub schemas create {{schema-name}} \
--type=PROTOCOL_BUFFER \
--definition='syntax = "proto3";message ProtocolBuffer {string event_name = 1;string purchaser = 2;int64 order_id = 3;int64 item_id = 4;}'

```
スキーマが正しく作成されたか検証を行います。 **Message is valid** と返ってきたら、OK です。
```bash
gcloud beta pubsub schemas validate-message \
--message-encoding=JSON \
--message='{"event_name": "Order received", "purchaser": "Taro Yamada", "order_id": 1, "item_id": 1 }'  \
--schema-name={{schema-name}}                 
```

### スキーマ付きトピックの作成
```bash
gcloud beta pubsub topics create {{topic-id}} \
--message-encoding=JSON \
--schema={{schema-name}}
```

### サブスクリプションの作成
```bash
gcloud pubsub subscriptions create {{sub-id}} \
--topic={{topic-id}}
```
<!-- Step 17 -->
## Eats サービスのコード修正 (v2)
Notification サービスと連携できるように Eats サービスのソースコードを変更します。
すでに実装は済んでいるので、コメントアウトされている箇所を戻していきます。  

レポジトリのルートに戻ります。
```bash
cd ~/cloudshell_open/gcp-getting-started-lab-jp/cloudrun2
```

Cloud Pub/Sub と連携するための Util パッケージのインポート
```bash
sed -i -e "s|//\"eats.com/util\"|\"eats.com/util\"|" eats/handler/eats.go
```

注文作成時に Cloud Pub/Sub にメッセージをパブリッシュ
```bash
sed -i -e "s|//util.Publish(\"Order received\", order.Purchaser, order.ID, order.ItemID)|util.Publish(\"Order received\", order.Purchaser, order.ID, order.ItemID)|g" eats/handler/eats.go
```

注文更新時に Cloud Pub/Sub にメッセージをパブリッシュ
```bash
sed -i -e "s|//util.Publish(\"Order updated\", order.Purchaser, order.ID, order.ItemID)|util.Publish(\"Order updated\", order.Purchaser, order.ID, order.ItemID)|g" eats/handler/eats.go
```

最後に Eats サービスが更新されたことを示す意味で、ルートパスのメッセージも変更しておきましょう。
```bash
sed -i -e "s|Version: \"v1\"|Version: \"v2\"|g" eats/handler/eats.go
```

<!-- Step 18 -->
## コンテナイメージをビルド、Artifact Registry へアップロード
#### Cloud Build を使ったコンテナイメージのビルドとアップロード
Docker コマンドでビルドすることも可能ですが、Cloud Build を使うことで簡単にコンテナイメージをビルドし、そのまま Artifact Registry へアップロードすることが可能です。

Eats サービス v2 (先程変更したもの) を Cloud Build でビルドします。
```bash
cd ./eats && gcloud builds submit --tag {{region}}-docker.pkg.dev/{{project-id}}/{{repo-name}}/eats:v2
```

[Cloud Console](https://console.cloud.google.com/cloud-build/builds?project={{project-id}}) にアクセスし、Cloud Build が動作していることを確認します。

同様に Notification Server も Cloud Build でビルドを行います。
```bash
cd ../notification && gcloud builds submit --tag {{region}}-docker.pkg.dev/{{project-id}}/{{repo-name}}/notification-server:v1
```

Eats サービス v2 と Notification Server のビルドが完了し、コンテナイメージが Artifact Registry にアップロードされたことを確認します。
```bash
gcloud container images list --repository={{region}}-docker.pkg.dev/{{project-id}}/{{repo-name}}
```

それぞれのタグまで細かく確認するには以下のコマンドで行います。
Eats サービス
```bash
gcloud container images list-tags {{region}}-docker.pkg.dev/{{project-id}}/{{repo-name}}/eats
```
Notification Server
```bash
gcloud container images list-tags {{region}}-docker.pkg.dev/{{project-id}}/{{repo-name}}/notification-server
```

Notification Client は Cloud Shell 上で実行するので、Artifact Registry にアップロードしなくてよいので、docker コマンドでビルドします。
```bash
docker build -t {{region}}-docker.pkg.dev/{{project-id}}/{{repo-name}}/notification-client:v1 -f Dockerfile.client .
```

ビルドが無事終わっているかの確認します。
```bash
docker images | grep notification-client
```

<!-- Step 19 -->
## Cloud Run へ各コンテナイメージをデプロイ
### Eats サービス v2 のデプロイ
Cloud Pub/Sub と連携するために必要な設定を環境変数にセットします。
PROJECT_ID はすでに設定済みですが、念の為再掲しておきます。

```bash
export PROJECT_ID={{project-id}}
```
```bash
export TOPIC_ID={{topic-id}}
```
Cloud Run へデプロイ
```bash
gcloud run deploy eats \
--image={{region}}-docker.pkg.dev/{{project-id}}/{{repo-name}}/eats:v2 \
--allow-unauthenticated \
--set-env-vars=DB_PWD=${DB_PWD},DB_USER=${DB_USER},DB_CONNECTION=${DB_CONNECTION},PROJECT_ID=${PROJECT_ID},TOPIC_ID=${TOPIC_ID} \
--set-cloudsql-instances=${DB_INSTANCE} \
--service-account="handson-sa@{{project-id}}.iam.gserviceaccount.com"
```

ルートパスにアクセスし、Eats サービスが v2 に更新されたことを確認します。
```bash
curl -X GET ${EATS_URL}/
```

次のように **v2** と返ってくれば、OK です。

```terminal
{"version":"v2","message":"This is Eats service API"}
```

### Notification Server のデプロイ
Notification Server は Eats サービスがトピックにパブリッシュしたメッセージを受信するため、サブスクリプションの ID を渡す必要があります。
```bash
export SUB_ID={{sub-id}}
```
Cloud Run へデプロイ  
gRPC を使うため、**--use-http2** オプションを付けています。
また、Notification サービスは gRPC の Server-side streaming を使った Long live connection となるため、Cloud Run のレスポンスタイムアウト値を 60 分 (3600 秒) に設定しておきます。
```bash
gcloud beta run deploy notification-server \
--image={{region}}-docker.pkg.dev/{{project-id}}/{{repo-name}}/notification-server:v1 \
--allow-unauthenticated \
--use-http2 \
--timeout=3600 \
--set-env-vars=PROJECT_ID=${PROJECT_ID},SUB_ID=${SUB_ID} \
--service-account="handson-sa@{{project-id}}.iam.gserviceaccount.com"
```

### Notification Client の実行
Notification Server からの通知を受け取るため、Notification Client を Cloud Shell 上で実行します。  
まず、Client の宛先となる Notification Server の URL を確認します。
```bash
export NOTIFICATION_DOMAIN=$(gcloud run services describe notification-server --format json | jq -r '.status.address.url' | sed 's|https://||g')
```

Notification Client を実行します。実行後、Notification Server と Long live connection を確立し、Notification Server から通知が送信されるのを待ちます。 
実行を中止せず、そのままにしておいてください。
```bash
docker run --name notification-client -e INSECURE=false -e DOMAIN=${NOTIFICATION_DOMAIN} -e PORT=443 {{region}}-docker.pkg.dev/{{project-id}}/{{repo-name}}/notification-client:v1
```
<walkthrough-footnote>Notification サービスを構築し、Eats サービスを Notitication サービスと連携できるように修正し、Cloud Run へ再デプロイしました。
次は Notification サービスの動作確認をしていきます。</walkthrough-footnote>

<!-- Step 20 -->
## 動作確認 1 通知が実際に飛ぶことの確認
### 注文作成(受付)の通知
注文を作成してみましょう。
新たなタブを開く場合は、Cloud Shell 上段の **+** ボタンのプルダウンからプロジェクト ID を選択して開いてください。  
新しく開いたタブの gcloud コマンドにはプロジェクト ID が設定されておらず、以降のコマンド実行が上手くいかない場合があるので、その場合は以下コマンドを実行してください。
```bash
gcloud config set core/project {{project-id}}
```

また新しいタブではこれまで設定した gcloud の設定や環境変数が設定されていないため、以降のステップで必要なものを新しいタブでも設定します。
```bash
gcloud config set run/region {{region}}
gcloud config set run/platform managed
```
```bash
export EATS_URL=$(gcloud run services describe eats --format json | jq -r '.status.address.url')
```
それでは、通知を発生させるため注文作成を行っていきましょう。以下のコマンドを5, 6回実行してみてください。  
尚、ここで複数回実行しているのはタイムラグがあるため、複数回同時に注文作成したほうが早く結果を確認できるためです。  
`purchaser` と `item_id` はお好きなものを選択してください。
```bash
curl -X POST -d '{"purchaser":"Taro Yamada","item_id":1}' ${EATS_URL}/orders
```

Notification Client を実行中のタブに戻って、通知が届いていることを確認してください。
次のように表示されていれば、OK です。
```terminal
2021/06/12 14:40:10 Subscribing...
2021/06/12 14:40:34 {"event_name":"Order received","purchaser":"Taro Yamada","order_id":2,"item_id":1}
2021/06/12 14:40:34 {"event_name":"Order received","purchaser":"Taro Yamada","order_id":3,"item_id":2}
2021/06/12 14:40:34 {"event_name":"Order received","purchaser":"Taro Yamada","order_id":4,"item_id":3}
```
尚、Notification Client は実装上、手動で実行中止にしない限り、動作し続けます。
途中でサーバーサイドからの切断があっても再度接続しなおします。

### 注文更新(変更)の通知
次に注文を更新した場合にも通知が飛ぶどうか確認しましょう。 先程、注文作成したタブに戻ってください。  
末尾のオーダー ID は各自の環境のお好きなものを使ってみてください。
更新内容も API のスキーマに沿っていれば以下のものでなくて構いません。
```bash
curl -X PUT -d '{"purchaser":"Taro Yamada","item_id":1,"item_completed":true}' ${EATS_URL}/orders/2
```
Notification Client を実行中のタブに戻って、通知が届いていることを確認してください。
次のように表示されていれば、OK です。
以下の例では、item_id が元々、2 だったものが、更新により 3 に変更され、通知内容にも反映されていることが分かるかと思います。
```terminal
2021/06/13 17:10:47 {"event_name":"Order updated","purchaser":"Taro Yamada","order_id":2,"item_id":3}
```

<walkthrough-footnote>Notification サービスの動作確認を行いました。Eats サービスと連携し、注文作成及び、更新時に gRPC Server-side streaming を使って通知がクライアントに飛んでくることを確認しました。</walkthrough-footnote>

<!-- Step 21 -->
## 動作確認 2 Cloud Run の段階的ロールアウト・ロールバック機能の確認
### ロールバック機能
Cloud Run には実運用に使える様々な機能があります。ここでは、段階的ロールアウト・ロールバック機能を試してみましょう。
現在 Eats サービス は v2 ですが、バグが発見され v1 に戻したい場合、ロールバック機能が使えます。

まず、1 つ前のリビジョンを確認し、環境変数にセットします。(v1)
こちらが、Cloud Run に初回にデプロイした Eats サービスを識別するリビジョンです。 
```bash
OLD_REV=$(gcloud run revisions list --format json | jq -r '.[].metadata.name' | grep 'eats-' | sort -r | sed -n 2p)
```
```bash
echo $OLD_REV
```
では確認した 1 つ前のリビジョンにロールバックを行いましょう。100 % のリクエスト トライフィックを 1 つ前のリビジョンに流します。
```bash
gcloud run services update-traffic eats --to-revisions=${OLD_REV}=100
```

ルートパスにアクセスし、**v1** にロールバックしたことを確認しましょう。
```bash
curl -X GET ${EATS_URL}/
```

```terminal
{"version":"v1","message":"This is Eats service API"}
```

### 段階的ロールアウト機能 (カナリーリリース)
アプリケーションの新しいバージョンがリリースされたときに、直後に 100 % のリクエスト トラフィックを流すのではなく、例えば 10% > 20% > 30% .... 100% と徐々に流していくリリース方式をカナリーリリースと呼びますが、Cloud Run でも実現可能です。  

早速試してみましょう。
今、Eats サービスは v1 に 100% のリクエストトラフィックを流しています。こちらを v1: 90%、v2:10% のトラフィックを流すように変更してみましょう。

v2 に 10% を流す設定を行います。この設定を行うことで、v1 へは自動的に 90% のリクエスト トラフィックが流れます。
```bash
gcloud run services update-traffic eats --to-revisions=LATEST=10
```

ルートパスに適当数アクセスし、10 回に 1 回程度 **v2** が表示されることを確認しましょう。
```bash
curl -X GET ${EATS_URL}/
```

最後に、v2 に 100% のリクエストトラフィックが流れるようにしましょう。
```bash
gcloud run services update-traffic eats --to-revisions=LATEST=100
```

ルートパスに適当数アクセスし、常に **v2** が表示されることを確認しましょう。
```bash
curl -X GET ${EATS_URL}/
```

<!-- Step 22 -->
## Congratulations!

<walkthrough-conclusion-trophy></walkthrough-conclusion-trophy>

これにて Cloud Run を使ったハンズオンは完了です！！

本ハンズオンで使った資材が不要な方は、次の手順でクリーンアップを行って下さい。

## クリーンアップ（プロジェクトを削除）

<walkthrough-tutorial-duration duration=10></walkthrough-tutorial-duration>

作成したリソースを個別に削除する場合は、こちらのページの手順を実施せずに次のページに進んで下さい。

### プロジェクトの削除

```bash
gcloud projects delete {{project-id}}
```

## クリーンアップ（個別リソースの削除）

### Cloud Run にデプロイした eats / notification-server の削除

```bash
gcloud run services delete eats
```

```bash
gcloud run services delete notification-server
```

### Cloud SQL インスタンスの削除
```bash
gcloud sql instances delete {{db-instance-name}}
```

### Cloud Pub/Sub トピック / サブスクリプション / スキーマ の削除
トピックの削除
```bash
gcloud pubsub topics delete {{topic-id}}
```
サブスクリプションの削除
```bash
gcloud pubsub subscriptions delete {{sub-id}}
```
スキーマの削除
```bash
gcloud beta pubsub schemas delete {{schema-name}}
```

### Artifact Registry のレポジトリ削除
```bash
gcloud artifacts repositories delete {{repo-name}} --location={{region}}
```

### サービスアカウントに付与したロールの取り消し

```bash
gcloud projects remove-iam-policy-binding {{project-id}} --member "serviceAccount:handson-sa@{{project-id}}.iam.gserviceaccount.com" --role "roles/editor"
```

### サービスアカウントの削除

```bash
gcloud iam service-accounts delete handson-sa@{{project-id}}.iam.gserviceaccount.com
```
