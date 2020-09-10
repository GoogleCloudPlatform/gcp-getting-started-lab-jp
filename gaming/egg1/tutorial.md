# E.G.G ハンズオン #1

## Google Cloud Platform（GCP）プロジェクトの選択

ハンズオンを行う GCP プロジェクトを作成し、 GCP プロジェクトを選択して **Start/開始** をクリックしてください。

**今回のハンズオンは Firestore Native mode を使って行うため、既存のプロジェクト（特にすでに使っているなど）だと不都合が生じる恐れがありますので新しいプロジェクトを作成してください。**


<walkthrough-project-setup>
</walkthrough-project-setup>


## はじめに

### **内容と目的**

本ハンズオンでは、Cloud Run を触ったことない方向けに、テスト アプリケーションを作成し、Cloud Firestore と Cloud Memorystore に接続してクエリをする方法などを学びます。
本ハンズオンを通じて、 Cloud Run を使ったアプリケーション開発のイメージを掴んでもらうことが目的です。


### **前提条件**

本ハンズオンははじめて Cloud Run に触れる方を想定しており、 事前知識がなくとも本ハンズオンの進行には影響ありません。
ハンズオン中で使用する GCP プロダクトについてより詳しく知りたい方は、Coursera の教材や公式ドキュメントを使い学んでいただくことをお勧めします。


### **対象プロダクト**

以下が今回学ぶ対象のプロタクトの一覧です。

- Cloud Run
- Cloud Firestore
- Cloud Memorystore
- Serverless VPC access


## ハンズオンの内容

下記の内容をハンズオン形式で学習します。

### **学習ステップ**
- 環境準備：10 分
  - プロジェクト作成
  - gcloud コマンドラインツール設定
  - GCP 機能（API）有効化設定

