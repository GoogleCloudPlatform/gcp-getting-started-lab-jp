# ハンズオン：Transactional workflows in microservices architecture

## 1. 事前準備

### 前提ハンズオンの完了

このハンズオンは、(tutorial-1.md)[tutorial-1.md]の内容を完了した後に、続けて実施する前提になります。

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

### ソースコードのダウンロード

次のコマンドを実行します。ここでは、Cloud Shell 端末のホームディレクトリーにこの GitHub リポジトリの内容をクローンしています。

```
cd $HOME
git clone https://github.com/GoogleCloudPlatform/transactional-microservice-examples
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

## 2. Choreography-saga パターン

## 3. Synchronous orchestration パターン
