# E.G.G ハンズオン #1

## Google Cloud Platform（GCP）プロジェクトの選択

ハンズオンを行う GCP プロジェクトを選択し、 **Start** をクリックしてください。

<walkthrough-project-setup>
</walkthrough-project-setup>


## ハンズオンの内容

### 対象プロダクト

以下が今回学ぶ対象のプロタクトの一覧です。

- Google App Engine
- Firestore
- Cloud SQL
- Serverless VPC access
- Google Cloud Memorystore
- Operations

### 下記の内容をハンズオン形式で学習します。

- 環境準備：10 分
  - プロジェクト作成
  - gcloud コマンドラインツール設定
  - App Engine 有効化設定
  - GCP 機能（API）有効化設定

- [App Engine (GAE)](https://cloud.google.com/appengine) を用いたアプリケーション開発：60 分
  - アプリケーションの作成
  - Firestore を使う
  - サーバーレス VPC アクセスの設定
  - Cloud SQL を使う
  - Memorystore for Redis を使う
  - チャレンジ問題

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

GCP は、CLI、GUI、Rest API から操作が可能です。ハンズオンでは主に CLI を使い作業を行いますが、GUI で確認する URL も合わせて掲載します。

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
gcloud app create --region=us-central
```

### ハンズオンで利用する GCP の API を有効化する

以下の機能を有効にします。

- Google Cloud Firestore API
- Cloud SQL
- Google Cloud Memorystore for Redis API

```bash
gcloud services enable sql-component.googleapis.com vpcaccess.googleapis.com
```

**GUI**: [APIライブラリ](https://console.cloud.google.com/apis/library?project={{project-id}})

### Firestore を有効にする

WIP

<walkthrough-footnote>必要な機能が使えるようになりました。次に GAE によるアプリケーションの開発に進みます。</walkthrough-footnote>

## Google App Engine を用いたアプリケーション開発

<walkthrough-tutorial-duration duration=60></walkthrough-tutorial-duration>

App Engine を利用したアプリケーション開発を体験します。

下記の手順で進めていきます。
### アプリケーションの作成

- app.yaml の作成
- アプリケーションコードの作成
- アプリケーションのデプロイ

### Firestore を使う

- Firestore の準備
- Firestore を操作するコードの作成
- アプリケーションのデプロイ

### サーバーレス VPC アクセスの設定

- サーバーレス VPC アクセスの設定

### Cloud SQL を使う

- Cloud SQL の準備
- Cloud SQL に接続するコードの作成
- アプリケーションのデプロイ

### Memorystore for Redis を使う

- Memorystore for Redis の準備
- Memorystore for Redis に接続するコードの作成
- アプリケーションのデプロイ

### チャレンジ問題

- Cloud Build でデプロイを自動化
- Operations を使ってメトリクスをみてみる、デバッグをする
- 負荷かけてみる

## app.yaml の作成

app.yaml は GAE を動かすために必要な定義ファイルです。ここで動作するランタイムの設定や静的ファイルホスティングの設定などがデキます。

### ファイルを作成する

まず app.yaml を作成します。

以下の内容で app.yaml を作成してください。Go アプリケーションとして必要な最低限な設定はこれだけです。

```yaml
runtime: go112
```

## アプリケーションコードの作成

設定ができたらあぷりけアプリケーションとして API サーバーを作成していきます。

まずはかんたんな HTTP レスポンスを返す API サーバーを作成します。
以下の内容で main.go を作成してください。単純な HTTP リクエストに対して `Hello EGG!` を返す Go のコードになります。

```go
package main

import (
	"fmt"
	"log"
	"net/http"
	"os"
)

func main() {
	http.HandleFunc("/", indexHandler)

	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
		log.Printf("Defaulting to port %s", port)
	}

	log.Printf("Listening on port %s", port)
	if err := http.ListenAndServe(":"+port, nil); err != nil {
		log.Fatal(err)
	}
}

func indexHandler(w http.ResponseWriter, r *http.Request) {
	if r.URL.Path != "/" {
		http.NotFound(w, r)
		return
	}
	fmt.Fprint(w, "Hello, Egg!")
}
```

作成できたら、ローカルで動かします。

```bash
go run main.go
```

ここまでは通常の Go アプリケーションと同じです。

<walkthrough-footnote>アプリケーションを作成し、起動することができました。次に実際にアプリケーションにアクセスしてみます。</walkthrough-footnote>

## Cloud Shell を使って確認する

Cloud Shell 環境の 8080 ポートを、アプリケーションの 8080 ポートに紐付け、バックグラウンドで起動します。

### CloudShell の機能を利用し、起動したアプリケーションにアクセスする

画面右上にあるアイコン <walkthrough-web-preview-icon></walkthrough-web-preview-icon> をクリックし、"プレビューのポート: 8080"を選択します。
これによりブラウザで新しいタブが開き、Cloud Shell 上で起動しているコンテナにアクセスできます。

正しくアプリケーションにアクセスできると、 `Hello EGG!` と表示されます。

## Cloud Shell を使ってデプロイする

GAE のデプロイは gcloud コマンドの以下のコマンドで実行できます。

```bash
gcloud app deploy
```

実行するとデプロイ対象の情報を表示して、 `Do you want to continue (Y/n)?` と聞かれます。確認して続行してください。
デプロイができたら、以下のコマンドを実行するとローカル環境だとブラウザが開きますが Cloud Shell だと URL のリンクが出力されるのでそちらをクリックしてみてください。

```bash
gcloud app browse
```

先程と同様に正しくアプリケーションにアクセスできると、 `Hello EGG!` と表示されます。

### こぼれ話

GAE はプロジェクト、サービス、バージョンから構成される `appspot.com` のサブドメインでアクセスできます。デフォルトのサービス、デフォルトのバージョンについては `{プロジェクトID}.appspot.com` でアクセスができます。

### こぼれ話2

デプロイの際に `.gcloudignore` が出力されるようなログが出たかもしれません。これはデプロイの際にファイルをアップロードしないように設定ファイルとして書いておくことができます。

<walkthrough-footnote>ローカル環境（Cloud Shell 内）で動いているアプリケーションにアクセスできました。次に Firestore を操作するための準備を進めます。</walkthrough-footnote>

## チャレンジ問題：HTTPS 対応してみる

アプリケーションを常時 HTTPS 化することが可能です。通常でも HTTPS は有効になっていますが、 HTTP でもアクセスできる状態です。これを常時 HTTPS にすることができます。
app.yaml の一番下に以下の内容を追記してデプロイしてみてください。

```
handlers:
  - url: /.*
    secure: always
    script: auto
```

デプロイ

```bash
gcloud app deploy
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

WIP
```bash
gcloud app services delete
gcloud app versions delete
```

ちなみに、 App Engine はアクセスがない場合はインスタンスが0になります。0になると App Engine についての課金は発生しません。

### Firestore データの削除

### Cloud SQL の削除

### Cloud Memorystore の削除
