# ハンズオン：マイクロサービスによるトランザクションの実装（２）

## 1. 事前準備

### 前提ハンズオンの完了

このハンズオンは、[tutorial-2.md](tutorial-2.md) の内容を完了した後に、続けて実施する前提になります。
[tutorial-2.md](tutorial-2.md) を完了したプロジェクト環境を利用して、このハンズオンを続けてください。

### Cloud Shell の起動

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

>GitHub リポジトリの内容は、Cloud Shell のディレクトリー `$HOME/transactional-microservice-examples` に
クローンしてあるものとします。

## 2. Firebase hosting による Web アプリケーションのデプロイ

このセクションで実施する内容

- OAuth 2.0 クライアントの作成
- Web アプリケーションのビルドとデプロイ
- Web アプリケーションの動作確認

### OAuth 2.0 クライアントの作成

Cloud Console の[「APIとサービス」](https://console.cloud.google.com/apis)メニューから
[「OAuth同意画面」](https://console.developers.google.com/apis/credentials/consent)
を開きます。

「User Type」に「外部」選択して、「作成」をクリックすると、「アプリ登録の編集」のウィザード画面が表示されます。
次の手順で設定を完了します。

1. 「OAuth 同意画面」では、次の情報を入力した後に、「保存して次へ」をクリックします。

 - アプリ名：任意の名称（例えば、`transaction demo`）を入力します。
 - ユーザーサポートメール：プロジェクトオーナーの Google アカウントのメールアドレスを選択します。
 - デベロッパーの連絡先情報：任意のメールアドレスを入力します。

2. 「スコープ」では、そのまま「保存して次へ」をクリックします。

3. 「テストユーザー」では、そのまま「保存して次へ」をクリックします。

4. 「概要」では、「ダッシュボードに戻る」をクリックして設定を完了します。


Cloud Console の[「APIとサービス」](https://console.cloud.google.com/apis)メニューから
[「認証情報」](https://console.developers.google.com/apis/credentials)を開きます。

「認証情報を作成」をクリックして、プルダウンメニューの「OAuthクライアントID」を選択すると、
「OAuthクライアントIDの作成」の設定画面が表示されます。次の手順で設定を完了します。

1. 「アプリケーションの種類」に「ウェブアプリケーション」を選択します。

2. 「認証済のJavaScript生成元」の下にある「URIを追加」をクリックして、URI に `https://[PROJECT ID].web.app` を入力します。（`[PROJECT ID]` の部分は、実際のプロジェクト ID に置き換えてください。）

3. 「作成」をクリックします。

4. 「OAuthクライアントを作成しました」というポップアップが表示されるので、「クライアント ID」に表示された文字列をコピーした後に、「OK」をクリックして設定を完了します。

次のコマンドを実行して、先ほどコピーしたクライアント ID を環境変数に保存しておきます。

```
CLIENT_ID=[Client ID]
```

次のコマンドを実行して、Web アプリケーションからアクセスする Cloud Run のサービスを再デプロイします。

```
gcloud run deploy order-service-async \
  --image gcr.io/$PROJECT_ID/order-service-async \
  --platform=managed --region=us-central1 \
  --no-allow-unauthenticated

gcloud run deploy customer-service-async \
  --image gcr.io/$PROJECT_ID/customer-service-async \
  --platform=managed --region=us-central1 \
  --no-allow-unauthenticated

gcloud run deploy order-service-sync \
  --image gcr.io/$PROJECT_ID/order-service-sync \
  --platform=managed --region=us-central1 \
  --no-allow-unauthenticated

gcloud run deploy customer-service-sync \
  --image gcr.io/$PROJECT_ID/customer-service-sync \
  --platform=managed --region=us-central1 \
  --no-allow-unauthenticated

gcloud run deploy order-processor-service \
  --image gcr.io/$PROJECT_ID/order-processor-service \
  --platform=managed --region=us-central1 \
  --no-allow-unauthenticated \
  --set-env-vars "PROJECT_ID=$PROJECT_ID"
```

> この作業は、先ほど作成したクライアント ID を Cloud Run のサービスから認識させるために必要になります。

### Web アプリケーションのビルドとデプロイ

次のコマンドを実行して、Web アプリケーションをビルドします。

```
cd $HOME/transactional-microservice-examples/frontend
gcloud builds submit . --config=cloudbuild.yaml
```

ビルドされたバイナリーは、Cloud Storage に保存されています。
次のコマンドを実行して、Cloud Shell のローカルディレクトリーにコピーします。

```
gsutil -m cp -r gs://${PROJECT_ID}-web-frontend-example-assets/build ./web_frontend_example/
```

Firebase hosting の管理操作を行うため、次のコマンドを実行して、Google アカウントの認証を行います。

```
firebase login --reauth --no-localhost
```

認証用のリンクが表示されるので、ブラウザーでリンクを開き、プロジェクトオーナーの Google アカウントで認証してください。
表示された認証コードをコピペして、Cloud Shell に入力すると認証が完了します。

> 認証用のリンクを開いた際に「認証エラー（エラー 400: invalid_request / Required parameter is missing: response_type）」
と表示された場合は、リンクのURLが正しく入力されていない可能性があります。テキストエディタなどにリンクをペーストして、正しくリンクが
コピーできているか確認してください。

次のコマンドを実行して、Firebase hosting の環境を初期化します。

```
cd $HOME/transactional-microservice-examples/frontend
mkdir firebase_hosting
cd firebase_hosting
firebase init hosting
```

最後のコマンドを実行すると、セットアップメニューが表示されるので、次の手順に従って、設定を完了してください。

1. 「Add Firebase to an existing Google Cloud Platform project」を選択します。

2. 「Please input the ID of the Google Cloud Project you would like to add Firebase:」に対して、
このハンズオンで使用しているプロジェクト ID を入力します。

3. 「What do you want to use as your public directory?」は、[Enter] で次に進みます。

4. 「Configure as a single-page app (rewrite all urls to /index.html)?」は、[Enter] で次に進みます。

5. 「Set up automatic builds and deploys with GitHub?」は、[Enter] で次に進みます。

6. 「Firebase initialization complete!」と表示されれば、セットアップは完了です。

次のコマンドを実行して、ビルドした Web アプリケーションを Firebase hosting にデプロイします。
ここでは、先ほど環境変数 `CLIENT_ID` に設定したクライアント ID を HTML ファイルに書き込んだ上でデプロイしています。

```
cp -r ../web_frontend_example/build/web/* public/
sed -i "s/__CLIENT_ID__/$CLIENT_ID/" public/index.html
cp ../firebase/firebase.json ./
firebase deploy
```

`Hosting URL` に表示された URL（`https://[Project ID].web.app`）をブラウザで開くと、
デプロイした Web アプリケーションが利用できます。


### Web アプリケーションの動作確認

はじめに、Web アプリケーションの画面右上にある「Sing in with Google」をクリックして、プロジェクトオーナーの Google アカウントでログインします。

### カスタマー情報の作成

画面左のメニュー「Customer」をクリックして、プルダウンメニューから「limit」を選びます。

「customer_id」と「limit」を下記のスクリーンショットと同様に入力して、「Send!」をクリックします。

<img src="https://raw.githubusercontent.com/GoogleCloudPlatform/transactional-microservice-examples/main/frontend/docs/img/screenshot01.png" width="720px">

「Response」の部分に、サービスからの応答メッセージが表示されます。画面上のスライドスイッチで「Sync（同期サービス）」「Async（非同期サービス）」を選択することができますが、この処理については、どちらでも同じ結果が得られます。

### 非同期サービスを用いてトランザクションを実行

画面左のメニュー「Order」をクリックして、スライドスイッチの「Async（非同期サービス）」を選択します。また、プルダウンメニューから「create」を選びます。

「customer_id」と「number」を下記のスクリーンショットと同様に入力して、「Send!」をクリックします。

<img src="https://raw.githubusercontent.com/GoogleCloudPlatform/transactional-microservice-examples/main/frontend/docs/img/screenshot02.png" width="720px">

「Response」の部分を見ると、オーダーの状態は「pending」になっていることがわかります。ここに表示された「order_id」をメモしておきます。

### オーダーの状態を確認

プルダウンメニューから「get」を選びます。

「customer_id」と「order_id」を下記のスクリーンショットと同様に入力して、「Send!」をクリックします。（「order_id」には、先ほどメモしたオーダー ID を入力してください。）

<img src="https://raw.githubusercontent.com/GoogleCloudPlatform/transactional-microservice-examples/main/frontend/docs/img/screenshot03.png" width="720px">

トランザクションが完了するまで、オーダーの状態は「pending」になります。1〜2分待ってから実行すると、オーダーの状態は「accepted」に変わります。

### 同期サービスを用いてトランザクションを実行

画面左のメニュー「Order」をクリックして、スライドスイッチの「Sync（同期サービス）」を選択します。また、プルダウンメニューから「process」を選びます。（「create」ではなく、「process」を選ぶ点に注意してください。）

「customer_id」と「number」を下記のスクリーンショットと同様に入力して、「Send!」をクリックします。

<img src="https://raw.githubusercontent.com/GoogleCloudPlatform/transactional-microservice-examples/main/frontend/docs/img/screenshot04.png" width="720px">

「Response」の部分を見ると、オーダーの状態は「accepted」になっていることがわかります。
