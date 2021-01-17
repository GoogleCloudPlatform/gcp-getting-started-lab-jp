# G.I.G ハンズオン #3

## Google Cloud Platform（GCP）プロジェクトの選択

ハンズオンを行う GCP プロジェクトを作成し、 GCP プロジェクトを選択して **Start/開始** をクリックしてください。

**今回のハンズオンは Firebase, Firestore を使って行うため、既存のプロジェクト (特にすでに使っているなど) だと不都合が生じる恐れがありますので新しいプロジェクトを作成してください。**

<walkthrough-project-setup>
</walkthrough-project-setup>

## ハンズオンの内容

### 目的

Firestore と Firebase を使って実装が複雑になりがちな認証、クライアントとのリアルタイム同期がスムーズに行えることを体験します。

### シナリオ

1. Firebase Hosting を使って静的ファイルをホスティング
2. Firestore のデータを更新してリアルタイムにデータが更新されることを確認
3. Firebase Authentication にて認証
4. Firestore Security Rules を用いてログイン済みユーザのみが閲覧可能なデータを作成

### 対象プロダクト

以下が今回学ぶ対象のプロタクトの一覧です。

- Firebase Hosting
- Firebase Authentication
- Firestore
- Firestore Security Rules

### 下記の内容をハンズオン形式で学習します。

- 環境準備: 10 分
  - GCPプロジェクト作成
  - gcloud コマンドラインツール設定
  - Firebase CLI のインストール
  - Firestore API 有効化
  - Firebase プロジェクト作成
  - Firebase で使用するリージョンの設定

- Firebase を用いた Web アプリケーション作成: 25 分
  - Firebase CLI の初期化
  - Firebase プロジェクトの初期化
  - Firebase Web アプリの追加
  - はじめてのデプロイ
  - Firestore のデータをリアルタイムに同期
  - Firebase Authentication の有効化
  - ログイン済みユーザのみ閲覧可能なデータの追加
  - Firebase Authentication の有効化
  - Firebase Authentication による認証

- クリーンアップ: 5 分
  - GCP プロジェクトごと削除
  - (オプション) Firebase プロジェクトの削除

## 環境準備

<walkthrough-tutorial-duration duration=10></walkthrough-tutorial-duration>

最初に、ハンズオンを進めるための環境準備を行います。

下記の設定を進めていきます。

- gcloud コマンドラインツール設定
- Firebase CLI のインストール
- Firestore API 有効化
  - Firestore 初期設定
- Firebase プロジェクト作成

## gcloud コマンドラインツール設定

前回と同様の内容なので、設定完了の方はスキップしてください。

### GCP プロジェクト ID を環境変数に設定

`GOOGLE_CLOUD_PROJECT` に GCP プロジェクト ID を設定します。

```bash
export GOOGLE_CLOUD_PROJECT="{{project-id}}"
```

### gcloud コマンドラインツールから利用するデフォルトプロジェクトを設定

プロジェクトを設定します。

```bash
gcloud config set project ${GOOGLE_CLOUD_PROJECT}
```

以下のコマンドで、現在の設定を確認できます。

```bash
gcloud config list
```

## Firebase CLI のインストール

```bash
npm install -g firebase-tools
```

## Firestore API 有効化

今回のハンズオンでは Firestore ネイティブモードを使用します。

