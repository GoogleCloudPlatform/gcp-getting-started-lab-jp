# G.I.G ハンズオン #1

## Google Cloud Platform（GCP）プロジェクトの選択

ハンズオンを行う GCP プロジェクトを作成し、 GCP プロジェクトを選択して **Start/開始** をクリックしてください。

**今回のハンズオンは GAE を使って行うため、既存のプロジェクト（特にすでに使っているなど）だと不都合が生じる恐れがありますので新しいプロジェクトを作成してください。**

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
- GAE 有効化設定
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


## GCP 環境設定 Part1

GCP では利用したい機能ごとに、有効化を行う必要があります。
ここでは、以降のハンズオンで利用する機能を事前に有効化しておきます。

### GAE を有効にする

GAE はロケーションを指定できますが、1プロジェクトにつき1ロケーションになります。最初に作ったロケーションにしたがい、そのプロジェクトは動きます。

```bash
gcloud app create --region=us-central
```

### ハンズオンで利用する GCP の API を有効化する

以下の機能を有効にします。

<walkthrough-enable-apis></walkthrough-enable-apis>

- Google Cloud Firestore API
- Cloud SQL
- Google Cloud Memorystore for Redis API
- Serverless VPC Access

```bash
gcloud services enable --async \
                       sql-component.googleapis.com \
                       vpcaccess.googleapis.com \
                       servicenetworking.googleapis.com \
                       sqladmin.googleapis.com \
                       redis.googleapis.com
```

