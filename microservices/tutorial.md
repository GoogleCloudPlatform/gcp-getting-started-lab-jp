# ハンズオン：Microservices development on GCP

## 事前準備

### GCP プロジェクトの作成

GCP プロジェクトを新規作成します。このハンズオンは、プロジェクトオーナーの権限で作業を進める前提ですので、自分専用のプロジェクトを用意するようにしてください。


### Cloud Datastore の有効化

Cloud Console から「[データストア](https://console.cloud.google.com/datastore)」メニューを
開いて、「DATASTORE モードを選択」をクリックします。
  
「ロケーションを選択」には「us-east1 (South Carolina)」を選択して、「データベースを作成」をクリックします。

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

### API の有効化

次のコマンドを実行します。ここでは、Cloud Build, Cloud Run, Cloud Scheduler, Workflows, の API を有効化しています。

```
gcloud services enable \
  cloudbuild.googleapis.com \
  run.googleapis.com \
  cloudscheduler.googleapis.com \
  workflows.googleapis.com
```

*コマンドの出力例*
```
Operation "operations/acf.411c0bde-0c11-47af-979a-2cc1680b5650" finished successfully.
```

### ソースコードのダウンロード

次のコマンドを実行します。ここでは、Cloud Shell 端末のホームディレクトリーにこの GitHub リポジトリの内容をクローンしています。

```
cd $HOME
git clone https://github.com/enakai00/gcp-getting-started-lab-jp
```

*コマンドの出力例*
```
Cloning into 'gcp-getting-started-lab-jp'...
remote: Enumerating objects: 161, done.
remote: Counting objects: 100% (161/161), done.
remote: Compressing objects: 100% (109/109), done.
remote: Total 1355 (delta 73), reused 89 (delta 35), pack-reused 1194
Receiving objects: 100% (1355/1355), 8.93 MiB | 4.78 MiB/s, done.
Resolving deltas: 100% (657/657), done.
```

## Cloud Run を用いた REST API サービスの構築

このセクションで実施する内容

- ローカル環境でのアプリの動作確認
- Cloud Build によるコンテナイメージのビルド
- Cloud Run にイメージをデプロイ
- デプロイしたサービスの動作確認

### ローカル環境でのアプリの動作確認

## Cloud Datastore によるデータの永続化

## Cloud PubSub によるイベントメッセージの交換

## Cloud Scheduler による定期的な処理の実行
