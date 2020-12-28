# ハンズオン：Transactional workflows in microservices architecture

## 1. 事前準備

### 前提ハンズオンの完了

このハンズオンは、[tutorial-1.md](tutorial-1.md) の内容を完了した後に、続けて実施する前提になります。
[tutorial-1.md](tutorial-1.md) を完了したプロジェクト環境を利用して、このハンズオンを続けてください。

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

### ソースコードのダウンロード

このハンズオンでは、GitHub リポジトリ [GoogleCloudPlatform/transactional-microservice-examples](https://github.com/GoogleCloudPlatform/transactional-microservice-examples) で公開されているソースコードを利用します。

次のコマンドを実行します。ここでは、Cloud Shell 端末のホームディレクトリーにこの GitHub リポジトリの内容をクローンしています。

```
cd $HOME
git clone https://github.com/GoogleCloudPlatform/transactional-microservice-examples
```

## 2. Choreography-saga パターン

このセクションで実施する内容

- Cloud Run へのサービスのデプロイ
- Cloud Pub/Sub の設定
- Cloud Scheduler の設定
- トランザクション処理の動作検証

### Cloud Run へのサービスのデプロイ

次のコマンドを実行します。ここでは、Order サービス（サービス名 `order-async`）、Customer サービス（サービス名 `customer-async`）、
および、Event publisher サービス（サービス名 `event-publisher`）について、それぞれのイメージのビルドとデプロイを行っています。

```
cd $HOME/transactional-microservice-examples/services/order-async
gcloud builds submit --tag gcr.io/$PROJECT_ID/order-service-async
gcloud run deploy order-service-async \
  --image gcr.io/$PROJECT_ID/order-service-async \
  --platform=managed --region=us-central1 \
  --no-allow-unauthenticated

cd $HOME/transactional-microservice-examples/services/customer-async
gcloud builds submit --tag gcr.io/$PROJECT_ID/customer-service-async
gcloud run deploy customer-service-async \
  --image gcr.io/$PROJECT_ID/customer-service-async \
  --platform=managed --region=us-central1 \
  --no-allow-unauthenticated

cd $HOME/transactional-microservice-examples/services/event-publisher
gcloud builds submit --tag gcr.io/$PROJECT_ID/event-publisher
gcloud run deploy event-publisher \
  --image gcr.io/$PROJECT_ID/event-publisher \
  --platform=managed --region=us-central1 \
  --no-allow-unauthenticated \
  --set-env-vars "PROJECT_ID=$PROJECT_ID"
```

> Python クライアントから Pub/Sub にイベントを発行する際は、トピック名を `projects/[Project ID]/topics/[Topic Name]` という
フォーマットで、Project ID を含めて指定する必要があります。上記のコマンドの最終行では、環境変数 `PROJECT_ID` を通じて Project ID を
コードに受け渡しています。

次のコマンドを実行して、Event publisher サービスがイベントデータベースの検索に使用する
インデックス [index.yaml](https://github.com/GoogleCloudPlatform/transactional-microservice-examples/blob/main/services/event-publisher/index.yaml) を作成します。

```
cd $HOME/transactional-microservice-examples/services/event-publisher
gcloud datastore indexes create index.yaml --quiet
```

Cloud Console から「[データストア](https://console.cloud.google.com/datastore)」メニューの「インデックス」
を開いてインデックスの作成状況を確認します。数分後に、緑のチェックマークが表示されるまでそのまま待ちます。

### Cloud Pub/Sub の設定

次のコマンドを実行して、Order サービスと Customer サービスがイベントメッセージの交換に使用する Pub/Sub のトピックを作成します。

```
gcloud pubsub topics create order-service-event
gcloud pubsub topics create customer-service-event
```

次のコマンドを実行して、Order サービスがイベントを発行するトピック `order-service-event` に対して、Customer サービスの API を
呼び出す Push サブスクリプション `push-order-to-customer` を定義します。ここでは、先のハンズオンで作成した
サービスアカウント `cloud-run-invoker` を再利用して、Customer サービスの API を呼び出す権限を設定した上で、P
ush サブスクリプションに紐づけています。

```
SERVICE_ACCOUNT_NAME="cloud-run-invoker"
SERVICE_ACCOUNT_EMAIL=${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com

SERVICE_NAME="customer-service-async"
SERVICE_URL=$(gcloud run services list --platform managed \
  --format="table[no-heading](URL)" --filter="SERVICE:${SERVICE_NAME}")

gcloud run services add-iam-policy-binding $SERVICE_NAME \
  --member=serviceAccount:$SERVICE_ACCOUNT_EMAIL \
  --role=roles/run.invoker \
  --platform=managed --region=us-central1

gcloud pubsub subscriptions create push-order-to-customer \
  --topic order-service-event \
  --push-endpoint=$SERVICE_URL/api/v1/customer/pubsub \
  --push-auth-service-account=$SERVICE_ACCOUNT_EMAIL
```

同様の処理を Customer サービスがイベントを発行するトピック `customer-service-event` に対しても行います。

次のコマンドを実行して、トピック `customer-service-event` に対して、Order サービスの API を
呼び出す Push サブスクリプション `push-customer-to-order` を定義します。

```
SERVICE_NAME="order-service-async"
SERVICE_URL=$(gcloud run services list --platform managed \
  --format="table[no-heading](URL)" --filter="SERVICE:${SERVICE_NAME}")

gcloud run services add-iam-policy-binding $SERVICE_NAME \
  --member=serviceAccount:$SERVICE_ACCOUNT_EMAIL \
  --role=roles/run.invoker \
  --platform=managed --region=us-central1

gcloud pubsub subscriptions create push-customer-to-order \
  --topic customer-service-event \
  --push-endpoint=$SERVICE_URL/api/v1/order/pubsub \
  --push-auth-service-account=$SERVICE_ACCOUNT_EMAIL
```

### Cloud Scheduler の設定

次のコマンドを実行して、Cloud Scheduler のジョブスケジュールを設定します。ここでは、
Event publisher サービス `event-publisher` を 1 分ごとに呼び出して、イベントデータベースに
記録されたイベントメッセージを Pub/Sub に発行するように設定しています。
また、先のハンズオンで作成したサービスアカウント `cloud-run-invoker` を再利用して、
Event publisher サービスの API を呼び出す権限を設定した上で、ジョブスケジュールに紐づけています。

```
SERVICE_NAME="event-publisher"
gcloud run services add-iam-policy-binding $SERVICE_NAME \
    --member=serviceAccount:$SERVICE_ACCOUNT_EMAIL \
    --role=roles/run.invoker \
    --platform=managed --region=us-central1

SERVICE_URL=$(gcloud run services list --platform managed \
    --format="table[no-heading](URL)" --filter="SERVICE:$SERVICE_NAME")
gcloud scheduler jobs create http event-publisher-scheduler \
       --schedule='* * * * *' \
       --http-method=GET \
       --uri=$SERVICE_URL \
       --oidc-service-account-email=$SERVICE_ACCOUNT_EMAIL \
       --oidc-token-audience=$SERVICE_URL/api/v1/event/publish
```

## 3. Synchronous orchestration パターン


## 4. Firebase hosting による Web アプリケーションの利用

