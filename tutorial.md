
# **クラウドネイティブなアプリケーション開発ハンズオン**

本ハンズオンではコンテナをサーバーレスで動かすサービスである [Cloud Run](https://cloud.google.com/run) そして、フルマネージドなデータベースである [Firestore](https://firebase.google.com/docs/firestore?hl=ja) の様々な機能を実際のリアルタイムチャット アプリケーションを用いて体験します。

Cloud Run

- Dockerfile、ソースコードから 1 コマンドで Cloud Run にデプロイ
- プライベートリリース (タグをつけたリリース) などのトラフィック コントロール
- 複数のサービスを Cloud Run で動かし連携させる

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

### **2. プロジェクト ID を設定する**
`your-project-id` を実際のプロジェクト ID に更新して実行してください。

```bash
export GOOGLE_CLOUD_PROJECT=your-project-id
```

### **3. gcloud のデフォルト設定**

```bash
gcloud config set project $GOOGLE_CLOUD_PROJECT
gcloud config set run/region us-central1
gcloud config set run/platform managed
```

ここではリージョンを東京、プラットフォームをフルマネージドに設定しました。この設定を行うことで、gcloud コマンドから Cloud Run を操作するときに毎回指定する必要がなくなります。

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
  pubsub.googleapis.com
```

**GUI**: [API ライブラリ](https://console.cloud.google.com/apis/library)

<walkthrough-footnote>必要な機能が使えるようになりました。次に実際に Cloud Run にアプリケーションをデプロイする方法を学びます。</walkthrough-footnote>

## **Firebase の設定**

ユーザー情報、チャットメッセージ情報は [Firestore](https://firebase.google.com/docs/firestore?hl=ja) に格納します。またリアルタイムでチャットを同期するためにも Firestore のリアルタイムアップデート機能を用います。

クライアント (JavaScript) から直接アクセスさせるため、Firebase の設定を行います。

### **1. Firebase プロジェクトの有効化**

**GUI** から Firebase を有効化します。

1. [Firebase コンソール](https://console.firebase.google.com/) にブラウザからアクセスします。
1. `Firebase プロジェクトを作成する`ボタンをクリックします。
1. プロジェクトの作成 (手順 1/3)

   `Google Cloud プロジェクトに Firebase を追加` のところからLabの Google Cloud プロジェクトを選択します。次に 規約への同意、利用目的のチェックマークを入れ、`続行` をクリックします。

   料金確認画面が表示された場合は、`プランを確認` ボタンをクリックします。

1. プロジェクトの作成 (手順 2/4)

   `続行` をクリックします。

1. プロジェクトの作成 (手順 3/3)

   `このプロジェクトで Google アナリティクスを有効にする` をオフにし、`プロジェクトを作成` をクリックします。

1. `新しいプロジェクトの準備ができました` と表示されたら `続行` をクリックします。

### **2. Firebase アプリケーションの作成**

**CLI** から実行します。

```bash
firebase apps:create -P $GOOGLE_CLOUD_PROJECT WEB streamchat
```

### **3. Firestore 設定のアプリケーションへの埋め込み**

```bash
cp ./src/streamchat-simple/.env.example ./src/streamchat-simple/.env
./scripts/firebase_config.sh ./src/streamchat-simple
```

## **Firebase Authentication の設定**

**GUI** から Firebase Authentication を有効化します。

スクリーンショットを見ながら進めたい方は、補足資料をご確認ください。

1. 以下のコマンドで出力された URL にブラウザからアクセスします。

   ```bash
   echo "https://console.firebase.google.com/project/$GOOGLE_CLOUD_PROJECT/overview?hl=ja"
   ```

1. 左パネルから　構築 > `Authentication` カードをクリックします。
1. `始める` ボタンをクリックします。
1. ログイン方法から `メール / パスワード` をクリックし、メール / パスワードを有効にします
1. `保存` ボタンをクリックします。
1. メール / パスワードのプロバイダに有効のチェックが付いていることを確認します。

## **Firestore データベース、セキュリティルールの設定**

### **1. Firestore データベースの作成**

データストアとして利用する Firestore を東京リージョンに作成します。

```bash
gcloud firestore databases create --location us-central1
```

### **2. Firestore を操作するための CLI の初期化**

```bash
firebase init firestore -P $GOOGLE_CLOUD_PROJECT
```

2つプロンプトが出ますが両方とも `Enter` を押しデフォルト設定を採用します。

### **3. セキュリティルール設定ファイルを上書き**

**注**: 以下のコマンドはコピー&ペーストで実行してください。

```shell
cat << EOF > firestore.rules
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /{document=**} {
      allow read: if request.auth != null;
      allow write: if false;
    }
  }
}
EOF
```

### **4. 更新したルールをデプロイ**

```bash
firebase deploy --only firestore:rules -P $GOOGLE_CLOUD_PROJECT
```

## **チャット アプリケーション用の事前設定**

Cloud Run では様々な方法でデプロイが可能です。ここでは以下の方法でアプリケーションをデプロイします。

- Dockerfile を利用して、Cloud Build でコンテナイメージを作成。作成したコンテナイメージを Cloud Run にデプロイ

### **1. Docker リポジトリ (Artifact Registry) の作成**

```bash
gcloud artifacts repositories create chat-repo \
  --repository-format docker \
  --location us-central1 \
  --description "Docker repository for stream chat"
