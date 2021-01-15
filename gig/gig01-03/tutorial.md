# G.I.G ハンズオン #3

## Google Cloud Platform（GCP）プロジェクトの選択

ハンズオンを行う GCP プロジェクトを作成し、 GCP プロジェクトを選択して **Start/開始** をクリックしてください。

**今回のハンズオンは Firebase, Firestore を使って行うため、既存のプロジェクト (特にすでに使っているなど) だと不都合が生じる恐れがありますので新しいプロジェクトを作成してください。**

<walkthrough-project-setup>
</walkthrough-project-setup>


## ハンズオンの内容

### 対象プロダクト

以下が今回学ぶ対象のプロタクトの一覧です。

- Firebase Hosting
- Firebase Authentication
- Firestore
- Firestore Security Rules

### 下記の内容をハンズオン形式で学習します。

- 環境準備: 10 分
  - プロジェクト作成
  - gcloud コマンドラインツール設定
  - Firebase 有効化設定
  - GCP 機能 (API) 有効化設定

- []

- [App Engine (GAE)](https://cloud.google.com/appengine) を用いたアプリケーション開発：60 分
  - アプリケーションの作成
  - Firestore を使う
  - サーバーレス VPC アクセスの設定
  - Memorystore for Redis を使う
  - チャレンジ問題

- クリーンアップ：10 分
  - プロジェクトごと削除
  - （オプション）個別リソースの削除
    - Firestore の削除
    - Memorystore の削除

## 環境準備

<walkthrough-tutorial-duration duration=10></walkthrough-tutorial-duration>

最初に、ハンズオンを進めるための環境準備を行います。

下記の設定を進めていきます。

- gcloud コマンドラインツール設定
- GAE 有効化設定
- GCP 機能（API）有効化設定

## gcloud コマンドラインツール

GCP は、CLI、GUI、Rest API から操作が可能です。ハンズオンでは主に CLI を使い作業を行いますが、GUI で確認する URL も合わせて掲載します。

### gcloud コマンドラインツールとは?

gcloud コマンドライン インターフェースは、GCP でメインとなる CLI ツールです。このツールを使用すると、コマンドラインから、またはスクリプトや他の自動化により、多くの一般的なプラットフォーム タスクを実行できます。

たとえば、gcloud CLI を使用して、以下のようなものを作成、管理できます。

- Google App Engine アプリケーション
- Google Compute Engine 仮想マシン
- Google Kubernetes Engine クラスタ

**ヒント**: gcloud コマンドラインツールについての詳細は[こちら](https://cloud.google.com/sdk/gcloud?hl=ja)をご参照ください。

<walkthrough-footnote>次に gcloud CLI をハンズオンで利用するための設定を行います。</walkthrough-footnote>


## TBD

- firebase hostingを使ってHTMLをpublishしてUIを作成する
- 未ログイン状態でUIに何も表示させてないことを確認
  - ここ、reactにするか何にするか決める
- publicなデータをfirestoreに突っ込む
  1. firestoreのテーブル作成
  2. firestoreに/publicにデータを入れる
  3. firestoreに/privateにデータを入れる
- publicなデータに対して、security ruleでpublic属性をつける
- privateなデータに対して、security ruleでprivate属性をつける
  - ログイン済みユーザのみが見れる状態にする
- UIに戻ってpublicなデータが見れるか確認する
- ログインの画面を出す
- ログインする
- ユーザが登録されているかをconsole上もしくはCLIで確認する
  - ここ、何で確認できるか確認する
- UIに戻ってprivateなデータが見れるか確認する

## TO-DO

- projectの準備
