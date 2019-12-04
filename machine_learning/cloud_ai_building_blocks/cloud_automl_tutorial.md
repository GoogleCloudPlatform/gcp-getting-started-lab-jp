[![Open in Cloud Shell](https://gstatic.com/cloudssh/images/open-btn.png)](https://console.cloud.google.com/cloudshell/open?git_repo=https://github.com/Youki/gcp-getting-started-lab-jp&tutorial=machine_learning/cloud_ai_building_blocks/cloud_automl_tutorial.md)

# Cloud AutoML Vision: データの準備

Cloud AutoML のハンズオンで利用するデータを準備する手順を解説します。この手順では Cloud AutoML Vision 用のバケット "gs://${PROJECT_ID}-vcm" が作成されていること、 Cloud AutoML Vision 用のバケットに対する適切なアクセス権限設定が完了していることを前提にしています。この前提条件に関する詳細は[こちら](https://cloud.google.com/vision/automl/docs/quickstart) のドキュメントをご確認下さい。

## 画像データとラベルデータの保存先バケット名を設定する

GCP プロジェクトの ID を確認します。

```bash
gcloud projects list
```

Cloud AutoML を利用するプロジェクトの ID を環境変数に設定します。


```bash
export PROJECT_ID=your-project-id
```

データのコピー先となるバケットの名前を設定します。

```bash
export BUCKET="${PROJECT_ID}-vcm"
```

バケットを作成します。

```bash
gsutil mb -p ${PROJECT_ID} -c regional -l us-central1 gs://${BUCKET}
```

## サンプル画像とラベルデータをコピーする

画像データをコピーします。このコマンドが完了するまでに 20 分程度かかります。

```bash
gsutil -m cp -R gs://cloud-ml-data/img/flower_photos/ gs://${BUCKET}/img/
```

ラベルデータを置換した結果をローカルファイルに保存します。

```bash
gsutil cat gs://${BUCKET}/img/flower_photos/all_data.csv | sed "s:cloud-ml-data:${BUCKET}:" > all_data.csv
```

前の手順で保存したファイルを Cloud AutoML Vision 用のバケットにアップロードします。

```bash
gsutil cp all_data.csv gs://${BUCKET}/csv/
```