```

### **2. サービスアカウントの作成**

デフォルトでは Cloud Run にデプロイされたアプリケーションは強い権限を持ちます。最小権限の原則に従い、必要最小限の権限を持たせるため、まずサービス用のアカウントを作成します。

```bash
gcloud iam service-accounts create streamchat
```

### **3. サービスアカウントへの権限追加**

チャットアプリケーションは認証情報の操作、Firestore の読み書き権限が必要です。先程作成したサービスアカウントに権限を付与します。

```bash
gcloud projects add-iam-policy-binding $GOOGLE_CLOUD_PROJECT \
  --member serviceAccount:streamchat@$GOOGLE_CLOUD_PROJECT.iam.gserviceaccount.com \
  --role 'roles/firebase.sdkAdminServiceAgent'
gcloud projects add-iam-policy-binding $GOOGLE_CLOUD_PROJECT \
  --member serviceAccount:streamchat@$GOOGLE_CLOUD_PROJECT.iam.gserviceaccount.com \
  --role 'roles/firebaseauth.admin'
gcloud projects add-iam-policy-binding $GOOGLE_CLOUD_PROJECT \
  --member serviceAccount:streamchat@$GOOGLE_CLOUD_PROJECT.iam.gserviceaccount.com \
  --role 'roles/iam.serviceAccountTokenCreator'
```

## **アプリケーションのデプロイ、試用**

### **1. チャット アプリケーションのデプロイ**

Cloud Build でコンテナイメージを作成、作成したイメージを Cloud Run にデプロイします。

```bash
gcloud builds submit ./src/streamchat-simple \
  --tag us-central1-docker.pkg.dev/$GOOGLE_CLOUD_PROJECT/chat-repo/streamchat && \
gcloud run deploy streamchat \
  --image us-central1-docker.pkg.dev/$GOOGLE_CLOUD_PROJECT/chat-repo/streamchat \
  --service-account streamchat@$GOOGLE_CLOUD_PROJECT.iam.gserviceaccount.com \
  --allow-unauthenticated
```

**注**: デプロイ完了まで 5 分程度かかります。

### **2. アプリケーションへブラウザからアクセス**

前のコマンドで出力された `Service URL` から URL をクリックすると、ブラウザのタブが開きチャットアプリケーションが起動します。

### **3. 新規ユーザーの登録**

最下部の `アカウントを登録する` をクリックし、ユーザー情報を入力、`登録 / Register` をクリックします。

うまく登録ができると、チャット画面に遷移します。

- 最下部のウィンドウからメッセージを入力できます。
- 右上の `サインアウト` ボタンからサインアウトが可能です。

### **4. リアルタイムチャットを確認**

Chrome の通常ウィンドウ、プライベートウィンドウそれぞれで別のアカウントでログインすることで、リアルタイムにチャットができていることが確認できます。

## **チャット アプリケーションの更新**

アプリケーションにダークモードの機能をつけたいと思います。

ここでは Cloud Run の機能の１つである、タグを利用した限定リリース機能を使い、新機能を限定した URL で動作確認し、問題ないことを確認した後、本番リリースするという手順を試します。

### **1. ダークモード機能の追加**

ダークモード機能は `darkmode` という別の Git ブランチに実装済みです。そちらにブランチを切り替えます。

```bash
git switch darkmode
```

### **2. ダークモードの限定リリース**

```bash
gcloud builds submit ./src/streamchat-simple \
  --tag us-central1-docker.pkg.dev/$GOOGLE_CLOUD_PROJECT/chat-repo/streamchat && \
