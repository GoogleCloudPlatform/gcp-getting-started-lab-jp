# G.I.G ハンズオン #1

## Google Cloud Platform（GCP）プロジェクトの選択

ハンズオンを行う GCP プロジェクトを作成し、 GCP プロジェクトを選択して **Start/開始** をクリックしてください。

**今回のハンズオンは Firestore Native mode を使って行うため、既存のプロジェクト（特に Datastore をすでに使っているなど）だと不都合が生じる恐れがありますので、新しいプロジェクトを作成してください。**


<walkthrough-project-setup>
</walkthrough-project-setup>


<!-- Step 1 -->
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


<!-- Step 2 -->
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
    - Serverless VPC Access コネクタの削除
    - VPC Subnet と VPC の削除
    - Container Registry に登録したコンテナイメージの削除
    - Owner 権限をつけた dev-key.json の削除
    - サービスアカウント dev-gig-sa の削除


<!-- Step 3 -->
## 環境準備

<walkthrough-tutorial-duration duration=10></walkthrough-tutorial-duration>

最初に、ハンズオンを進めるための環境準備を行います。

下記の設定を進めていきます。

- gcloud コマンドラインツール設定
- GCP 機能（API）有効化設定
- サービスアカウント設定


<!-- Step 4 -->
## gcloud コマンドラインツール

Google Cloud は、CLI、GUI、Rest API から操作が可能です。ハンズオンでは主に CLI を使い作業を行いますが、GUI で確認する URL も併せて掲載します。


### gcloud コマンドラインツールとは?

gcloud コマンドライン インターフェースは、GCP でメインとなる CLI ツールです。このツールを使用すると、コマンドラインから、またはスクリプトや他の自動化により、多くの一般的なプラットフォーム タスクを実行できます。

たとえば、gcloud CLI を使用して、以下のようなものを作成、管理できます。

- Google Compute Engine 仮想マシン
- Google Kubernetes Engine クラスタ
- Google Cloud SQL インスタンス

