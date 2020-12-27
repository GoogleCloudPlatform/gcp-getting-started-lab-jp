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

次のコマンドを実行します。ここでは、簡単な REST API を提供するサンプルアプリ [main.py](https://github.com/enakai00/gcp-getting-started-lab-jp/blob/master/microservices/helloworld/main.py) をローカル環境で実行しています。

```
cd $HOME/gcp-getting-started-lab-jp/microservices/helloworld
python3 main.py
```

*コマンドの出力例*
```
 * Serving Flask app "main" (lazy loading)
 * Environment: production
   WARNING: This is a development server. Do not use it in a production deployment.
   Use a production WSGI server instead.
 * Debug mode: on
 * Running on http://0.0.0.0:8080/ (Press CTRL+C to quit)
 * Restarting with stat
 * Debugger is active!
 * Debugger PIN: 185-356-817
``` 

アプリケーションはフォアグラウンドで実行を続けているので、新しい Cloud Shell 端末を開いて、そちらからアプリケーションにリクエストを送信します。

次のコマンドを実行します。

```
curl http://localhost:8080
```

*コマンドの出力例*
```
Hello world service.
```

次は、POST メソッドでデータを送信します。次のコマンドを実行します。

```
curl -X POST \
  -H "Content-Type: application/json" \
  -d '{"name":"Google Cloud Platform"}' \
  -s http://localhost:8080/api/v1/hello
```

*コマンドの出力例*
```
{
  "message": "Hello, Google Cloud Platform!"
}
```

動作確認ができたら、Ctrl+C でアンプルアプリを停止します。

### Cloud Build によるコンテナイメージのビルド

次のコマンドを実行します。ここでは、[Dockerfile](https://github.com/enakai00/gcp-getting-started-lab-jp/blob/master/microservices/helloworld/Dockerfile)に
従って、コンテナイメージをビルドしています。

```
cd $HOME/gcp-getting-started-lab-jp/microservices/helloworld
gcloud builds submit --tag gcr.io/$PROJECT_ID/helloworld-service
```

*コマンドの出力例*
```
Creating temporary tarball archive of 4 file(s) totalling 1.8 KiB before compression.
Uploading tarball of [.] to [gs://microservices-hands-on_cloudbuild/source/1609051197.03811-c0082d92ec804586ae303353057a9dc0.tgz]

...中略...

DONE
-----------------------------------------------------------------------------------------------------------------------------------------------
ID                                    CREATE_TIME                DURATION  SOURCE                                                              
                                 IMAGES                                                      STATUS
40cf97df-aeb7-44a9-b007-d906a56319c3  2020-12-27T06:39:59+00:00  22S       gs://microservices-hands-on_cloudbuild/source/1609051197.03811-c0082
d92ec804586ae303353057a9dc0.tgz  gcr.io/microservices-hands-on/helloworld-service (+1 more)  SUCCESS
```

ビルドの履歴とログは、Cloud Console から「[Cloud Build](https://console.cloud.google.com/cloud-build/)」メニューを
開いて確認することができます。

ビルド済のイメージは、Cloud Container Registry に保存されています。Cloud Console から「[Container Regstry](https://console.cloud.google.com/gcr/)」メニューを
開いて、保存されたイメージを確認することができます。次のコマンドで確認することもできます。

イメージの一覧を表示します。
```
gcloud container images list
```
*コマンドの出力例*
```
NAME
gcr.io/microservices-hands-on/helloworld-service
```

特定のイメージのタグを表示します。
```
gcloud container images list-tags gcr.io/microservices-hands-on/helloworld-service
```
*コマンドの出力例*
```
DIGEST        TAGS    TIMESTAMP
894a35cdfc88  latest  2020-12-27T06:40:16
```



### Cloud Run にイメージをデプロイ


## Cloud Datastore によるデータの永続化

## Cloud PubSub によるイベントメッセージの交換

## Cloud Scheduler による定期的な処理の実行
