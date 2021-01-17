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

- Firebase を用いた Web アプリケーション作成: 25分
  - Firebase CLI の初期化
  - Firebase プロジェクト作成
  - Firestore Database 初期設定
  - アプリケーションのデプロイ(Firebase Hosting)
  - Firestore をクライアント側と同期
  - アプリケーションの認証
  - Firestore Security Rules を用いたセキュアなデータ管理

- クリーンアップ: 10 分
  - プロジェクトごと削除
  - (オプション) 個別リソースの削除
    - Firebase プロジェクトの削除
      - 可能なのか
        - yes => まるごと削除
        - no => Firestore の削除, Firebase のアプリケーションの登録解除, Firestore Security Rulesの削除

## 環境準備

<walkthrough-tutorial-duration duration=10></walkthrough-tutorial-duration>

最初に、ハンズオンを進めるための環境準備を行います。
前回と同様の内容なので、設定完了の方はスキップしてください。

下記の設定を進めていきます。

- gcloud コマンドラインツール設定
- Firebase CLI のインストール
- Firebase プロジェクト作成
- Firestore API 有効化
  - Firestore 初期設定

## gcloud コマンドラインツール設定

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
2. ![switch to native mode](gig/gig01-03/static/screenshot/firestore-select-mode.png) の画面よりネイティブモードを選択します
3. ![select to nam5](gig/gig01-03/static/screenshot/firestore-select-region.png) の画面より nam5 リージョンを選択します


## Firebase プロジェクト作成



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
