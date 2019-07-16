[![Open in Cloud Shell](https://gstatic.com/cloudssh/images/open-btn.png)](https://console.cloud.google.com/cloudshell/open?git_repo=https://github.com/Youki/gcp-getting-started-lab-jp&tutorial=machine_learning/cloud_ai_building_blocks/cloud_automl_tutorial.md)


# Cloud AutoML: 画像データとラベルデータをコピーする

画像データとラベルデータをコピーする手順を解説します。なお、この手順では、事前に
AutoML Vision が利用するバケット (gs://${PROJECT_ID}-vcm) が作成されていること、
またそのバケットに対して適切なアクセス設定が行われていることを前提としています。
この前提は[こちら](https://cloud.google.com/vision/automl/docs/quickstart) をご
確認下さい。

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

## サンプル画像とラベルデータをコピーする

画像データをコピーします。このコマンドが完了するまでに 20 分程度かかります。

```bash
gsutil -m cp -R gs://cloud-ml-data/img/flower_photos/ gs://${BUCKET}/img/
```

ラベルデータを置換した結果をアップロードします。

```bash
gsutil cat gs://${BUCKET}/img/flower_photos/all_data.csv | sed "s:cloud-ml-data:${BUCKET}:" > all_data.csv
gsutil -m cp -R gs://cloud-ml-data/img/flower_photos/ gs://${BUCKET}/img/
```
