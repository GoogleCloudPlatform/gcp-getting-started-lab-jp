# Anthos clusters on Bare Metal の停止

<walkthrough-watcher-constant key="region" value="asia-northeast1"></walkthrough-watcher-constant>
<walkthrough-watcher-constant key="zone" value="asia-northeast1-c"></walkthrough-watcher-constant>
<walkthrough-watcher-constant key="vpc" value="baremetal"></walkthrough-watcher-constant>
<walkthrough-watcher-constant key="subnet" value="baremetal"></walkthrough-watcher-constant>
<walkthrough-watcher-constant key="sa" value="sa-baremetal"></walkthrough-watcher-constant>
<walkthrough-watcher-constant key="cluster" value="baremetal-trial"></walkthrough-watcher-constant>
<walkthrough-watcher-constant key="vm-workst" value="workstation"></walkthrough-watcher-constant>
<walkthrough-watcher-constant key="vm-hybrid" value="hybrid-master"></walkthrough-watcher-constant>
<walkthrough-watcher-constant key="vm-worker" value="hybrid-worker"></walkthrough-watcher-constant>

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
gcloud container hub memberships delete {{cluster}} --quiet
```

Anthos に関する API を停止しましょう。

```bash
gcloud services disable anthos.googleapis.com anthosgke.googleapis.com
```

## 仮想マシン・ネットワーク資源の削除

VM を停止し、

```bash
gcloud compute instances delete {{vm-workst}} --zone {{zone}} --quiet
gcloud compute instances delete {{vm-hybrid}} --zone {{zone}} --quiet
gcloud compute instances delete {{vm-worker}} --zone {{zone}} --quiet
```

ファイアウォールと

```bash
gcloud compute firewall-rules delete allow-from-iap --quiet
gcloud compute firewall-rules delete allow-from-internal --quiet
gcloud compute firewall-rules delete allow-from-internet --quiet
```

VPC も削除しましょう。

```bash
gcloud compute networks subnets delete {{subnet}} --region={{region}} --quiet
gcloud compute networks delete {{vpc}} --quiet
```

## サービス アカウントの削除

サービス アカウントも削除しましょう。

```bash
gcloud iam service-accounts delete "{{sa}}@{{project-id}}.iam.gserviceaccount.com" --quiet
```

## プロジェクトの削除

もしこの手順のためにプロジェクトを作成していた場合は、不要な料金の発生を避けるためにプロジェクトを削除してください。

```bash
gcloud projects delete {{project-id}}
```

## これで終わりです

<walkthrough-conclusion-trophy></walkthrough-conclusion-trophy>

すべて完了しました。
