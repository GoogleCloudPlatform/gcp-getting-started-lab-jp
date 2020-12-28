# ハンズオン：Transactional workflows in microservices architecture (Frontend application)

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

### Web アプリケーションのビルドとデプロイ

### Web アプリケーションの動作確認

