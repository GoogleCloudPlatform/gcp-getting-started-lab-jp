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

<walkthrough-enable-apis></walkthrough-enable-apis>

- Google Cloud Firestore API
- Cloud SQL
- Google Cloud Memorystore for Redis API

```bash
gcloud services enable sql-component.googleapis.com vpcaccess.googleapis.com
```

<walkthrough-spotlight-pointer console-nav-menu="">API ライブラリ</walkthrough-spotlight-pointer>
**GUI**: [APIライブラリ](https://console.cloud.google.com/apis/library?project={{project-id}})

### サービスアカウントの作成

ローカルの開発で使用するサービスアカウントを作成します。

```bash
gcloud iam service-accounts create dev-egg-sa
```

作成したサービスアカウントに権限を付与します。 *今回のハンズオンはオーナー権限を付与していますが、実際の開発の現場では適切な権限のみを付与しましょう！

```bash
gcloud projects add-iam-policy-binding {{project-id}} --member "serviceAccount:dev-egg-sa@{{project-id}}.iam.gserviceaccount.com" --role "roles/owner"
```

キーファイルを生成します。

```bash
gcloud iam service-accounts keys create dev-key.json --iam-account dev-egg-sa@{{project-id}}.iam.gserviceaccount.com
```

**GUI**: [サービスアカウント](https://console.cloud.google.com/iam-admin/serviceaccounts?project={{project-id}}) 

作成したキーを環境変数に設定します。

```bash
export GOOGLE_APPLICATION_CREDENTIALS=`pwd`/dev-key.json
```

### Firestore を有効にする

今回のハンズオンでは Firestore のネイティブモードを使用します。

GCP コンソールの [Datastore](https://console.cloud.google.com/datastore/entities/query/kind?project={{project-id}}) に移動し、 [SWITCH TO NATICE MODE] をクリックしてください。

![switch1](https://storage.googleapis.com/egg-resources/egg1/public/firestore-switch-to-native1.png)
![switch2](https://storage.googleapis.com/egg-resources/egg1/public/firestore-switch-to-native2.png)

もしかしたらこちらの画面が表示されている場合もあります。同様にネイティブモードを選択していただければOKです。

![select-firestore-mode](https://storage.googleapis.com/egg-resources/egg1/public/select-mode.png)

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

確認が終わったら、Ctrl+c で実行中のアプリケーションを停止します。

<walkthrough-footnote>ローカル環境（Cloud Shell 内）で動いているアプリケーションにアクセスできました。次にデプロイをします。</walkthrough-footnote>

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
サービス、バージョンを指定する場合は以下のような形式のドメインになります。

WIP

### こぼれ話2

デプロイの際に `.gcloudignore` が出力されるようなログが出たかもしれません。これはデプロイの際にファイルをアップロードしないように設定ファイルとして書いておくことができます。

<walkthrough-footnote>実際に App Engine にデプロイができました！次に Firestore を操作するための準備を進めます。</walkthrough-footnote>

## チャレンジ問題：HTTPS 対応してみる

アプリケーションを常時 HTTPS 化することが可能です。通常でも HTTPS は有効になっていますが、 HTTP でもアクセスできる状態です。これを常時 HTTPS にすることができます。
`app.yaml` の一番下に以下の内容を追記してデプロイしてみてください。

```yaml
handlers:
  - url: /.*
    secure: always
    script: auto
```

デプロイする

```bash
gcloud app deploy
```

## Firestore を使う

次にFirestoreを使うようにアプリケーションを編集していきます。

### 依存関係の追加

Firestore にアクセスするためのクライアントライブラリを追加します。 Go 言語の場合、 `go.mod` でアプリケーションの依存関係を設定します。`app.yaml` と同じ場所に `go.mod` ファイルを配置してください。

以下の内容で `go.mod` ファイルを作成してください。

```
module egg1
go 1.12
require (
        cloud.google.com/go/firestore v1.2.0
        google.golang.org/api v0.21.0
)
```

### データの追加処理

`main.go` ファイルに以下のコードを追加します。
まずは import の中に以下を追記してください。

```go
	"cloud.google.com/go/firestore"
	"encoding/json"
	"io"
	"strconv"
```

次に、main 関数にハンドラを追加します。

```go
    http.HandleFunc("/", indexHandler) // ここは既存の行
    http.HandleFunc("/firestore", firestoreHandler)
```

次に、Firestoreにリクエストのデータを追加するコードを追加します。一番下に以下のコードを追記してください。

```go

func getUserBody(r *http.Request) (u Users, err error) {
	length, err := strconv.Atoi(r.Header.Get("Content-Length"))
	if err != nil {
		return u, err
	}

	body := make([]byte, length)
	length, err = r.Body.Read(body)
	if err != nil && err != io.EOF {
		return u, err
	}

	//parse json
	err = json.Unmarshal(body[:length], &u)
	if err != nil {
		return u, err
	}
    log.Print(u)
    return u, nil
}

func firestoreHandler(w http.ResponseWriter, r *http.Request) {

	// Firestore クライアント作成
	pid := os.Getenv("GOOGLE_CLOUD_PROJECT")
	ctx := r.Context()
	client, err := firestore.NewClient(ctx, pid)
	if err != nil {
		log.Fatal(err)
	}
	defer client.Close()

	if r.Method == http.MethodPost {
        // 追加処理

        u, err := getUserBody(r)
        if err != nil {
            log.Fatal(err)
            w.WriteHeader(http.StatusInternalServerError)
            return
        }
		// 書き込み
		ref, _, err := client.Collection("users").Add(ctx, u)
		if err != nil {
			log.Fatalf("Failed adding data: %v", err)
			w.WriteHeader(http.StatusInternalServerError)
			return
		}
		log.Print("success: id is %v", ref.ID)
		fmt.Fprintf(w, "success: id is %v \n", ref.ID)
	} else {
		w.WriteHeader(http.StatusMethodNotAllowed)
		return
	}
}

type Users struct {
	Id    string `firestore:id, json:id`
	Email string `firestore:email, json:email`
	Name  string `firestore:name, json:name`
}

```

こちらのコードは実際のプロジェクトの Firestore に追加しています。
ローカルでアプリケーションを動かして、Firestore にデータが入るところを確認しましょう。

```bash
go run main.go
```

Cloud Shell のタブをもう一つ開き、データを投入してみます。

```bash
curl -X POST -d '{"email":"test@example.com", "name":"テスト太郎"}' localhost:8080/firestore
```

**いくつかデータの内容を変更して実行してみましょう！**

[Firestore コンソール](https://console.cloud.google.com/firestore/data/?project={{project-id}})でデータが入っていることを確認しましょう。

元の Cloud Shell タブに戻り、Ctrl+c で実行中のアプリケーションを停止します。

### データの取得処理

登録したデータを取得する実装をしていきます。
同様に `main.go` の `firestoreHandler` を編集していきます。

が、まずは import の中に以下を追記してください。

```go
	"google.golang.org/api/iterator"
```

次にデータを取得するコードを書いていきます。POSTのifブロックとelseブロックの間に以下を追記してください。**コードのネストに注意しましょう**

```go
	} else if r.Method == http.MethodGet {
        // Firestore データ取得 （全件取得）
		iter := client.Collection("users").Documents(ctx)
		var u []Users

		for {
			doc, err := iter.Next()
			if err == iterator.Done {
                // データが無ければ終了
				break
			}
			if err != nil {
				log.Fatal(err)
			}
			var user Users
			err = doc.DataTo(&user)
			if err != nil {
				log.Fatal(err)
			}
			log.Print(user)
			u = append(u, user)
		}
		if len(u) == 0 {
			w.WriteHeader(http.StatusNoContent)
		} else {
			json, err := json.Marshal(u)
			if err != nil {
				w.WriteHeader(http.StatusInternalServerError)
				return
			}
			w.Write(json)
		}
    } else { // ここは既存の行なのでコピーしない
```

編集が終わったら動かして確認してみましょう。

```bash
go run main.go
```

先程と同様にCloud Shellの別のタブから、リクエストを投げてみましょう。先程投入したデータのJSONが返ってきます。

```bash
curl localhost:8080/firestore
```

### データの更新処理

先程追加したログの中に作成したデータの一意なIDが出力されていると思います。
次に、そのIDを使って、データを更新する処理を追加します。

```go
```

### データの削除処理

### デプロイする

最終的な `main.go` は以下のようになっているはずです。

```
WIP
```

## チャレンジ問題

WIP

### ブルーグリーンデプロイメントをしてみよう

GAE では、バージョンを用いることでブルーグリーンデプロイメントを簡単に実施できます。

### オートスケールさせてみよう

### アプリケーションのモニタリングをしてみよう

### サービスを分割してみよう

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
