# E.G.G ハンズオン #1

## Google Cloud Platform（GCP）プロジェクトの選択

ハンズオンを行う GCP プロジェクトを選択し、 **Start** をクリックしてください。

<walkthrough-project-setup>
</walkthrough-project-setup>


## ハンズオンの内容

下記の内容をハンズオン形式で学習します。

- 環境準備：10 分
  - gcloud コマンドラインツール設定
  - App Engine 有効化設定
  - GCP 機能（API）有効化設定

- [App Engine (GAE)](https://cloud.google.com/appengine) を用いたアプリケーション開発：60 分
  - app.yaml の作成
  - アプリケーションコードの作成
  - アプリケーションのデプロイ
  - Firestore の準備
  - Firestore を操作するコードの作成
  - アプリケーションのデプロイ
  - サーバーレス VPC アクセスの設定
  - Cloud SQL の準備
  - Cloud SQL に接続するコードの作成
  - アプリケーションのデプロイ
  - Memorystore for Redis の準備
  - Memorystore for Redis に接続するコードの作成
  - アプリケーションのデプロイ
  - チャレンジ問題
    - Cloud Build でデプロイを自動化
    - Operations を使ってメトリクスをみてみる、デバッグをする
    - 負荷かけてみる

- クリーンアップ：10 分
  - プロジェクトごと削除
  - （オプション）個別リソースの削除
    - Cloud SQL の削除
    - Firestore の削除
    - Memorystore の削除


## 環境準備

<walkthrough-tutorial-duration duration=10></walkthrough-tutorial-duration>

最初に、ハンズオンを進めるための環境準備を行います。

下記の設定を進めていきます。

- gcloud コマンドラインツール設定
- App Engine 有効化設定
- GCP 機能（API）有効化設定

## gcloud コマンドラインツール

GCP は、CLI、GUI から操作が可能です。ハンズオンでは主に CLI を使い作業を行いますが、GUI で確認する URL も合わせて掲載します。

### gcloud コマンドラインツールとは?

gcloud コマンドライン インターフェースは、GCP でメインとなる CLI ツールです。このツールを使用すると、コマンドラインから、またはスクリプトや他の自動化により、多くの一般的なプラットフォーム タスクを実行できます。

たとえば、gcloud CLI を使用して、以下のようなものを作成、管理できます。

- Google App Engine アプリケーション
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

<walkthrough-footnote>CLI（gcloud）を利用する準備が整いました。次にハンズオンで利用する機能を有効化します。</walkthrough-footnote>


## GCP 環境設定

GCP では利用したい機能ごとに、有効化を行う必要があります。
ここでは、以降のハンズオンで利用する機能を事前に有効化しておきます。

### App Engine を有効にする

App Engine はロケーションを指定できますが、1プロジェクトにつき1ロケーションになります。最初に作ったロケーションにしたがい、そのプロジェクトは動きます。

```bash
gcloud app create 
```

### ハンズオンで利用する GCP の API を有効化する

```bash
gcloud services enable --async sql-component.googleapis.com vpcaccess.googleapis.com
```

**GUI**: [APIライブラリ](https://console.cloud.google.com/apis/library?project={{project-id}})

<walkthrough-footnote>必要な機能が使えるようになりました。次に GAE によるアプリケーションの開発に進みます。</walkthrough-footnote>

## Google App Engine を用いたアプリケーション開発

<walkthrough-tutorial-duration duration=40></walkthrough-tutorial-duration>

App Engine を利用したアプリケーション開発を体験します。

下記の手順で進めていきます。

- app.yaml の作成
- アプリケーションコードの作成
- Firestore の準備
- Firestore を操作するコードの作成
- Memorystore for Redis の準備
- サーバーレス VPC アクセスの設定
- Memorystore for Redis に接続するコードの作成

## app.yaml の作成

app.yaml は GAE を動かすために必要な定義ファイルです。ここで動作するランタイムの設定や静的ファイルホスティングの設定などがデキます。

### ファイルを作成する

まず app.yaml を作成します。

## アプリケーションコードの作成

API サーバーを作成していきます。

まずはかんたんな HTTP レスポンスを返す API サーバーを作成します。

### Cloud Shell を使って確認する

**ヒント**: Cloud Shell 環境の 8080 ポートを、コンテナの 8080 ポートに紐付け、バックグラウンドで起動します。

<walkthrough-footnote>アプリケーションをコンテナ化し、起動することができました。次に実際にアプリケーションにアクセスしてみます。</walkthrough-footnote>

### Cloud Shell を使ってデプロイする

### CloudShell の機能を利用し、起動したアプリケーションにアクセスする

画面右上にあるアイコン <walkthrough-web-preview-icon></walkthrough-web-preview-icon> をクリックし、"プレビューのポート: 8080"を選択します。
これによりブラウザで新しいタブが開き、Cloud Shell 上で起動しているコンテナにアクセスできます。

正しくアプリケーションにアクセスできると、下記のような画面が表示されます。

![BrowserAccessToMainController](https://storage.googleapis.com/devops-handson-for-github/BrowserAccessToMainController.png)

<walkthrough-footnote>ローカル環境（Cloud Shell 内）で動いているコンテナにアクセスできました。次に GKE で動かすための準備を進めます。</walkthrough-footnote>


## チャレンジ問題：処理に時間がかかっているページの改善

/bench1 にアクセスをするとレスポンスに時間がかかっていることを確認しました。それを修正し、Kubernetes にデプロイしてみましょう。

```bash
echo "http://${SERVICE_IP}/bench1"
```


## Congraturations!

<walkthrough-conclusion-trophy></walkthrough-conclusion-trophy>

これにて GAE を使ったアプリケーション開発のハンズオンは完了です！！

デモで使った資材が不要な方は、次の手順でクリーンアップを行って下さい。

## クリーンアップ（プロジェクトを削除）

作成したリソースを個別に削除する場合は、こちらのページの手順を実施せずに次のページに進んで下さい。

### プロジェクトの削除

```bash
gcloud projects delete {{project-id}}
```

## クリーンアップ（個別リソースの削除）

### GAE の削除

プロジェクトを削除しない場合、GAE のサービス、バージョンを削除することができますが、最初に指定したロケーションは変更できない点については注意してください。（ロケーションを変更したい場合は別プロジェクトを作成することになります。）

<WIP>
```bash
gcloud app services delete
gcloud app versions delete
```
</WIP>

### Firestore データの削除

### Cloud SQL の削除

### Cloud Memorystore の削除
