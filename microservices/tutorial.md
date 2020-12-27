# ハンズオン：Microservices development on GCP

## 1. 事前準備

### GCP プロジェクトの作成

GCP プロジェクトを新規作成します。このハンズオンは、プロジェクトオーナーの権限で作業を進める前提ですので、自分専用のプロジェクトを用意するようにしてください。


### Cloud Datastore の有効化

Cloud Console から「[データストア](https://console.cloud.google.com/datastore)」メニューを
開いて、「DATASTORE モードを選択」をクリックします。
  
「ロケーションを選択」には「us-east1 (South Carolina)」を選択して、「データベースを作成」をクリックします。

### Cloud Shell の起動

これ以降の作業は、基本的には、Cloud Shell 端末でのコマンド操作で行います。

Cloud Shell を開いて、次のコマンドを実行します。ここでは、Project ID を環境変数にセットすると共に、gcloud コマンドのデフォルトプロジェクトに設定します。
（`[your project ID]` の部分はハンズオンを進める環境の Project ID に置き換えてください。）

```
PROJECT_ID=[your project ID]
gcloud config set project $PROJECT_ID
```

「Cloud Shell の承認」というポップアップが表示されますので、「承認」をクリックしてください。

*コマンドの出力例*
```
Updated property [core/project].
```

**注意：作業中に新しい Cloud Shell 端末を開いた場合は、必ず、最初にこのコマンドを実行してください。**

### API の有効化

次のコマンドを実行します。ここでは、Cloud Build, Cloud Run, Cloud Scheduler, Workflows, の API を有効化しています。

```
gcloud services enable \
  cloudbuild.googleapis.com \
  run.googleapis.com \
  cloudscheduler.googleapis.com \
  workflows.googleapis.com
```

*コマンドの出力例*
```
Operation "operations/acf.411c0bde-0c11-47af-979a-2cc1680b5650" finished successfully.
```

### ソースコードのダウンロード

次のコマンドを実行します。ここでは、Cloud Shell 端末のホームディレクトリーにこの GitHub リポジトリの内容をクローンしています。

```
cd $HOME
git clone https://github.com/enakai00/gcp-getting-started-lab-jp
```

*コマンドの出力例*
```
Cloning into 'gcp-getting-started-lab-jp'...
remote: Enumerating objects: 161, done.
remote: Counting objects: 100% (161/161), done.
remote: Compressing objects: 100% (109/109), done.
remote: Total 1355 (delta 73), reused 89 (delta 35), pack-reused 1194
Receiving objects: 100% (1355/1355), 8.93 MiB | 4.78 MiB/s, done.
Resolving deltas: 100% (657/657), done.
```

## 2. Cloud Run を用いた REST API サービスの構築

このセクションで実施する内容

- ローカル環境でのアプリの動作確認
- Cloud Build によるコンテナイメージのビルド
- Cloud Run にイメージをデプロイ
- デプロイしたサービスの動作確認

### ローカル環境でのアプリの動作確認

次のコマンドを実行します。ここでは、簡単な REST API を提供するサンプルアプリ [main.py](https://github.com/enakai00/gcp-getting-started-lab-jp/blob/master/microservices/hello_world/main.py) をローカル環境で実行しています。

```
cd $HOME/gcp-getting-started-lab-jp/microservices/hello_world
python3 main.py
```

*コマンドの出力例*
```
 * Serving Flask app "main" (lazy loading)
 * Environment: production
   WARNING: This is a development server. Do not use it in a production deployment.
   Use a production WSGI server instead.
 * Debug mode: on
 * Running on http://0.0.0.0:8080/ (Press CTRL+C to quit)
 * Restarting with stat
 * Debugger is active!
 * Debugger PIN: 185-356-817
``` 

アプリケーションはフォアグラウンドで実行を続けているので、新しい Cloud Shell 端末を開いて、そちらから curl コマンドでアプリケーションにリクエストを送信します。

次のコマンドを実行します。

```
curl http://localhost:8080
```

*コマンドの出力例*
```
Hello world service.
```

次は、POST メソッドでデータを送信します。次のコマンドを実行します。

```
curl -X POST \
  -H "Content-Type: application/json" \
  -d '{"name":"Google Cloud Platform"}' \
  -s http://localhost:8080/api/v1/hello
```

*コマンドの出力例*
```
{
  "message": "Hello, Google Cloud Platform!"
}
```

動作確認ができたら、Ctrl+C でアンプルアプリを停止します。

### Cloud Build によるコンテナイメージのビルド

次のコマンドを実行します。ここでは、[Dockerfile](https://github.com/enakai00/gcp-getting-started-lab-jp/blob/master/microservices/hello_world/Dockerfile) に
従って、コンテナイメージをビルドしています。

> Dockerfile の末尾 `CMD exec gunicorn ...` から分かるように、このイメージでは、[Gunicorn](https://gunicorn.org/) を用いてアプリケーションを起動します。

```
cd $HOME/gcp-getting-started-lab-jp/microservices/hello_world
gcloud builds submit --tag gcr.io/$PROJECT_ID/hello-world-service
```

*コマンドの出力例*
```
Creating temporary tarball archive of 4 file(s) totalling 1.8 KiB before compression.
Uploading tarball of [.] to [gs://microservices-hands-on_cloudbuild/source/1609051197.03811-c0082d92ec804586ae303353057a9dc0.tgz]

...中略...

DONE
-----------------------------------------------------------------------------------------------------------------------------------------------
ID                                    CREATE_TIME                DURATION  SOURCE                                                                                               IMAGES                                                       STATUS
40cf97df-aeb7-44a9-b007-d906a56319c3  2020-12-27T06:39:59+00:00  22S       gs://microservices-hands-on_cloudbuild/source/1609051197.03811-c0082d92ec804586ae303353057a9dc0.tgz  gcr.io/microservices-hands-on/hello-world-service (+1 more)  SUCCESS
```

ビルドの履歴とログは、Cloud Console から「[Cloud Build](https://console.cloud.google.com/cloud-build/)」メニューを
開いて確認することができます。

ビルド済のイメージは、Cloud Container Registry に保存されています。Cloud Console から「[Container Regstry](https://console.cloud.google.com/gcr/)」メニューを
開いて、保存されたイメージを確認することができます。次のコマンドで確認することもできます。

イメージの一覧を表示します。
```
gcloud container images list
```
*コマンドの出力例*
```
NAME
gcr.io/microservices-hands-on/hello-world-service
```

特定のイメージのタグを表示します。
```
gcloud container images list-tags gcr.io/$PROJECT_ID/hello-world-service
```
*コマンドの出力例*
```
DIGEST        TAGS    TIMESTAMP
894a35cdfc88  latest  2020-12-27T06:40:16
```

### Cloud Run にイメージをデプロイ

次のコマンドを実行します。ここでは、先ほど作成したイメージを Cloud Run の実行環境にデプロイしています。サービス名には、`hello-world-service` を指定しています。

```
gcloud run deploy hello-world-service \
  --image gcr.io/$PROJECT_ID/hello-world-service \
  --platform=managed --region=us-central1 \
  --no-allow-unauthenticated
```

*コマンドの出力例*
```
Deploying container to Cloud Run service [hello-world-service] in project [microservices-hands-on] region [us-central1]
✓ Deploying new service... Done.                                                           
  ✓ Creating Revision...
  ✓ Routing traffic...
Done.
Service [hello-world-service] revision [hello-world-service-00001-rix] has been deployed and is serving 100 percent of traffic.
Service URL: https://hello-world-service-tf5atlwfza-uc.a.run.app
```

最後に表示された `Service URL` がデプロイされたサービスのエンドポイントになります。

### デプロイしたサービスの動作確認

次のコマンドを実行します。ここでは、サービス `hello-world-service` に対するエンドポイントを取得して、環境変数 `SERVICE_URL` に保存しています。

```
SERVICE_NAME="hello-world-service"
SERVICE_URL=$(gcloud run services list --platform managed \
  --format="table[no-heading](URL)" --filter="SERVICE:${SERVICE_NAME}")
echo $SERVICE_URL
```

*コマンドの出力例*
```
https://hello-world-service-tf5atlwfza-uc.a.run.app
```

POST メソッドでデータを送信して、動作を確認します。次のコマンドを実行します。

```
curl -X POST -H "Authorization: Bearer $(gcloud auth print-identity-token)" \
  -H "Content-Type: application/json" \
  -d '{"name":"Google Cloud Platform"}' \
  -s ${SERVICE_URL}/api/v1/hello 
```

*コマンドの出力例*
```
{"message":"Hello, Google Cloud Platform!"}
```

ここでは、`gcloud auth print-identity-token` で取得したアクセストークンを用いて認証を行っています。
この場合は、gcloud コマンドを実行したユーザーアカウントの権限でトークンが取得されます。

> GCP 上で稼働するアプリケーションからアクセスする際は、アプリケーションに紐づいたサービスアカウントの権限でトークンを取得します。
外部のクライアントからアクセスする際は、OAuth 2.0 を用いて Google アカウントのユーザー認証を行うことで、トークンが取得できるようになります。

Cloud Console から「[Cloud Run](https://console.cloud.google.com/run/)」メニューを開くと、デプロイされたサービスの状態やアクセスログを確認することができます。
一定時間アクセスが無いと、コンテナが自動停止する様子もログから確認できます。

## 3. Cloud Datastore によるデータの永続化

このセクションで実施する内容

- コンテナイメージのビルドとデプロイ
- デプロイしたサービスの動作確認

### コンテナイメージのビルドとデプロイ

ここでは、ユーザーが自分の名前とメッセージを登録できる、簡易的なメッセージボードのアプリケーションをデプロイします。登録したデータは、Cloud Datastore に保存されます。

> Python のアプリケーションから Cloud Datastore にアクセスするには、google-cloud-datastore パッケージに含まれるクライアントライブラリを使用します。そのため、コンテナイメージを作成する際に、[requirements.txt](https://github.com/enakai00/gcp-getting-started-lab-jp/blob/master/microservices/hmessage_board/requirements.txt) で google-cloud-datastore パッケージをインストールしています。

次のコマンドを実行します。ここでは、[Dockerfile](https://github.com/enakai00/gcp-getting-started-lab-jp/blob/master/microservices/hmessage_board/Dockerfile) に
従って、コンテナイメージをビルドしています。

```
cd $HOME/gcp-getting-started-lab-jp/microservices/message_board
gcloud builds submit --tag gcr.io/$PROJECT_ID/message-board-service
```

*コマンドの出力例*
```
Creating temporary tarball archive of 5 file(s) totalling 4.0 KiB before compression.
Uploading tarball of [.] to [gs://microservices-hands-on_cloudbuild/source/1609062140.736345-217a1fac5e4a4cdf8c5a2a5e8e1f8dfa.tgz]

...中略...

DONE
------------------------------------------------------------------------------------------------------------------------

ID                                    CREATE_TIME                DURATION  SOURCE                                                                                               IMAGES                                                       STATUS18ee06e6-bb5e-49e7-9d8a-b233a20fa3f0  2020-12-27T09:47:38+00:00  31S       gs://microservices-hands-on_cloudbuild/source/1609062456.723272-599b79cc128348d7a17c165a7f817d20.tgz  gcr.io/microservices-hands-on/message-board-service (+1 more)  SUCCESS
```

次のコマンドを実行します。ここでは、先ほど作成したイメージを Cloud Run の実行環境にデプロイしています。サービス名には、`message-board-service` を指定しています。

```
gcloud run deploy message-board-service \
  --image gcr.io/$PROJECT_ID/message-board-service \
  --platform=managed --region=us-central1 \
  --no-allow-unauthenticated
```

*コマンドの出力例*
```
Deploying container to Cloud Run service [message-board-service] in project [microservices-hands-on] region [us-central1]
✓ Deploying new service... Done.              
  ✓ Creating Revision... Revision deployment finished. Waiting for health check to begin.
  ✓ Routing traffic...
Done.
Service [message-board-service] revision [message-board-service-00001-xoy] has been deployed and is serving 100 percent of traffic.
Service URL: https://message-board-service-tf5atlwfza-uc.a.run.app
```

### デプロイしたサービスの動作確認

このアプリケーションは、Datastore に対して、次のような検索処理を行います。

```
    query = ds_client.query(kind='Message') # Create a query object for kind 'Message'.
    query.add_filter('name', '=', name)     # Add a filter condition.
    query.order = ['timestamp']             # Add a sort condition.
```

この検索に必要なインデックス [`index.yaml`](https://github.com/enakai00/gcp-getting-started-lab-jp/blob/master/microservices/hmessage_board/index.yaml) を事前に定義しておく必要があります。次のコマンドを実行して、インデックスを定義します。

```
cd $HOME/gcp-getting-started-lab-jp/microservices/message_board
gcloud datastore indexes create index.yaml --quiet
```

*コマンドの出力例*
```
Configurations to update:
descriptor:      [index.yaml]
type:            [datastore indexes]
target project:  [microservices-hands-on]
.... 100%...done.
```

コマンド出力からは、インデックスの作成が完了したように見えますが、実際にはバックグラウンドで作成処理が継続しています。
Cloud Console から「[データストア](https://console.cloud.google.com/datastore)」メニューの「インデックス」
を開いてインデックスの作成状況を確認します。数分後に、緑のチェックマークが表示されるまでそのまま待ちます。

> 適切なインデックスを作成せずに検索を実行するとエラーが発生します。その際、コンテナの実行ログに、必要なインデックスの定義を示すエラーメッセージが表示されます。

　*エラーメッセージの例*
  ```
  2020-12-27 19:10:06.645 JST  details = "no matching index found. recommended index is:
  2020-12-27 19:10:06.645 JST - kind: Message
  2020-12-27 19:10:06.645 JST  properties:
  2020-12-27 19:10:06.645 JST  - name: name
  2020-12-27 19:10:06.645 JST  - name: timestamp
  ```

次のコマンドを実行します。ここでは、ユーザー名 `Bob` のメッセージを登録しています。

```
SERVICE_NAME="message-board-service"
SERVICE_URL=$(gcloud run services list --platform managed \
    --format="table[no-heading](URL)" --filter="SERVICE:${SERVICE_NAME}")
curl -X POST -H "Authorization: Bearer $(gcloud auth print-identity-token)" \
  -H "Content-Type: application/json" \
  -d '{"name":"Bob", "message":"I am at lunch now."}' \
  -s ${SERVICE_URL}/api/v1/store | jq .
```

> 最後の `jq` コマンドは出力された JSON 文字列を整形するためのものです。JSON 文字列以外を受け取った場合は、
`parse error: Invalid numeric literal at line 1, column 10` のようなメッセージが表示されます。
このような場合は、`jq` コマンドを取り除いて、整形前の出力メッセージを確認してください。

*コマンドの出力例*
```
{
  "message": "I am at lunch now.",
  "name": "Bob",
  "timestamp": "Sun, 27 Dec 2020 10:08:56 GMT"
}
```

次のコマンドを実行します。ここでは、ユーザー名 `Bob` のメッセージを取り出しています。

```
curl -X POST -H "Authorization: Bearer $(gcloud auth print-identity-token)" \
  -H "Content-Type: application/json" \
  -d '{"name":"Bob"}' \
  -s ${SERVICE_URL}/api/v1/retrieve | jq .
```

*コマンドの出力例*
```
{
  "messages": [
    {
      "message": "I am at lunch now.",
      "timestamp": "Sun, 27 Dec 2020 10:08:56 GMT"
    }
  ],
  "name": "Bob"
}
```

Datastore に保存されたデータは、Cloud Console の「[データストア](https://console.cloud.google.com/datastore)」メニューの「エンティティ」
から確認できます。「種類」に「Message」を選択すると、先ほど保存したデータが表示されます。「名前/ID」の列は自動で割り当てられた Key を示します。

## Cloud PubSub によるイベントメッセージの交換

## Cloud Scheduler による定期的な処理の実行