**ヒント**: gcloud コマンドラインツールについての詳細は[こちら](https://cloud.google.com/sdk/gcloud?hl=ja)をご参照ください。

<walkthrough-footnote>次に gcloud CLI をハンズオンで利用するための設定を行います。</walkthrough-footnote>


<!-- Step 5 -->
## gcloud コマンドラインツール設定

gcloud コマンドでは操作の対象とするプロジェクトの設定が必要です。

### GCP のプロジェクト ID を環境変数に設定

環境変数 `GOOGLE_CLOUD_PROJECT` に GCP プロジェクト ID を設定します。

```bash
export GOOGLE_CLOUD_PROJECT="{{project-id}}"
```

### CLI（gcloud コマンド） から利用する GCP のデフォルトプロジェクトを設定

操作対象のプロジェクトを設定します。
権限を与えるための確認画面が出たら承認して進めます。

```bash
gcloud config set project $GOOGLE_CLOUD_PROJECT
```

<walkthrough-footnote>CLI（gcloud）を利用する準備が整いました。次にハンズオンで利用する機能を有効化します。</walkthrough-footnote>


<!-- Step 6 -->
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

```bash
gcloud services enable \
  cloudbuild.googleapis.com \
  containerregistry.googleapis.com \
  run.googleapis.com \
  redis.googleapis.com \
  vpcaccess.googleapis.com \
  servicenetworking.googleapis.com
```

**GUI**: [APIライブラリ](https://console.cloud.google.com/apis/library?project={{project-id}})または、クラウドコンソールの各サービスのページを開くと有効化ボタンが表示されます。

<!-- Step 7 -->
## GCP 環境設定 Part2

### サービスアカウントの作成

サービスアカウントとは、アプリケーションやVMインスタンスが使用するアカウントです。
サービスアカウントを作成し、アプリがそれを使用するようにします。

```bash
gcloud iam service-accounts create dev-gig-sa
```

作成したサービスアカウントに権限を付与します。 **今回のハンズオンは編集者権限を付与していますが、実際の開発の現場では必要最小限の権限を付与しましょう！**

```bash
gcloud projects add-iam-policy-binding {{project-id}} --member "serviceAccount:dev-gig-sa@{{project-id}}.iam.gserviceaccount.com" --role "roles/editor"
```

認証用のキーファイルを生成します。

```bash
gcloud iam service-accounts keys create dev-key.json --iam-account dev-gig-sa@{{project-id}}.iam.gserviceaccount.com
```

**GUI**: [サービスアカウント](https://console.cloud.google.com/iam-admin/serviceaccounts?project={{project-id}})

作成したキーを環境変数に設定します。クライアントライブラリは `GOOGLE_APPLICATION_CREDENTIALS` に設定されたファイルを使って認証を行います。

```bash
export GOOGLE_APPLICATION_CREDENTIALS=$(pwd)/dev-key.json
```

<!-- Step 8 -->
## GCP 環境設定 Part3

### Firestore を有効にする

今回のハンズオンでは Firestore のネイティブモードを使用します。

GCP コンソールの [Datastore](https://console.cloud.google.com/datastore/entities/query/kind?project={{project-id}}) に移動してください。

ネイティブモードを選択して進めてください。

![select-firestore-mode](https://storage.googleapis.com/egg-resources/egg1/public/select-mode.png)

その次のロケーション選択では `us-west2` を選択してください。

#### 別の画面が出る場合

**Datastore モードを選んだ場合でも、まだ一度もデータを登録していなければネイティブモードへの切り替えが可能です。**

`データベースが空であるため、ネイティブ モードの Cloud Firestore に切り替えてより多くの機能を利用できます。`というメッセージが表示された場合は、右上の`ネイティブ モードに切り替える`をクリックし、次に `モードを切り替え` をクリックしてください。

![switch1](https://storage.googleapis.com/egg-resources/egg1/public/firestore-switch-to-native1.png)
![switch2](https://storage.googleapis.com/egg-resources/egg1/public/firestore-switch-to-native2.png)

### ネイティブモードを有効にした後

ネイティブモードが有効になると、[Firestore コンソール](https://console.cloud.google.com/firestore/data/?project={{project-id}})でデータ管理の画面が有効になります。

<walkthrough-footnote>必要な機能が使えるようになりました。次に Cloud Run によるアプリケーションの開発に進みます。</walkthrough-footnote>


<!-- Step 9 -->
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
  - チャレンジ問題


<!-- Step 10 -->
## Cloud Shell 復旧手順

もしハンズオン中に Cloud Shell を閉じてしまったり、リロードした場合、以下のコマンドを再実行してから作業を再開してください。(Step 1 から順番に進めている場合はこのページはスキップいただいて結構です)

**Step 10 以降からの再開**

- 環境変数 `GOOGLE_CLOUD_PROJECT` に GCP プロジェクト ID を設定

```bash
export GOOGLE_CLOUD_PROJECT="{{project-id}}"
```

- CLI（gcloud コマンド） から利用する GCP のデフォルトプロジェクトを設定

```bash
gcloud config set project $GOOGLE_CLOUD_PROJECT
```

- 作業用のディレクトリへ移動

```bash
cd ~/cloudshell_open/gcp-getting-started-lab-jp/gig/gig02-01
```

- シークレットキーの参照先を設定

```bash
export GOOGLE_APPLICATION_CREDENTIALS=$(pwd)/dev-key.json
```

**Step 16 以降からの再開**

上記に加えて、以下も実行してからお進みください。

- Cloud Run の URL の取得

```bash
URL=$(gcloud run services describe --format=json --region=us-central1 --platform=managed gig02-app | jq .status.url -r)
echo ${URL}
```

<!-- Step 11 -->
## アプリケーション コードの確認

**このステップのコードは answer/step11/main.go と同じです。**

ハンズオン用のサンプル Web アプリケーションとして　Go 言語で API サーバーを作成していきます。

まずはカレント ディレクトリにある main.go を確認してください。
単純な HTTP リクエストに対して `Hello, GIG!` を返す Go のコードになります。


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
	fmt.Fprint(w, "Hello, GIG!")
}
```

確認できたら、Cloud Shell 上で動かしてみましょう。

```bash
go run main.go
```

ここまでは通常の Go アプリケーションと同じです。

**注意事項：今回のコードはあくまでサンプルの実装になりますのでご注意ください。**

<walkthrough-footnote>アプリケーションを作成し、起動することができました。次に実際にアプリケーションにアクセスしてみます。</walkthrough-footnote>


<!-- Step 12 -->
## Cloud Shell 上でアプリケーションを起動する

### CloudShell の機能を利用し、起動したアプリケーションにアクセスする

エディタ画面の右上にあるアイコン <walkthrough-web-preview-icon></walkthrough-web-preview-icon> をクリックし、"ポート 8080 でプレビュー"を選択します。
これによりブラウザで新しいタブが開き、Cloud Shell 上で起動しているコンテナにアクセスできます。

正しくアプリケーションにアクセスできると、 **Hello, GIG!** と表示されます。

確認が終わったら、Cloud Shell 上で Ctrl+C を入力して実行中のアプリケーションを停止します。

<walkthrough-footnote>Cloud Shell 上で動いているアプリケーションにアクセスできました。次にアプリケーションをコンテナ化します。</walkthrough-footnote>


<!-- Step 13 -->
## Cloud Shell 上でコンテナ化されたアプリケーションを起動する

### コンテナを作成する

Go 言語で作成されたサンプル Web アプリケーションをコンテナ化します。
ここで作成したコンテナは Cloud Shell インスタンスのローカルに保存されます。

```bash
docker build -t gcr.io/$GOOGLE_CLOUD_PROJECT/gig02-app:v1 .
```

**ヒント**: `docker build` コマンドを叩くと、Dockerfile が読み込まれ、そこに記載されている手順通りにコンテナが作成されます。

### Cloud Shell 上でコンテナを起動する

上の手順で作成したコンテナを Cloud Shell 上で起動します。

```bash
docker run -p 8080:8080 \
--name gig02-app \
-e GOOGLE_APPLICATION_CREDENTIALS=/tmp/keys/dev-key.json \
-v $PWD/dev-key.json:/tmp/keys/dev-key.json:ro \
gcr.io/$GOOGLE_CLOUD_PROJECT/gig02-app:v1
```

**ヒント**: Cloud Shell 環境の 8080 ポートを、コンテナの 8080 ポートに紐付け、フォアグラウンドで起動しています。

<walkthrough-footnote>アプリケーションをコンテナ化し、起動することができました。次に実際にアプリケーションにアクセスしてみます。</walkthrough-footnote>


<!-- Step 14 -->
## 作成したコンテナの動作確認

### CloudShell の機能を利用し、起動したアプリケーションにアクセスする

画面右上にあるアイコン <walkthrough-web-preview-icon></walkthrough-web-preview-icon> をクリックし、"ポート 8080 でプレビュー"を選択します。
これによりブラウザで新しいタブが開き、Cloud Shell 上で起動しているコンテナにアクセスできます。

正しくアプリケーションにアクセスできると、先程と同じように `Hello GIG!` と表示されます。

確認が終わったら、Cloud Shell 上で Ctrl+C を入力して実行中のコンテナを停止します。


<walkthrough-footnote>Cloud Shell 上で動いているコンテナにアクセスできました。次に Cloud Run にデプロイするための準備を進めます。</walkthrough-footnote>


<!-- Step 15 -->
## イメージのレジストリへの登録

先程作成したイメージは Cloud Shell 内に保存されているため、他の場所から参照ができません。
他の場所から利用できるようにするために、GCP 上のプライベートなイメージ置き場（コンテナレジストリ）に登録します。

### 作成したイメージをコンテナレジストリ（Google Container Registry）へ登録（プッシュ）する

```bash
docker push gcr.io/$GOOGLE_CLOUD_PROJECT/gig02-app:v1
```

**GUI**: [コンテナレジストリ](https://console.cloud.google.com/gcr/images/{{project-id}}?project={{project-id}})

<walkthrough-footnote>次に Cloud Run にコンテナをデプロイをします。</walkthrough-footnote>


<!-- Step 16 -->
## Cloud Run にコンテナをデプロイする

### gcloud コマンドで Cloud Run の Service を作成し、コンテナをデプロイします

Cloud Run でのサービス名は gig02-app にしています。

```bash
gcloud run deploy --image=gcr.io/$GOOGLE_CLOUD_PROJECT/gig02-app:v1 \
  --service-account="dev-gig-sa@{{project-id}}.iam.gserviceaccount.com" \
  --platform=managed \
  --region=us-central1 \
  --allow-unauthenticated \
  gig02-app
```

**参考**: デプロイが完了するまで、1〜2分程度かかります。

**GUI**: [Cloud Run](https://console.cloud.google.com/run?project={{project-id}})

### Cloud Run の Service の URLを取得します

```bash
URL=$(gcloud run services describe --format=json --region=us-central1 --platform=managed gig02-app | jq -r .status.url)
echo ${URL}
```

ブラウザから取得した URL を開いてアプリケーションの動作を確認します。

**GUI**: [Cloud Run サービス情報](https://console.cloud.google.com/run/detail/us-central1/gig02-app/general?project={{project-id}})


<!-- Step 17 -->
## Cloud Runのログを確認します

### コンテナのログを確認
**GUI**: [Cloud Run ログ](https://console.cloud.google.com/run/detail/us-central1/gig02-app/logs?project={{project-id}})

アクセスログを確認します。

<walkthrough-footnote>Cloud Run にサンプル Web アプリケーションがデプロイされました。次は Cloud Build の設定に入ります。</walkthrough-footnote>



<!-- Step 18 -->
## Cloud Build によるビルド、デプロイの自動化

Cloud Build を利用し今まで手動で行っていたアプリケーションのビルド、コンテナ化、リポジトリへの登録、Cloud Run へのデプロイを自動化します。

### Cloud Build サービスアカウントへの権限追加

Cloud Build を実行する際に利用されるサービスアカウントを取得し、環境変数に格納します。

```bash
export CB_SA=$(gcloud projects get-iam-policy $GOOGLE_CLOUD_PROJECT | grep cloudbuild.gserviceaccount.com | uniq | cut -d ':' -f 2)
```

上で取得したサービスアカウントに Cloud Build から自動デプロイをさせるため Cloud Run 管理者とサービス アカウント ユーザーのロールを与えます。

```bash
gcloud projects add-iam-policy-binding $GOOGLE_CLOUD_PROJECT  --member serviceAccount:$CB_SA --role roles/run.admin
```

```bash
gcloud projects add-iam-policy-binding $GOOGLE_CLOUD_PROJECT  --member serviceAccount:$CB_SA --role roles/iam.serviceAccountUser
```

<walkthrough-footnote>Cloud Build で利用するサービスアカウントに権限を付与し、Cloud Run に自動デプロイできるようにしました。</walkthrough-footnote>


<!-- Step 19 -->
## Cloud Build によるビルド、デプロイの自動化

### cloudbuild.yaml の確認

Cloud Build のジョブの中身は `gig02-01` フォルダ下にある `cloudbuild.yaml` に定義されているので中身を確認してみましょう。

```
steps:
- name: 'gcr.io/cloud-builders/docker'
  args: ['build', '-t', 'gcr.io/$PROJECT_ID/gig02-app:$BUILD_ID', '.']

- name: 'gcr.io/cloud-builders/docker'
  args: ['push', 'gcr.io/$PROJECT_ID/gig02-app:$BUILD_ID']

- name: 'gcr.io/cloud-builders/gcloud'
  args: [
    'run',
    'deploy',
    '--image=gcr.io/$PROJECT_ID/gig02-app:$BUILD_ID',
    '--service-account=dev-gig-sa@$PROJECT_ID.iam.gserviceaccount.com',
    '--platform=managed',
    '--region=us-central1',
    '--allow-unauthenticated',
    '--set-env-vars',
    'GOOGLE_CLOUD_PROJECT=$PROJECT_ID',
    'gig02-app',
  ]
```

3つあるステップは上から順にDockerイメージのビルド、プッシュ、Cloud Run へのデプロイを行っています。

手動で docker build コマンドでコンテナをビルドした際は、イメージのタグを固定の `gcr.io/{{project-id}}/gig02-app:v1` としていましたが、Cloud Build の1ステップ目を見ると `gcr.io/{{project-id}}/gig02-app:$BUILD_ID` としている事が分かります。$BUILD_ID には Cloud Build のジョブの ID が入ります。

<walkthrough-footnote>それでは　Cloud Build のジョブを実行してみましょう。</walkthrough-footnote>


<!-- Step 20 -->
## Cloud Build によるビルド、デプロイの自動化

### Cloud Build のジョブの実行

```bash
gcloud builds submit .
```

**ヒント**: コマンド末尾の `.` は、 カレント ディレクトリに存在するコンフィグファイル `cloudbuild.yaml` を使うことを示します。


### ジョブの確認

[Cloud Build の履歴](https://console.cloud.google.com/cloud-build/builds;region=global?project={{project-id}}) にアクセスし、ビルドが実行されていることを確認します。


### Cloud Run の確認

Cloud Run のコンテナの Image URL が Cloud Build で作成されたイメージになっていることを確認します。

**GUI**: [Cloud Run リビジョン](https://console.cloud.google.com/run/detail/us-central1/gig02-app/revisions?project={{project-id}})


<walkthrough-footnote>Cloud Build による自動ビルド・デプロイの設定が完了しました。次は Firestore を読み書きする実装に入ります。</walkthrough-footnote>


<!-- Step 21 -->
## Firestore の利用

サンプル Web アプリケーションが Firestore を利用するように編集していきます。今回は、基本的な CRUD 処理を実装します。

### 依存関係の追加

Firestore にアクセスするためにクライアントライブラリが必要です。
Go 言語の場合、 `go.mod` に Go パッケージの依存関係が記載されます。

今回のハンズオンで使う依存関係を全て書いた `go.mod` ファイルは既に `gig02-01` フォルダに配置済みです。

```
module github.com/GoogleCloudPlatform/gcp-getting-started-lab-jp/gig/gig02-01

go 1.16

require (
	cloud.google.com/go v0.80.0 // indirect
	cloud.google.com/go/firestore v1.5.0
	github.com/golang/protobuf v1.5.2 // indirect
	github.com/gomodule/redigo v2.0.0+incompatible
	golang.org/x/mod v0.4.2 // indirect
	golang.org/x/net v0.0.0-20210331060903-cb1fcc7394e5 // indirect
	golang.org/x/oauth2 v0.0.0-20210323180902-22b0adad7558 // indirect
	google.golang.org/api v0.43.0
	google.golang.org/genproto v0.0.0-20210330181207-2295ebbda0c6 // indirect
)
```

<walkthrough-footnote>Firestore を操作するコードを実装していきましょう。</walkthrough-footnote>



<!-- Step 22 -->
## Firestore の利用

### データの追加・取得機能

**このステップで作成したコードは answer/step22/main.go になります。**

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
		ref, _, err := client.Collection("users").Add(ctx, u)
		if err != nil {
			log.Fatalf("Failed adding data: %v", err)
			w.WriteHeader(http.StatusInternalServerError)
			return
		}
		log.Printf("success: id is %v", ref.ID)
		fmt.Fprintf(w, "success: id is %v \n", ref.ID)

	// 取得処理
	case http.MethodGet:
		docs, err := client.Collection("users").Documents(ctx).GetAll()
		if err != nil {
			log.Fatal(err)
		}
		if len(docs) == 0 {
			w.WriteHeader(http.StatusNoContent)
			return
		}

		var users []User
		for _, doc := range docs {
			var u User
			if err := doc.DataTo(&u); err != nil {
				log.Fatal(err)
			}
			u.ID = doc.Ref.ID
			log.Print(u)
			users = append(users, u)
		}
		json, err := json.Marshal(users)
		if err != nil {
			w.WriteHeader(http.StatusInternalServerError)
			return
		}
		w.Write(json)

	// それ以外のHTTPメソッド
	default:
		w.WriteHeader(http.StatusMethodNotAllowed)
		return
	}
}

type User struct {
	ID    string `firestore:"-" json:"id"`
	Email string `firestore:"email" json:"email"`
	Name  string `firestore:"name" json:"name"`
}

func getUserBody(r *http.Request) (u User, err error) {
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

こちらのコードは実際のプロジェクトの Firestore にデータを追加、または Firestore からデータを取得しようとしています。

<walkthrough-footnote>次のステップでコードをデプロイし、動作を確認してみましょう。</walkthrough-footnote>


<!-- Step 23 -->
## デプロイと確認 (Firestore 登録・取得機能の追加)

### Cloud Run へのデプロイ

Cloud Build を実行し、アプリケーションを Cloud Run にデプロイしてみましょう。

```bash
gcloud builds submit .
```

### URL の表示

以下のコマンドで URL を表示します。

```bash
echo $URL
```

### Firestore を利用した操作の実施

Cloud Shell から Cloud Run の Service の URL に対して、以下のような cURL コマンドをいくつか実行し、データの登録・取得の処理が行われることを確認しましょう。

**登録**

```
curl -X POST -d '{"email":"taro@example.com", "name":"Cloud Taro"}' ${URL}/firestore
```

**取得（全件）**

```
curl ${URL}/firestore
```

<walkthrough-footnote>次は登録済みのデータを更新・削除する実装を行います。</walkthrough-footnote>


<!-- Step 24 -->
## Firestore の利用
### データの更新・削除処理

**このステップで作成したコードは answer/step24/main.go になります。**

先程のステップで実装したデータの登録処理では、各データに対して一意な ID が付与されていました。
ここでは、その ID を用いてデータを更新・削除する処理を追加します。
リクエストのパスに対象の ID を指定することとします。

更新 API では、複数のドキュメント（コレクション）の中から一意なユーザデータのドキュメントを対象とするため、 `.Doc(id)` のように ID を指定しています。そして、そのドキュメントに対して Set メソッドを使って受け取ったリクエストの内容を書き込みます。

削除 API は指定された ID のドキュメントを削除するようにしています。

`main.go` の import の中に以下を追記してください。

```go
"strings"
```

main 関数の中でハンドラ関数を追加します。

```go
	http.HandleFunc("/firestore/", firestoreHandler)
```

続いて `MethodGet` の case 句の後に以下の case 句を追記しましょう。

```go
	// 更新処理
	case http.MethodPut:
		id := strings.TrimPrefix(r.URL.Path, "/firestore/")
		u, err := getUserBody(r)
		if err != nil {
			log.Fatal(err)
			w.WriteHeader(http.StatusInternalServerError)
			return
		}

		_, err = client.Collection("users").Doc(id).Set(ctx, u)
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
```

<walkthrough-footnote>データ更新・削除の機能を実装したので Cloud Run にデプロイしましょう。</walkthrough-footnote>


<!-- Step 25 -->
## デプロイと確認 (Firestore 更新・削除機能の追加)

### Cloud Run へのデプロイ

Cloud Build を実行し、アプリケーションを Cloud Run にデプロイしてみましょう。

```bash
gcloud builds submit .
```

### URL の表示

以下のコマンドで URL を表示します。

```bash
echo $URL
```

### Firestore を利用した操作の実施

Cloud Shell から Cloud Run の Service の URL に対して、以下のような cURL コマンドをいくつか実行し、データの更新・削除の処理が行われることを確認しましょう。

**更新**

`<ID>` へはコンソールや GET リクエストなどで確認した `id` の値をセットしてください。

![firestore-id](https://storage.googleapis.com/egg-resources/egg1/public/firestore-id.jpg)

```bash
curl -X PUT -d '{"email":"taro@example.net", "name":"Cloud Taro"}' ${URL}/firestore/<ID>
```

**削除**

`<ID>` へは削除する `id` の値を指定してください。

```bash
curl -X DELETE ${URL}/firestore/<ID>
```

<walkthrough-footnote>Firestore についての実装は以上になります。次に Memorystore を操作できるようにしていきます。</walkthrough-footnote>


<!-- Step 26 -->
## Serverless VPC Access のコネクタを作成する

ここからは Memorystore を Cloud Run と連携させていきます。
まずは VPC ネットワークを作成します。

```bash
gcloud compute networks create gigvpc --subnet-mode=custom
```

VPC の中にサブネットを設定します。

```bash
gcloud compute networks subnets create us-subnet --network=gigvpc --region=us-central1 --range=10.128.0.0/20
```

作成したサブネットの範囲内に Serverless VPC Access コネクタを設定します。コネクタを介して Cloud Run から Memorystore にアクセスできるようになります。

```bash
gcloud compute networks vpc-access connectors create gig-vpc-connector \
--network gigvpc \
--region us-central1 \
--range 10.129.0.0/28
```


<!-- Step 27 -->
## Memorystore for Redis を使う

Memorystore for Redis を使ってデータのキャッシュをしてみましょう。
Firestore のデータをキャッシュから返せるように修正していきます。

### Redis インスタンスを作成する

```bash
gcloud redis instances create --network=gigvpc --region=us-central1 gigcache
```


<!-- Step 28 -->
## Firestore ハンドラの修正

**このステップで作成したコードは answer/step28/main.go になります。**

現在、ユーザーデータを全件取るしかなくキャッシュする意味がないため、単一ユーザのデータをキーを指定して取得する機能を追加します。

`main.go` の firestoreHandler の MethodGet を修正していきます。以下の内容に修正してください。

```go
	// 取得処理
	case http.MethodGet:
		id := strings.TrimPrefix(r.URL.Path, "/firestore/")
		log.Printf("id=%v", id)
		if id == "/firestore" || id == "" {
			docs, err := client.Collection("users").Documents(ctx).GetAll()
			if err != nil {
				log.Fatal(err)
			}
			if len(docs) == 0 {
				w.WriteHeader(http.StatusNoContent)
				return
			}

			var users []User
			for _, doc := range docs {
				var u User
				if err := doc.DataTo(&u); err != nil {
					log.Fatal(err)
				}
				u.ID = doc.Ref.ID
				log.Print(u)
				users = append(users, u)
			}
			json, err := json.Marshal(users)
			if err != nil {
				w.WriteHeader(http.StatusInternalServerError)
				return
			}
			w.Write(json)
			return
		}
		// (Step 29) 置き換えここから
		doc, err := client.Collection("users").Doc(id).Get(ctx)
		if err != nil {
			w.WriteHeader(http.StatusInternalServerError)
			return
		}
		var u User
		if err := doc.DataTo(&u); err != nil {
			log.Fatal(err)
		}
		u.ID = doc.Ref.ID
		json, err := json.Marshal(u)
		if err != nil {
			w.WriteHeader(http.StatusInternalServerError)
			return
		}
		w.Write(json)
		// (Step 29) 置き換えここまで
```

これでまずは単一のユーザーデータを取得できるようになりました。


<!-- Step 29 -->
## Firestore ハンドラの修正
次に Redis 操作のためのコードを追加します。

**このステップで作成したコードは answer/step29/main.go になります。**

import に以下を追記してください。

```go
"github.com/gomodule/redigo/redis"
```

main 関数の最初の処理として以下を追記してください。

```go
	// Redis 初期化
	initRedis()
```

`main.go` 末尾に以下を追記してください。

```go
var pool *redis.Pool

func initRedis() {

	host := os.Getenv("REDIS_HOST")
	port := os.Getenv("REDIS_PORT")
	addr := fmt.Sprintf("%s:%s", host, port)

	pool = &redis.Pool{
		MaxIdle: 10,
		Dial:    func() (redis.Conn, error) { return redis.Dial("tcp", addr) },
	}
}
```

Firestore クライアント作成のブロックと switch 文の間に以下を追記してください。

```go
	// Redis クライアント作成
	conn := pool.Get()
	defer conn.Close()
```

先程の単一ユーザーデータを取得するコードに対して、キャッシュを取得・セットするコードを追加します。
取得処理にあるコメントの `(Step 29) 置き換えここから` から `(Step 29) 置き換えここまで` の部分を以下のコードに置き換えましょう。

```go
		// (Step 29) 置き換えここから
		// Redis クライアント作成
		cache, err := redis.String(conn.Do("GET", id))
		if err != nil {
			log.Println(err)
		}
		log.Printf("cache : %v", cache)

		if cache != "" {
			w.Write([]byte(cache))
			log.Printf("cache hit")
			return
		}
		doc, err := client.Collection("users").Doc(id).Get(ctx)
		if err != nil {
			w.WriteHeader(http.StatusInternalServerError)
			return
		}
		var u User
		if err := doc.DataTo(&u); err != nil {
			log.Fatal(err)
		}
		u.ID = doc.Ref.ID
		json, err := json.Marshal(u)
		if err != nil {
			w.WriteHeader(http.StatusInternalServerError)
			return
		}
		conn.Do("SET", id, string(json))
		w.Write(json)

	// (Step 29) 置き換えここまで
```

<!-- Step 30 -->
## Cloud Run のデプロイ オプションの更新

Serverless VPC Access は Cloud Run デプロイ時に `--vpc-connector` を指定することで接続設定ができます。
また、環境変数で Memorystore for Redis への接続情報を Cloud Run のコンテナに持たせることができます。

### Redis インスタンスの IP アドレスの確認

以下のコマンドを実行して Redis インスタンスの IP アドレスを取得します。

```bash
gcloud redis instances list --format=json  --region=us-central1 | jq -r '.[0].host'
```

### cloudbuild.yaml の更新

cloudbuild.yaml を以下のように更新します。
**REDIS_HOST** の `XXX.XXX.XXX.XXX` には先程作成した REDIS_HOST の IP アドレスを指定してください。

```
steps:
- name: 'gcr.io/cloud-builders/docker'
  args: ['build', '-t', 'gcr.io/$PROJECT_ID/gig02-app:$BUILD_ID', '.']

- name: 'gcr.io/cloud-builders/docker'
  args: ['push', 'gcr.io/$PROJECT_ID/gig02-app:$BUILD_ID']

- name: 'gcr.io/cloud-builders/gcloud'
  args: [
    'run',
    'deploy',
    '--image=gcr.io/$PROJECT_ID/gig02-app:$BUILD_ID',
    '--service-account=dev-gig-sa@$PROJECT_ID.iam.gserviceaccount.com',
    '--platform=managed',
    '--region=us-central1',
    '--allow-unauthenticated',
    '--vpc-connector=gig-vpc-connector',
    '--set-env-vars',
    'GOOGLE_CLOUD_PROJECT=$PROJECT_ID',
    '--set-env-vars',
    'REDIS_HOST=XXX.XXX.XXX.XXX',
    '--set-env-vars',
    'REDIS_PORT=6379',
    'gig02-app',
  ]
```


<!-- Step 31 -->
## デプロイと確認 (キャッシュ機能の追加)

### Cloud Run へのデプロイ

Cloud Build を実行し、アプリケーションを Cloud Run にデプロイしてみましょう。

```bash
gcloud builds submit .
```

### URL の表示

以下のコマンドで URL を表示します。

```bash
echo $URL
```

Firestore エンドポイントに登録されているデータの ID で 2 回アクセスして、レスポンスの時間が短くなっている（キャッシュが効いている）事を確認します。

```bash
curl ${URL}/firestore/<ID>
```

### コンテナのログを確認
**GUI**: [Cloud Run ログ](https://console.cloud.google.com/run/detail/us-central1/gig02-app/logs?project={{project-id}})

アクセスログから 2 回目のアクセスの処理時間が短くなっていることを確認します。
また、アプリのログからキャッシュがヒットしていることも確認します。

<walkthrough-footnote>ハンズオンの内容は以上になります。お疲れさまでした。</walkthrough-footnote>


<!-- Step 32 -->
## チャレンジ問題: Cloud Run の新リビジョンの段階的なデプロイ

Cloud Run には、リビジョン間でトラフィックを切り替える機能があり、A/B テストやカナリアデプロイを行なうことが可能です。main.go の `Hello, GIG!` の文言を任意の言葉に変更し、以下の手順でトラフィックの段階的な移行を試してみましょう。

### couldbuild.yaml の変更

以下のように Cloud Run のデプロイ オプションに **--no-traffic** を追加します。
**REDIS_HOST** の `XXX.XXX.XXX.XXX` には先程作成した REDIS_HOST の IP アドレスを指定してください。

```
steps:
- name: 'gcr.io/cloud-builders/docker'
  args: ['build', '-t', 'gcr.io/$PROJECT_ID/gig02-app:$BUILD_ID', '.']

- name: 'gcr.io/cloud-builders/docker'
  args: ['push', 'gcr.io/$PROJECT_ID/gig02-app:$BUILD_ID']

- name: 'gcr.io/cloud-builders/gcloud'
  args: [
    'run',
    'deploy',
    '--image=gcr.io/$PROJECT_ID/gig02-app:$BUILD_ID',
    '--service-account=dev-gig-sa@$PROJECT_ID.iam.gserviceaccount.com',
    '--platform=managed',
    '--region=us-central1',
    '--allow-unauthenticated',
    '--vpc-connector=gig-vpc-connector',
    '--set-env-vars',
    'GOOGLE_CLOUD_PROJECT=$PROJECT_ID',
    '--set-env-vars',
    'REDIS_HOST=XXX.XXX.XXX.XXX',
    '--set-env-vars',
    'REDIS_PORT=6379',
    '--no-traffic',
    'gig02-app',
  ]
```

### Cloud Build のジョブを実行

```bash
gcloud builds submit .
```

### リビジョン情報の確認

以下のコマンドを実行します。

```bash
gcloud run revisions list --platform=managed --region=us-central1 --service=gig02-app
```

**--no-traffic** を指定しているため、まだ以前のリビジョンがトラフィックを処理しています。

**GUI**: [Cloud Run 変更内容（リビジョン）](https://console.cloud.google.com/run/detail/us-central1/gig02-app/revisions?hl=ja&project={{project-id}})

### Cloud Run のトラフィック切り替えの実行

以下のコマンドで半分のトラフィックを最新のリビジョンに切り替えます。`to-revisions`には一つ前のステップで調べた最新のリビジョン名を指定してください。

```bash
gcloud run services update-traffic --to-revisions=gig02-app-00008-ruw=50 --platform=managed --region=us-central1 gig02-app
```

**GUI**: [Cloud Run 変更内容（リビジョン）](https://console.cloud.google.com/run/detail/us-central1/gig02-app/revisions?hl=ja&project={{project-id}})


### アプリケーションの確認

以下のコマンドで URL を表示します。

```bash
echo $URL
```

cURL コマンドを何度か使って、以前のメッセージと最新のメッセージの両方が返ってくることを確認します。

### 全てのトラフィックの切り替え

下記のコマンドを使って全てのトラフィックを最新のリビジョンへ向けます。完了したら、以前と同様に cURL コマンドを使って最新のメッセージのみが返ってくることを確認します。

```bash
gcloud run services update-traffic --to-latest --platform=managed --region=us-central1 gig02-app
```

## チャレンジ問題: Cloud Source Repositories へのコミットをトリガーにしたデプロイ

[Cloud Source Repositories](https://cloud.google.com/source-repositories/) へリポジトリを作成して [Cloud Build トリガー](https://cloud.google.com/cloud-build/docs/running-builds/automate-builds) を設定し、Git の Push をトリガーにしたアプリケーションのビルド、Cloud Run へのデプロイを自動化してみましょう。

### Cloud Source Repository（CSR）に Git レポジトリを作成

今回利用しているソースコードを配置するためのプライベート Git リポジトリを、Cloud Source Repository（CSR）に作成します。

```bash
gcloud source repos create gig02-handson
```

**GUI**: [Source Repository](https://source.cloud.google.com/{{project-id}}/gig02-handson): 作成前にアクセスすると拒否されます。

### Cloud Build トリガーを作成

Cloud Build に前の手順で作成した、プライベート Git リポジトリに push が行われたときに起動されるトリガーを作成します。

```bash
gcloud beta builds triggers create cloud-source-repositories --description="gig02handson" --repo=gig02-handson --branch-pattern=".*" --build-config="gig/gig02-01/cloudbuild.yaml"
```

**GUI**: [ビルドトリガー](https://console.cloud.google.com/cloud-build/triggers?project={{project-id}})

### Git クライアント設定

Git クライアントで CSR と認証するための設定を行います。

```bash
git config --global credential.https://source.developers.google.com.helper gcloud.sh
```

**ヒント**: git コマンドと gcloud で利用している IAM アカウントを紐付けるための設定です。

### 利用者設定

USERNAME を自身のユーザ名に置き換えて実行し、利用者を設定します。

```bash
git config --global user.name "USERNAME"
```

### メールアドレス設定

USERNAME@EXAMPLE.com を自身のメールアドレスに置き換えて実行し、利用者のメールアドレスを設定します。

```bash
git config --global user.email "USERNAME@EXAMPLE.com"
```

### Git リポジトリ設定

CSR を Git のリモートレポジトリとして登録します。
これで git コマンドを使い Cloud Shell 上にあるファイル群を管理することができます。

```bash
git remote add google https://source.developers.google.com/p/$GOOGLE_CLOUD_PROJECT/r/gig02-handson
```

### CSR への資材の転送（プッシュ）

以前の手順で作成した CSR は空の状態です。
git push コマンドを使い、CSR に資材を転送（プッシュ）します。

```bash
git push google master
```

**GUI**: [Source Repository](https://source.cloud.google.com/{{project-id}}/gig02-handson) から資材がプッシュされたことを確認できます。


### Cloud Build の自動実行を確認

[Cloud Build の履歴](https://console.cloud.google.com/cloud-build/builds?project={{project-id}}) にアクセスし、git push コマンドを実行した時間にビルドが実行されていることを確認します。
恐らくこのビルドは失敗していると思います。更に時間に余裕がある方は、どこがエラーになっているか Cloud Build のログから確認して修正してみましょう！

## チャレンジ問題: キャッシュのライフサイクル

これまでの実装では、キャッシュの保持期間の設定がなされていないため、データを変更したり削除したりした後もキャッシュに残った古いデータが返されてしまいます。
キャッシュの保持期間を設定したり、データの変更や削除のときにキャッシュも書き換えたりすることでデータの不整合をなくしましょう。

- 参考: Redis のコマンドリファレンス
  - [SET](https://redis.io/commands/set) - 有効期間を設定するオプションがあります
  - [DEL](https://redis.io/commands/del) - 指定されたデータを削除します

## チャレンジ問題: Buildpacks

Buildpacks を使うと、Dockerfile を書かなくてもアプリのソースコードからイメージをビルドすることができるようになります。

Cloud Shell では `pack` コマンドは最初から使えるようになっているので、Dockerfile を削除しても `pack` コマンドでビルドできることを確かめてみましょう。
Google が提供するビルダーの名称は `gcr.io/buildpacks/builder:v1` です。.NET, Go, Java, Node.js, Python をサポートしています。

- 参考 [Buildpacksのドキュメント](https://buildpacks.io/docs/app-developer-guide/build-an-app/)


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
gcloud run services delete gig02-app --platform managed --region=us-central1
```

### Firestore データの削除

Firestore コンソールから、ルートコレクションを削除してください。今回のハンズオンで作成したすべての user データが削除されます。

### Cloud Memorystore の削除

```bash
gcloud redis instances delete gigcache --region=us-central1
```

### Serverless VPC Access コネクタの削除

```bash
gcloud compute networks vpc-access connectors delete gig-vpc-connector --region us-central1
```


### VPC の削除

```bash
gcloud compute networks subnets delete us-subnet --region=us-central1
```

```bash
gcloud compute networks delete gigvpc
```

### Container Registry に登録したコンテナイメージの削除

Container Registry コンソールから、イメージを選択して削除してください。

### Cloud Source Repositories に作成したリポジトリの削除

[CSR の設定画面](https://source.cloud.google.com/admin/settings?projectId={{project-id}}&repository=gig02-handson) にアクセスし、「このリポジトリを削除」を実行

### 編集者権限をつけた dev-key.json の削除

```bash
rm ~/cloudshell_open/gcp-getting-started-lab-jp/gig/gig02-01/dev-key.json
```

### サービスアカウントに付与したロールの取り消し

```bash
gcloud projects remove-iam-policy-binding {{project-id}} --member "serviceAccount:dev-gig-sa@{{project-id}}.iam.gserviceaccount.com" --role "roles/editor"
```

### サービスアカウントの削除

```bash
gcloud iam service-accounts delete dev-gig-sa@{{project-id}}.iam.gserviceaccount.com
```
