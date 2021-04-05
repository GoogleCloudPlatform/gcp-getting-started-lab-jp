# Slurm & Lustre クラスタの運用

<walkthrough-watcher-constant key="region" value="asia-northeast1"></walkthrough-watcher-constant>
<walkthrough-watcher-constant key="zone" value="asia-northeast1-c"></walkthrough-watcher-constant>
<walkthrough-watcher-constant key="lustre" value="lustre"></walkthrough-watcher-constant>
<walkthrough-watcher-constant key="slurm" value="slurm-01"></walkthrough-watcher-constant>

## 始めましょう

[Lustre](https://www.lustre.org/) による分散ストレージと [Slurm](https://slurm.schedmd.com/documentation.html) ベースの計算クラスタを運用するための手順です。

**所要時間**: 約 30 分

**前提条件**:

- "Slurm と Lustre による HPC 環境の構築" によりクラスタが構築されていること

**[開始]** ボタンをクリックして次のステップに進みます。

## プロジェクトの設定

この手順の中で実際にリソースを構築する対象のプロジェクトを選択してください。

<walkthrough-project-billing-setup permissions="compute.googleapis.com"></walkthrough-project-billing-setup>

## CLI の初期値

CLI の初期値を設定します。

```bash
gcloud config set project "{{project-id}}"
gcloud config set compute/region {{region}}
gcloud config set compute/zone {{zone}}
```

## システムの停止

システム全体を停止する場合、以下の手順で行います。

1. Slurm クラスタ（計算ノード）の[一時停止](https://cloud.google.com/compute/docs/instances/suspend-resume-instance?hl=ja)
2. Lustre クラスタ（オブジェクトストレージ）の停止
3. Lustre クラスタ（メタデータ）の停止

## Slurm クラスタの停止

管理ノード群を一時停止します。

```text
mgmt=$( gcloud deployment-manager deployments describe {{slurm}} --format json \
    | jq -r '.resources[]|select(.type=="compute.v1.instance")|.name' \
    | grep -v image)
for id in ${mgmt}; do
    gcloud beta compute instances suspend "${id}" --zone={{zone}}
done
```

## Lustre クラスタの停止

サーバーの一覧を取得し、オブジェクト ストレージ サーバ（OSS）を停止します。

```text
oss=$( gcloud deployment-manager deployments describe {{lustre}} --format json \
    | jq -r '.resources[]|select(.type=="compute.v1.instance")|.name' \
    | grep oss)
for id in ${oss}; do
    gcloud compute instances stop "${id}" --zone={{zone}}
done
```

メタデータ サーバ（MDS）を停止します。

```text
mds=$( gcloud deployment-manager deployments describe {{lustre}} --format json \
    | jq -r '.resources[]|select(.type=="compute.v1.instance")|.name' \
    | grep mds)
for id in ${mds}; do
    gcloud compute instances stop "${id}" --zone={{zone}}
done
```

## システムの再開

システムを再開する場合、以下の手順で行います。

1. Lustre クラスタ（メタデータ）の開始
2. Lustre クラスタ（オブジェクトストレージ）の開始

## Lustre クラスタの開始

サーバーの一覧を取得し、MDS を起動します。

```text
for id in ${mds}; do
    gcloud compute instances start "${id}" --zone={{zone}}
done
```

初期化が完了するのをまちます。MDS で ‘Started Google Compute Engine Startup Scripts.’ と出力されるまでお待ち下さい。

```bash
gcloud compute ssh {{lustre}}-mds1 --zone {{zone}} \
    --command "sudo journalctl -fu google-startup-scripts.service"
```

OSS を起動します。

```text
for id in ${oss}; do
    gcloud compute instances start "${id}" --zone={{zone}}
done
```

初期化が完了するのをまちます。‘Started Google Compute Engine Startup Scripts.’ と出力されるまでお待ち下さい。

```bash
gcloud compute ssh {{lustre}}-oss1 --zone {{zone}} \
    --command "sudo journalctl -fu google-startup-scripts.service"
```

## Slurm クラスタの再開

管理ノード群を再開します。

```text
for id in ${mgmt}; do
    gcloud beta compute instances resume "${id}" --zone={{zone}}
done
```

## これで終わりです

<walkthrough-conclusion-trophy></walkthrough-conclusion-trophy>

以上ですべて完了です。
