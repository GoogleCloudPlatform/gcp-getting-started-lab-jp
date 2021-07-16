# Anthos clusters on Bare Metal の停止

<walkthrough-watcher-constant key="region" value="asia-northeast1"></walkthrough-watcher-constant>
<walkthrough-watcher-constant key="zone" value="asia-northeast1-c"></walkthrough-watcher-constant>
<walkthrough-watcher-constant key="sa" value="sa-anthos-ac"></walkthrough-watcher-constant>
<walkthrough-watcher-constant key="cluster" value="anthos"></walkthrough-watcher-constant>

## プロジェクトの設定

この手順の中でリソースを削除する対象のプロジェクトを選択してください。

<walkthrough-project-billing-setup permissions="compute.googleapis.com"></walkthrough-project-billing-setup>

## Anthos 管理下からの除外

gcloud のデフォルト プロジェクトを設定します。

```bash
export GOOGLE_CLOUD_PROJECT="{{project-id}}"
gcloud config set project "${GOOGLE_CLOUD_PROJECT}"
```

Google Cloud 上で Anthos clusters on Bare Metal のクラスタを統合管理するために、実はクラスタ構築時に、自動的に Hub と言われるサービスへクラスタが登録されていました。以下のコマンドで Hub からクラスタを除外できます。

```bash
gcloud container hub memberships delete "{{cluster}}-gke-${account}" --quiet
gcloud container hub memberships delete "{{cluster}}-attached-${account}" --quiet
```

Anthos に関する API を停止しましょう。

```bash
gcloud services disable anthos.googleapis.com anthosgke.googleapis.com
```

## クリーンアップ（プロジェクトを削除）

作成したリソースを個別に削除する場合は、こちらのページの手順を実施せずに次のページに進んで下さい。

### GCP のデフォルトプロジェクト設定の削除

```bash
gcloud config unset project
```

### プロジェクトの削除

```bash
gcloud projects delete {{project-id}}
```

## これで終わりです

<walkthrough-conclusion-trophy></walkthrough-conclusion-trophy>

すべて完了しました。
