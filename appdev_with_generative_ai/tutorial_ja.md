# **Google Cloud で始める生成 AI を活用したアプリケーション開発入門**

## **ハンズオン概要**

本ハンズオンでは、[Cloud Run](https://cloud.google.com/run), [Firebase](https://firebase.google.com/) といった Google Cloud イチ押しのマネージドなサービスをフル活用し、クラウドネイティブなアプリケーション開発を体験します。そしてそのアプリケーションに生成 AI を使ったインテリジェントな機能を追加することで、実際のサービスと生成 AI の組み合わせの事例を学んでいただけます。

以下が今回のハンズオンで利用する主要なサービスです。

**Cloud Run**

- Dockerfile、ソースコードから 1 コマンドで Cloud Run にデプロイ
- プライベートリリース (タグをつけたリリース) などのトラフィック コントロール
- 複数のサービスを Cloud Run で動かし連携させる

**Firebase**

- 認証 (Firebase Authentication)
- NoSQL データベース (Firestore)
- オブジェクトストレージ (Cloud Storage for Firebase)

**Vertex AI**

- 生成 AI の API (Palm2 API)
- モデルの作成
- モデルのチューニング

今回は以下の 2 つのアプリケーションを構築していくことで、Google Cloud を使った生成 AI のアプリケーション組み込みを学びます。

- クラウドにファイルを保存する Web アプリケーション (Knowledge Drive)
- 生成 AI 機能を担当するアプリケーション (GenAI App)

## **Google Cloud プロジェクトの確認**

開いている Cloud Shell のプロンプトに `(黄色の文字)` の形式でプロジェクト ID が表示されていることを確認してください。

これが表示されている場合は、Google Cloud のプロジェクトが正しく認識されています。

表示されていない場合は、以下の手順で Cloud Shell を開き直して下さい

1. Cloud Shell を閉じる
1. 上のメニューバーのプロジェクト選択部分で払い出されたプロジェクトが選択されていることを確認する。
1. Cloud Shell を再度開く

## **環境準備**

<walkthrough-tutorial-duration duration=10></walkthrough-tutorial-duration>

最初に、ハンズオンを進めるための環境準備を行います。

下記の設定を進めていきます。

- gcloud コマンドラインツール設定
- Google Cloud 機能（API）有効化設定

## **gcloud コマンドラインツール**

Google Cloud は、コマンドライン（CLI）、GUI から操作が可能です。ハンズオンでは主に CLI を使い作業を行いますが、GUI で確認する URL も合わせて掲載します。

### **1. gcloud コマンドラインツールとは?**

gcloud コマンドライン インターフェースは、Google Cloud でメインとなる CLI ツールです。このツールを使用すると、コマンドラインから、またはスクリプトや他の自動化により、多くの一般的なプラットフォーム タスクを実行できます。

たとえば、gcloud CLI を使用して、以下のようなものを作成、管理できます。

- Google Kubernetes Engine クラスタ
- Google Cloud SQL インスタンス

**ヒント**: gcloud コマンドラインツールについての詳細は[こちら](https://cloud.google.com/sdk/gcloud?hl=ja)をご参照ください。

### **2. gcloud からの Cloud Run のデフォルト設定**

Cloud Run の利用するリージョン、プラットフォームのデフォルト値を設定します。

```bash
gcloud config set run/region asia-northeast1
gcloud config set run/platform managed
```

ここではリージョンを東京、プラットフォームをフルマネージドに設定しました。この設定を行うことで、gcloud コマンドから Cloud Run を操作するときに毎回指定する必要がなくなります。

## **参考: Cloud Shell の接続が途切れてしまったときは?**

一定時間非アクティブ状態になる、またはブラウザが固まってしまったなどで `Cloud Shell` の接続が切れてしまう場合があります。

その場合は `再接続` をクリックした後、以下の対応を行い、チュートリアルを再開してください。

![再接続画面](https://raw.githubusercontent.com/GoogleCloudPlatform/gcp-getting-started-lab-jp/master/workstations_with_generative_ai/images/reconnect_cloudshell.png)

### **1. チュートリアル資材があるディレクトリに移動する**

```bash
cd ~/gcp-getting-started-lab-jp/appdev_with_generative_ai
```

### **2. チュートリアルを開く**

```bash
teachme tutorial_ja.md
```

### **3. gcloud のデフォルト設定**

```bash
gcloud config set run/region asia-northeast1
gcloud config set run/platform managed
```

途中まで進めていたチュートリアルのページまで `Next` ボタンを押し、進めてください。

## **Google Cloud 環境設定**

Google Cloud では利用したい機能（API）ごとに、有効化を行う必要があります。
ここでは、以降のハンズオンで利用する機能を事前に有効化しておきます。

```bash
gcloud services enable \
  run.googleapis.com \
  artifactregistry.googleapis.com \
  cloudbuild.googleapis.com \
  firestore.googleapis.com \
  pubsub.googleapis.com \
  eventarc.googleapis.com \
  sqladmin.googleapis.com \
  aiplatform.googleapis.com \
  translate.googleapis.com \
  firebasestorage.googleapis.com
```

**GUI**: [API ライブラリ](https://console.cloud.google.com/apis/library)

<walkthrough-footnote>必要な機能が使えるようになりました。次に Firebase の設定方法を学びます。</walkthrough-footnote>

## **Firebase の設定**

Knowledge Drive では、ユーザー情報は [Firebase Authentication](https://firebase.google.com/docs/auth)、アプリケーションのメタデータは [Cloud Firestore](https://firebase.google.com/docs/firestore)、 そしてファイルの格納場所として [Cloud Storage for Firebase](https://firebase.google.com/docs/storage) を活用します。Firebase の機能を活用することで、リアルタイム性の高い Web アプリケーションを開発することができます。

### **1. Firebase プロジェクトの有効化**

**GUI** から Firebase を有効化します。

1. [Firebase コンソール](https://console.firebase.google.com/) にブラウザからアクセスします。
1. `プロジェクトを作成` または `プロジェクトを追加` ボタンをクリックします。
1. プロジェクトの作成 (手順 1/3)

   `プロジェクト名を入力` のところから作成済みの Google Cloud プロジェクトを選択します。次に 規約への同意、利用目的のチェックマークを入れ、`続行` をクリックします。

   料金確認画面が表示された場合は、`プランを確認` ボタンをクリックします。

1. プロジェクトの作成 (手順 2/4)

   `続行` をクリックします。

1. プロジェクトの作成 (手順 3/3)

   `このプロジェクトで Google アナリティクスを有効にする` をオフにし、`Firebase を追加` をクリックします。

1. `新しいプロジェクトの準備ができました` と表示されたら `続行` をクリックします。

### **2. Firebase アプリケーションの作成**

**CLI** から実行します。

```bash
firebase apps:create -P $GOOGLE_CLOUD_PROJECT WEB knowledge-drive
```

### **3. Firebase 設定のアプリケーションへの埋め込み**

```bash
./scripts/firebase_config.sh ./src/knowledge-drive
```

全ての NEXT_PUBLIC_FIREBASE_XXXX という出力の右辺 (=より後ろ) に、文字列が設定されていれば成功です。

## **Firebase Authentication の設定**

**GUI** から Firebase Authentication を有効化します。

1. 以下のコマンドで出力された URL にブラウザからアクセスします。

   ```bash
   echo "https://console.firebase.google.com/project/$GOOGLE_CLOUD_PROJECT/overview?hl=ja"
   ```

1. `Authentication` カードをクリックします。
1. `始める` ボタンをクリックします。
1. `新しいプロバイダを追加` ボタンをクリックします。
1. ネイティブのプロバイダから `メール / パスワード` をクリックします。
1. メール / パスワードの `有効にする` をクリックし、有効化します。
1. `保存` ボタンをクリックします。
1. メール / パスワードのプロバイダに有効のチェックが付いていることを確認します。

## **Firestore データベース、セキュリティルールの設定**

### **1. Firestore データベースの作成**

データストアとして利用する Firestore を東京リージョンに作成します。

```bash
gcloud firestore databases create --location asia-northeast1
```

### **2. Firestore を操作するための CLI の初期化**

```bash
firebase init firestore -P $GOOGLE_CLOUD_PROJECT
```

2 つプロンプトが出ますが両方とも `Enter` を押しデフォルト設定を採用します。

### **3. セキュリティルール設定ファイルを上書き**

**注**: 以下のコマンドはコピー&ペーストで実行してください。

```shell
cat << EOF > firestore.rules
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /users/{userId} {
      allow read: if request.auth != null
                  && request.auth.uid == userId;
      match /items/{itemId} {
        allow read, write: if request.auth != null
                           && request.auth.uid == userId;
      }
    }
  }
}
EOF
```

### **4. Firebase インデックス設定ファイルの上書き**

**注**: 以下のコマンドはコピー&ペーストで実行してください。

```shell
cat << EOF > firestore.indexes.json
{
  "indexes": [
    {
      "collectionGroup": "items",
      "queryScope": "COLLECTION",
      "fields": [
        {
          "fieldPath": "parent",
          "order": "ASCENDING"
        },
        {
          "fieldPath": "timestamp",
          "order": "DESCENDING"
        }
      ]
    },
    {
      "collectionGroup": "items",
      "queryScope": "COLLECTION",
      "fields": [
        {
          "fieldPath": "name",
          "order": "ASCENDING"
        },
        {
          "fieldPath": "timestamp",
          "order": "DESCENDING"
        }
      ]
    }
  ],
  "fieldOverrides": []
}
EOF
```

### **5. 更新したセキュリティルール、インデックスをデプロイ**

```bash
firebase deploy --only firestore -P $GOOGLE_CLOUD_PROJECT
```

## **Cloud Storage for Firebase、セキュリティルールの設定**

### **1. Firebase のデフォルトロケーションの設定**

**GUI** からデフォルトロケーションを設定します。

1. 以下のコマンドで出力された URL にブラウザからアクセスします。

   ```bash
   echo "https://console.firebase.google.com/project/$GOOGLE_CLOUD_PROJECT/overview?hl=ja"
   ```

1. 左メニュー上部のプロジェクトの概要右の `歯車マーク`、`プロジェクトの設定` の順にクリックします。
1. `全般` タブが選択されていることを確認します。
1. `デフォルトの GCP リソース ロケーション` の鉛筆マークをクリックします。
1. `asia-northeast1` が選択されていることを確認し、`完了` をクリックします。

### **2. Cloud Storage を利用するための CLI の初期化**

ファイルのストレージとして利用する Cloud Storage の CLI を設定します。

```bash
firebase init storage -P $GOOGLE_CLOUD_PROJECT
```

1 つプロンプトが出ますが `Enter` を押しデフォルト設定を採用します。

### **3. セキュリティルール設定ファイルを上書き**

**注**: 以下のコマンドはコピー&ペーストで実行してください。

```shell
cat << EOF > storage.rules
rules_version = '2';
service firebase.storage {
  match /b/{bucket}/o {
    match /files/{userId}/{itemId} {
      allow read, write: if request.auth != null
                         && request.auth.uid == userId;
    }
  }
}
EOF
```

### **4. 更新したセキュリティルールをデプロイ**

```bash
firebase deploy --only storage -P $GOOGLE_CLOUD_PROJECT
```

## **Knowledge Drive デプロイの事前設定**

Cloud Run では様々な方法でデプロイが可能です。ここでは以下の方法でアプリケーションをデプロイします。

- Dockerfile を利用して、Cloud Build でコンテナイメージを作成。作成したコンテナイメージを Cloud Run にデプロイ

### **1. Docker リポジトリ (Artifact Registry) の作成**

```bash
gcloud artifacts repositories create drive-repo \
  --repository-format docker \
  --location asia-northeast1 \
  --description "Docker repository for knowledge drive"
```

### **2. サービスアカウントの作成**

デフォルトでは Cloud Run にデプロイされたアプリケーションは強い権限を持ちます。最小権限の原則に従い、必要最小限の権限を持たせるため、まずサービス用のアカウントを作成します。

```bash
gcloud iam service-accounts create knowledge-drive
```

### **3. サービスアカウントへの権限追加**

Knowledge Drive は認証情報の操作、Firestore の読み書き権限が必要です。先程作成したサービスアカウントに権限を付与します。

```bash
gcloud projects add-iam-policy-binding $GOOGLE_CLOUD_PROJECT \
  --member serviceAccount:knowledge-drive@$GOOGLE_CLOUD_PROJECT.iam.gserviceaccount.com \
  --role 'roles/firebase.sdkAdminServiceAgent'
gcloud projects add-iam-policy-binding $GOOGLE_CLOUD_PROJECT \
  --member serviceAccount:knowledge-drive@$GOOGLE_CLOUD_PROJECT.iam.gserviceaccount.com \
  --role 'roles/firebaseauth.admin'
gcloud projects add-iam-policy-binding $GOOGLE_CLOUD_PROJECT \
  --member serviceAccount:knowledge-drive@$GOOGLE_CLOUD_PROJECT.iam.gserviceaccount.com \
  --role 'roles/iam.serviceAccountTokenCreator'
```

## **Knowledge Drive のデプロイ**

Cloud Build でコンテナイメージを作成、作成したイメージを Cloud Run にデプロイします。

```bash
gcloud builds submit ./src/knowledge-drive \
  --tag asia-northeast1-docker.pkg.dev/$GOOGLE_CLOUD_PROJECT/drive-repo/knowledge-drive && \
gcloud run deploy knowledge-drive \
  --image asia-northeast1-docker.pkg.dev/$GOOGLE_CLOUD_PROJECT/drive-repo/knowledge-drive \
  --service-account knowledge-drive@$GOOGLE_CLOUD_PROJECT.iam.gserviceaccount.com \
  --allow-unauthenticated
```

**注**: デプロイ完了まで 5 分程度かかります。

## **Knowledge Drive の試用**

### **1. アプリケーションへブラウザからアクセス**

前のコマンドで出力された `Service URL` から URL をクリックすると、ブラウザのタブが開きチャットアプリケーションが起動します。

### **2. 新規ユーザーの登録**

最下部の `アカウントを登録する` をクリックし、ユーザー情報を入力、`登録 / Register` をクリックします。

うまく登録ができると、ファイル管理画面に遷移します。

### **3. 色々な機能の試用**

- `新規` ボタンから新しいフォルダの作成、ローカルにあるファイルのアップロードが可能です。
- 右上の `アバター` マークをクリックするとログアウトが可能です。
- 上部の検索バーから、ファイル名、フォルダ名の検索が可能です。完全一致検索となっていることに注意してください。
- フォルダは階層化でき、ファイルはアップロード後クリックすると、別のタブで表示することができます。

### **4. 別アカウントでの動作を確認**

一度ログアウトし、別のアカウントを作成してサインインしてみましょう。

先に作成したアカウントとはファイル、フォルダが分離されていることがわかります。

## **生成 AI を活用しアップロード済みファイルをベースにした回答生成機能 (GenAI App) の追加**

Knowledge Drive に、生成 AI を活用し質問文への回答を返す機能である GenAI App を追加します。

今回は、GenAI App も個別の Cloud Run サービスでデプロイし、2 つのサービスを連携させるようにします。

## **Cloud SQL データベースの作成、設定**

ファイルのテキストデータを Embedding に変換し、Cloud SQL for PostgreSQL に保存する構成とします。

### **1. Cloud SQL データベースインスタンスを作成**

```bash
gcloud sql instances create pg15-pgvector-demo --database-version=POSTGRES_15 \
    --region=asia-northeast1 --cpu=1 --memory=4GB --root-password=handson
```

最大 10 分程度かかります。

### **2. Cloud SQL データベースを作成**

```bash
gcloud sql databases create docs --instance=pg15-pgvector-demo
```

### **3. データベースユーザーの作成**

```bash
gcloud sql users create docs-admin \
  --instance=pg15-pgvector-demo \
  --password=handson
```

### **4. データベースに接続**

```bash
gcloud sql connect pg15-pgvector-demo --user=docs-admin --database=docs
```

パスワードを聞かれますので `handson` と入力してください。

データベースに接続するとプロンプトの表示が変わります。

### **5. ベクトル検索用拡張機能の追加**

**注**: 以下のコマンドはコピー&ペーストで実行してください。

```shell
CREATE EXTENSION IF NOT EXISTS vector;
```

### **6. Embedding データ用テーブルの作成**

**注**: 以下のコマンドはコピー&ペーストで実行してください。

```shell
CREATE TABLE docs_embeddings(
  document_id VARCHAR(1024) NOT NULL,
  content TEXT,
  metadata TEXT,
  user_id TEXT,
  embedding vector(768));
```

### **7. データベースから切断**

```bash
exit
```

これでデータベースの準備が完了しました。

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

生成 AI 処理アプリケーションは Cloud SQL、Vertex AI などのサービスへのアクセス権限が必要です。

```bash
gcloud projects add-iam-policy-binding $GOOGLE_CLOUD_PROJECT \
  --member serviceAccount:genai-app@$GOOGLE_CLOUD_PROJECT.iam.gserviceaccount.com \
  --role roles/cloudsql.client
gcloud projects add-iam-policy-binding $GOOGLE_CLOUD_PROJECT \
  --member serviceAccount:genai-app@$GOOGLE_CLOUD_PROJECT.iam.gserviceaccount.com \
  --role roles/aiplatform.user
gcloud projects add-iam-policy-binding $GOOGLE_CLOUD_PROJECT \
  --member serviceAccount:genai-app@$GOOGLE_CLOUD_PROJECT.iam.gserviceaccount.com \
  --role roles/storage.objectUser
gcloud projects add-iam-policy-binding $GOOGLE_CLOUD_PROJECT \
  --member=serviceAccount:genai-app@$GOOGLE_CLOUD_PROJECT.iam.gserviceaccount.com \
  --role=roles/eventarc.eventReceiver
gcloud projects add-iam-policy-binding $GOOGLE_CLOUD_PROJECT \
  --member serviceAccount:genai-app@$GOOGLE_CLOUD_PROJECT.iam.gserviceaccount.com \
  --role roles/datastore.user
```

### **3 GenAI App のビルド、デプロイ**

```bash
gcloud builds submit ./src/genai-app \
  --tag asia-northeast1-docker.pkg.dev/$GOOGLE_CLOUD_PROJECT/drive-repo/genai-app && \
gcloud run deploy genai-app \
  --image asia-northeast1-docker.pkg.dev/$GOOGLE_CLOUD_PROJECT/drive-repo/genai-app \
  --service-account genai-app@$GOOGLE_CLOUD_PROJECT.iam.gserviceaccount.com \
  --no-allow-unauthenticated --set-env-vars "PJID=$GOOGLE_CLOUD_PROJECT"
```

## **Eventarc の設定**

ユーザーがファイルをアップロードしたときに生成 AI アプリを呼び出すように、Eventarc の設定を行います。

### **1. 前準備**

```bash
SERVICE_ACCOUNT="$(gsutil kms serviceaccount -p $GOOGLE_CLOUD_PROJECT)"
gcloud projects add-iam-policy-binding $GOOGLE_CLOUD_PROJECT \
  --member="serviceAccount:${SERVICE_ACCOUNT}" \
  --role='roles/pubsub.publisher'
gcloud run services add-iam-policy-binding genai-app \
  --member="serviceAccount:genai-app@${GOOGLE_CLOUD_PROJECT}.iam.gserviceaccount.com" \
  --role='roles/run.invoker'
```

### **2. Eventarc トリガーの作成**

```bash
gcloud eventarc triggers create genai-app \
  --destination-run-service=genai-app \
  --destination-run-region=asia-northeast1 \
  --location=asia-northeast1 \
  --event-filters="type=google.cloud.storage.object.v1.finalized" \
  --event-filters="bucket=$GOOGLE_CLOUD_PROJECT.appspot.com" \
  --service-account=genai-app@$GOOGLE_CLOUD_PROJECT.iam.gserviceaccount.com \
  --destination-run-path=/register_doc
```

以下のようなエラーが出た場合は、数分待ってから再度コマンドを実行してください。

```
ERROR: (gcloud.eventarc.triggers.create) FAILED_PRECONDITION: Invalid resource state for "": Permission denied while using the Eventarc Service Agent.
```

### **3. サブスクリプションの確認応答時間の修正**

```bash
SUBSCRIPTION=$(gcloud pubsub subscriptions list --format json | jq -r '.[].name')
gcloud pubsub subscriptions update \
  $SUBSCRIPTION --ack-deadline=300
```

## **Knowledge Drive の更新**

### **1. GenAI App API を呼び出す権限を付与**

```bash
gcloud run services add-iam-policy-binding genai-app \
  --member=serviceAccount:knowledge-drive@$GOOGLE_CLOUD_PROJECT.iam.gserviceaccount.com \
  --role=roles/run.invoker
```

### **2. GenAI App との連携機能追加**

GenAI App と連携するために、Knowledge Drive を更新します。

```bash
git switch genai-app-integration
```

### **3. 連携機能のデプロイ**

```bash
GENAI_APP_URL=$(gcloud run services describe genai-app --region asia-northeast1 --format json | jq -r '.status.url')
gcloud builds submit ./src/knowledge-drive \
  --tag asia-northeast1-docker.pkg.dev/$GOOGLE_CLOUD_PROJECT/drive-repo/knowledge-drive && \
gcloud run deploy knowledge-drive \
  --image asia-northeast1-docker.pkg.dev/$GOOGLE_CLOUD_PROJECT/drive-repo/knowledge-drive \
  --service-account knowledge-drive@$GOOGLE_CLOUD_PROJECT.iam.gserviceaccount.com \
  --allow-unauthenticated --set-env-vars "SEARCH_HOST=$GENAI_APP_URL"
```

## **連携機能の確認**

### **1. ファイルのアップロード**

GenAI App は PDF ファイルを読み取り、処理します。

以下の中から学習させてみたい PDF をローカル PC にダウンロードし、Knowledge Drive からアップロードしてください。

- [Cloud Run](https://storage.googleapis.com/genai-handson-20230929/CloudRun.pdf)
- [Cloud SQL](https://storage.googleapis.com/genai-handson-20230929/CloudSQL.pdf)
- [Cloud Storage for Firebase](https://storage.googleapis.com/genai-handson-20230929/CloudStorageforFirebase.pdf)
- [Firebase Authentication](https://storage.googleapis.com/genai-handson-20230929/FirebaseAuthentication.pdf)
- [Firestore](https://storage.googleapis.com/genai-handson-20230929/Firestore.pdf)
- [Palm API と LangChain の連携](https://storage.googleapis.com/genai-handson-20230929/PalmAPIAndLangChain.pdf)

### **2. GenAI App への質問**

上部検索バー上の右の方のアイコンをクリックすると、ファイル/フォルダ名検索と GenAI App への質問機能を切り替えられるようになっています。

GenAI App への質問に切り替え、先程アップロードしたファイルの情報に関連する質問を投げてみましょう。

無事、回答が返ってくれば成功です。

### **3. 色々試してみる**

様々な PDF をアップロードして回答がどのように変わるか試してみましょう。

## **Congraturations!**

<walkthrough-conclusion-trophy></walkthrough-conclusion-trophy>

これにて生成 AI を用いたアプリケーション開発ハンズオンが完了です。

Qwiklabs に戻り、`ラボを終了` ボタンをクリックし、ハンズオンを終了します。
