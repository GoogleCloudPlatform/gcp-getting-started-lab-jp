# Slurm による HPC 環境の構築

<walkthrough-watcher-constant key="region" value="asia-northeast1"></walkthrough-watcher-constant>
<walkthrough-watcher-constant key="zone" value="asia-northeast1-c"></walkthrough-watcher-constant>
<walkthrough-watcher-constant key="vpc" value="hpc"></walkthrough-watcher-constant>
<walkthrough-watcher-constant key="subnet" value="hpc"></walkthrough-watcher-constant>
<walkthrough-watcher-constant key="subnet-range" value="10.128.0.0/16"></walkthrough-watcher-constant>
<walkthrough-watcher-constant key="slurm" value="slurm-01"></walkthrough-watcher-constant>
<walkthrough-watcher-constant key="slurm-image" value="projects/schedmd-slurm-public/global/images/family/schedmd-slurm-20-11-4-hpc-centos-7"></walkthrough-watcher-constant>
<walkthrough-watcher-constant key="slurm-image-hyperthreads" value="False"></walkthrough-watcher-constant>

## 始めましょう

[Slurm](https://slurm.schedmd.com/documentation.html) ベースの計算クラスタを構築するための手順です。

**所要時間**: 約 15 分

**前提条件**:

- 計算クラスタのためのプロジェクトが作成してある
- プロジェクトのオーナー権限をもつアカウントでログインしている

**[開始]** ボタンをクリックして次のステップに進みます。

## プロジェクトの設定

この手順の中で実際にリソースを構築する対象のプロジェクトを選択してください。

<walkthrough-project-billing-setup permissions="compute.googleapis.com"></walkthrough-project-billing-setup>

## VPC の作成

CLI の初期値を設定します。

```bash
gcloud config set project "{{project-id}}"
gcloud config set compute/region {{region}}
gcloud config set compute/zone {{zone}}
```

[Private Google Access](https://cloud.google.com/vpc/docs/private-access-options?hl=ja#pga) を有効にした ** VPC** を作成します。

```bash
gcloud compute networks create {{vpc}} --subnet-mode=custom
```

```bash
gcloud compute networks subnets create {{subnet}} \
    --range={{subnet-range}} --network={{vpc}} \
    --enable-private-ip-google-access
```

## ファイアウォールの設定

[Identity-Aware Proxy](https://cloud.google.com/iap?hl=ja)、内部ネットワークからの接続を許可します。

```bash
gcloud compute firewall-rules create allow-from-iap \
    --network={{vpc}} --direction=INGRESS --priority=1000 \
    --action=ALLOW --rules=tcp:22,icmp \
    --source-ranges=35.235.240.0/20
```

```bash
gcloud compute firewall-rules create allow-from-internal \
    --network={{vpc}} --direction=INGRESS --priority=1000 \
    --action=ALLOW --rules=tcp:0-65535,udp:0-65535,icmp \
    --source-ranges=10.0.0.0/8
```

## 計算クラスタの構築の準備 (1)

作業ディレクトリのルートにもどりスクリプトをダウンロードし、作業ディレクトリを移動します。

```bash
git clone https://github.com/SchedMD/slurm-gcp.git ~/slurm-gcp && cd ~/slurm-gcp/dm
```

クラスタを柔軟に設定できるよう、一部制約を変更します。

```bash
sed -ie "s|minimum     : 300|minimum     : 60|g" slurm-cluster.jinja.schema
```

## 計算クラスタの構築の準備 (2)

slurm-cluster.yaml を編集しましょう。

```text
cat << EOF >slurm-cluster.yaml
imports:
- path: slurm-cluster.jinja

resources:
- name: {{slurm}}-resources
  type: slurm-cluster.jinja
  properties:
    cluster_name            : {{slurm}}
    vpc_net                 : {{vpc}}
    vpc_subnet              : {{subnet}}
    zone                    : {{zone}}

    # ヘッドノード
    controller_image        : {{slurm-image}}
    controller_machine_type : n1-standard-2
    controller_disk_size_gb : 30
    external_controller_ip  : False

    # ログインノード
    login_image             : {{slurm-image}}
    login_machine_type      : n1-standard-2
    external_login_ips      : False
    login_node_count        : 0

    # 計算クラスタ
    external_compute_ips : False
    suspend_time         : 120

    partitions:
      - name              : partition1
        image             : {{slurm-image}}
        image_hyperthreads: {{slurm-image-hyperthreads}}
        machine_type      : c2-standard-4
        max_node_count    : 10
        zone              : {{zone}}
        vpc_subnet        : {{subnet}}
        enable_placement  : True
EOF
```

## 計算クラスタの構築

### 計算クラスタの VM 作成

以下コマンドで、計算クラスタを構築しましょう。

```bash
gcloud services enable deploymentmanager.googleapis.com
gcloud deployment-manager deployments create {{slurm}} \
    --config slurm-cluster.yaml
```

### エラーが起こったら

`Quota 'SSD_TOTAL_GB' exceeded.` など、クラスタ構築時にエラーが起こってしまったら、[内容を確認しデプロイメントをいったん削除](https://console.cloud.google.com/dm/deployments) します。問題が解決したら改めてクラスタ構築をお試しください。

### 計算クラスタの初期化

クラスタの構成が完了するまで進行状況をトラッキングします。‘Started Google Compute Engine Startup Scripts.’ と出力されていることを確認します。出力されていない場合 2、3 分お待ち下さい。

```bash
gcloud compute ssh {{slurm}}-controller --zone {{zone}} \
    --command "sudo journalctl -fu google-startup-scripts.service"
```

## 挙動の確認

管理ノードに入り、クラスタの状況を確認、そして試しにジョブを投入してみます。

```bash
gcloud compute ssh {{slurm}}-controller --zone {{zone}}
```

Slurm クラスタの状況を確認してみます。

```bash
sinfo
```

ジョブを定義し

```text
cat << EOF >hostname_sleep.sh
#!/bin/bash
#SBATCH --job-name=hostname_sleep
#SBATCH --output=out_%j.txt
#SBATCH --nodes=2

srun hostname
srun lscpu | grep -e Socket -e Core -e Thread
sleep 5
EOF
```

ジョブを投入し、状況を確認してみます。ジョブの投入をトリガーにクラスタがスケールするため、 [squeue](https://slurm.schedmd.com/squeue.html#SECTION_JOB-STATE-CODES) の応答 ST（ステータス）が CD（COMPLETED: 完了）になるのを待ちます。

```bash
sbatch hostname_sleep.sh
watch -n 3 squeue
```

処理が完了したら出力されたファイルやジョブ情報を確認してみます。

```bash
ls
sacct
```

確認ができたらサーバーからログアウトしましょう。

## 環境の削除

計算クラスタの削除

```bash
gcloud deployment-manager deployments delete {{slurm}}
```

Firewall, VPC の削除

```bash
gcloud compute firewall-rules delete allow-from-iap --quiet
gcloud compute firewall-rules delete allow-from-internal --quiet
gcloud compute networks subnets delete {{subnet}} --quiet
gcloud compute networks delete {{vpc}} --quiet
```

## これで終わりです

<walkthrough-conclusion-trophy></walkthrough-conclusion-trophy>

すべて完了しました。

**作業後は忘れずにクリーンアップする**: もしこの手順のためにプロジェクトを作成していた場合は、不要な料金の発生を避けるためにプロジェクトを削除してください。

```bash
gcloud projects delete {{project-id}}
```
