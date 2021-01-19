# ハンズオン：マイクロサービスによるトランザクションの実装（１）

## 1. 事前準備

### 前提ハンズオンの完了

このハンズオンは、[tutorial-1.md](tutorial-1.md) の内容を完了した後に、続けて実施する前提になります。[tutorial-1.md](tutorial-1.md) を完了したプロジェクト環境を利用して、このハンズオンを続けてください。

**参考**：ここで使用するアプリケーションの仕組み（トランザクション処理の実装方法）については、下記の README が参考になります。
- [Lab: Using GCP services to execute transactional workflows in microservices architecture](https://github.com/GoogleCloudPlatform/transactional-microservice-examples)

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

**注意：作業中に新しい Cloud Shell 端末を開いた場合は、必ず、最初にこのコマンドを実行してください。**

### ソースコードのダウンロード

このハンズオンでは、GitHub リポジトリ [GoogleCloudPlatform/transactional-microservice-examples](https://github.com/GoogleCloudPlatform/transactional-microservice-examples) で公開されているソースコードを利用します。

次のコマンドを実行します。ここでは、Cloud Shell 端末のホームディレクトリーにこの GitHub リポジトリの内容をクローンしています。

```
cd $HOME
git clone https://github.com/GoogleCloudPlatform/transactional-microservice-examples
```

## 2. Choreography-based saga パターンによる非同期トランザクションの実装

このセクションで実施する内容

- Cloud Run へのサービスのデプロイ
- Cloud Pub/Sub の設定
- Cloud Scheduler の設定
- 非同期トランザクションの動作確認

### Cloud Run へのサービスのデプロイ

次のコマンドを実行します。ここでは、Order サービス（サービス名 `order-service-async`）、Customer サービス（サービス名 `customer-service-async`）、および、Event publisher サービス（サービス名 `event-publisher`）について、それぞれのイメージのビルドとデプロイを行っています。

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

次のコマンドを実行して、Event publisher サービスがイベントデータベースの検索に使用するインデックス [index.yaml](https://github.com/GoogleCloudPlatform/transactional-microservice-examples/blob/main/services/event-publisher/index.yaml) を作成します。

```
cd $HOME/transactional-microservice-examples/services/event-publisher
gcloud datastore indexes create index.yaml --quiet
```

Cloud Console から「[データストア](https://console.cloud.google.com/datastore)」メニューの「[インデックス](https://console.cloud.google.com/datastore/indexes)」を開いてインデックスの作成状況を確認します。数分後に、緑のチェックマークが表示されるまでそのまま待ちます。

### Cloud Pub/Sub の設定

次のコマンドを実行して、Order サービスと Customer サービスがイベントメッセージの交換に使用する Pub/Sub のトピックを作成します。

```
gcloud pubsub topics create order-service-event
gcloud pubsub topics create customer-service-event
```

次のコマンドを実行して、Order サービスがイベントを発行するトピック `order-service-event` に対して、Customer サービスの API を呼び出す Push サブスクリプション `push-order-to-customer` を定義します。ここでは、先のハンズオンで作成したサービスアカウント `cloud-run-invoker` を再利用して、Customer サービスの API を呼び出す権限を設定した上で、Push サブスクリプションに紐づけています。

```
SERVICE_ACCOUNT_NAME="cloud-run-invoker"
SERVICE_ACCOUNT_EMAIL=${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com

SERVICE_NAME="customer-service-async"
SERVICE_URL=$(gcloud run services list --platform managed \
  --format="table[no-heading](URL)" --filter="metadata.name:${SERVICE_NAME}")

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

次のコマンドを実行して、トピック `customer-service-event` に対して、Order サービスの API を呼び出す Push サブスクリプション `push-customer-to-order` を定義します。

```
SERVICE_NAME="order-service-async"
SERVICE_URL=$(gcloud run services list --platform managed \
  --format="table[no-heading](URL)" --filter="metadata.name:${SERVICE_NAME}")

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

次のコマンドを実行して、Cloud Scheduler のジョブスケジュールを設定します。ここでは、Event publisher サービス `event-publisher` を 1 分ごとに呼び出して、イベントデータベースに記録されたイベントメッセージを Pub/Sub に発行するように設定しています。また、先のハンズオンで作成したサービスアカウント `cloud-run-invoker` を再利用して、Event publisher サービスの API を呼び出す権限を設定した上で、ジョブスケジュールに紐づけています。

```
SERVICE_ACCOUNT_NAME="cloud-run-invoker"
SERVICE_ACCOUNT_EMAIL=${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com

SERVICE_NAME="event-publisher"
gcloud run services add-iam-policy-binding $SERVICE_NAME \
    --member=serviceAccount:$SERVICE_ACCOUNT_EMAIL \
    --role=roles/run.invoker \
    --platform=managed --region=us-central1

SERVICE_URL=$(gcloud run services list --platform managed \
    --format="table[no-heading](URL)" --filter="metadata.name:$SERVICE_NAME")
gcloud scheduler jobs create http event-publisher-scheduler \
       --schedule='* * * * *' \
       --http-method=GET \
       --uri=$SERVICE_URL/api/v1/event/publish \
       --oidc-service-account-email=$SERVICE_ACCOUNT_EMAIL \
       --oidc-token-audience=$SERVICE_URL/api/v1/event/publish
```

### 非同期トランザクションの動作確認

次のコマンドを実行して、Order サービス、Customer サービス、それぞれのエンドポイントを環境変数に保存します。

```
SERVICE_NAME="customer-service-async"
CUSTOMER_SERVICE_URL=$(gcloud run services list --platform managed \
    --format="table[no-heading](URL)" --filter="metadata.name:${SERVICE_NAME}")
SERVICE_NAME="order-service-async"
ORDER_SERVICE_URL=$(gcloud run services list --platform managed \
    --format="table[no-heading](URL)" --filter="metadata.name:${SERVICE_NAME}")
```

次のコマンドを実行して、新規のカスタマー情報を作成します。ここでは、クレジットの利用上限を 10,000 に設定しています。

```
curl -X POST -H "Authorization: Bearer $(gcloud auth print-identity-token)" \
  -H "Content-Type: application/json" \
  -d '{"customer_id":"customer01", "limit":10000}' \
  -s ${CUSTOMER_SERVICE_URL}/api/v1/customer/limit | jq .
```

*実行結果の例*
```
{
  "credit": 0,
  "customer_id": "customer01",
  "limit": 10000
}
```

次のコマンドを実行して、カスタマー情報を取得します。作成時と同じ情報が得られます。

```
curl -X POST -H "Authorization: Bearer $(gcloud auth print-identity-token)" \
  -H "Content-Type: application/json" \
  -d '{"customer_id":"customer01"}' \
  -s ${CUSTOMER_SERVICE_URL}/api/v1/customer/get | jq .
```

*実行結果の例*
```
{
  "credit": 0,
  "customer_id": "customer01",
  "limit": 10000
}
```

次のコマンドを実行して、新規のオーダーリクエストを発行します。ここでは、発注数を 10 に指定しています。

```
curl -X POST -H "Authorization: Bearer $(gcloud auth print-identity-token)" \
  -H "Content-Type: application/json" \
  -d '{"customer_id":"customer01", "number":10}' \
  -s ${ORDER_SERVICE_URL}/api/v1/order/create | jq .
```

*実行結果の例*
```
{
  "customer_id": "customer01",
  "number": 10,
  "order_id": "ca7eff1e-b8ed-47f3-a79b-95ffda31f3b0",
  "status": "pending"
}
```

上記の実行結果では、オーダー ID `ca7eff1e-b8ed-47f3-a79b-95ffda31f3b0` が割り当てられており、
オーダーの状態は `pending` になっています。

この後で使用するため、次のコマンドを実行して、表示されたオーダー ID を環境変数に保存します。
（オーダー ID の値は実際の出力結果に合わせて変更してください。）

```
ORDER_ID="ca7eff1e-b8ed-47f3-a79b-95ffda31f3b0"
```

次のコマンドを実行して、オーダーの状態を確認します。

```
curl -X POST -H "Authorization: Bearer $(gcloud auth print-identity-token)" \
  -H "Content-Type: application/json" \
  -d "{\"customer_id\":\"customer01\", \"order_id\":\"$ORDER_ID\"}" \
  -s ${ORDER_SERVICE_URL}/api/v1/order/get | jq .
```

*実行結果の例*
```
{
  "customer_id": "customer01",
  "number": 10,
  "order_id": "ca7eff1e-b8ed-47f3-a79b-95ffda31f3b0",
  "status": "pending"
}
```

オーダーの状態が `pending` の場合は、トランザクションの処理がまだ完了していません。1〜2 分待ってから、再度、次のコマンドを実行してオーダーの状態を確認します。

```
curl -X POST -H "Authorization: Bearer $(gcloud auth print-identity-token)" \
  -H "Content-Type: application/json" \
  -d "{\"customer_id\":\"customer01\", \"order_id\":\"$ORDER_ID\"}" \
  -s ${ORDER_SERVICE_URL}/api/v1/order/get | jq .
```

*実行結果の例*
```
{
  "customer_id": "customer01",
  "number": 10,
  "order_id": "ca7eff1e-b8ed-47f3-a79b-95ffda31f3b0",
  "status": "accepted"
}
```

オーダーの状態が `accepted` になっていれば、トランザクションは完了しています。

次のコマンドを実行して、カスタマー情報を確認します。

```
curl -X POST -H "Authorization: Bearer $(gcloud auth print-identity-token)" \
  -H "Content-Type: application/json" \
  -d '{"customer_id":"customer01"}' \
  -s ${CUSTOMER_SERVICE_URL}/api/v1/customer/get | jq .
```

*実行結果の例*
```
{
  "credit": 1000,
  "customer_id": "customer01",
  "limit": 10000
}
```

オーダーが受け入れらたので、クレジットの使用量が 1,000 に増加しています。（Customer サービスには、「オーダー数 x 100」のクレジットを使用するというビジネスロジックが実装されています。）


続いて、クレジットの利用上限を超えるオーダーをリクエストを発行してみます。次のコマンドを実行して、発注数を 95 に指定したオーダーリクエストを発行します。

```
curl -X POST -H "Authorization: Bearer $(gcloud auth print-identity-token)" \
  -H "Content-Type: application/json" \
  -d '{"customer_id":"customer01", "number":95}' \
  -s ${ORDER_SERVICE_URL}/api/v1/order/create | jq .
```

*実行結果の例*
```
{
  "customer_id": "customer01",
  "number": 95,
  "order_id": "fa29381d-e349-4cef-b8e7-da296a4d87a6",
  "status": "pending"
}
```

次のコマンドを実行して、表示されたオーダー ID（この例では `fa29381d-e349-4cef-b8e7-da296a4d87a6`）を環境変数に保存します。

```
ORDER_ID="fa29381d-e349-4cef-b8e7-da296a4d87a6"
```

1〜2 分待ってから、次のコマンドを実行してオーダーの状態を確認します。

```
curl -X POST -H "Authorization: Bearer $(gcloud auth print-identity-token)" \
  -H "Content-Type: application/json" \
  -d "{\"customer_id\":\"customer01\", \"order_id\":\"$ORDER_ID\"}" \
  -s ${ORDER_SERVICE_URL}/api/v1/order/get | jq .
```

*実行結果の例*
```
{
  "customer_id": "customer01",
  "number": 95,
  "order_id": "fa29381d-e349-4cef-b8e7-da296a4d87a6",
  "status": "rejected"
}
```

オーダーの状態は、`rejected` になっていることがわかります。

次のコマンドを実行してユーザー情報を確認します。

```
curl -X POST -H "Authorization: Bearer $(gcloud auth print-identity-token)" \
  -H "Content-Type: application/json" \
  -d '{"customer_id":"customer01"}' \
  -s ${CUSTOMER_SERVICE_URL}/api/v1/customer/get | jq .
```

*実行結果の例*
```
{
  "credit": 1000,
  "customer_id": "customer01",
  "limit": 10000
}
```

クレジットの使用量は先ほどと変わっていないことがわかります。

## 3. Synchronous orchestration パターンによる同期トランザクションの実装

このセクションで実施する内容

- Cloud Run へのサービスのデプロイ
- Workflows へのワークフローのデプロイ
- 同期トランザクションの動作確認

### Cloud Run へのサービスのデプロイ

次のコマンドを実行します。ここでは、Order サービス（サービス名 `order-service-sync`）、Customer サービス（サービス名 `customer-service-sync`）、および、Order processor サービス（サービス名 `order-processor-service`）について、それぞれのイメージのビルドとデプロイを行っています。

```
cd $HOME/transactional-microservice-examples/services/order-sync
gcloud builds submit --tag gcr.io/$PROJECT_ID/order-service-sync
gcloud run deploy order-service-sync \
  --image gcr.io/$PROJECT_ID/order-service-sync \
  --platform=managed --region=us-central1 \
  --no-allow-unauthenticated

cd $HOME/transactional-microservice-examples/services/customer-sync
gcloud builds submit --tag gcr.io/$PROJECT_ID/customer-service-sync
gcloud run deploy customer-service-sync \
  --image gcr.io/$PROJECT_ID/customer-service-sync \
  --platform=managed --region=us-central1 \
  --no-allow-unauthenticated

cd $HOME/transactional-microservice-examples/services/order-processor
gcloud builds submit --tag gcr.io/$PROJECT_ID/order-processor-service
gcloud run deploy order-processor-service \
  --image gcr.io/$PROJECT_ID/order-processor-service \
  --platform=managed --region=us-central1 \
  --no-allow-unauthenticated \
  --set-env-vars "PROJECT_ID=$PROJECT_ID"
```

> Workflows は現在ベータ版のためクライアントライブラリーが用意されておらず、Order processor サービスからワークフローを実行する際は、REST API を直接に呼び出しています。この際、API の URL にプロジェクト ID が含まれるため、上記のコマンドの最終行では、環境変数 PROJECT_ID を通じて Project ID をコードに受け渡しています。

### Workflows へのワークフローのデプロイ

ワークフローから Cloud Run 上のサービス（Order サービス `order-service-sync`、および、Customer サービス `customer-service-sync`）の API を呼び出す際は、適切な権限を持ったサービスアカウントを紐づける必要があります。ここでは、先のハンズオンで作成したサービスアカウント `cloud-run-invoker` を再利用します。

次のコマンドを実行して、Cloud IAM のポリシー設定を追加します。ここでは、サービスアカウント `cloud-run-invoker` が、サービス `order-service-sync`、および、`customer-service-sync` に対して、`run.invoker` と `run.viewer` のロールを持つように設定しています。

```
SERVICE_ACCOUNT_NAME="cloud-run-invoker"
SERVICE_ACCOUNT_EMAIL=${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com

SERVICE_NAME="order-service-sync"
gcloud run services add-iam-policy-binding $SERVICE_NAME \
    --member=serviceAccount:$SERVICE_ACCOUNT_EMAIL \
    --role=roles/run.invoker \
    --platform=managed --region=us-central1
gcloud run services add-iam-policy-binding $SERVICE_NAME \
    --member=serviceAccount:$SERVICE_ACCOUNT_EMAIL \
    --role=roles/run.viewer \
    --platform=managed --region=us-central1

SERVICE_NAME="customer-service-sync"
gcloud run services add-iam-policy-binding $SERVICE_NAME \
    --member=serviceAccount:$SERVICE_ACCOUNT_EMAIL \
    --role=roles/run.invoker \
    --platform=managed --region=us-central1
gcloud run services add-iam-policy-binding $SERVICE_NAME \
    --member=serviceAccount:$SERVICE_ACCOUNT_EMAIL \
    --role=roles/run.viewer \
    --platform=managed --region=us-central1
```

> Workflows から Cloud Run のサービスを呼び出す際は、`run.invoker` に加えて、`run.viewer` のロールが必要になります。

次のコマンドを実行して、ワークフローのテンプレート [order_workflow.yaml.template](https://github.com/GoogleCloudPlatform/transactional-microservice-examples/blob/main/services/order-processor/order_workflow.yaml.template) に、Order サービスと Customer サービスのエンドポイントを書き込んで、デプロイ可能なワークフローのファイルを作成します。

```
SERVICE_NAME="customer-service-sync"
CUSTOMER_SERVICE_URL=$(gcloud run services list --platform managed \
    --format="table[no-heading](URL)" --filter="metadata.name:${SERVICE_NAME}")
SERVICE_NAME="order-service-sync"
ORDER_SERVICE_URL=$(gcloud run services list --platform managed \
    --format="table[no-heading](URL)" --filter="metadata.name:${SERVICE_NAME}")
    
cd $HOME/transactional-microservice-examples/services/order-processor
cp order_workflow.yaml.template order_workflow.yaml
sed -i "s#ORDER-SERVICE-URL#${ORDER_SERVICE_URL}#" order_workflow.yaml
sed -i "s#CUSTOMER-SERVICE-URL#${CUSTOMER_SERVICE_URL}#" order_workflow.yaml
```

次のコマンドを実行して、ワークフローをデプロイします。ここでは、サービスアカウント `cloud-run-invoker` の権限でワークフローを実行するように設定しています。

```
gcloud beta workflows deploy order_workflow \
  --source=order_workflow.yaml \
  --service-account=$SERVICE_ACCOUNT_EMAIL
```

デプロイしたワークフローの情報は、Cloud Console の「[ワークフロー](https://console.cloud.google.com/workflows)」メニューから確認することができます。

### 同期トランザクションの動作確認

次のコマンドを実行して、Order サービス、Customer サービス、および、Order processor サービス、それぞれのエンドポイントを環境変数に保存します。

```
SERVICE_NAME="order-service-sync"
ORDER_SERVICE_URL=$(gcloud run services list --platform managed \
    --format="table[no-heading](URL)" --filter="metadata.name:${SERVICE_NAME}")

SERVICE_NAME="customer-service-sync"
CUSTOMER_SERVICE_URL=$(gcloud run services list --platform managed \
    --format="table[no-heading](URL)" --filter="metadata.name:${SERVICE_NAME}")

SERVICE_NAME="order-processor-service"
ORDER_PROCESSOR_URL=$(gcloud run services list --platform managed \
    --format="table[no-heading](URL)" --filter="metadata.name:${SERVICE_NAME}")
```

次のコマンドを実行して、新規のカスタマー情報を作成します。ここでは、クレジットの利用上限を 10,000 に設定しています。

```
curl -X POST -H "Authorization: Bearer $(gcloud auth print-identity-token)" \
  -H "Content-Type: application/json" \
  -d '{"customer_id":"customer02", "limit":10000}' \
  -s ${CUSTOMER_SERVICE_URL}/api/v1/customer/limit | jq .
```

*実行結果の例*
```
{
  "credit": 0,
  "customer_id": "customer02",
  "limit": 10000
}
```

次のコマンドを実行して、新規のオーダーリクエストを発行します。ここでは、発注数を 10 に指定しています。Order サービスではなく、Order processor サービスにリクエストを送信している点に注意してください。

```
curl -X POST -H "Authorization: Bearer $(gcloud auth print-identity-token)" \
  -H "Content-Type: application/json" \
  -d '{"customer_id":"customer02", "number":10}' \
  -s ${ORDER_PROCESSOR_URL}/api/v1/order/process | jq .
```

*実行結果の例*
```
{
  "customer_id": "customer02",
  "number": 10,
  "order_id": "61c0726f-5e36-4d0a-a828-240469eddd60",
  "status": "accepted"
}
```

ワークフローを用いて、同期的にトランザクションがおこなわれるため、すぐに最終結果が返ります。ここでは、オーダーの状態は、`accepted` になっていることがわかります。

>ワークフローを定義した直後に実行すると、認証に必要な処理が完了しておらず、`"message": "Internal error occured."` というメッセージが返る場合があります。このような時は、数秒待ってから再実行してください。

次のコマンドを実行して、カスタマー情報を確認します。

```
curl -X POST -H "Authorization: Bearer $(gcloud auth print-identity-token)" \
  -H "Content-Type: application/json" \
  -d '{"customer_id":"customer02"}' \
  -s ${CUSTOMER_SERVICE_URL}/api/v1/customer/get | jq .
```

*実行結果の例*
```
{
  "credit": 1000,
  "customer_id": "customer02",
  "limit": 10000
}
```

オーダーが受け入れらたので、クレジットの使用量が 1,000 に増加しています。

続いて、クレジットの利用上限を超えるオーダーをリクエストを発行します。次のコマンドを実行して、 発注数を 95 に指定したオーダーリクエストを発行します。

```
curl -X POST -H "Authorization: Bearer $(gcloud auth print-identity-token)" \
  -H "Content-Type: application/json" \
  -d '{"customer_id":"customer02", "number":95}' \
  -s ${ORDER_PROCESSOR_URL}/api/v1/order/process | jq .
``` 

*実行結果の例*
```
{
  "customer_id": "customer02",
  "number": 95,
  "order_id": "8cc2b711-c1be-471a-8adf-188cd5d583bd",
  "status": "rejected"
}
```

先ほどと同様に、すぐに最終結果が返ります。ここでは、オーダーの状態は、`rejected` になっています。