1. [Datastore](https://console.cloud.google.com/datastore/entities/query/kind?project={{project-id}})に移動します
2. ![switch to native mode](https://storage.googleapis.com/gig-03/static/screenshot/firestore-select-mode.png) の画面よりネイティブモードを選択します
3. ![select to nam5](https://storage.googleapis.com/gig-03/static/screenshot/firestore-select-region.png) の画面より nam5 リージョンを選択します
4. リージョンを選択後、 *データベースを作成* ボタンをクリックします
5. `データベースを作成しています。` というメッセージが表示され、Firestore のデータベースを表示するページにリダイレクトされます

## Firebase プロジェクト作成

1. [Firebase Console](https://console.firebase.google.com/)に移動します
2. ![create a new firebase project](https://storage.googleapis.com/gig-03/static/screenshot/firebase-create-project.png) *プロジェクトを追加* をクリックします
3. ![name firebase project id](https://storage.googleapis.com/gig-03/static/screenshot/firebase-name-project-id.png) プロジェクト名にGCP プロジェクト ID ({{project-id}}) を入力して *続行* をクリックします
4. ![firebase billing plan](https://storage.googleapis.com/gig-03/static/screenshot/firebase-billing-plan.png)Blaze プラン (従量課金制) になっていることを確認し、 *プランを確認* をクリックします
5. **続行** をクリックします
6. ![firebase disalbe ga](https://storage.googleapis.com/gig-03/static/screenshot/firebase-disable-ga.png)今回はGoogle Analyticsを使用しないので、こちらは一旦 *有効にする* のボタンをOFFにして *Firebaseを追加* をクリックします
7. **新しいプロジェクトの準備ができました** と表示されたらプロジェクトの作成は完了です

## Firebase で使用するリージョンの設定

1. [Firebase Console 内の Setting ページ](https://console.firebase.google.com/project/{{project-id}}/settings/general) に移動します
2. ![Firebase default location](https://storage.googleapis.com/gig-03/static/screenshot/firebase-default-location.png) *デフォルトの GCP リソースロケーション* を `nam5` に設定します

これにて環境準備は完了です。

## Firebase を用いた Web アプリケーション作成

<walkthrough-tutorial-duration duration=25></walkthrough-tutorial-duration>

Firebase プロジェクト上に Web アプリケーションを作成し、

- Firebase Hosting
- Firebase Authentication
- Firestore Security Rules

を連携していきます。

## Firebase CLI の初期化

Firebase CLI が使用できるように初期化を行います。

```bash
firebase login --no-localhost
```

1. 上記コマンドの結果、表示されたURLをブラウザにて開きます
2. アカウントの選択画面が表示されるので Google Account を指定します
3. ![allow Firebase CLI](https://storage.googleapis.com/gig-03/static/screenshot/allow-firebase-cli.png) *許可* をクリックします
4. ![firebase authorization code](https://storage.googleapis.com/gig-03/static/screenshot/firebase-authorization-code.png) 認可コードが表示されるので、コピーし、CLIの `Paste authorization code here:` の項目にペーストします
5. `Success! Logged in as 選択した Google Account` が表示されれば完了です

```bash
firebase projects:list
```

こちらのコマンドで権限のある Firebase Project の一覧を確認できます。

## Firebase プロジェクトの初期化

```bash
firebase init
```

対話式のコマンドが立ち上がります。

### 1. 使用する Firebase CLI の選択

```
? Which Firebase CLI features do you want to set up for this folder? Press Space to select features, then Enter to confirm your choices.
 ◯ Database: Configure Firebase Realtime Database and deploy rules
 ◉ Firestore: Deploy rules and create indexes for Firestore
 ◯ Functions: Configure and deploy Cloud Functions
❯◉ Hosting: Configure and deploy Firebase Hosting sites
 ◯ Storage: Deploy Cloud Storage security rules
 ◯ Emulators: Set up local emulators for Firebase features
 ◯ Remote Config: Get, deploy, and rollback configurations for Remote Config
```

矢印キーまたは j k で上下に移動し、 `Firestore` , `Hosting` を space キーで選択肢、 Enter キーで決定します。

### 2. Firebase プロジェクト名の入力

```
? Please select an option: (Use arrow keys)
❯ Use an existing project
  Create a new project
  Add Firebase to an existing Google Cloud Platform project
  Don't set up a default project
```

`Use an existing project` を選択肢、決定します。

```
? Please input the project ID you would like to use:
```

先程作成した Firebase プロジェクト名 ({{project-id}}) を入力し決定します。

### 3. Firestore Security Rules の設定ファイルの名前の設定

```
? What file should be used for Firestore Rules? (firestore.rules)
```

デフォルトのまま変更せずに決定します。

### 4. Firestore Indexes の設定ファイルの名前の設定

```
? What file should be used for Firestore indexes? (firestore.indexes.json)
```

デフォルトのまま変更せずに決定します。

### 5. デプロイの際の公開用ディレクトリの名前の設定

```
? What do you want to use as your public directory? (public)
```

デフォルトのまま変更せずに決定します。

### 6. single-page app の設定

```
? Configure as a single-page app (rewrite all urls to /index.html)? (y/N)
```

N (No) を入力して決定します。

### 7. Github 連携の設定

```
? Set up automatic builds and deploys with GitHub? (y/N)
```

N (No) を入力して決定します。

### 8. 404.html の上書き設定

```
? File public/404.html already exists. Overwrite? (y/N)
```

今回は 404.html を別途用意してあるので N (No) を入力して決定します。

### 9. index.html の上書き設定

```
? File public/index.html already exists. Overwrite? (y/N)
```

今回は index.html を別途用意してあるので N (No) を入力して決定します。

```
i  Writing configuration info to firebase.json...
i  Writing project information to .firebaserc...
i  Writing gitignore file to .gitignore...

✔  Firebase initialization complete!
```

が表示されれば完了です。

## Firebase Web アプリの追加

Firebase でアプリケーションを開始するためには(言い換えるとブラウザ、または Android , iOS 上で Firebase の機能を使ったアプリケーションを開発するためには)、はじめに Firebase プロジェクト上にアプリケーションを作成する必要があります。

```bash
firebase apps:create WEB gig-03
```

*App Information* として `App ID` が出力されます。この `App ID` を使って

```bash
firebase apps:sdkconfig WEB APP_ID_PLACEHOLDER
```

`APP_ID_PLACEHOLDER` の部分を差し替えて Firebase SDK で使用する設定を取得できるか確認しておきましょう。(今回は `<script src="/__/firebase/init.js"></script>` を使用しているのでこの設定を個別に設定する箇所はありません。)

## はじめてのデプロイ

Firebase Hosting の channel 機能を使ってはじめてのデプロイをやってみましょう。

```bash
firebase hosting:channel:deploy {{project-id}}-first-deploy --expires 30m
```

- `hosting:channel:deploy` コマンド: 本番デプロイのような形ではなく、一時的に有効なURLを作成して、動作確認を行うためのコマンドです
- `{{project-id}}-first-deploy` 引数 : git で言うところの branch のような概念で、 Firebase プロジェクトに対して任意の Hosting 用 Channel を作成することが可能です
- `--expires 30m` : 30分後に消失する設定です

コマンドの出力に URL が出力されるので、ブラウザでアクセスしてみてください。

<walkthrough-footnote>こちらのコマンドに関しては [Advent Calender の Gossy-san の記事](https://gossy-86158.medium.com/firebase-update-summary-2020-98fd5e8f10e5)でも取り上げられているので詳細は是非こちらを御覧ください</walkthrough-footnote>

## Firestore のデータをリアルタイムに同期

はじめてのデプロイではデータを何も登録していないので、画面上には何も表示されていませんでしたが、 Firebase にデータを登録して、リアルタイムに同期されることを確認しましょう。

### Firestore にデータを登録

1. [Firestore の UI](https://console.cloud.google.com/firestore/data/?project={{project-id}})に移動します
2. ![firestore initial public data](https://storage.googleapis.com/gig-03/static/screenshot/firestore-first-public-data.png) 図のように公開するデータを入力します
3. *保存* をクリックします

### Firestore Security Rules に `public` Collection の公開を設定する

Cloud Editor にて Firestore Security Rules の設定ファイル <walkthrough-editor-open-file filePath="cloudshell_open/gcp-getting-started-lab-jp/gig/gig01-03/firestore.rules">"firestore.rules"</walkthrough-editor-open-file> を開きます。 (fileへのリンクが開かない場合は、エディタのファイルペインより、直接選択してください。)

```
service cloud.firestore {
  match /databases/{database}/documents {
    match /public/{document=**} {
      allow read: if true;
    }
  }
}
```

上記の内容でファイルの中身を入れ替えます。

- `match /public/{document=**}` : `public` Collection 配下のすべてのドキュメントを示します
- `allow read: if true;` : すべてのユーザが read 可能です

変更した内容を以下のコマンドを使ってデプロイしておきましょう。

```bash
firebase deploy --only firestore:rules
```

### Firestore のデータがブラウザに反映されているか確認

ブラウザに戻って一度リロードすれば Firestore のデータが同期されています。

### Firestore のデータをUIから変更してリアルタイム同期させる

1. [Firestore の UI](https://console.cloud.google.com/firestore/data/?project={{project-id}})に移動します
2. 先程作成したデータの `title` の値(`gig-03`)を適当に変更してみてください
3. ブラウザに戻るとリアルタイムに値が変更されているのが確認できます

#### Tips: ローカルマシンで変更を確認する

```
firebase serve
```

コマンドを叩くと [localhost:5000](http://localhost:5000) にサーバが立ち上がり、UI (index.html) のローカル上で確認することも可能です。

## ログイン済みユーザのみ閲覧可能なデータの追加

### Firestore へデータを追加

1. [Firestore の UI](https://console.cloud.google.com/firestore/data/?project={{project-id}})に移動します
2. ![Insert Data Authenticated Only into Firestore](https://storage.googleapis.com/gig-03/static/screenshot/firestore-private-data.png) `private` Collection を新たに作成し、新規にデータを追加します

### ログイン済みユーザ用の Firestore Security Rules

Cloud Editor にて Firestore Security Rules の設定ファイル <walkthrough-editor-open-file filePath="cloudshell_open/gcp-getting-started-lab-jp/gig/gig01-03/firestore.rules">"firestore.rules"</walkthrough-editor-open-file> を開きます。 (fileへのリンクが開かない場合は、エディタのファイルペインより、直接選択してください。)

```
service cloud.firestore {
  match /databases/{database}/documents {
    match /public/{document=**} {
      allow read: if true;
    }
    match /private/{document=**} {
      allow read: if request.auth.uid != null;
    }
  }
}
```

上記の内容でファイルの中身をお入れ替えます。

- `allow read: if request.auth.uid != null;` : ユーザIDが存在していれば read 可能です

## Firebase Authentication の有効化

1. [Firebase Authentication の設定ページ](https://console.firebase.google.com/project/{{project-id}}/authentication/providers) に移動します
2. ![Firebase All Authentication Providers](https://storage.googleapis.com/gig-03/static/screenshot/firebase-authentication-providers.png) から `メール / パスワード` の右側の鉛筆アイコンをクリックします
3. ![Firebase Mail and Password Authentication Provider Configuration](https://storage.googleapis.com/gig-03/static/screenshot/firebase-authentication-email-provider.jpg) *有効にする* をONにして *保存* をクリックします

## Firebase Authentication による認証

### ブラウザからサインアップ

1. ブラウザ上の*サインアップ / サインイン*をクリックします
2. メールアドレス, あなたの名前, パスワード を入力します
3. *保存* をクリックしてサインアップを完了させます
4. トップページにリダイレクトされると、ログイン済みユーザのみが閲覧できるように設定した `private` Collection の内容が表示されています

### 認証済みユーザの一覧を取得

認証済みユーザの一覧を取得して、正しくログインできているか確認します。

```bash
firebase auth:export users.json
```

`users.json` ファイルにユーザの一覧(ここでは今サインアップしたユーザ)が表示されます。

### ログアウト

ブラウザから Firebase Authentication でサインアップしたユーザをログアウトします。

1. *ログアウト* をクリックします
2. ログイン済みユーザのみが閲覧可能が非表示になっていることを確認します

## クリーンアップ

### GCP プロジェクトの削除

GCP プロジェクトをまるごと削除できる方は

```
gcloud projects delete {{project-id}}
```

にて削除を行います。

### Firebase プロジェクトの削除

1. [Firebase Console 一般設定](https://console.firebase.google.com/project/korekai-da/settings/general)に移動します
2. 画面最下部までスクロールして、 *プロジェクトを削除* をクリックします