gcloud run deploy streamchat \
  --image us-central1-docker.pkg.dev/$GOOGLE_CLOUD_PROJECT/chat-repo/streamchat \
  --service-account streamchat@$GOOGLE_CLOUD_PROJECT.iam.gserviceaccount.com \
  --no-traffic \
  --tag darkmode \
  --allow-unauthenticated
```

### **3. 動作確認**

前の手順で出力された URL (darkmode が 含まれている URL) をクリックし、ダークモードが正しく動いているかを確認します。

また元々アクセスしていた URL には影響が無いことも合わせて確認しておきましょう。

### **4. ダークモードのリリース**

限定公開されていたダークモードを全体にリリースします。

```bash
gcloud run services update-traffic streamchat --to-latest
```

元々の URL でもダークモードが追加されたことを確認します。

## **放送禁止用語フィルタ機能の追加**

チャットが荒れないように、放送禁止用語が含まれているメッセージはフィルタする機能を追加したいと思います。

今回は、放送禁止用語かどうかを判断する機能を別の Cloud Run サービスでデプロイし、2 つのサービスを非同期で連携させるようにします。

## **Pub/Sub トピックの作成、チャットアプリケーションの権限設定**

Google Cloud ではサービス連携を非同期で行うためのサービスとして [Pub/Sub](https://cloud.google.com/pubsub?hl=ja) というサービスが用意されています。

可用性、拡張性も高く、様々なユースケースに対応しています。

### **1. Pub/Sub トピックの作成**

メッセージを送る先としてトピックを作成します。

```bash
gcloud pubsub topics create streamchat
```

### **2. チャットアプリケーションへの権限追加**

チャットアプリケーションに Pub/Sub トピックへのメッセージ送信権限を付与します。

```bash
gcloud pubsub topics add-iam-policy-binding streamchat \
  --member serviceAccount:streamchat@$GOOGLE_CLOUD_PROJECT.iam.gserviceaccount.com \
  --role 'roles/pubsub.publisher'
```

## **禁止用語判定サービスのデプロイ**

### **1. 放送禁止判定サービス用のサービスアカウントを作成**

```bash
gcloud iam service-accounts create banchecker
```

### **2. 放送禁止判定サービス用のサービスアカウントへの権限設定**

```bash
gcloud projects add-iam-policy-binding $GOOGLE_CLOUD_PROJECT \
  --member serviceAccount:banchecker@$GOOGLE_CLOUD_PROJECT.iam.gserviceaccount.com \
  --role 'roles/datastore.user'
```

### **3. 禁止用語判定サービスのデプロイ**

```bash
gcloud builds submit ./src/banchecker-simple \
  --tag us-central1-docker.pkg.dev/$GOOGLE_CLOUD_PROJECT/chat-repo/banchecker && \
gcloud run deploy banchecker \
  --image us-central1-docker.pkg.dev/$GOOGLE_CLOUD_PROJECT/chat-repo/banchecker \
  --service-account banchecker@$GOOGLE_CLOUD_PROJECT.iam.gserviceaccount.com \
  --no-allow-unauthenticated
```

## **Pub/Sub からの連携設定**

### **1. Pub/Sub 用のサービスアカウントを作成**

```bash
gcloud iam service-accounts create sub-to-banchecker
```

### **2. Pub/Sub 用のサービスアカウントへの権限設定**

```bash
gcloud run services add-iam-policy-binding banchecker \
  --member serviceAccount:sub-to-banchecker@$GOOGLE_CLOUD_PROJECT.iam.gserviceaccount.com \
  --role 'roles/run.invoker'