**GUI**: [APIライブラリ](https://console.cloud.google.com/apis/library?project={{project-id}})

## GCP 環境設定 Part2

### サービスアカウントの作成

ローカルの開発で使用するサービスアカウントを作成します。

```bash
gcloud iam service-accounts create dev-gig-sa
```

作成したサービスアカウントに権限を付与します。 **今回のハンズオンはオーナー権限を付与していますが、実際の開発の現場では適切な権限を付与しましょう！**

```bash
gcloud projects add-iam-policy-binding {{project-id}} --member "serviceAccount:dev-gig-sa@{{project-id}}.iam.gserviceaccount.com" --role "roles/owner"
```

キーファイルを生成します。

```bash
gcloud iam service-accounts keys create dev-key.json --iam-account dev-gig-sa@{{project-id}}.iam.gserviceaccount.com
```

**GUI**: [サービスアカウント](https://console.cloud.google.com/iam-admin/serviceaccounts?project={{project-id}}) 

作成したキーを環境変数に設定します。

```bash
export GOOGLE_APPLICATION_CREDENTIALS=$(pwd)/dev-key.json
```

## GCP 環境設定 Part3

### Firestore を有効にする

今回のハンズオンでは Firestore のネイティブモードを使用します。

GCP コンソールの [Datastore](https://console.cloud.google.com/datastore/entities/query/kind?project={{project-id}}) に移動し、 [SWITCH TO NATIVE MODE] をクリックしてください。

1. 切り替え画面

![switch1](https://storage.googleapis.com/egg-resources/egg1/public/firestore-switch-to-native1.png)
![switch2](https://storage.googleapis.com/egg-resources/egg1/public/firestore-switch-to-native2.png)

2. 次に、もしかしたらこちらの画面が表示されている場合もあります。同様にネイティブモードを選択していただければOKです。

![select-firestore-mode](https://storage.googleapis.com/egg-resources/egg1/public/select-mode.png)

3. ネイティブモードが有効になると、[Firestore コンソール](https://console.cloud.google.com/firestore/data/?project={{project-id}})でデータ管理の画面が有効になります。

**Datastore モードの場合でも、まだ一度もデータを登録していなければネイティブモードへの切り替えが可能です。**

<walkthrough-footnote>必要な機能が使えるようになりました。次に GAE によるアプリケーションの開発に進みます。</walkthrough-footnote>

## Google App Engine を用いたアプリケーション開発

<walkthrough-tutorial-duration duration=60></walkthrough-tutorial-duration>

Google App Engine (GAE) を利用したアプリケーション開発を体験します。

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

## app.yaml の作成

app.yaml は GAE を動かすために必要な定義ファイルです。ここで動作するランタイムの設定や静的ファイルホスティングの設定などができます。

### ファイルを作成する

まず app.yaml を作成します。

以下の内容で app.yaml を作成してください。Go アプリケーションとして必要な最低限な設定はこれだけです。

```yaml
runtime: go112
```

## アプリケーションコードの作成

設定ができたらハンズオンアプリケーションとして API サーバーを作成していきます。

まずはかんたんな HTTP レスポンスを返す API サーバーを作成します。
以下の内容で main.go を作成してください。単純な HTTP リクエストに対して `Hello GIG!` を返す Go のコードになります。

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
	fmt.Fprint(w, "Hello, GIG!")
}
```

作成できたら、ローカルで動かします。

```bash
go run main.go
```

ここまでは通常の Go アプリケーションと同じです。

**注意事項：今回のコードはあくまでサンプルの実装になりますのでご注意ください。**

<walkthrough-footnote>アプリケーションを作成し、起動することができました。次に実際にアプリケーションにアクセスしてみます。</walkthrough-footnote>

## Cloud Shell を使って確認する

Cloud Shell 環境の 8080 ポートを、アプリケーションの 8080 ポートに紐付け、バックグラウンドで起動します。

### CloudShell の機能を利用し、起動したアプリケーションにアクセスする

画面右上にあるアイコン <walkthrough-web-preview-icon></walkthrough-web-preview-icon> をクリックし、"プレビューのポート: 8080"を選択します。
これによりブラウザで新しいタブが開き、Cloud Shell 上で起動しているコンテナにアクセスできます。

正しくアプリケーションにアクセスできると、 `Hello GIG!` と表示されます。

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

先程と同様に正しくアプリケーションにアクセスできると、 `Hello GIG!` と表示されます。

<walkthrough-footnote>実際に GAE にデプロイができました！次に Firestore を操作するための準備を進めます。</walkthrough-footnote>

## こぼれ話

### こぼれ話1

GAE はプロジェクト、サービス、バージョンから構成される `appspot.com` のサブドメインでアクセスできます。デフォルトのサービス、デフォルトのバージョンについては `{プロジェクトID}.appspot.com` でアクセスができます。
サービス、バージョンを指定する場合は以下のような形式のドメインになります。

```
https://VERSION_ID-dot-SERVICE_ID-dot-PROJECT_ID.REGION_ID.r.appspot.com
```

- `VERSION_ID` : GAE にデプロイしたアプリケーションのバージョンIDになります。
- `SERVICE_ID` : GAE にデプロイしたアプリケーションのサービスIDになります。デフォルトサービスの場合、 `default` になります。
- `PROJECT_ID` : GAE を使っているプロジェクトIDになります。
- `REGION_ID` : 最初に選択したリージョンIDになります。（現在は省略可能です。）
- `-dot-` : 各要素は `-dot-` で連結されます。

上記を組み合わせて指定することで、トラフィックを0%にしているアプリケーションでもアクセスして確認が可能です。

### こぼれ話2

デプロイの際に `.gcloudignore` が出力されるようなログが出たかもしれません。これはデプロイの際にファイルをアップロードしないように設定ファイルとして書いておくことができます。

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

次にFirestoreを使うようにアプリケーションを編集していきます。基本的な CRUD 処理を実装します。

### 依存関係の追加

Firestore にアクセスするためのクライアントライブラリを追加します。 Go 言語の場合、 `go.mod` でアプリケーションの依存関係を設定します。`app.yaml` と同じ場所に `go.mod` ファイルを配置してください。

以下の内容で `go.mod` ファイルを作成してください。今回のハンズオンで使う依存関係を全部書いています。

```
module gig1

go 1.12

require (
	cloud.google.com/go/firestore v1.2.0
	github.com/c2h5oh/datasize v0.0.0-20200112174442-28bbd4740fee // indirect
	github.com/go-sql-driver/mysql v1.5.0
	github.com/gomodule/redigo v2.0.0+incompatible
	github.com/influxdata/tdigest v0.0.1 // indirect
	github.com/mailru/easyjson v0.7.1 // indirect
	github.com/tsenart/go-tsz v0.0.0-20180814235614-0bd30b3df1c3 // indirect
	github.com/tsenart/vegeta v12.7.0+incompatible // indirect
	google.golang.org/api v0.21.0
)
```

最初の実行時に展開に数分時間がかかるかもしれません。

<walkthrough-footnote>Firestoreを操作するコードを実装していきましょう。</walkthrough-footnote>

## Firestore を使う

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

func firestoreHandler(w http.ResponseWriter, r *http.Request) {

	// Firestore クライアント作成
	pid := os.Getenv("GOOGLE_CLOUD_PROJECT")
	ctx := r.Context()
	client, err := firestore.NewClient(ctx, pid)
	if err != nil {
		log.Fatal(err)
	}
	defer client.Close()

	switch r.Method {
	// 追加処理
	case http.MethodPost:
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
    // それ以外のHTTPメソッド
	default:
		w.WriteHeader(http.StatusMethodNotAllowed)
		return
	}
}

type Users struct {
	Id    string `firestore:id, json:id`
	Email string `firestore:email, json:email`
	Name  string `firestore:name, json:name`
}

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

```

こちらのコードは実際のプロジェクトの Firestore にデータを追加しています。
ローカルでアプリケーションを動かして、Firestore にデータが入るところを確認しましょう。

貼り付けたコードはインデントが崩れてたりする場合があるので、適宜 `go fmt main.go` で整えてください。

```bash
go run main.go
```

Cloud Shell のタブを新しく開き（＋ボタン）、データを投入するリクエストを送ります。以下のコマンドをコピーして Cloud Shell のコンソールに貼り付けて実行してください。

```bash
curl -X POST -d '{"email":"tamago@example.com", "name":"Egg Taro"}' localhost:8080/firestore
```

**いくつかデータの内容を変更して実行してみましょう！**

### データの確認

[Firestore コンソール](https://console.cloud.google.com/firestore/data/?project={{project-id}})でデータが入っていることを確認しましょう。

元の Cloud Shell タブに戻り、Ctrl+c で実行中のアプリケーションを停止します。

<walkthrough-footnote>次は登録したデータを Firestore から取得して返す実装を行います。</walkthrough-footnote>

## Firestore を使う

### データの取得処理

登録したデータを取得する実装をしていきます。
同様に `main.go` の `firestoreHandler` を編集していきます。

が、まずは import の中に以下を追記してください。

```go
	"google.golang.org/api/iterator"
```

次にデータを取得するコードを書いていきます。POSTの case 句の後に以下の case 句を追記しましょう。

```go
	// 取得処理
	case http.MethodGet:
		id := strings.TrimPrefix(r.URL.Path, "/firestore/")
		log.Printf("id=%v", id)
		if id == "/firestore" || id == "" {
			iter := client.Collection("users").Documents(ctx)
			var u []Users

			for {
				doc, err := iter.Next()
				if err == iterator.Done {
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
				user.Id = doc.Ref.ID
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
		} else {

			doc, err := client.Collection("users").Doc(id).Get(ctx)
			if err != nil {
				w.WriteHeader(http.StatusInternalServerError)
				return
			}
			var u Users
			err = doc.DataTo(&u)
			if err != nil {
				log.Fatal(err)
			}
			u.Id = doc.Ref.ID
			json, err := json.Marshal(u)
			if err != nil {
				w.WriteHeader(http.StatusInternalServerError)
				return
			}
			w.Write(json)
		}
```

編集が終わったら動かして確認してみましょう。

```bash
go run main.go
```

先程と同様にCloud Shellの別のタブから、リクエストを投げてみましょう。先程投入したデータのJSONが返ってきます。

```bash
curl localhost:8080/firestore
```

<walkthrough-footnote>次は登録済みのデータを更新する実装を行います。</walkthrough-footnote>

## Firestore を使う

### データの更新処理

先程追加したログの中に作成したデータの一意なIDが出力されていると思います。
次に、そのIDを使って、データを更新する処理を追加します。

```go
	// 更新処理
	case http.MethodPut:
		u, err := getUserBody(r)
		if err != nil {
			log.Fatal(err)
			w.WriteHeader(http.StatusInternalServerError)
			return
		}

		_, err = client.Collection("users").Doc(u.Id).Set(ctx, u)
		if err != nil {
			w.WriteHeader(http.StatusInternalServerError)
			return
		}

		fmt.Fprintln(w, "success updating")
```

編集が終わったら動かして確認してみましょう。

```bash
go run main.go
```

Doc にIDの値をセットすることで一意なユーザーデータを対象にし、Set 関数で受け取ったリクエストの内容で更新します。

id の値はコンソールなどで確認した値をセットしてください。

![firestore-id](https://storage.googleapis.com/egg-resources/egg1/public/firestore-id.jpg)

```bash
curl -X PUT -d '{"id": "<Document ID>", "email":"test@example.com", "name":"Egg Taro"}' localhost:8080/firestore
```

<walkthrough-footnote>次は登録済みのデータを削除する実装を行います。</walkthrough-footnote>

## Firestore を使う

### データの削除処理

最後に、データの削除処理を行います。

削除APIはパスパラメータでIDを指定する形式にしましょう。
`main.go` の import の中に以下を追記してください。

```go
  "strings"
```

main 関数の HandleFunc に以下を追加します。

```go
	http.HandleFunc("/firestore/", firestoreHandler)
```

次にデータを削除するコードを書いていきます。PUTの case 句の後に以下の case 句を追記しましょう。

```go
	// 削除処理
	case http.MethodDelete:
		id := strings.TrimPrefix(r.URL.Path, "/firestore/")
		_, err := client.Collection("users").Doc(id).Delete(ctx)
		if err != nil {
			w.WriteHeader(http.StatusInternalServerError)
			return
        }
        fmt.Fprintln(w, "success deleting")
```

編集が終わったら確認します。

```bash
go run main.go
```

削除対象のIDは何でも構いません。先程更新したIDでもいいでしょう。

```bash
curl -X DELETE localhost:8080/firestore/<Document ID>
```

<walkthrough-footnote>最後に、ここまでのアプリケーションを GAE にデプロイします。</walkthrough-footnote>

## Firestore を使う

### デプロイする

ここまで実装してきた Firestore 操作のコードを GAE にデプロイします。

```bash
gcloud app deploy
```

先程までに試した操作を GAE に向けていくつか実行してみてください。（ローカルでも GAE と同じ Firestore を使っているため、データはすでにあると思います。）

登録

```bash
curl -X POST -d '{"email":"tamago@example.com", "name":"Egg Taro"}' https://{{project-id}}.appspot.com/firestore
```

取得（全件）

```bash
curl https://{{project-id}}.appspot.com/firestore
```

取得（１件）

```bash
curl https://{{project-id}}.appspot.com/firestore/<Document ID>
```

更新

```bash
curl -X PUT -d '{"id": "<Document ID>", "email":"test@example.com", "name":"Egg Taro"}' https://{{project-id}}.appspot.com/firestore
```

削除

```bash
curl -X DELETE https://{{project-id}}.appspot.com/firestore/<Document ID>
```

最終的な `main.go` は以下のようになっているはずです。

```go
package main

import (
	"cloud.google.com/go/firestore"
	"encoding/json"
	"fmt"
	"google.golang.org/api/iterator"
	"io"
	"log"
	"net/http"
	"os"
	"strconv"
	"strings"
)

func main() {
	http.HandleFunc("/", indexHandler)
	http.HandleFunc("/firestore", firestoreHandler)
	http.HandleFunc("/firestore/", firestoreHandler)

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
	fmt.Fprint(w, "Hello, GIG!")
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

	switch r.Method {
	// 追加処理
	case http.MethodPost:
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
		// それ以外のHTTPメソッド
		// 取得処理
	case http.MethodGet:
		id := strings.TrimPrefix(r.URL.Path, "/firestore/")
		log.Printf("id=%v", id)
		if id == "/firestore" || id == "" {
			iter := client.Collection("users").Documents(ctx)
			var u []Users

			for {
				doc, err := iter.Next()
				if err == iterator.Done {
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
				user.Id = doc.Ref.ID
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
		} else {

			doc, err := client.Collection("users").Doc(id).Get(ctx)
			if err != nil {
				w.WriteHeader(http.StatusInternalServerError)
				return
			}
			var u Users
			err = doc.DataTo(&u)
			if err != nil {
				log.Fatal(err)
			}
			u.Id = doc.Ref.ID
			json, err := json.Marshal(u)
			if err != nil {
				w.WriteHeader(http.StatusInternalServerError)
				return
			}
			w.Write(json)
		}
		// 更新処理
	case http.MethodPut:
		u, err := getUserBody(r)
		if err != nil {
			log.Fatal(err)
			w.WriteHeader(http.StatusInternalServerError)
			return
		}

		_, err = client.Collection("users").Doc(u.Id).Set(ctx, u)
		if err != nil {
			w.WriteHeader(http.StatusInternalServerError)
			return
		}

		fmt.Fprintln(w, "success updating")
		// 削除処理
	case http.MethodDelete:
		id := strings.TrimPrefix(r.URL.Path, "/firestore/")
		_, err := client.Collection("users").Doc(id).Delete(ctx)
		if err != nil {
			w.WriteHeader(http.StatusInternalServerError)
			return
		}
		fmt.Fprintln(w, "success deleting")
	default:
		w.WriteHeader(http.StatusMethodNotAllowed)
		return
	}
}

type Users struct {
	Id    string `firestore:id, json:id`
	Email string `firestore:email, json:email`
	Name  string `firestore:name, json:name`
}

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

```

<walkthrough-footnote>Firestore についての実装は以上になります。次に Memorystore を操作できるようにしていきます。</walkthrough-footnote>

## Serverless VPC Access のコネクタを作成する

まずは VPC ネットワークを作成します。

```bash
gcloud compute networks create gigvpc --subnet-mode=custom
```

```bash
gcloud compute networks subnets create us-subnet --network=gigvpc --region=us-central1 --range=10.128.0.0/20
```

```bash
gcloud compute networks vpc-access connectors create gig-vpc-connector \
--network gigvpc \
--region us-central1 \
--range 10.129.0.0/28
```

<!-- 
## Cloud SQL を設定する

### Cloud SQL インスタンスの作成

今回は MySQL を利用します。

```bash
gcloud beta sql instances create --network=gigvpc --region=us-central1 --root-password=gigpassword --no-assign-ip gigsql
```

### データベース作成

Cloud Shell から接続する場合、Cloud SQL から見ると外部からの接続になるため、一時的にパブリックなIPを付与します。

```bash
gcloud sql instances patch --assign-ip gigsql
```

Cloud SQL のインスタンスに接続します。パスワードを尋ねられるので、作成時に指定したパスワードを入力します。

```bash
gcloud sql connect gigsql
```

接続できたら、データベースとテーブルを作成します。

```bash
create database gig;
```

```bash
create table gig.user (id varchar(10), email varchar(255), name varchar(255));
```

データベースとテーブルが作成できたら、パブリックIPを閉じます。
```bash
gcloud sql instances patch --no-assign-ip gigsql
```

<walkthrough-footnote>データベース側の準備は以上です。</walkthrough-footnote>

## App Engne に Cloud SQL を使うように修正する

MySQL は慣れてる方も多いと思うので、登録と取得のみを実装します。

### 接続情報を定義する

`app.yaml` を編集して、接続情報を定義します。以下の内容をファイルの末尾に追記してください。

```yaml
vpc_access_connector:
  name: "projects/{{project-id}}/locations/us-central1/connectors/gig-vpc-connector"

env_variables:
  DB_INSTANCE: "{{project-id}}:us-central1:gigsql"
  DB_USER: root
  DB_PASS: gigpassword
```

`app.yaml` に DB パスワードを書いていることに不安を持った方もいるかも知れません。 [Cloud KMS](https://cloud.google.com/kms/) を使うことで機密情報を保護することができます。

### データベースアクセスをアプリケーションに実装する

`main.go` の import に以下の依存関係を追加します。

```go
	"database/sql"
    _ "github.com/go-sql-driver/mysql"
```

`main.go` に以下のコードを追記します。

```go

var db *sql.DB
func initConnectionPool() (*sql.DB, error) {

    var (
        dbUser     = os.Getenv("DB_USER")
        dbPwd      = os.Getenv("DB_PASS")
        dbInstance = os.Getenv("DB_INSTANCE")
        dbName = "gig"
    )
    dbURI := fmt.Sprintf("%s:%s@unix(/cloudsql/%s)/%s", dbUser, dbPwd, dbInstance, dbName)
    dbPool, err := sql.Open("mysql", dbURI)
    if err != nil {
        return nil, fmt.Errorf("sql.Open: %v", err)
    }
    dbPool.SetMaxIdleConns(5)
    dbPool.SetMaxOpenConns(5)
    dbPool.SetConnMaxLifetime(1800)

    return dbPool, nil
}

```

main 関数の頭のところに以下のコードを追加します。

```go
	var err error
    // DB
    db, err = initConnectionPool()
    if err != nil {
        log.Fatalf("unable to connect: %s", err)
    }

```

main 関数に sqlHandler を追加します。
```go
	http.HandleFunc("/sql", sqlHandler)
```

sqlHandler 関数を追加します。

```go
func sqlHandler(w http.ResponseWriter, r *http.Request) {

	switch r.Method {
	case http.MethodPost:
		u, err := getUserBody(r)
		if err != nil {
			log.Fatal(err)
			w.WriteHeader(http.StatusInternalServerError)
			return
        }

        ins, err := db.Prepare("INSERT INTO user(id, email, name) VALUES(?,?,?)")
        if err != nil {
			log.Fatal(err)
			w.WriteHeader(http.StatusInternalServerError)
			return
        }
        defer ins.Close()
        _, err = ins.Exec(u.Id, u.Email, u.Name)
        if err != nil {
			log.Fatal(err)
			w.WriteHeader(http.StatusInternalServerError)
			return
        }
		log.Print("success: id is %v", u.Id)
		fmt.Fprintf(w, "success: id is %v \n", u.Id)
        
	case http.MethodGet:
		rows, err := db.Query(`SELECT id, email, name FROM user`)
		if err != nil {
			log.Fatal(err)
			w.WriteHeader(http.StatusInternalServerError)
			return
		}
		defer rows.Close()
		var users []Users
		for rows.Next() {
			var u Users
			err = rows.Scan(&u.Id, &u.Email, &u.Name)
			if err != nil {
			    log.Fatal(err)
				w.WriteHeader(http.StatusInternalServerError)
				return
			}
			users = append(users, u)
		}
		if len(users) == 0 {
			w.WriteHeader(http.StatusNoContent)
		} else {
			json, err := json.Marshal(users)
			if err != nil {
			    log.Fatal(err)
				w.WriteHeader(http.StatusInternalServerError)
				return
			}
			w.Write(json)
		}
	// それ以外のHTTPメソッド
	default:
		w.WriteHeader(http.StatusMethodNotAllowed)
		return
	}
}
```

これをデプロイして実際に試してみましょう。

```bash
gcloud app deploy
```

まずは登録。

```
curl -X POST -d '{"id": "00001", "email":"tamago@example.com", "name":"タマゴ1"}' https://{{project-id}}.appspot.com/sql
```

そして取得。

```bash
curl https://{{project-id}}/sql
```

<walkthrough-footnote>Cloud SQL は以上です。次にMemorystore for Redis を使って Firestore の取得結果をキャッシュします。</walkthrough-footnote> -->

## Memorystore for Redis を使う

Memorystore for Redis を使ってデータのキャッシュをしてみましょう。
現在Beta版で Memorystore for Memcached も利用できますので、そちらを試してみても良いかもしれません。
Firestore のデータをキャッシュから返せるように修正していきます。

### Redis インスタンスを作成する

```bash
gcloud redis instances create --network=gigvpc --region=us-central1 gigcache
```

作成できたら、以下のコマンドを実行して Redis インスタンスの IP アドレスを取得します。

```bash
gcloud redis instances list --format=json  --region=us-central1 | jq .[0].host
```

### 接続設定

本来なら GAE から Memorystore に接続する場合は Serverless VPC Access の設定が必要になりますが、今回 Cloud SQL で設定済みなので省略できます。

`app.yaml` の環境変数とコネクタの設定をを追記しましょう。

```yaml
vpc_access_connector:
  name: "projects/{{project-id}}/locations/us-central1/connectors/gig-vpc-connector"

env_variables:
  REDIS_HOST: 10.224.127.11
  REDIS_PORT: 6379
```

`REDIS_HOST` の値は先程設定した REDIS_HOST の値を記載してください。

## Firestore ハンドラの修正

現在、全件取っているだけでキャッシュする意味がないため、キーで取得できるようにまずは修正します。

`main.go` の firestoreHandler 、 MethodGet のところを修正していきます。以下の内容に修正してください。

```go
	case http.MethodGet:
		id := strings.TrimPrefix(r.URL.Path, "/firestore/")
		log.Printf("id=%v", id)
		if id == "/firestore" || id == "" {
			iter := client.Collection("users").Documents(ctx)
			var u []Users

			for {
				doc, err := iter.Next()
				if err == iterator.Done {
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
				user.Id = doc.Ref.ID
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
		} else {
            doc, err := client.Collection("users").Doc(id).Get(ctx)
            if err != nil {
                w.WriteHeader(http.StatusInternalServerError)
                return
            }
            var u Users
            err = doc.DataTo(&u)
            if err != nil {
                log.Fatal(err)
            }
            u.Id = doc.Ref.ID
            json, err := json.Marshal(u)
            if err != nil {
                w.WriteHeader(http.StatusInternalServerError)
                return
            }
            w.Write(json)
		}
```

これでまずは単一のユーザーデータを取得できるようになりました。

次に Redis 操作のためのコードを追加します。 

import に以下を追記してください。

```go
    "github.com/gomodule/redigo/redis"
```

main 関数の最初のところに以下を追記してください。

```go
	// Redis
	initRedis()
```

`main.go` 末尾に以下を追記してください。

```go
var pool *redis.Pool

func initRedis() {
	var (
		host = os.Getenv("REDIS_HOST")
		port = os.Getenv("REDIS_PORT")
		addr = fmt.Sprintf("%s:%s", host, port)
	)
	pool = redis.NewPool(func() (redis.Conn, error) {
		return redis.Dial("tcp", addr)
	}, 10)
}
```

else の方が今回単一ユーザーデータを取得するようにしたところですが、こちらにキャッシュを取得するようなコードを追加します。
元のところを else で囲むので、まるっと以下に置き換えてみましょう。

```go

            // Redis クライアント作成
            conn := pool.Get()
            defer conn.Close()

            cache, err := redis.String(conn.Do("GET", id))
            if err != nil {
                log.Println(err)
            }
            log.Printf("cache : %v", cache)

            if cache != "" {
                json, err := json.Marshal(cache)
                if err != nil {
                    w.WriteHeader(http.StatusInternalServerError)
                    return
                }
                w.Write(json)
                log.Printf("find cache")
            } else {
                doc, err := client.Collection("users").Doc(id).Get(ctx)
                if err != nil {
                    w.WriteHeader(http.StatusInternalServerError)
                    return
                }
                var u Users
                err = doc.DataTo(&u)
                if err != nil {
                    log.Fatal(err)
                }
                u.Id = doc.Ref.ID
                json, err := json.Marshal(u)
                if err != nil {
                    w.WriteHeader(http.StatusInternalServerError)
                    return
                }
                conn.Do("SET", id, string(json))
			    w.Write(json)
            }
```

コードが編集できたら、デプロイしましょう。

```bash
gcloud app deploy
```

Firestore エンドポイントに登録されているデータのIDで2回アクセスして、レスポンスの時間が短くなっている（キャッシュが効いている）事を確認します。

```bash
curl https://{{project-id}}.appspot.com/firestore/<ID>
```

<walkthrough-footnote>ハンズオンの内容は以上になります。お疲れさまでした。</walkthrough-footnote>

## チャレンジ問題

### オートスケールさせてみよう

[vegeta](https://github.com/tsenart/vegeta) を使って GAE にアクセスを大量に発生させてみましょう。（vegeta でなくても、使い慣れたものを使えばOKです。）

インストール

```bash
go get -u github.com/tsenart/vegeta
```

アタック (Cloud Shell で実行すると送信する側のリソースが足りなくて時間がかかるかもしれません。可能だったらお手元の PC で実行することをオススメします。)

```bash
echo "GET https://{{project-id}}.appspot.com/firestore" | vegeta attack -rate=1000 -duration=10s | tee /tmp/result.bin
```

レポート
```bash
vegeta report /tmp/result.bin
```

リクエストに応じてインスタンスがスケールすることを [GCP コンソール](https://console.cloud.google.com/appengine/instances?project={{project-id}}) で確認しましょう。

### Firestore でクエリをしてみよう

今回のハンズオンでは全件を取ってくる処理になっていますが、実際には検索条件などを実装すると思います。
[こちら](https://cloud.google.com/firestore/docs/query-data/queries)を参考に検索条件を追加してみましょう。

Firestore のクエリについては[制限事項](https://firebase.google.com/docs/firestore/query-data/queries#query_limitations)がありますが、クエリを実行できます。

### 色んなデプロイメントをしてみよう

GAE では、バージョンを用いることでブルーグリーンデプロイメントを簡単に実施できます。 先程デプロイで使っていた `gcloud app deploy` はオプションを指定しないと常に最新が有効になります。  
最新をデプロイしておいて任意のタイミングで切り替えるブルーグリーンデプロイメントなどが GAE ではデプロイ時のオプションとその後の設定で可能になります。

```bash
gcloud app deploy --no-promote
```

`--no-promote` オプションを指定することでアプリケーションをデプロイするけどトラフィックはデプロイしたアプリケーションに流さない、ということができます。確認するには、前述のこぼれ話に書いた URL に直接アクセスするか、GCP コンソールからでもリンクを取得できます。

例えば、最新のデプロイを確認後に以下のコマンドで切り替えることができます。

```bash
gcloud app versions migrate $VERSION_ID
```

### アプリケーションのモニタリングをしてみよう

[Cloud Monitoring](https://console.cloud.google.com/monitoring?project={{project-id}})を使うことでコンソールよりも詳細な情報な確認することができます。（初回アクセス時は最初の表示までに時間がかかるかもしれません。）

[GAE ダッシュボード](https://console.cloud.google.com/monitoring/dashboards/resourceDetail/gae_application,project_id:{{project-id}}?project={{project-id}}&timeDomain=1h)で GAE の状態を監視することができます。

[Cloud Trace](https://console.cloud.google.com/traces/list?project={{project-id}}) で時間のかかったリクエストを分析することもできます。

### デプロイしたアプリケーションをデバッグする

[Cloud Debug](https://cloud.google.com/debugger) は、デプロイされた GAE アプリケーションのコードを確認でき、本番環境のリクエストをデバッグすることができます。今回はGo言語で開発していたため未対応ですが、Java, Pythonでは利用できます。

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
GAE はアクセスがない場合はインスタンスが0になります。0になると GAE についての課金は発生しません。

```bash
gcloud app services delete ${SERVICE_ID} // 今回は default サービスしか使っていないため、 default サービスは削除できません。
```

```bash
gcloud app versions delete ${VERSION_ID} // default サービスのバージョンは最後の一つは削除できません。
```

このため、厳密に GAE を完全に消去したい場合はプロジェクトを削除してください。

### Firestore データの削除

Firestore コンソールから、ルートコレクションを削除してください。今回のハンズオンで作成したすべての user データが消えます。

<!-- 
### Cloud SQL の削除

```bash
gcloud sql instances delete gigsql-1
``` -->

### Cloud Memorystore の削除

```bash
gcloud redis instances delete gigcache --region=us-central1
```

<walkthrough-footnote>クリーンアップは以上になります。ありがとうございました。</walkthrough-footnote>
