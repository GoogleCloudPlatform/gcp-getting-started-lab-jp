# ハンズオン：GCP のサーバーレスコンポーネントを利用したマイクロサービス開発入門

## 1. 事前準備

### GCP プロジェクトの作成

GCP プロジェクトを新規作成します。このハンズオンは、プロジェクトオーナーの権限で作業を進める前提ですので、自分専用のプロジェクトを用意するようにしてください。

**参考**
- [Cloud Console を開く](https://console.cloud.google.com/)
- [Cloud Shell の使用方法](https://cloud.google.com/shell/docs/using-cloud-shell)

### Cloud Datastore の有効化

Cloud Console から「[データストア](https://console.cloud.google.com/datastore)」メニューを開いて、「DATASTORE モードを選択」をクリックします。
  
「ロケーションを選択」には「us-east1 (South Carolina)」を選択して、「データベースを作成」をクリックします。

### Cloud Shell の起動

これ以降の作業は、基本的には、Cloud Shell 端末でのコマンド操作で行います。

Cloud Shell を開いて、次のコマンドを実行します。ここでは、Project ID を環境変数にセットすると共に、gcloud コマンドのデフォルトプロジェクトに設定します。（`[your project ID]` の部分はハンズオンを進める環境の Project ID に置き換えてください。）

```
PROJECT_ID=[your project ID]
gcloud config set project $PROJECT_ID
```

「Cloud Shell の承認」というポップアップが表示されますので、「承認」をクリックしてください。

*コマンドの出力例*
```
Updated property [core/project].
```

**注意：作業中に新しい Cloud Shell 端末を開いた場合は、必ず、最初に上記のコマンドを実行して、環境変数 PROJECT_ID とデフォルトプロジェクトを正しく設定ください。**

### API の有効化

次のコマンドを実行します。ここでは、Cloud Build, Cloud Run, Cloud Scheduler, Workflows の API を有効化しています。

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
git clone https://github.com/GoogleCloudPlatform/gcp-getting-started-lab-jp
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

次のコマンドを実行します。ここでは、簡単な REST API を提供するサンプルアプリケーション [main.py](hello_world/main.py) をローカル環境で実行しています。この API は、名前を受け取って、対応する定型メッセージを返します。

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

アプリケーションはフォアグラウンドで実行を続けているので、新しい Cloud Shell のタブを開いて、そちらから curl コマンドでアプリケーションにリクエストを送信します。

>Cloud Shell 端末画面の上部にある「＋」ボタンで新しいタブが開きます。

次のコマンドを実行します。ベース URL に GET メソッドでアクセスすると、サービス名を示すメッセージが返ります。

```
curl http://localhost:8080
```

*コマンドの出力例*
```
Hello world service.
```

次は、POST メソッドで API `api/v1/hello` にデータを送信します。次のコマンドを実行します。

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

動作確認ができたら、サンプルアプリを実行中の端末に戻って、Ctrl+C でサンプルアプリを停止します。

### Cloud Build によるコンテナイメージのビルド

次のコマンドを実行します。ここでは、[Dockerfile](hello_world/Dockerfile) に
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

ビルドの履歴とログは、Cloud Console から「[Cloud Build](https://console.cloud.google.com/cloud-build/)」メニューを開いて確認することができます。

ビルド済のイメージは、Cloud Container Registry に保存されています。Cloud Console から「[Container Regstry](https://console.cloud.google.com/gcr/)」メニューを開いて、保存されたイメージを確認することができます。次のように、コマンドで確認することもできます。

次のコマンドを実行して、イメージの一覧を表示します。
```
gcloud container images list
```
*コマンドの出力例*
```
NAME
gcr.io/microservices-hands-on/hello-world-service
```

次のコマンドを実行して、特定のイメージのタグを表示します。
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

>エンドポイントの URL はデプロイ時にユニークなアドレスが自動で割り当てられるので、出力結果は環境によって異なります。

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

> GCP 上で稼働するアプリケーションからアクセスする際は、アプリケーションに紐づいたサービスアカウントの権限でトークンを取得します。外部のクライアントからアクセスする際は、OAuth 2.0 を用いて Google アカウントのユーザー認証を行うことで、トークンが取得できるようになります。

Cloud Console から「[Cloud Run](https://console.cloud.google.com/run/)」メニューを開くと、デプロイされたサービスの状態やアクセスログを確認することができます。一定時間アクセスが無いと、コンテナが自動停止する様子もログから確認できます。

## 3. Cloud Datastore によるデータの永続化

このセクションで実施する内容

- コンテナイメージのビルドとデプロイ
- デプロイしたサービスの動作確認

### コンテナイメージのビルドとデプロイ

ここでは、ユーザーが自分の名前とメッセージを登録できる、簡易的なメッセージボードのアプリケーションをデプロイします。登録したデータは、Cloud Datastore に保存されます。

> Python のアプリケーションから Cloud Datastore にアクセスするには、google-cloud-datastore パッケージに含まれるクライアントライブラリを使用します。そのため、コンテナイメージを作成する際に、[requirements.txt](message_board/requirements.txt) で google-cloud-datastore パッケージをインストールしています。

次のコマンドを実行します。ここでは、[Dockerfile](message_board/Dockerfile) に従って、コンテナイメージをビルドしています。

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

この検索に必要なインデックス [`index.yaml`](message_board/index.yaml) を事前に定義しておく必要があります。次のコマンドを実行して、インデックスを定義します。

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

コマンド出力からは、インデックスの作成が完了したように見えますが、実際にはバックグラウンドで作成処理が継続しています。Cloud Console から「[データストア](https://console.cloud.google.com/datastore)」メニューの「[インデックス](https://console.cloud.google.com/datastore/indexes)」を開いてインデックスの作成状況を確認します。数分後に、緑のチェックマークが表示されるまでそのまま待ちます。

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

> 最後の `jq` コマンドは出力された JSON 文字列を整形するためのものです。JSON 文字列以外を受け取った場合は、`parse error: Invalid numeric literal at line 1, column 10` のようなメッセージが表示されます。このような場合は、`jq` コマンドを取り除いて、整形前の出力メッセージを確認してください。

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

Datastore に保存されたデータは、Cloud Console の「[データストア](https://console.cloud.google.com/datastore)」メニューの「[エンティティ](https://console.cloud.google.com/datastore/entities)」から確認できます。「種類」に「Message」を入力すると、先ほど保存したデータが表示されます。「名前/ID」の列は自動で割り当てられた Key を示します。

> Cloud Datastore では、一般のデータベースのテーブルに相当するものを「Kind」と呼びます。日本語では「カインド」といいますが、公式の日本語ドキュメントでは、「種類」と訳されていることもあります。

## 4. Cloud Pub/Sub による非同期通信

このセクションで実施する内容

- コンテナイメージのビルドとデプロイ
- Pub/Sub トピックの作成とトークン作成ロールの設定
- Push サブスクリプションの作成
- Cloud Storage の Pub/Sub 通知設定と動作確認

### コンテナイメージのビルドとデプロイ

ここでは、Cloud Storage にファイルが保存されると、そのファイルに関する情報を PubS/ub 経由で受け取って、Cloud Datastore に記録するアプリケーションをデプロイします。Pub/Sub からのメッセージは、Push サブスクリプションを用いて、REST API で受け取ります。

次のコマンドを実行します。ここでは、[Dockerfile](storage_logging/Dockerfile) に従って、コンテナイメージをビルドしています。

```
cd $HOME/gcp-getting-started-lab-jp/microservices/storage_logging
gcloud builds submit --tag gcr.io/$PROJECT_ID/storage-logging-service
```

*コマンドの出力例*
```
Creating temporary tarball archive of 4 file(s) totalling 2.3 KiB before compression.
Uploading tarball of [.] to [gs://microservices-hands-on_cloudbuild/source/1609114643.194448-6fd1aaa87c1641ffa5366058e6cf6312.tgz]

...中略...

DONE
------------------------------------------------------------------------------------------------------------------------

ID                                    CREATE_TIME                DURATION  SOURCE                                                                                                IMAGES                                                           STATUS
6fb28c89-a470-440f-a107-b3049be5d77e  2020-12-28T00:17:25+00:00  33S       gs://microservices-hands-on_cloudbuild/source/1609114643.194448-6fd1aaa87c1641ffa5366058e6cf6312.tgz  gcr.io/microservices-hands-on/storage-logging-service (+1 more)  SUCCESS
```

次のコマンドを実行します。ここでは、先ほど作成したイメージを Cloud Run の実行環境にデプロイしています。サービス名には、`storage-logging-service` を指定しています。

```
gcloud run deploy storage-logging-service \
  --image gcr.io/$PROJECT_ID/storage-logging-service \
  --platform=managed --region=us-central1 \
  --no-allow-unauthenticated
```

*コマンドの出力例*
```
Deploying container to Cloud Run service [storage-logging-service] in project [microservices-hands-on] region [us-central1]
✓ Deploying new service... Done.                                                           
  ✓ Creating Revision...
  ✓ Routing traffic...
Done.
Service [storage-logging-service] revision [storage-logging-service-00001-qed] has been deployed and is serving 100 percent of traffic.
Service URL: https://storage-logging-service-tf5atlwfza-uc.a.run.app
```

### Pub/Sub トピックの作成とトークン作成ロールの設定

次のコマンドを実行します。ここでは、`storage-event` という名前の Pub/Sub トピックを作成しています。

```
gcloud pubsub topics create storage-event
```

*コマンドの出力例*
```
Created topic [projects/microservices-hands-on/topics/storage-event].
```

この後、Push サブスクリプションを作成して、Cloud Run で稼働中のサービスの REST API を呼び出すように設定しますが、API を呼び出す際には、Pub/Sub は内部的に API 認証のアクセストークンを取得する必要があります。このため、Pub/Sub に紐づけられたサービスアカウント `service-${PROJECT_NUMBER}@gcp-sa-pubsub.iam.gserviceaccount.com` に対して、アクセストークンを取得する権限を設定しておきます。

次のコマンドを実行して、Cloud IAM のポリシー設定を追加します。ここでは、Pub/Sub のサービスアカウントが、プロジェクト全体に対して、`iam.serviceAccountTokenCreator` ロールを持つように設定しています。

```
PROJECT_NUMBER=$(gcloud projects describe $PROJECT_ID --format "value(projectNumber)")
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member=serviceAccount:service-${PROJECT_NUMBER}@gcp-sa-pubsub.iam.gserviceaccount.com \
  --role=roles/iam.serviceAccountTokenCreator
```

*コマンドの出力例*
```
Updated IAM policy for project [microservices-hands-on].
bindings:

...（中略）...

- members:
  - serviceAccount:service-104350195296@gcp-sa-pubsub.iam.gserviceaccount.com
  role: roles/iam.serviceAccountTokenCreator

...（以下省略）...
```

### Push サブスクリプションの作成

先ほど作成したトピック `storage-event` に Push サブスクリプションを作成して、Cloud Run にデプロイしたサービス `storage-logging-service` の API を呼び出すように設定します。この際、Cloud Run の API を呼び出す権限を持ったサービスアカウントを作成して、Push サブスクリプションに紐づけておく必要があります。

まずはじめに、次のコマンドを実行して、新しいサービスアカウント `cloud-run-invoker` を作成します。

```
SERVICE_ACCOUNT_NAME="cloud-run-invoker"
gcloud iam service-accounts create $SERVICE_ACCOUNT_NAME \
  --display-name "Cloud Run Invoker"
```

*コマンドの出力例*
```
Created service account [cloud-run-invoker].
```

サービスアカウントは e-mail アドレスで識別されます。次のコマンドを実行して、サービスアカウント `cloud-run-invoker` の e-mail アドレスを環境変数に保存しておきます。

```
SERVICE_ACCOUNT_EMAIL=${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com
```

次のコマンドを実行して、Cloud IAM のポリシー設定を追加します。ここでは、サービスアカウント `cloud-run-invoker` が、Cloud Run にデプロイしたサービス `storage-logging-service` に対して、`run.invoker` ロールを持つように設定しています。

```
SERVICE_NAME="storage-logging-service"
gcloud run services add-iam-policy-binding $SERVICE_NAME \
  --member=serviceAccount:$SERVICE_ACCOUNT_EMAIL \
  --role=roles/run.invoker \
  --platform=managed --region=us-central1
```

*コマンドの出力例*
```
Updated IAM policy for service [storage-logging-service].
bindings:
- members:
  - serviceAccount:cloud-run-invoker@microservices-hands-on.iam.gserviceaccount.com
  role: roles/run.invoker
etag: BwW3e2-7tbA=
version: 1
```

最後に、次のコマンドを実行して、Push サブスクリプション `push-storage-event` を作成します。ここでは、サービスアカウント `cloud-run-invoker` の権限で `storage-logging-service` サービスの API `api/v1/pubsub` にメッセージを POST するように設定しています。

```
SERVICE_URL=$(gcloud run services list --platform managed \
  --format="table[no-heading](URL)" --filter="SERVICE:${SERVICE_NAME}")
gcloud pubsub subscriptions create push-storage-event \
  --topic storage-event \
  --push-endpoint=$SERVICE_URL/api/v1/pubsub \
  --push-auth-service-account=$SERVICE_ACCOUNT_EMAIL
```

*コマンドの出力例*
```
Created subscription [projects/microservices-hands-on/subscriptions/push-storage-event].
```

作成したトピック、および、サブスクリプションの情報は、Cloud Console の「[Pub/Sub](https://console.cloud.google.com/cloudpubsub)」メニューから確認できます。

### Cloud Storage の Pub/Sub 通知設定と動作確認

Cloud Storage のバケットを作成して、ファイルがアップロードされると Pub/Sub にイベントを発行するように通知設定を行います。

はじめに次のコマンドを実行して、バケットを作成します。

```
BUCKET=gs://${PROJECT_ID}-photostore
gsutil mb -l us-central1 $BUCKET
```

*コマンドの出力例*
```
Creating gs://microservices-hands-on-photostore/...
```

次のコマンドを実行して、トピック `storage-event` への通知設定を行います。ファイルのアップロードだけではなく、削除や更新などの際もイベントが発行されます。

```
gsutil notification create -t storage-event -f json $BUCKET
```

*コマンドの出力例*
```
Created notification config projects/_/buckets/microservices-hands-on-photostore/notificationConfigs/1
```

次のコマンドを実行して、バケットにファイルをアップロードします。

```
curl -s -o /tmp/faulkner.jpg https://cloud.google.com/vision/docs/images/faulkner.jpg
gsutil cp /tmp/faulkner.jpg $BUCKET/
```

*コマンドの出力例*
```
Copying file:///tmp/faulkner.jpg [Content-Type=image/jpeg]...
- [1 files][163.1 KiB/163.1 KiB]
Operation completed over 1 objects/163.1 KiB.
```

> サービス `storage-logging-service` は、次のコードで受け取ったイベントを処理します。メッセージのメタデータから、ファイルのアップロードイベント（`OBJECT_FINALIZE`）を識別して、メッセージ本体に含まれるデータにタイムスタンプを加えたものを Datastore に保存します。

[`main.py`](storage_logging/main.py)
```
    envelope = request.get_json()
    message = envelope['message']
    attributes = message['attributes'] # Event meta data
    if attributes['eventType'] != 'OBJECT_FINALIZE':
        resp = {'message': 'This is Not a file upload event.'}
        return resp, 200

    data = json.loads(base64.b64decode(message['data']).decode('utf-8')) # Event body
    data['timestamp'] = datetime.datetime.utcnow()  # Add timestamp

    incomplete_key = ds_client.key('StorageLog')   # Create a new key for kind 'StorageLog'.
    event_entity = datastore.Entity(key=incomplete_key) # Create a new entity.
    event_entity.update(data)                 # Update the entity's contents.
    ds_client.put(event_entity)               # Store the entity in Datastore.
```

Cloud Console の「[データストア](https://console.cloud.google.com/datastore)」メニューの「[エンティティ](https://console.cloud.google.com/datastore/entities)」から、イベントの情報が記録されていることを確認します。「種類」に「StorageLog」を選択すると、先ほどファイルをアップロードした際に保存されたエンティティが確認できます。

## 5. Cloud Scheduler による定期処理

このセクションで実施する内容

- Cloud Scheduler の設定と動作確認

### Cloud Scheduler の設定と動作確認

先ほどのセクションでデプロイしたサービス `storage-logging-service` には、API `api/v1/purge` を GET メソッドで呼び出すと、3分以上前のログを Datastore から削除する機能が実装されています。Cloud Scheduler を用いて、この機能を定期実行します。

Cloud Scheduler から Cloud Run にデプロイしたサービスを呼び出すには、適切な権限を持ったサービスアカウントを紐づけておく必要があります。ここでは、以前のセクションで作成したサービスアカウント `cloud-run-invoker` を再利用することにします。

はじめに次のコマンドを実行して、Cloud IAM のポリシー設定を追加します。ここでは、サービスアカウント `cloud-run-invoker` が、Cloud Run にデプロイしたサービス `storage-logging-service` に対して、`run.invoker` ロールを持つように設定しています。

```
SERVICE_ACCOUNT_NAME="cloud-run-invoker"
SERVICE_ACCOUNT_EMAIL=${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com
SERVICE_NAME="storage-logging-service"
gcloud run services add-iam-policy-binding $SERVICE_NAME \
    --member=serviceAccount:$SERVICE_ACCOUNT_EMAIL \
    --role=roles/run.invoker \
    --platform=managed --region=us-central1
```

*コマンドの出力例*
```
Updated IAM policy for service [storage-logging-service].
bindings:
- members:
  - serviceAccount:cloud-run-invoker@microservices-hands-on.iam.gserviceaccount.com
  role: roles/run.invoker
etag: BwW3fMnVPdw=
version: 1
```

次のコマンドを実行して、Cloud Scheduler に新しいジョブスケジュールを定義します。ここでは、サービスアカウント `cloud-run-invoker` を用いて、サービス `storage-logging-service` の API `api/v1/purge` を１分ごとに呼び出すように設定しています。

```
SERVICE_NAME="storage-logging-service"
SERVICE_URL=$(gcloud run services list --platform managed \
  --format="table[no-heading](URL)" --filter="SERVICE:${SERVICE_NAME}")
gcloud scheduler jobs create http log-purge-job \
       --schedule='* * * * *' \
       --http-method=GET \
       --uri=$SERVICE_URL/api/v1/purge \
       --oidc-service-account-email=$SERVICE_ACCOUNT_EMAIL \
       --oidc-token-audience=$SERVICE_URL/api/v1/purge
```       

Cloud Console の「[Cloud Scheduler](https://console.cloud.google.com/cloudscheduler)」メニューからジョブの定義と実行結果を確認します。「今すぐ実行」をクリックして、ジョブを実行することもできます。ジョブの実行に成功すると、3分以上前に保存されたログが Datastore から削除されています。Cloud Console の「[データストア](https://console.cloud.google.com/datastore)」メニューの「[エンティティ](https://console.cloud.google.com/datastore/entities)」から、「種類」に「StorageLog」を入力して、古いエンティティが削除されていることを確認してください。

>エンティティの確認画面では、画面右上のリフレッシュボタンを押すと最新の情報が反映されます。
