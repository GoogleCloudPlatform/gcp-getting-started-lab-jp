# **Google Cloud で始める生成 AI を活用したアプリケーション開発入門 (サーバーレス版)**

## **ハンズオン概要**

本ハンズオンでは、[Cloud Run](https://cloud.google.com/run), [Vertex AI](https://cloud.google.com/vertex-ai)、[BigQuery](https://cloud.google.com/bigquery) , [Identity-Aware Proxy](https://cloud.google.com/security/products/iap) といった Google Cloud イチ押しのマネージドなサービスをフル活用し、クラウドネイティブなアプリケーション開発を体験します。そしてそのアプリケーションに生成 AI を使ったインテリジェントな機能を追加することで、実際のサービスと生成 AI の組み合わせの事例を学んでいただけます。

以下が今回のハンズオンで利用する主要なサービスです。

**Cloud Run**

- Dockerfile、ソースコードから 1 コマンドで Cloud Run にデプロイ
- プライベートリリース (タグをつけたリリース) などのトラフィック コントロール
- 複数のサービスを Cloud Run で動かし連携させる

**Vertex AI**

- 生成 AI の API (Gemini 1.5 Flash)
- テキストをエンべディング化する API (Text Embeddings API)
- モデルの作成
- モデルのチューニング

**BigQuery (Log Analytics)**

- Log Analytics の有効化
- ログバケット、ログルータの設定
- アプリケーションログの分析

**Firestore**

- データベースの作成
- アプリケーションデータの格納
- エンべディングの格納
- エンべディングの近傍検索

今回は以下の 2 つのアプリケーションを構築していくことで、Google Cloud を使った生成 AI のアプリケーションへの組み込みを学びます。

- クラウドにファイルを保存する Web アプリケーション (Knowledge Drive)
- 生成 AI 機能を担当するアプリケーション (GenAI App)

## **Google Cloud プロジェクトの確認**

開いている Cloud Shell のプロンプトに `(黄色の文字)` の形式でプロジェクト ID が表示されていることを確認してください。

これが表示されている場合は、Google Cloud のプロジェクトが正しく認識されています。

表示されていない場合は、以下の手順で Cloud Shell を開き直して下さい

1. Cloud Shell を閉じる
1. 上のメニューバーのプロジェクト選択部分で払い出されたプロジェクトが選択されていることを確認する。
1. Cloud Shell を再度開く

## **参考: Cloud Shell の接続が途切れてしまったときは?**

一定時間非アクティブ状態になる、またはブラウザが固まってしまったなどで `Cloud Shell` の接続が切れてしまう場合があります。

その場合は `再接続` をクリックした後、以下の対応を行い、チュートリアルを再開してください。

![再接続画面](https://raw.githubusercontent.com/GoogleCloudPlatform/gcp-getting-started-lab-jp/master/workstations_with_generative_ai/images/reconnect_cloudshell.png)

### **1. チュートリアル資材があるディレクトリに移動する**

```bash
cd ~/gcp-getting-started-lab-jp/appdev_genai_googlecloud
```

### **2. チュートリアルを開く**

```bash
teachme tutorial_serverless_ja.md
```

途中まで進めていたチュートリアルのページまで `Next` ボタンを押し、進めてください。

## **Google Cloud 環境設定**

### **1. Google Cloud 機能有効化**

Google Cloud では利用したい機能（API）ごとに、有効化を行う必要があります。
ここでは、以降のハンズオンで利用する機能を事前に有効化しておきます。

```bash
gcloud services enable \
  run.googleapis.com \
  artifactregistry.googleapis.com \
  cloudbuild.googleapis.com \
  pubsub.googleapis.com \
  eventarc.googleapis.com \
  sqladmin.googleapis.com \
  aiplatform.googleapis.com \
  translate.googleapis.com \
  iamcredentials.googleapis.com \
  bigquery.googleapis.com \
  compute.googleapis.com \
  cloudresourcemanager.googleapis.com \
  iap.googleapis.com \
  firestore.googleapis.com
```

**GUI**: [API ライブラリ](https://console.cloud.google.com/apis/library)

### **2. Vertex AI 関連機能の有効化**

[Vertex AI](https://console.cloud.google.com/vertex-ai) にアクセスし `すべての推奨 API を有効化` ボタンをクリックします。

<walkthrough-footnote>必要な機能が使えるようになりました。次に BigQuery (Log Analytics) の設定方法を学びます。</walkthrough-footnote>

## **BigQuery (Log Analytics) の設定 (ログバケット)**

後ほど Log Analytics を利用して、ログを分析します。できる限り多くのログを集めておくために、ここで Cloud Run のログを送るためのバケットを作成します。

### **1. ログバケットの作成**

```bash
gcloud logging buckets create run-analytics-bucket \
  --location asia-northeast1 \
  --enable-analytics
```

**注**: 最大 3 分程度時間がかかります。

### **2. ログシンクの作成**

```bash
gcloud logging sinks create run-analytics-sink \
  logging.googleapis.com/projects/$GOOGLE_CLOUD_PROJECT/locations/asia-northeast1/buckets/run-analytics-bucket \
  --log-filter 'logName:"run.googleapis.com"'
```

## **Firestore データベースの作成、設定**

### **1. Firestore データベースの作成**

```bash
gcloud firestore databases create --location asia-northeast1
```

### **2. Firestore データベースにインデックスを設定**

```bash
gcloud firestore indexes composite create --collection-group=items --field-config=field-path=parent,order=ascending --field-config=field-path=createdAt,order=descending
```

**注**: データベース作成直後にコマンドを実行した場合、エラーがでることがあります。その場合は少し時間をあけて実行してください。

## **Cloud Storage バケットの作成、設定**

Knowledge Drive は実際のファイルの保存に Cloud Storage を利用します。

### **1. バケットの作成**

```bash
gcloud storage buckets create gs://$GOOGLE_CLOUD_PROJECT-knowledge-drive --location asia-northeast1
```

### **2. バケットへの CORS 設定**

Cloud Storage はデフォルトで [クロスオリジンリソースシェアリング (CORS)](https://cloud.google.com/storage/docs/cross-origin?hl=ja) のセキュリティポリシーが設定されています。

このセキュリティポリシーのため、Knowledge Drive のクライアントアプリ (ブラウザで稼働) から、Cloud Storage へのファイルアップロードが拒否されてしまいます。ここではそのセキュリティを緩和し、ファイルアップロードを行えるように設定しています。

```bash
gcloud storage buckets update gs://$GOOGLE_CLOUD_PROJECT-knowledge-drive \
  --cors-file=./assets/cors.json
```

## **Knowledge Drive のデプロイ**

### **1. サービスアカウントの作成**

Google Cloud ではアプリケーションに権限を付与する場合、サービスアカウント (個人のアカウントではないアカウント) を利用します。

デフォルトでは Cloud Run にデプロイされたアプリケーションは強い権限を持ちます。最小権限の原則に従い、必要最小限の権限を持たせるため、まずサービス用のアカウントを作成します。

```bash
gcloud iam service-accounts create knowledge-drive
```

### **2. サービスアカウントへの権限追加**

Knowledge Drive は署名付き URL の作成、Firestore の読み書き権限が必要です。先程作成したサービスアカウントに権限を付与します。

```bash
gcloud projects add-iam-policy-binding $GOOGLE_CLOUD_PROJECT \
  --member serviceAccount:knowledge-drive@$GOOGLE_CLOUD_PROJECT.iam.gserviceaccount.com \
  --role 'roles/iam.serviceAccountTokenCreator'
gcloud projects add-iam-policy-binding $GOOGLE_CLOUD_PROJECT \
  --member serviceAccount:knowledge-drive@$GOOGLE_CLOUD_PROJECT.iam.gserviceaccount.com \
  --role 'roles/datastore.user'
gcloud projects add-iam-policy-binding $GOOGLE_CLOUD_PROJECT \
  --member serviceAccount:knowledge-drive@$GOOGLE_CLOUD_PROJECT.iam.gserviceaccount.com \
  --role 'roles/storage.objectUser'
```

### **3. Knowledge Drive のデプロイ**

Cloud Run では様々な方法でデプロイが可能です。ここでは以下の方法でアプリケーションをデプロイします。

- Dockerfile を利用して、1 コマンドでソースコードから Cloud Run にデプロイ

```bash
gcloud run deploy knowledge-drive \
  --source ./src/knowledge-drive-firestore \
  --service-account knowledge-drive@$GOOGLE_CLOUD_PROJECT.iam.gserviceaccount.com \
  --allow-unauthenticated \
  --region asia-northeast1 \
  --set-env-vars BUCKET_NAME=$GOOGLE_CLOUD_PROJECT-knowledge-drive \
  --quiet
```

**注**: デプロイ完了まで最長 8 分程度かかります。

## **Knowledge Drive の試用**

### **1. アプリケーションへブラウザからアクセス**

前のコマンドで出力された `Service URL` から URL をクリックすると、ブラウザのタブが開き、Knowledge Drive (Google Drive ライクファイル共有アプリ) が起動します。

### **2. フォルダの作成**

`新規` ボタンから `新しいフォルダの作成` をクリック、フォルダ名を入力し新しいフォルダを作成します。

### **3. 色々な機能の試用**

- `新規` ボタンからローカルにあるファイルのアップロードが可能です。
- 上部の検索バーから、ファイル名、フォルダ名の部分一致検索が可能です。
- フォルダは階層化でき、ファイルはアップロード後クリックすると、別のタブで表示することができます。

**注**: URL を知っている方は誰でもアクセス可能です。機密情報を含んだファイルはアップロードしないようにご注意ください。

## **生成 AI を活用しアップロード済みファイルをベースにした回答生成機能 (GenAI App) の追加**

Knowledge Drive に、生成 AI を活用し質問文への回答を返す機能である GenAI App を追加します。

今回は、GenAI App も個別の Cloud Run サービスでデプロイし、2 つのサービスを連携させるようにします。

## **GenAI App のデプロイ**

GenAI App もコンテナで Cloud Run で稼働させます。このアプリケーションは大きく以下の 2 つの機能を持っています。

- PDF ファイルが Cloud Storage に置かれると、それをトリガーにファイルの取得、Embedding の生成、データベースへの格納
- 質問文を受け取り、回答を生成して返す

### **1. サービスアカウントの作成**

このサービス用のアカウントを作成します。

```bash
gcloud iam service-accounts create genai-app
```

### **2. サービスアカウントへの権限追加**

生成 AI 処理アプリケーションは Firestore、Cloud Storage、Vertex AI などのサービスへのアクセス権限が必要です。

```bash
gcloud projects add-iam-policy-binding $GOOGLE_CLOUD_PROJECT \
  --member serviceAccount:genai-app@$GOOGLE_CLOUD_PROJECT.iam.gserviceaccount.com \
  --role roles/datastore.user
gcloud projects add-iam-policy-binding $GOOGLE_CLOUD_PROJECT \
  --member serviceAccount:genai-app@$GOOGLE_CLOUD_PROJECT.iam.gserviceaccount.com \
  --role roles/aiplatform.user
gcloud storage buckets add-iam-policy-binding gs://$GOOGLE_CLOUD_PROJECT-knowledge-drive \
  --member="serviceAccount:genai-app@$GOOGLE_CLOUD_PROJECT.iam.gserviceaccount.com" \
  --role="roles/storage.admin"
gcloud projects add-iam-policy-binding $GOOGLE_CLOUD_PROJECT \
  --member=serviceAccount:genai-app@$GOOGLE_CLOUD_PROJECT.iam.gserviceaccount.com \
  --role=roles/eventarc.eventReceiver
```

### **3 GenAI App のビルド、デプロイ**

```bash
gcloud run deploy genai-app \
  --source ./src/genai-app-firestore \
  --service-account genai-app@$GOOGLE_CLOUD_PROJECT.iam.gserviceaccount.com \
  --no-allow-unauthenticated \
  --set-env-vars "FLASK_PROJECT_ID=$GOOGLE_CLOUD_PROJECT" \
  --region asia-northeast1 \
  --quiet
```

## **Eventarc の設定**

ユーザーがファイルをアップロードしたときに生成 AI アプリを呼び出すように、Eventarc の設定を行います。

### **1. 前準備**

```bash
SERVICE_ACCOUNT="$(gcloud storage service-agent --project $GOOGLE_CLOUD_PROJECT)"
gcloud projects add-iam-policy-binding $GOOGLE_CLOUD_PROJECT \
  --member="serviceAccount:${SERVICE_ACCOUNT}" \
  --role='roles/pubsub.publisher'
gcloud run services add-iam-policy-binding genai-app \
  --member="serviceAccount:genai-app@${GOOGLE_CLOUD_PROJECT}.iam.gserviceaccount.com" \
  --role='roles/run.invoker' \
  --region asia-northeast1
```

### **2. Eventarc トリガーの作成**

```bash
gcloud eventarc triggers create genai-app-register-doc \
  --destination-run-service=genai-app \
  --destination-run-region=asia-northeast1 \
  --location=asia-northeast1 \
  --event-filters="type=google.cloud.storage.object.v1.finalized" \
  --event-filters="bucket=$GOOGLE_CLOUD_PROJECT-knowledge-drive" \
  --service-account=genai-app@$GOOGLE_CLOUD_PROJECT.iam.gserviceaccount.com \
  --destination-run-path=/register_doc
```

以下のようなエラーが出た場合は、数分待ってから再度コマンドを実行してください。

```
ERROR: (gcloud.eventarc.triggers.create) FAILED_PRECONDITION: Invalid resource state for "": Permission denied while using the Eventarc Service Agent.
```

## **非同期連携の設定**

今の非同期連携では以下の 2 つの問題があります。

- PDF ファイルの処理が 10 秒以内に終わらないと、エラー扱いになりリトライしてしまう
- リトライ回数に制限がなく、PDF ファイルの処理に失敗するとリトライされ続けてしまう＝リソースコストが上がり続けてしまう

これを解決するために以下の設定を行います。

- 各非同期処理の処理待ち時間を 300 秒 (5 分) に修正
- 最小リトライの間隔を 300 秒 (5 分) に修正
- 合計 5 回非同期の処理に失敗したら、リトライをやめる (デッドレタートピックに入れる)

### **1. デッドレタートピックの作成**

```bash
gcloud pubsub topics create genai-app-dead-letter
```

### **2. デッドレタートピック関連の権限設定**

```bash
PROJECT_NUMBER=$(gcloud projects describe $GOOGLE_CLOUD_PROJECT --format="value(projectNumber)")
SUBSCRIPTION=$(gcloud pubsub subscriptions list --format json | jq -r '.[].name')
gcloud pubsub topics add-iam-policy-binding genai-app-dead-letter \
  --member="serviceAccount:service-$PROJECT_NUMBER@gcp-sa-pubsub.iam.gserviceaccount.com" \
  --role="roles/pubsub.publisher"
gcloud pubsub subscriptions add-iam-policy-binding $SUBSCRIPTION \
  --member="serviceAccount:service-$PROJECT_NUMBER@gcp-sa-pubsub.iam.gserviceaccount.com" \
  --role="roles/pubsub.subscriber"
```

### **3. デッドレタートピックの設定、サブスクリプションの処理待ち時間、最小リトライ間隔の修正**

```bash
./scripts/setup_eventarc_subscription.sh genai-app-register-doc
```

## **Knowledge Drive の更新**

### **1. GenAI App API を呼び出す権限を付与**

```bash
gcloud run services add-iam-policy-binding genai-app \
  --member=serviceAccount:knowledge-drive@$GOOGLE_CLOUD_PROJECT.iam.gserviceaccount.com \
  --role=roles/run.invoker \
  --region asia-northeast1
```

### **2. 連携機能の有効化**

環境変数から GenAI App のアクセス先 URL を設定します。

```bash
GENAI_APP_URL=$(gcloud run services describe genai-app --region asia-northeast1 --format json | jq -r '.status.url')
gcloud run services update knowledge-drive \
  --region asia-northeast1 \
  --set-env-vars BUCKET_NAME=$GOOGLE_CLOUD_PROJECT-knowledge-drive \
  --set-env-vars SEARCH_HOST=$GENAI_APP_URL
```

### **3. ベクター検索を有効化するために Firestore にインデックスを作成**

```bash
gcloud firestore indexes composite create \
  --collection-group=embeddings \
  --query-scope=COLLECTION \
  --field-config=vector-config='{"dimension":"768","flat": "{}"}',field-path=embedding
```

## **連携機能の確認**

### **1. ファイルのアップロード**

GenAI App は PDF ファイルを読み取り、処理します。

以下の中から学習させてみたい PDF をローカル PC にダウンロードし、Knowledge Drive からアップロードしてください。

** Google Cloud ドキュメント**

- [Cloud Run](https://storage.googleapis.com/genai-handson-20230929/CloudRun.pdf)
- [Cloud SQL](https://storage.googleapis.com/genai-handson-20230929/CloudSQL.pdf)
- [Cloud Storage for Firebase](https://storage.googleapis.com/genai-handson-20230929/CloudStorageforFirebase.pdf)
- [Firebase Authentication](https://storage.googleapis.com/genai-handson-20230929/FirebaseAuthentication.pdf)
- [Firestore](https://storage.googleapis.com/genai-handson-20230929/Firestore.pdf)
- [Palm API と LangChain の連携](https://storage.googleapis.com/genai-handson-20230929/PalmAPIAndLangChain.pdf)

** Google Cloud ホワイトペーパー (英語)**

- [クラウドチームの編成](https://services.google.com/fh/files/misc/designing_cloud_teams.pdf)
- [Google Cloud の AI 導入フレームワーク](https://services.google.com/fh/files/misc/ai_adoption_framework_whitepaper.pdf)
- [Google Cloud 導入フレームワーク](https://services.google.com/fh/files/misc/google_cloud_adoption_framework_whitepaper.pdf)
- [統合データ分析プラットフォームの構築](https://services.google.com/fh/files/misc/googlecloud_unified_analytics_data_platform_paper_2021.pdf)
- [データベースを強みにする](https://services.google.com/fh/files/misc/guide_to_google_cloud_databases.pdf)
- [クラウドのデータ ガバナンスに関する原則とベスト プラクティス](https://services.google.com/fh/files/misc/principles_best_practices_for_data-governance.pdf)
- [マイクロサービスでクラウド ネイティブなアプローチを採用](https://cloud.google.com/files/Cloud-native-approach-with-microservices.pdf)

PDF ファイルが処理され検索対象に加わると、`ファイルのアイコンが青色` に変わります。

### **2. GenAI App への質問**

上部 `検索バー上の右の方のアイコンをクリック` すると、ファイル/フォルダ名検索と GenAI App への質問機能 (薄紫色に変わります) を切り替えられるようになっています。

GenAI App への質問に切り替え、先程アップロードしたファイルの情報に関連する質問を投げてみましょう。

無事、回答が返ってくれば成功です。

## **PDF、画像ファイルの要約生成機能の追加**

### **1. Eventarc トリガーの作成**

```bash
gcloud eventarc triggers create genai-app-summarize \
  --destination-run-service=genai-app \
  --destination-run-region=asia-northeast1 \
  --location=asia-northeast1 \
  --event-filters="type=google.cloud.storage.object.v1.finalized" \
  --event-filters="bucket=$GOOGLE_CLOUD_PROJECT-knowledge-drive" \
  --service-account=genai-app@$GOOGLE_CLOUD_PROJECT.iam.gserviceaccount.com \
  --destination-run-path=/summarize
```

### **2. デッドレタートピックの設定、サブスクリプションの処理待ち時間、最小リトライ間隔の修正**

```bash
./scripts/setup_eventarc_subscription.sh genai-app-summarize
```

### **3. 要約生成機能の動作確認**

PDF または画像ファイル (JPG, PNG 形式) をアプリケーションからアップロードします。

要約が生成されると `ファイルアイコンの右上に緑色のチェックマーク` が表示されます。その状態で、`ファイル名にマウスオーバー` をすると要約が表示されます。

## **Identity-Aware Proxy の利用**

デプロイ済みの Knowledge Drive アプリは、現在インターネットから誰でもアクセス可能で、ユーザーの区別もありません。

ここで [Identity-Aware Proxy](https://cloud.google.com/security/products/iap) という製品を用いて、アプリケーションにユーザー認証機能を追加します。

これを行うことで以下のような機能が追加されます。

- 特定のユーザー (Google アカウント) のみアクセス可能にする
- アップロードしたファイルがユーザーごとに保存される
- 生成 AI を用いた回答もユーザーごとのファイルから回答が生成される

## **外部アプリケーションロードバランサの作成、確認**

### **1. ロードバランサの作成**

Cloud Run と Identity-Aware Proxy を組み合わせて利用するには、まずロードバランサを作成する必要があります。

ロードバランサの作成は複数の手順が必要なため、ここではスクリプトにまとめて実行します。

```bash
bash ./assets/lb.sh
```

### **2. ロードバランサ経由でのアクセス確認**

以下のコマンドの出力をクリックし、ロードバランサ経由で Knowledge Drive にアクセスできることを確認します。

```bash
KNOWLEDGE_DRIVE_IP=$(gcloud compute addresses describe knowledge-drive-ip --format="get(address)" --global)
echo https://kd-${KNOWLEDGE_DRIVE_IP//./-}.nip.io
```

**注**: アクセスできるようになるまでに、最大 15 分程度の時間がかかります。

## **Identity-Aware Proxy の設定**

### **1. 管理画面に遷移**

<walkthrough-spotlight-pointer spotlightId="console-nav-menu">ナビゲーションメニュー</walkthrough-spotlight-pointer> -> セキュリティ -> Identity-Aware Proxy の順に進みます。

### **2. OAuth 同意画面の設定**

1. `同意画面を構成`　ボタンをクリック
1. `外部` のチェックボックスをチェックし、`作成` ボタンをクリック
1. `アプリ名` に `knowledge-drive` と入力
1. `ユーザーサポートメール` をクリックし、表示されたメールアドレスを選択
1. `デベロッパーの連絡先情報` にご自身のメールアドレスを入力し、`保存して次へ` ボタンをクリック
1. `スコープ` 画面では何も変更せずに `保存して次へ` ボタンをクリック
1. `テストユーザー` 画面では何も変更せずに `保存して次へ` ボタンをクリック
1. `概要` 画面では最下部まで移動し、`ダッシュボードに戻る` ボタンをクリック
1. 上の手順 #1 に従い、Identity-Aware Proxy の管理画面に戻る

### **3. Identity-Aware Proxy の有効化**

1. `knowledge-drive-bs` の右の IAP スライダーをクリックする
1. 有効化の確認画面で、構成要件の確認チェックボックスをチェックする
1. `有効にする` をクリックする
1. 少し待ち、ステータスが `OK` になることを確認する

これで Identity-Aware proxy の設定が完了しました。

## **アクセス可能ユーザーの追加**

今回は Qwiklabs から払い出されたアカウント (student-xxxxxxxx@qwiklabs.net) をアクセス可能なように設定します。

### **1. Identity-Aware Proxy 有効化の確認**

先程アクセスしていたロードバランサ経由の URL にアクセスします。

```bash
KNOWLEDGE_DRIVE_IP=$(gcloud compute addresses describe knowledge-drive-ip --format="get(address)" --global)
echo https://kd-${KNOWLEDGE_DRIVE_IP//./-}.nip.io
```

正しく設定ができていると、Google サインイン画面に遷移します。有効化に少し時間がかかるため、アクセスできてしまっている方は少し待ってみてください。

ご自身の Google アカウントを選択し、アクセスが拒否されることを確認します。

### **2. OAuth 同意画面からテストユーザーを追加**

1. [OAuth 同意画面](https://console.cloud.google.com/apis/credentials/consent) をクリックし、OAuth 同意画面に遷移
1. `テストユーザー` の `+ ADD USERS` ボタンをクリックし、 Qwiklabs アカウントのメールアドレスを入力し、`保存` ボタンをクリックする
1. `テストユーザー` のリストに、入力したメールアドレスが追加されたことを確認する

### **3. Identity-Aware Proxy へユーザーの追加**

```bash
ACCOUNT=$(gcloud config get account)
gcloud iap web add-iam-policy-binding \
  --resource-type backend-services \
  --service knowledge-drive-bs \
  --role 'roles/iap.httpsResourceAccessor' \
  --member "user:$ACCOUNT"
```

## **Identity-Aware Proxy の動作確認**

### **1. アプリケーションへのアクセス確認**

再度、ロードバランサ経由の URL にアクセスし、Google サインイン画面から Qwiklabs のアカウントを選びます。

```bash
KNOWLEDGE_DRIVE_IP=$(gcloud compute addresses describe knowledge-drive-ip --format="get(address)" --global)
echo https://kd-${KNOWLEDGE_DRIVE_IP//./-}.nip.io
```

正しく設定ができていると、Knowledge Drive の管理画面にアクセスが可能です。

アクセスができない場合は少し待ってみてください。

### **2. アプリケーションの動作確認**

アプリケーションはログインユーザーを認識し、元々アップロードされていたファイルは見えなくなっています。

フォルダの作成、ファイルのアップロードを実行し、`オーナー` が自分のメールアドレスになっていることを確認します。

また他に利用できる Google アカウントをお持ちの方は前ステップの #2, #3 を参考にその Google アカウントを登録し、複数のアカウントでログインしてみて、複数のユーザーが正しくアプリケーションを利用できることを確認します。

## **セキュリティの向上**

ロードバランサ経由でのアクセスに認証を設定しましたが、直接 Cloud Run にアクセスすると認証無しで管理画面にアクセスできてしまいます。

そこで、Cloud Run の設定を変更し、直接のアクセスをさせないようにします。

### **1. 直接アクセスできることを確認**

以下のコマンドを実行し出力された URL をクリックして確認します。

```bash
gcloud run services describe knowledge-drive \
  --region asia-northeast1 --format "value(status.url)"
```

### **2. アクセス元を Google Cloud の内部、またはロードバランサに限定**

```bash
gcloud run services update knowledge-drive \
  --region asia-northeast1 \
  --ingress internal-and-cloud-load-balancing
```

出力された URL をクリックし、アクセスができないこと (Error: Page not Found) が表示されることを確認します。

### **3. ロードバランサ経由でのアクセス確認**

ロードバランサ経由の URL にアクセスし、問題なくアクセスできることを確認します。

```bash
KNOWLEDGE_DRIVE_IP=$(gcloud compute addresses describe knowledge-drive-ip --format="get(address)" --global)
echo https://kd-${KNOWLEDGE_DRIVE_IP//./-}.nip.io
```

## **Log Analytics (BigQuery) を使ったログ分析**

### **1. Log Analytics 画面に遷移**

<walkthrough-spotlight-pointer spotlightId="console-nav-menu">ナビゲーションメニュー</walkthrough-spotlight-pointer> -> ロギング -> ログ分析 の順に進みます。

### **2. データが取得されているかを確認**

以下の `コマンドの出力結果をクエリ入力画面に貼り付け`、`クエリを実行` ボタンをクリックし実行してみてください。

```shell
cat << EOF

SELECT
  timestamp, severity, resource.type, log_name, text_payload, proto_payload, json_payload
FROM
  \`$GOOGLE_CLOUD_PROJECT.asia-northeast1.run-analytics-bucket._AllLogs\`
LIMIT 50

EOF
```

うまくログが取れていた場合、いくつかのログがテーブル形式で表示されます。

### **3. 様々なクエリを試してみる**

1. リクエスト数が多い順に URL へのアクセス数を調べる

```shell
cat << EOF

SELECT
  http_request.request_url, COUNT(http_request.request_url) AS request_count
FROM
  \`$GOOGLE_CLOUD_PROJECT.asia-northeast1.run-analytics-bucket._AllLogs\`
WHERE
  http_request IS NOT NULL AND
  http_request.request_url IS NOT NULL
GROUP BY
  http_request.request_url
ORDER BY
  COUNT(http_request.request_url) DESC
LIMIT 50

EOF
```

2. リクエストに関係ない、アプリケーションログ情報

```shell
cat << EOF

SELECT
  text_payload, count(text_payload) as payload_count
FROM
  \`$GOOGLE_CLOUD_PROJECT.asia-northeast1.run-analytics-bucket._AllLogs\`
WHERE
  text_payload IS NOT NULL AND
  log_id != "run.googleapis.com/requests"
GROUP BY
  text_payload
ORDER BY
  count(text_payload) DESC
LIMIT 50

EOF
```

様々な条件でログをクエリすることが可能です。

[サンプル SQL クエリ](https://cloud.google.com/logging/docs/analyze/examples?hl=ja) を参考に色々試してみてください。

## **Congraturations!**

<walkthrough-conclusion-trophy></walkthrough-conclusion-trophy>

これにて生成 AI を用いたアプリケーション開発ハンズオンが完了です。

Qwiklabs に戻り、`ラボを終了` ボタンをクリックし、ハンズオンを終了します。
