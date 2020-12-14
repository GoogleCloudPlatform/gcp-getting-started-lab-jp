# GIG ハンズオン #2

## Google Cloud Platform（GCP）プロジェクトの選択

ハンズオンを行う GCP プロジェクトを作成し、 GCP プロジェクトを選択して **Start/開始** をクリックしてください。

**なるべく新しいプロジェクトを作成してください。**

<walkthrough-project-setup>
</walkthrough-project-setup>

## ハンズオンの内容

今回のハンズオンは、[ETL Processing on GCP Using Dataflow and BigQuery Toggle Lab Panel favorite_border Add to favorites](https://www.qwiklabs.com/focuses/3459?parent=catalog)がベースになっています。
  

#### シナリオ
本日ハンズオンでは、以下のようなシナリオを想定しています。

1. Cloud Storage に毎日同じファイル名で、ファイルが格納される
2. Cloud Storage に格納されたデータに対して、Dataflow によってバッチ処理を行う
3. 処理されたデータは BigQuery に格納される
3. BigQuery のテーブルは毎回 Truncate する
4. バッチ処理は1日1回、朝9時に開始される。
  

#### 対象プロダクト

以下が今回のハンズオンで利用するプロダクトの一覧です。

- Google Cloud Storage
- Cloud Dataflow
- Cloud Scheduler
- BigQuery
- IAM

#### 下記の内容をハンズオン形式で学習します。

- 環境準備：10 分
  - プロジェクト作成
  - gcloud コマンドラインツール設定
  - GCP 機能（API）有効化設定

- [Cloud Dataflow](https://cloud.google.com/dataflow/docs)  を用いた ETL 処理：45 分
  - GCS のバケット作成
  - BigQuery データセットの作成
  - データの取り込み
  - データの加工
  - テンプレートの作成
  - Cloud Scheduler によるスケジューリング

- クリーンアップ：5 分
  - プロジェクトごと削除
  - 個別のリソース削除


# 環境準備

<walkthrough-tutorial-duration duration=10></walkthrough-tutorial-duration>

最初に、ハンズオンを進めるための環境準備を行います。
前回と同じ内容ですので、わかる方はスキップしてください。（API の有効化は忘れずに）

下記の設定を進めていきます。

- gcloud コマンドラインツール設定
- GCP 機能（API）有効化設定

## gcloud コマンドラインツール設定
#### GCP のプロジェクト ID を環境変数に設定

環境変数 `GOOGLE_CLOUD_PROJECT` に GCP プロジェクト ID を設定します。

```bash
export GOOGLE_CLOUD_PROJECT="{{project-id}}"
```

#### CLI（gcloud コマンド）から利用する GCP のデフォルトプロジェクトを設定

操作対象のプロジェクトを設定します。

```bash
gcloud config set project $GOOGLE_CLOUD_PROJECT
```

デフォルトのリージョンを設定します。

```bash
gcloud config set compute/region us-central1
```

以下のコマンドで、現在の設定を確認できます。
```bash
gcloud config list
```

### Tips
ちなみに gcloud コマンドには、config 設定をまとめて切り替える方法があります。
アカウントやプロジェクト、デフォルトのリージョン、ゾーンの切り替えがまとめて切り替えられるので、おすすめの機能です。
```bash
gcloud config configurations list
```


## GCP 機能（API）有効化設定

GCP では利用したい機能ごとに、有効化を行う必要があります。
以下の機能を有効にします。

<walkthrough-enable-apis></walkthrough-enable-apis>
- Cloud Scheduler
- Cloud Dataflow
- BigQuery API

```bash
gcloud services enable dataflow.googleapis.com \
                       cloudscheduler.googleapis.com \
                       bigquery.googleapis.com 
```

## パイプラインの構築

<walkthrough-tutorial-duration duration=45></walkthrough-tutorial-duration>

以下のステップで、構築していきます。

1. GCSのバケット作成
2. BigQuery データセットの作成
4. データの取り込み
5. データの加工
6. テンプレートの作成
7. Cloud Scheduler によるスケジューリング

今実行する Python プログラムは、以下のような処理を行うものです。

1. GCS からファイルを取り込む
2. 加工処理を行う 
3. BigQuery に出力

## Google Cloud Storage(GCS) 

### バケットの作成

データが最初に格納されるGCSを設定していきましょう。
まずは、make bucket コマンドを実行して、GCS のバケットを作成します。

```bash
gsutil mb -c regional -l us-central1 gs://{{project-id}}-gig2
```

### データのインポート

Dataflow のサンプルデータを、バケットへコピーします。

```bash
gsutil cp gs://spls/gsp290/data_files/head_usa_names.csv gs://{{project-id}}-gig2/data_files/
```

このようなデータが入っています。
```csv
state,gender,year,name,number,created_date
AK,F,1910,Dorothy,5,11/28/2016
AK,F,1910,Lucy,6,11/28/2016
AK,M,1910,George,5,11/28/2016
AK,M,1910,Paul,6,11/28/2016
AK,M,1910,William,5,11/28/2016
AK,F,1910,Anna,10,11/28/2016
AK,F,1910,Mary,14,11/28/2016
AK,F,1910,Helen,7,11/28/2016
AK,M,1910,James,7,11/28/2016
```

上記のファイルの全量が `gs://spls/gsp290/data_files/usa_names.csv` にありますが、処理に時間がかかるので今回のハンズオンでは利用しません。
ぜひ復習のときには、こちらのデータセットでも試してください。

## BigQuery

### データセットの作成
次に、処理されたデータが格納される先である、BigQueryのデータセットを作成します。

```bash
bq mk lake_gig2
```

## Dataflow

### Python 環境のセットアップ

#### path 移動
```bash
cd dataflow
```

#### venv をインストール
```bash
sudo apt-get install -y python3-venv
```

#### venv 作成 & アクティベート 
```bash
python3 -m venv venv
```

```bash
source venv/bin/activate
```

#### setuptools をアップグレード
```bash
pip install --upgrade pip setuptools
```

#### apache-beam をインストール
```bash
pip install apache-beam[gcp]
```

#### Cloud Shell Editor のフォルダ
左のフォルダペインで以下のフォルダを展開しておきましょう。
`cloudshell_open > gcp-getting-started-lab-jp > gig > gig01-02`


## データの取り込み

早速、Dataflow のプログラムを実行してみましょう。
今実行する Python パイプラインは、以下のようなステップで処理を行うものです。

1. GCS からファイルを取り込む
2. ファイルのヘッダー行を除外
3. BigQuery に出力

Dataflow では、１つのプログラムの実行単位を Job と呼びます。
以下のコマンドは、`data_ingestion.py` を実行しています。

```bash
python data_ingestion.py --project={{project-id}} --runner=DataflowRunner --staging_location=gs://{{project-id}}-gig2/test --temp_location gs://{{project-id}}-gig2/test --input gs://{{project-id}}-gig2/data_files/head_usa_names.csv --save_main_session
```

#### 実行の確認（Dataflow）
コンソール[Dataflow](https://console.cloud.google.com/dataflow?project={{project-id}})で、Job が実行されていることを確認してみます。

Status が Succeeded となっていることを確認してください。
また Job をクリックすると、詳細を見ることができます。

Dataflow の Job は、以下のコマンドでも確認できます。
```bash
gcloud dataflow jobs list
```

#### 実行の確認（BigQuery）
Dataflow のフローチャートを見ると BigQuery への書き込みも成功しているかと思います。
実際にコンソールから[BigQuery](https://console.cloud.google.com/bigquery?project={{project-id}}&p={{project-id}}&d=lake_gig2&page=dataset)から確認してみましょう。

`スキーマ`からテーブルのスキーマが確認できます。すべて行がカンマでパースされ、STRING型でBigQueryにロードされています。
`プレビュー`をクリックすると、実際のデータが確認できます。

## データの加工

次に、データを加工して、BigQuery に格納してみましょう。
今実行する Python パイプラインは、以下のようなステップで処理を行うものです。

1. GCS からファイルを取り込む
2. ファイルのヘッダー行を除外
3. 読み取った行をオブジェクトに変換
4. BigQuery に出力

ここでは、STRING だった `created_date` を DATE に、`number` を INTEGER に加工しています。

```bash
python data_transformation.py --project={{project-id}} --runner=DataflowRunner --staging_location=gs://{{project-id}}-gig2/test --temp_location gs://{{project-id}}-gig2/test --input gs://{{project-id}}-gig2/data_files/head_usa_names.csv --save_main_session
```

#### 実行の確認
[Dataflow](https://console.cloud.google.com/dataflow?project={{project-id}})
[BigQuery](https://console.cloud.google.com/bigquery?project={{project-id}}&p={{project-id}}&d=lake_gig2&page=dataset)


## テンプレートの作成
Dataflow の Job をスケジューリングするために、
このコードをテンプレートとして利用できるようにする必要があります。
テンプレート化するにあたって、引数は若干の修正が必要になります。

以下のコマンドでテンプレートが作成できます。
```bash
python data_transformation_for_template.py --project={{project-id}} --runner=DataflowRunner --staging_location=gs://{{project-id}}-gig2/test --temp_location gs://{{project-id}}-gig2/test --template_location gs://{{project-id}}-gig2/templates/DataTransformationTemplate --experiment=use_beam_bq_sink
```

コンソールで、[GCS のバケット](https://console.cloud.google.com/storage/browser/{{project-id}}?forceOnBucketsSortingFiltering=false&cloudshell=false&project={{project-id}})を確認してみましょう。

以下のコマンドでも確認できます。
```bash
gsutil ls gs://{{project-id}}-gig2/templates/DataTransformationTemplate
```

## Dataflow Job をテンプレートから実行する

以下のコマンドで、Dataflow の Job を実行します。
テンプレート化しているため、`Python` を実行するのではなく、
`gcloud` コマンドからの実行になります。

```bash
gcloud dataflow jobs run transform_from_template \
    --gcs-location gs://{{project-id}}-gig2/templates/DataTransformationTemplate \
    --parameters input=gs://{{project-id}}-gig2/data_files/head_usa_names.csv \
    --parameters output=lake_gig2.usa_names_transformed_from_template
``` 

コンソールで確認してみましょう
[Dataflow](https://console.cloud.google.com/dataflow?project={{project-id}})
  
[BigQuery](https://console.cloud.google.com/bigquery?project={{project-id}}&p={{project-id}}&d=lake_gig2&t=usa_names&page=dataset)

これで、Dataflow 側は自動化の準備ができたので、スケジューリングの設定を進めていきます。

## Scheduler から Dataflow の Job を実行する

Cloud Scheduler は HTTP、Pub/Sub、GAE HTTP をターゲットとすることが可能です。
今回は、Dataflow の API に対して HTTP リクエストで Job をキックします。

Dataflow の Job を Template から実行するエンドポイントは以下になります。
```
https://dataflow.googleapis.com/v1b3/projects/{{project-id}}/templates:launch?gcsPath=gs://{{project-id}}-gig2/templates/DataTransformationTemplate
```

また、先程付与していたパラメータは `request body` として付与します。


## サービスアカウントの作成

Scheduler が Dataflow の API を呼ぶためのサービスアカウントを作成します。

```bash
gcloud iam service-accounts create dev-gig-scheduler
```

作成したサービスアカウントに権限を付与します。  
**今回のハンズオンはオーナー権限を付与していますが、実際の開発の現場では適切な権限を付与しましょう！**

```bash
gcloud projects add-iam-policy-binding {{project-id}} \
--member "serviceAccount:dev-gig-scheduler@{{project-id}}.iam.gserviceaccount.com" \
--role "roles/owner"
```

## Scheduler Job の作成

まずターミナルで、Path を移動します。
```bash
cd ../scheduler
```

`dataflow_message_body.json` というファイルを開き、以下をコピペしてください。
```json
{
  "jobName": "run_template_from_scheduler",
  "parameters": {
    "input": "gs://{{project-id}}-gig2/data_files/head_usa_names.csv",
    "output": "lake_gig2.usa_names_transformed_scheduler"
  }
}
```

以下のコマンドで Scheduler Job を作成します。
環境によっては、App Engine app がないというメッセージが出る可能性があります。
作成する必要がありますので、適宜リージョンを選択してください。

```bash
gcloud scheduler jobs create http schedule_for_dataflow \
--schedule="every day 09:00" \
--uri="https://dataflow.googleapis.com/v1b3/projects/{{project-id}}/templates:launch?gcsPath=gs://{{project-id}}-gig2/templates/DataTransformationTemplate" \
--message-body-from-file="dataflow_message_body.json" \
--oauth-service-account-email="dev-gig-scheduler@{{project-id}}.iam.gserviceaccount.com"
```

[コンソール](https://console.cloud.google.com/cloudscheduler?project={{project-id}})で確認してみましょう。
コンソールに、Job が表示されていると思います。
`RUN NOW` をクリックすると、作成した Job が即時実行されます。クリックし、
[Dataflow](https://console.cloud.google.com/dataflow?project={{project-id}})、[BigQuery](https://console.cloud.google.com/bigquery?project={{project-id}}&p={{project-id}}&d=lake_gig2&t=usa_names&page=dataset)をそれぞれ確認してください。


## クリーンアップ

<walkthrough-tutorial-duration duration=5></walkthrough-tutorial-duration>

#### プロジェクトを削除出来る方
プロジェクトを削除出来る方は、削除してしまってください。


#### プロジェクトを削除出来ない方

Cloud Scheduler Job の削除
```bash
gcloud scheduler jobs delete schedule_for_dataflow
```

BigQuery のデータセット削除
```bash
bq rm lake_gig2
```

GCS のバケット削除
```bash
gsutil rm -r gs://{{project-id}}-gig2/
```