- [Cloud Run](https://cloud.google.com/run) を用いたアプリケーション開発：60 分
  - サンプル アプリケーションのコンテナ化
  - コンテナの [Google Container Registry](https://cloud.google.com/container-registry/) への登録
  - Cloud Run のデプロイ
  - Cloud Firestore の利用
  - サーバーレス VPC アクセスの設定
  - Cloud Memorystore for Redis の利用
  - チャレンジ問題

- クリーンアップ：10 分
  - プロジェクトごと削除
  - （オプション）個別リソースの削除
    - Cloud Run の削除
    - Cloud Firestore の削除
    - Cloud Memorystore の削除


## 環境準備

<walkthrough-tutorial-duration duration=10></walkthrough-tutorial-duration>

最初に、ハンズオンを進めるための環境準備を行います。

下記の設定を進めていきます。

- gcloud コマンドラインツール設定
- GCP 機能（API）有効化設定
- サービスアカウント設定


## gcloud コマンドラインツール

Google Cloud は、CLI、GUI、Rest API から操作が可能です。ハンズオンでは主に CLI を使い作業を行いますが、GUI で確認する URL も合わせて掲載します。


### gcloud コマンドラインツールとは?

gcloud コマンドライン インターフェースは、GCP でメインとなる CLI ツールです。このツールを使用すると、コマンドラインから、またはスクリプトや他の自動化により、多くの一般的なプラットフォーム タスクを実行できます。

たとえば、gcloud CLI を使用して、以下のようなものを作成、管理できます。

- Google Compute Engine 仮想マシン
- Google Kubernetes Engine クラスタ
- Google Cloud SQL インスタンス

**ヒント**: gcloud コマンドラインツールについての詳細は[こちら](https://cloud.google.com/sdk/gcloud?hl=ja)をご参照ください。

<walkthrough-footnote>次に gcloud CLI をハンズオンで利用するための設定を行います。</walkthrough-footnote>


## gcloud コマンドラインツール設定

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

### デフォルトリージョンを設定

リージョナルリソースを作成する際に指定するデフォルトのリージョンを設定します。

```bash
gcloud config set compute/region us-central1
```


<walkthrough-footnote>CLI（gcloud）を利用する準備が整いました。次にハンズオンで利用する機能を有効化します。</walkthrough-footnote>


## GCP 環境設定 Part1

GCP では利用したい機能ごとに、有効化を行う必要があります。
ここでは、以降のハンズオンで利用する機能を事前に有効化しておきます。


### ハンズオンで利用する GCP の API を有効化する

以下の機能を有効にします。

<walkthrough-enable-apis></walkthrough-enable-apis>

- Cloud Build API
- Google Container Registry API
- Google Cloud Firestore API
- Google Cloud Memorystore for Redis API
- Serverless VPC Access API
- Cloud SQL

```bash
gcloud services enable \
  cloudbuild.googleapis.com \
  containerregistry.googleapis.com \
  run.googleapis.com \
  redis.googleapis.com \
  vpcaccess.googleapis.com \
  servicenetworking.googleapis.com \
  sql-component.googleapis.com \
  sqladmin.googleapis.com
```

**GUI**: [APIライブラリ](https://console.cloud.google.com/apis/library?project={{project-id}})

## GCP 環境設定 Part2

### サービスアカウントの作成

ローカルの開発で使用するサービスアカウントを作成します。

```bash
gcloud iam service-accounts create dev-egg-sa
```

作成したサービスアカウントに権限を付与します。 **今回のハンズオンはオーナー権限を付与していますが、実際の開発の現場では適切な権限を付与しましょう！**

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
export GOOGLE_APPLICATION_CREDENTIALS=$(pwd)/dev-key.json
```

## GCP 環境設定 Part3

### Firestore を有効にする

今回のハンズオンでは Firestore のネイティブモードを使用します。

GCP コンソールの [Datastore](https://console.cloud.google.com/datastore/entities/query/kind?project={{project-id}}) に移動し、 [SWITCH TO NATIVE MODE] をクリックしてください。

1. 切り替え画面

![switch1](https://storage.googleapis.com/egg-resources/egg1/public/firestore-switch-to-native1.png)
![switch2](https://storage.googleapis.com/egg-resources/egg1/public/firestore-switch-to-native2.png)

2. もしかしたらこちらの画面が表示されている場合もあります。同様にネイティブモードを選択していただければOKです。

![select-firestore-mode](https://storage.googleapis.com/egg-resources/egg1/public/select-mode.png)

3. ネイティブモードが有効になると、[Firestore コンソール](https://console.cloud.google.com/firestore/data/?project={{project-id}})でデータ管理の画面が有効になります。

**Datastore モードの場合でも、まだ一度もデータを登録していなければネイティブモードへの切り替えが可能です。**

<walkthrough-footnote>必要な機能が使えるようになりました。次に Cloud Run によるアプリケーションの開発に進みます。</walkthrough-footnote>

## Cloud Run を用いたアプリケーション開発

<walkthrough-tutorial-duration duration=60></walkthrough-tutorial-duration>

Cloud Run を利用したアプリケーション開発を体験します。

下記の手順で進めていきます。
  - サンプル アプリケーションのコンテナ化
  - コンテナの [Google Container Registry](https://cloud.google.com/container-registry/) への登録
  - Cloud Run のデプロイ
  - Cloud Firestore の利用
  - サーバーレス VPC アクセスの設定
  - Cloud Memorystore for Redis の利用
  - Cloud SQL の利用
  - チャレンジ問題


## アプリケーション コードの確認

ハンズオン用のサンプル Web アプリケーションとして　Go 言語で API サーバーを作成していきます。

まずはカレント ディレクトリにある main.go を確認してください。
単純な HTTP リクエストに対して `Hello, EGG!` を返す Go のコードになります。


```go:main.go
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

確認できたら、ローカルで動かしてみましょう。

```bash
go run main.go
```

ここまでは通常の Go アプリケーションと同じです。

**注意事項：今回のコードはあくまでサンプルの実装になりますのでご注意ください。**

<walkthrough-footnote>アプリケーションを作成し、起動することができました。次に実際にアプリケーションにアクセスしてみます。</walkthrough-footnote>

## Cloud Shell を使って確認する

Cloud Shell 環境の 8080 ポートを、アプリケーションの 8080 ポートに紐付け、フォアグラウンドで起動します。

### CloudShell の機能を利用し、起動したアプリケーションにアクセスする

画面右上にあるアイコン <walkthrough-web-preview-icon></walkthrough-web-preview-icon> をクリックし、"プレビューのポート: 8080"を選択します。
これによりブラウザで新しいタブが開き、Cloud Shell 上で起動しているコンテナにアクセスできます。

正しくアプリケーションにアクセスできると、 **Hello, EGG!** と表示されます。

確認が終わったら、Ctrl+c で実行中のアプリケーションを停止します。

<walkthrough-footnote>ローカル環境（Cloud Shell 内）で動いているアプリケーションにアクセスできました。次にアプリケーションのコンテナ化をします。</walkthrough-footnote>

## Cloud Shell を使ってデプロイする

### コンテナを作成する

Go 言語で作成されたサンプル Web アプリケーションをコンテナ化します。
ここで作成したコンテナはローカルディスクに保存されます。

```bash
docker build -t gcr.io/$GOOGLE_CLOUD_PROJECT/egg1-app:v1 .
```

**ヒント**: `docker build` コマンドを叩くと、Dockerfile が読み込まれ、そこに記載されている手順通りにコンテナが作成されます。

### Cloud Shell 上でコンテナを起動する

上の手順で作成したコンテナを Cloud Shell 上で起動します。

```bash
docker run -p 8080:8080 \
--name egg1-app \
-e GOOGLE_APPLICATION_CREDENTIALS=/tmp/keys/auth.json \
-v $PWD/auth.json:/tmp/keys/auth.json:ro \
gcr.io/$GOOGLE_CLOUD_PROJECT/egg1-app:v1
```

**ヒント**: Cloud Shell 環境の 8080 ポートを、コンテナの 8080 ポートに紐付け、フォアグラウンドで起動しています。

<walkthrough-footnote>アプリケーションをコンテナ化し、起動することができました。次に実際にアプリケーションにアクセスしてみます。</walkthrough-footnote>


## 作成したコンテナの動作確認

### CloudShell の機能を利用し、起動したアプリケーションにアクセスする

画面右上にあるアイコン <walkthrough-web-preview-icon></walkthrough-web-preview-icon> をクリックし、"プレビューのポート: 8080"を選択します。
これによりブラウザで新しいタブが開き、Cloud Shell 上で起動しているコンテナにアクセスできます。

正しくアプリケーションにアクセスできると、先程と同じように `Hello EGG!` と表示されます。

確認が終わったら、Ctrl+c で実行中の Docker コンテナを停止します。


<walkthrough-footnote>ローカル環境（Cloud Shell 内）で動いているコンテナにアクセスできました。次に Cloud Run にデプロイするための準備を進めます。</walkthrough-footnote>

## コンテナのレジストリへの登録

先程作成したコンテナはローカルに保存されているため、他の場所から参照ができません。
他の場所から利用できるようにするために、GCP 上のプライベートなコンテナ置き場（コンテナレジストリ）に登録します。

### 作成したコンテナをコンテナレジストリ（Google Container Registry）へ登録（プッシュ）する

```bash
docker push gcr.io/$GOOGLE_CLOUD_PROJECT/egg1-app:v1
```

**GUI**: [コンテナレジストリ](https://console.cloud.google.com/gcr/images/{{project-id}}?project={{project-id}})

<walkthrough-footnote>次に Cloud Run にコンテナをデプロイをします。</walkthrough-footnote>


## Cloud Run にコンテナをデプロイする

### gcloud コマンドで Cloud Run を作成し、コンテナをデプロイします

Cloud Run の名前は egg1-app にしています。

```bash
gcloud run deploy --image=gcr.io/$GOOGLE_CLOUD_PROJECT/egg1-app:v1 \
  --service-account="dev-egg-sa@{{project-id}}.iam.gserviceaccount.com" \
  --platform=managed \
  --region=us-central1 \
  --allow-unauthenticated \
  egg1-app
```

**参考**: デプロイが完了するまで、1〜2分程度かかります。

**GUI**: [Cloud Run](https://console.cloud.google.com/run?project={{project-id}})

### URLを取得して、アプリケーションの動作を確認します
```bash
URL=$(gcloud run services describe --format=json --region=us-central1 --platform=managed egg1-app | jq .status.url -r)
echo ${URL}
```

**GUI**: [Cloud Run サービス情報](https://console.cloud.google.com/run/detail/us-central1/egg1-app/general?project={{project-id}})


## Cloud Runのログを確認します

### コンテナのログを確認
**GUI**: [Cloud Run ログ](https://console.cloud.google.com/run/detail/us-central1/egg1-app/logs?project={{project-id}})

アクセスログを確認します。

<walkthrough-footnote>Cloud Run にサンプル Web アプリケーションがデプロイされました。次は Firestore の利用に入ります。</walkthrough-footnote>

## Firestore の利用

サンプル Web アプリケーションが Firestore を利用するように編集していきます。今回は、基本的な CRUD 処理を実装します。

### 依存関係の追加

Firestore にアクセスするためにクライアントライブラリを追加します。
Go 言語の場合、 `go.mod` でアプリケーションの依存関係を設定できます。

今回のハンズオンで使う依存関係を全て書いた `go.mod` ファイルは既に `egg1` フォルダに配置済みです。

```
module github.com/GoogleCloudPlatform/gcp-getting-started-lab-jp/gaming/egg1/

go 1.15

require (
	cloud.google.com/go/firestore v1.3.0
	github.com/gomodule/redigo v2.0.0+incompatible
	golang.org/x/net v0.0.0-20200904194848-62affa334b73 // indirect
	golang.org/x/oauth2 v0.0.0-20200902213428-5d25da1a8d43 // indirect
	golang.org/x/sys v0.0.0-20200909081042-eff7692f9009 // indirect
	golang.org/x/tools v0.0.0-20200908211811-12e1bf57a112 // indirect
	google.golang.org/api v0.31.0
	google.golang.org/genproto v0.0.0-20200904004341-0bd0a958aa1d // indirect
	google.golang.org/grpc v1.32.0 // indirect
)
```

初回の `main.go` 実行時はモジュールの展開に数分時間かかる場合がございます。

<walkthrough-footnote>Firestoreを操作するコードを実装していきましょう。</walkthrough-footnote>

## Firestore の利用

### データの追加処理

**このステップで作成したコードは answer/step18/main.go になります。**

`main.go` ファイルに以下のコードを追加します。
まずは import の中に以下を追記してください。

```go
"encoding/json"
"io"
"strconv"
"cloud.google.com/go/firestore"
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

```
curl -X POST -d '{"email":"tamago@example.com", "name":"たまご太郎"}' localhost:8080/firestore
```

**いくつかデータの内容を変更して実行してみましょう！**

### データの確認

[Firestore コンソール](https://console.cloud.google.com/firestore/data/?project={{project-id}})でデータが入っていることを確認しましょう。

元の Cloud Shell タブに戻り、Ctrl+c で実行中のアプリケーションを停止します。

<walkthrough-footnote>次は登録したデータを Firestore から取得して返す実装を行います。</walkthrough-footnote>


## Firestore の利用

### データの取得処理

**このステップで作成したコードは answer/step19/main.go になります。**

登録したデータを取得する実装をしていきます。
同様に `main.go` の `firestoreHandler` を編集していきます。

まずは import の中に以下を追記してください。

```go
  "google.golang.org/api/iterator"
```

次にデータを取得するコードを書いていきます。POSTの case 句の後に以下の case 句を追記しましょう。

```go
  // 取得処理
  case http.MethodGet:
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
```

編集が終わったら動かして確認してみましょう。

```bash
go run main.go
```

先程と同様に Cloud Shell の別のタブから、リクエストを投げてみましょう。先程投入したデータの JSON が返ってきます。

```bash
curl localhost:8080/firestore
```

<walkthrough-footnote>次は登録済みのデータを更新する実装を行います。</walkthrough-footnote>

## Firestore の利用


### データの更新処理

**このステップで作成したコードは answer/step20/main.go になります。**

先程追加したログの中に作成したデータの一意な ID が出力されていると思います。
次に、その ID を使って、データを更新する処理を追加します。

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

Doc に ID の値をセットすることで一意なユーザーデータを対象にし、Set 関数で受け取ったリクエストの内容で更新します。

id の値はコンソールなどで確認した値をセットしてください。

![firestore-id](https://storage.googleapis.com/egg-resources/egg1/public/firestore-id.jpg)

```
curl -X PUT -d '{"id": "<更新対象のID>", "email":"test@example.com", "name":"エッグ次郎"}' localhost:8080/firestore
```

<walkthrough-footnote>次は登録済みのデータを削除する実装を行います。</walkthrough-footnote>


## Firestore の利用

### データの削除処理

**このステップで作成したコードは answer/step21/main.go になります。**

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

次にデータを削除するコードを書いていきます。PUT の case 句の後に以下の case 句を追記しましょう。

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

削除対象の ID は何でも構いません。先程更新した ID でもいいでしょう。

```
curl -X DELETE localhost:8080/firestore/<削除対象のID>
```

<walkthrough-footnote>更新したアプリケーションを Cloud Run にデプロイします。</walkthrough-footnote>

## Cloud Run へのデプロイ

### コンテナのビルド

ここまで実装してきた Firestore 操作のコードを `egg1-app:v2` としてコンテナ化します。

```bash
docker build -t gcr.io/$GOOGLE_CLOUD_PROJECT/egg1-app:v2 .
```

### コンテナのプッシュ

Google Container Registry にアップロードします。

```bash
docker push gcr.io/$GOOGLE_CLOUD_PROJECT/egg1-app:v2
```

### Cloud Run の新しいリビジョンのデプロイ

以下のコマンドを実行します。

```bash
gcloud run deploy \
  --no-traffic \
  --image=gcr.io/$GOOGLE_CLOUD_PROJECT/egg1-app:v2 \
  --service-account="dev-egg-sa@{{project-id}}.iam.gserviceaccount.com" \
  --platform=managed \
  --region=us-central1 \
  --allow-unauthenticated \
  --set-env-vars "GOOGLE_CLOUD_PROJECT={{project-id}}" \
  egg1-app
```

**--no-traffic** を指定しているため、まだ以前のリビジョンがトラフィックを処理しています。

### リビジョン情報の確認

以下のコマンドを実行します。

```bash
gcloud run revisions list --platform=managed --region=us-central1 --service=egg1-app
```

**GUI**: [Cloud Run 変更内容（リビジョン）](https://console.cloud.google.com/run/detail/us-central1/egg1-app/revisions?hl=ja&project={{project-id}})



## Cloud Run のトラフィック切り替え

### トラフィック切り替えの実行

以下のコマンドで全てのトラフィックを最新のリビジョンに切り替えます。

```bash
gcloud run services update-traffic --to-latest --platform=managed --region=us-central1 egg1-app
```

**GUI**: [Cloud Run 変更内容（リビジョン）](https://console.cloud.google.com/run/detail/us-central1/egg1-app/revisions?hl=ja&project={{project-id}})


## アプリケーションの確認

### URL の表示

以下のコマンドで URL を表示します。

```bash
echo $URL
```

### Firestore を利用した操作の実施

先程、ローカル環境で試した操作を Cloud Run に向けていくつか実行してみてください。
ローカルでも Cloud Run と同じ Firestore を使っているため、同じデータがあるはずです。

**登録**

```bash
curl -X POST -d '{"email":"tamago@example.com", "name":"たまご太郎"}' ${URL}/firestore
```

**取得（全件）**

```bash
curl ${URL}/firestore
```

**取得（１件）**

```bash
curl ${URL}/firestore/<取得対象のID>
```

**更新**

```bash
curl -X PUT -d '{"id": "<更新対象のID>", "email":"test@example.com", "name":"エッグ次郎"}' ${URL}/firestore
```

**削除**

```bash
curl -X DELETE ${URL}/firestore/<削除対象のID>
```
<walkthrough-footnote>Firestore についての実装は以上になります。次に Memorystore を操作できるようにしていきます。</walkthrough-footnote>


## Serverless VPC Access のコネクタを作成する

ここからは Memorystore を Cloud Run と連携させていきます。
まずは VPC ネットワークを作成します。

```bash
gcloud compute networks create eggvpc --subnet-mode=custom
```

```bash
gcloud compute networks subnets create us-subnet --network=eggvpc --region=us-central1 --range=10.128.0.0/20
```

```bash
gcloud compute networks vpc-access connectors create egg-vpc-connector \
--network eggvpc \
--region us-central1 \
--range 10.129.0.0/28
```


## Memorystore for Redis を使う

Memorystore for Redis を使ってデータのキャッシュをしてみましょう。
Firestore のデータをキャッシュから返せるように修正していきます。

### Redis インスタンスを作成する

```bash
gcloud redis instances create --network=eggvpc --region=us-central1 eggcache
```

作成できたら、以下のコマンドを実行して Redis インスタンスの IP アドレスを取得します。

```bash
gcloud redis instances list --format=json  --region=us-central1 | jq '.[0].host'
```

## Firestore ハンドラの修正

**このステップで作成したコードは answer/step27/main.go になります。**

現在、全件取っているだけでキャッシュする意味がないため、キーで取得できるようにまずは修正します。

`main.go` の firestoreHandler の MethodGet を修正していきます。以下の内容に修正してください。

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

## Cloud Run へのデプロイ
### コンテナのビルド

egg1-app:v3 としてコンテナ化します。

```bash
docker build -t gcr.io/$GOOGLE_CLOUD_PROJECT/egg1-app:v3 .
```

### コンテナのプッシュ

Google Container Registry にアップロードします。

```bash
docker push gcr.io/$GOOGLE_CLOUD_PROJECT/egg1-app:v3
```

### Cloud Run の新しいリビジョンのデプロイ

Serverless VPC Access は Cloud Run デプロイ時に `--vpc-connector` を指定することで接続設定ができます。
また、環境変数で Memorystore for Redis への接続情報を付与してデプロイをします。
**REDIS_HOST** には先程作成した REDIS_HOST の IP アドレスを指定してください。

```bash
gcloud run deploy \
  --image=gcr.io/$GOOGLE_CLOUD_PROJECT/egg1-app:v3 \
  --vpc-connector egg-vpc-connector \
  --service-account="dev-egg-sa@{{project-id}}.iam.gserviceaccount.com" \
  --platform=managed \
  --region=us-central1 \
  --allow-unauthenticated \
  --set-env-vars "GOOGLE_CLOUD_PROJECT={{project-id}}" \
  --set-env-vars REDIS_HOST=XXX.XXX.XXX.XXX \
  --set-env-vars REDIS_PORT=6379 \
  egg1-app
```

今回のデプロイは最新のリビジョンにすぐにトラフィックが流れるように **--no-traffic** を指定せずにデプロイしました。

**GUI**: [Cloud Run 変更内容（リビジョン）](https://console.cloud.google.com/run/detail/us-central1/egg1-app/revisions?hl=ja&project={{project-id}})


## アプリケーションの確認

### URL の表示

以下のコマンドで URL を表示します。

```bash
echo $URL
```

Firestore エンドポイントに登録されているデータのIDで2回アクセスして、レスポンスの時間が短くなっている（キャッシュが効いている）事を確認します。

```bash
curl ${URL}firestore/<ID>
```

<walkthrough-footnote>ハンズオンの内容は以上になります。お疲れさまでした。</walkthrough-footnote>

## チャレンジ問題

### Cloud Build を使ってコンテナのビルドとデプロイを自動化してみよう


### Serverless NEG を使って複数の Cloud Run サービスをパスルーティングしてみよう


## Congraturations!

<walkthrough-conclusion-trophy></walkthrough-conclusion-trophy>

これにて Cloud Run を使ったアプリケーション開発のハンズオンは完了です！！

デモで使った資材が不要な方は、次の手順でクリーンアップを行って下さい。

## クリーンアップ（プロジェクトを削除）

作成したリソースを個別に削除する場合は、こちらのページの手順を実施せずに次のページに進んで下さい。

### プロジェクトの削除

```bash
gcloud projects delete {{project-id}}
```

## クリーンアップ（個別リソースの削除）

### Cloud Run の削除

```bash
gcloud run services delete egg1-app
```

### Firestore データの削除

Firestore コンソールから、ルートコレクションを削除してください。今回のハンズオンで作成したすべての user データが削除されます。

<!--
### Cloud SQL の削除

```bash
gcloud sql instances delete eggsql-1
``` -->

### Cloud Memorystore の削除

```bash
gcloud redis instances delete eggcache --region=us-central1
```

<walkthrough-footnote>クリーンアップは以上になります。ありがとうございました。</walkthrough-footnote>

<!--
## Cloud SQL を設定する

### Cloud SQL インスタンスの作成

今回は MySQL を利用します。

```bash
gcloud beta sql instances create --network=eggvpc --region=us-central1 --root-password=eggpassword --no-assign-ip eggsql
```

### データベース作成

Cloud Shell から接続する場合、Cloud SQL から見ると外部からの接続になるため、一時的にパブリックなIPを付与します。

```bash
gcloud sql instances patch --assign-ip eggsql
```

Cloud SQL のインスタンスに接続します。パスワードを尋ねられるので、作成時に指定したパスワードを入力します。

```bash
gcloud sql connect eggsql
```

接続できたら、データベースとテーブルを作成します。

```bash
create database egg;
```

```bash
create table egg.user (id varchar(10), email varchar(255), name varchar(255));
```

データベースとテーブルが作成できたら、パブリックIPを閉じます。
```bash
gcloud sql instances patch --no-assign-ip eggsql
```

<walkthrough-footnote>データベース側の準備は以上です。</walkthrough-footnote>

## Cloud Run に Cloud SQL を使うように修正する

MySQL は慣れてる方も多いと思うので、登録と取得のみを実装します。

### 接続情報を定義する

`app.yaml` を編集して、接続情報を定義します。以下の内容をファイルの末尾に追記してください。

```yaml
vpc_access_connector:
  name: "projects/{{project-id}}/locations/us-central1/connectors/egg-vpc-connector"

env_variables:
  DB_INSTANCE: "{{project-id}}:us-central1:eggsql"
  DB_USER: root
  DB_PASS: eggpassword
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
        dbName = "egg"
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