```

### **3. Pub/Sub から判定サービスへのトリガー設定**

```bash
CHECKER_URL=$(gcloud run services describe banchecker --format json | jq -r '.status.address.url')
gcloud pubsub subscriptions create sub-to-banchecker \
  --topic streamchat \
  --push-endpoint $CHECKER_URL \
  --push-auth-service-account sub-to-banchecker@$GOOGLE_CLOUD_PROJECT.iam.gserviceaccount.com
```

## **チャットアプリケーションの更新**

禁止用語判定をするためのサービスのデプロイ、連携設定はできましたが、まだチャットアプリケーションはそちらに対応しておらず、直接 Firestore にデータを書き込んでいます。

ここでチャットアプリケーションを更新し、Firestore に書き込むのではなく、Pub/Sub にメッセージを書き込むように修正します。

### **1. 放送禁止用語判定サービスとの連携機能追加**

```bash
git switch banchecker-integration
```

### **2. Firebase インデックス設定ファイルの上書き**

**注**: 以下のコマンドはコピー&ペーストで実行してください。

```shell
cat << EOF > firestore.indexes.json
{
  "indexes": [
    {
      "collectionGroup": "messages",
      "queryScope": "COLLECTION",
      "fields": [
        {
          "fieldPath": "banned",
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

### **3. インデックスの反映**

```bash
firebase deploy --only firestore:indexes -P $GOOGLE_CLOUD_PROJECT
```

### **4. 連携機能のデプロイ**

```bash
gcloud builds submit ./src/streamchat-simple \
  --tag us-central1-docker.pkg.dev/$GOOGLE_CLOUD_PROJECT/chat-repo/streamchat && \
gcloud run deploy streamchat \
  --image us-central1-docker.pkg.dev/$GOOGLE_CLOUD_PROJECT/chat-repo/streamchat \
  --service-account streamchat@$GOOGLE_CLOUD_PROJECT.iam.gserviceaccount.com \
  --allow-unauthenticated
```

## **放送禁止用語判定フィルタの動作確認**

チャットウィンドウの `トップチャット` をクリックすると、フィルタ済みのメッセージと、すべてのメッセージの表示を切り替えることが可能です。

放送禁止用語を含めたメッセージを送信して、フィルタがかかっているかを確かめてみましょう。

## **CI / CD パイプラインの構築**

<walkthrough-tutorial-duration duration=20></walkthrough-tutorial-duration>

ここまで、チャットアプリケーションのビルド、デプロイなどを手動で実施してきました。

Cloud Run では GitLab、GitHub などのソースコード リポジトリと Cloud Build を連携させ、ソースコードが Push されたことを検知してデプロイするというパイプラインを簡単に構築できます。

ここで構築するパイプラインのアーキテクチャは下記になります。

[アーキテクチャ参考](https://github.com/GoogleCloudPlatform/gcp-getting-started-lab-jp/blob/master/minitap/images/cicd_pipeline.png?raw=true)

## **GitLab アカウントとプロジェクトの準備**

ソースコードを GitLab に格納し、CI/CD パイプラインを構築します。

### **1. GitLab アカウントの確認**

GitLab アカウントをお持ちでない場合は、[GitLab.com](https://gitlab.com/users/sign_up) で無料アカウントを作成してください。

### **2. GitLab で新しいプロジェクトを作成**

1. GitLab にログインし、新しいプロジェクトを作成します
2. プロジェクト名を `cloudrun-chat-app` とします
3. プロジェクトの可視性は `Private` を選択します

## **Git クライアント設定**

### **1. ユーザ、メールアドレス設定**

USERNAME, USERNAME@EXAMPLE.com を自身のユーザ名、メールアドレスに置き換えて実行し、利用者を設定します。

```bash
git config --global user.name "USERNAME"
git config --global user.email "USERNAME@EXAMPLE.com"
```

### **2. GitLab リモートリポジトリの追加**

GitLab プロジェクトの URL を使用してリモートリポジトリを追加します。
`YOUR_GITLAB_USERNAME` を実際の GitLab ユーザ名に置き換えてください。

```bash
git remote add gitlab https://gitlab.com/YOUR_GITLAB_USERNAME/cloudrun-chat-app.git
```

## **GitLab への資材のプッシュ**

### **1. 現在の変更をコミット**

今まで修正していた内容をコミット、確定します。

```bash
git add . && git commit -m "Add chat application features"
```

### **2. GitLab へプッシュ**

GitLab のリポジトリに資材を転送（プッシュ）します。初回プッシュ時は GitLab の認証情報（ユーザ名とパスワード、またはアクセストークン）の入力が求められます。

```bash
# 現在のブランチを確認
CURRENT_BRANCH=$(git branch --show-current)
git push -u gitlab $CURRENT_BRANCH
```

**ヒント**: GitLab では、パスワードの代わりに Personal Access Token の使用を推奨しています。[こちら](https://gitlab.com/-/profile/personal_access_tokens) から作成できます。

<walkthrough-footnote>Cloud Shell 上にある資材を GitLab のリポジトリにプッシュしました。次にこのリポジトリを参照先として、Cloud Run の CI/CD を設定します。</walkthrough-footnote>

## **Cloud Run の CI / CD 設定**

### **1. Cloud Build API を有効化（既に有効化済みの場合はスキップ）**

```bash
gcloud services enable cloudbuild.googleapis.com
```

### **2. Cloud Build 構成ファイルの作成**

プロジェクトのルートディレクトリに `cloudbuild.yaml` を作成します：

```bash
cat > cloudbuild.yaml << 'EOF'
steps:
  # チャットアプリケーションのビルド
  - name: 'gcr.io/cloud-builders/docker'
    args: ['build', '-t', 'us-central1-docker.pkg.dev/$GOOGLE_CLOUD_PROJECT/chat-repo/streamchat', './src/streamchat-simple']

  # Docker イメージのプッシュ
  - name: 'gcr.io/cloud-builders/docker'
    args: ['push', 'us-central1-docker.pkg.dev/$GOOGLE_CLOUD_PROJECT/chat-repo/streamchat']

  # Cloud Run へのデプロイ
  - name: 'gcr.io/google.com/cloudsdktool/cloud-sdk'
    entrypoint: gcloud
    args:
      - 'run'
      - 'deploy'
      - 'streamchat'
      - '--image=us-central1-docker.pkg.dev/$GOOGLE_CLOUD_PROJECT/chat-repo/streamchat'
      - '--region=us-central1'
      - '--platform=managed'
      - '--allow-unauthenticated'
      - '--service-account=streamchat@$GOOGLE_CLOUD_PROJECT.iam.gserviceaccount.com'

  # 放送禁止用語チェッカーのビルド（必要な場合）
  - name: 'gcr.io/cloud-builders/docker'
    args: ['build', '-t', 'us-central1-docker.pkg.dev/$GOOGLE_CLOUD_PROJECT/chat-repo/banchecker', './src/banchecker-simple']

  # Docker イメージのプッシュ
  - name: 'gcr.io/cloud-builders/docker'
    args: ['push', 'us-central1-docker.pkg.dev/$GOOGLE_CLOUD_PROJECT/chat-repo/banchecker']

  # Cloud Run へのデプロイ
  - name: 'gcr.io/google.com/cloudsdktool/cloud-sdk'
    entrypoint: gcloud
    args:
      - 'run'
      - 'deploy'
      - 'banchecker'
      - '--image=us-central1-docker.pkg.dev/$GOOGLE_CLOUD_PROJECT/chat-repo/banchecker'
      - '--region=us-central1'
      - '--platform=managed'
      - '--no-allow-unauthenticated'
      - '--service-account=banchecker@$GOOGLE_CLOUD_PROJECT.iam.gserviceaccount.com'
EOF
```

### **3. Cloud Build サービスアカウントに権限を付与**

Cloud Build がCloud Run にデプロイできるよう権限を付与します：

```bash
PROJECT_NUMBER=$(gcloud projects describe $GOOGLE_CLOUD_PROJECT --format='value(projectNumber)')
gcloud projects add-iam-policy-binding $GOOGLE_CLOUD_PROJECT \
  --member="serviceAccount:${PROJECT_NUMBER}@cloudbuild.gserviceaccount.com" \
  --role="roles/run.developer"

# サービスアカウントを使用する権限も追加
gcloud iam service-accounts add-iam-policy-binding \
  streamchat@$GOOGLE_CLOUD_PROJECT.iam.gserviceaccount.com \
  --member="serviceAccount:${PROJECT_NUMBER}@cloudbuild.gserviceaccount.com" \
  --role="roles/iam.serviceAccountUser"

gcloud iam service-accounts add-iam-policy-binding \
  banchecker@$GOOGLE_CLOUD_PROJECT.iam.gserviceaccount.com \
  --member="serviceAccount:${PROJECT_NUMBER}@cloudbuild.gserviceaccount.com" \
  --role="roles/iam.serviceAccountUser"
```

### **4. アプリケーションの修正**

チャットアプリケーションのタイトルを少し変更してみます。

`minitap/cloud_run/src/streamchat-simple/app/live_chat/components/ChatHeader.tsx`

### **5. Cloud Buildのpipelineの動作確認**
以下を実行してください。

```bash
gcloud builds submit . --config=cloudbuild.yaml
```

## **Cloud BuildをSource Code Repositoryの変更によってTriggerする場合(参考）**

Cloud Run で GitLab と連携した CI/CD を設定するには、Cloud Build トリガーを作成できます。
以下はあくまでも例です。今回のハンズオンでは含めません。

### **1. Cloud Build トリガーの作成**

GUI から Cloud Build のトリガーを作成します。

<walkthrough-spotlight-pointer spotlightId="console-nav-menu">ナビゲーションメニュー</walkthrough-spotlight-pointer> -> CI/CD -> Cloud Build -> トリガー

「トリガーを作成」ボタンをクリックします。

### **2. トリガーの設定**

以下の設定を行います：

1. **名前**: `streamchat-trigger`
2. **リージョン**: `us-central1 (東京)`
3. **イベント**: `ブランチに push する`
4. **ソース**:
   - リポジトリ: `接続` をクリックし、GitLab を選択
   - GitLab との連携を設定（初回のみ）
   - リポジトリで `cloudrun-chat-app` を選択
   - ブランチ: `^main$` または現在使用しているブランチ名

### **3. ビルド設定**

1. **タイプ**: `Cloud Build 構成ファイル（yaml または json）`
2. **Cloud Build 構成ファイルの場所**: `/cloudbuild.yaml`

「作成」をクリックします。

### **4. GitLab に変更をプッシュ**

```bash
git add cloudbuild.yaml
git commit -m "Add Cloud Build configuration for chat app"
git push gitlab $CURRENT_BRANCH
```

<walkthrough-footnote>これで Cloud Run と GitLab を Cloud Build を介して連携させました。次にこのパイプラインの動作を確認します。</walkthrough-footnote>

## **Congratulations!**

<walkthrough-conclusion-trophy></walkthrough-conclusion-trophy>

これにて [Cloud Run](https://cloud.google.com/run) を使ったハンズオンが完了です。

デモで使った資材が不要な方は、次の手順でクリーンアップを行って下さい。

## **クリーンアップ（プロジェクトを削除）**

ハンズオン用に利用したプロジェクトを削除し、コストがかからないようにします。

### **1. Google Cloud のデフォルトプロジェクト設定の削除**

```bash
gcloud config unset project
```

### **2. プロジェクトの削除**

```bash
gcloud projects delete $GOOGLE_CLOUD_PROJECT
```

### **3. ハンズオン資材の削除**

```bash
cd $HOME && rm -rf gcp-getting-started-cloudrun gopath
```

<walkthrough-footnote>GitLab と Cloud Build を使った CI/CD パイプラインが正常に動作することを確認しました。これでコードの変更を GitLab にプッシュするだけで、自動的にチャットアプリケーションがデプロイされるようになりました。</walkthrough-footnote>
