# Anthos clusters on Bare Metal の起動

<walkthrough-watcher-constant key="region" value="asia-northeast1"></walkthrough-watcher-constant>
<walkthrough-watcher-constant key="zone" value="asia-northeast1-c"></walkthrough-watcher-constant>
<walkthrough-watcher-constant key="vpc" value="baremetal"></walkthrough-watcher-constant>
<walkthrough-watcher-constant key="subnet" value="baremetal"></walkthrough-watcher-constant>
<walkthrough-watcher-constant key="subnet-range" value="10.128.0.0/16"></walkthrough-watcher-constant>
<walkthrough-watcher-constant key="sa" value="sa-baremetal"></walkthrough-watcher-constant>
<walkthrough-watcher-constant key="cluster" value="baremetal-trial"></walkthrough-watcher-constant>
<walkthrough-watcher-constant key="vm-workst" value="workstation"></walkthrough-watcher-constant>
<walkthrough-watcher-constant key="vm-hybrid" value="hybrid-master"></walkthrough-watcher-constant>
<walkthrough-watcher-constant key="vm-worker" value="hybrid-worker"></walkthrough-watcher-constant>

## 始めましょう

[Anthos clusters on Bare Metal](https://cloud.google.com/anthos/clusters/docs/bare-metal?hl=ja) を Google Compute Engine 上に構築する手順です。

本手順では以下の図のようにマルチクラスタ、つまり Admin Cluster が複数の User Cluster を管理できる構成をとります。

![マルチクラスタ](https://raw.github.com/wiki/pottava/google-cloud-tutorials/anthos-baremetal/multi-cluster.png)

実際には [ハイブリッド クラスタ](https://cloud.google.com/anthos/clusters/docs/bare-metal/1.6/installing/install-prep#hybrid_cluster_deployment) 1 つの構成です。

![完成図](https://raw.github.com/wiki/pottava/google-cloud-tutorials/anthos-baremetal/1-5.png)

**所要時間**: 約 45 分

**前提条件**:

- Google Cloud 上にプロジェクトが作成してある
- プロジェクトのオーナー権限をもつアカウントで Cloud Shell にログインしている

**[開始]** ボタンをクリックして次のステップに進みます。

## プロジェクトの設定

この手順の中で実際にリソースを構築する対象のプロジェクトを選択してください。

<walkthrough-project-billing-setup permissions="compute.googleapis.com"></walkthrough-project-billing-setup>

## 環境準備

最初に、ハンズオンを進めるための環境準備を行います。

下記の設定を進めていきます。

- gcloud コマンドライン ツール設定
- 機能（API）有効化
- サービス アカウント設定

## gcloud コマンドラインツール

Google Cloud は、CLI、GUI から操作が可能です。ハンズオンでは主に CLI を使い作業を行います。

### **gcloud コマンドラインツールとは？**

gcloud コマンドライン インターフェースは、Google Cloud でメインとなる CLI ツールです。このツールを使用すると、コマンドラインから、またはスクリプトや他の自動化手法により、多くの一般的なプラットフォーム タスクを実行できます。

たとえば、gcloud CLI を使用して、以下のようなものを作成、管理できます。

- Google Compute Engine 仮想マシン
- Google Kubernetes Engine クラスタ

**ヒント**: gcloud コマンドライン ツールについての詳細は [こちら](https://cloud.google.com/sdk/gcloud?hl=ja) をご参照ください。

## gcloud コマンドラインツール設定 - プロジェクト

gcloud コマンドでは操作の対象とするプロジェクトの設定が必要です。

### **Google Cloud のプロジェクト ID を環境変数に設定**

環境変数 `GOOGLE_CLOUD_PROJECT` に Google Cloud プロジェクト ID を設定します。

```bash
export GOOGLE_CLOUD_PROJECT="{{project-id}}"
```

### **CLI（gcloud コマンド） のデフォルト プロジェクトを設定**

操作対象のプロジェクトを設定します。

```bash
gcloud config set project "${GOOGLE_CLOUD_PROJECT}"
```

## API の有効化

Google Cloud では利用したい機能ごとに、有効化を行う必要があります。
ここでは、以降のハンズオンで利用する機能を事前に有効化しておきます。

```bash
gcloud services enable anthos.googleapis.com anthosgke.googleapis.com cloudresourcemanager.googleapis.com container.googleapis.com gkeconnect.googleapis.com gkehub.googleapis.com serviceusage.googleapis.com stackdriver.googleapis.com monitoring.googleapis.com logging.googleapis.com
```

`Operation 〜 finished successfully.` と表示が出ることを確認します。

## gcloud コマンドラインツール設定 - [リージョン、ゾーン](https://cloud.google.com/compute/docs/regions-zones?hl=ja)

### **デフォルト リージョンの設定**

リソースを操作するデフォルトのリージョンとして、{{region}} を指定します。

```bash
gcloud config set compute/region {{region}}
```

### **デフォルト ゾーンの設定**

リソースを操作するデフォルトのゾーンとして、{{zone}} を指定します。

```bash
gcloud config set compute/zone {{zone}}
```

<walkthrough-footnote>必要な機能が使えるようになりました。次にワークショップ環境を確認します</walkthrough-footnote>

## サービス アカウントの作成

オンプレミス（想定の）環境へ Anthos をインストールしたり、Google Cloud と通信したりするための [サービス アカウント](https://cloud.google.com/iam/docs/service-accounts?hl=ja) を用意します。今回はハンズオンなのでひとつのサービス アカウントで進めますが、実際には役割ごとに用意し、[IAM の安全な使用](https://cloud.google.com/iam/docs/using-iam-securely?hl=ja) に従った運用が可能です。

```bash
gcloud iam service-accounts create {{sa}}
```

### **権限の付与**

サービス アカウントを利用し、オンプレミス（想定の）環境から Google Cloud へ接続したりメトリクスを送信したりするための権限を付与します。

```bash
gcloud projects add-iam-policy-binding ${GOOGLE_CLOUD_PROJECT} --member="serviceAccount:{{sa}}@${GOOGLE_CLOUD_PROJECT}.iam.gserviceaccount.com" --role="roles/gkehub.connect"
gcloud projects add-iam-policy-binding ${GOOGLE_CLOUD_PROJECT} --member="serviceAccount:{{sa}}@${GOOGLE_CLOUD_PROJECT}.iam.gserviceaccount.com" --role="roles/gkehub.admin"
gcloud projects add-iam-policy-binding ${GOOGLE_CLOUD_PROJECT} --member="serviceAccount:{{sa}}@${GOOGLE_CLOUD_PROJECT}.iam.gserviceaccount.com" --role="roles/logging.logWriter"
gcloud projects add-iam-policy-binding ${GOOGLE_CLOUD_PROJECT} --member="serviceAccount:{{sa}}@${GOOGLE_CLOUD_PROJECT}.iam.gserviceaccount.com" --role="roles/monitoring.metricWriter"
gcloud projects add-iam-policy-binding ${GOOGLE_CLOUD_PROJECT} --member="serviceAccount:{{sa}}@${GOOGLE_CLOUD_PROJECT}.iam.gserviceaccount.com" --role="roles/monitoring.dashboardEditor"
gcloud projects add-iam-policy-binding ${GOOGLE_CLOUD_PROJECT} --member="serviceAccount:{{sa}}@${GOOGLE_CLOUD_PROJECT}.iam.gserviceaccount.com" --role="roles/stackdriver.resourceMetadata.writer"
```

## モニタリング ダッシュボードの有効化

Anthos clusters on Bare Metal はクラスタ作成時、自動的に [Cloud Operations ダッシュボード](https://cloud.google.com/monitoring/charts/dashboards?hl=ja) を作成し、クラスタの状況を概観できるようセットアップします。事前に [ワークスペース](https://cloud.google.com/monitoring/workspaces/create?hl=ja) を作っておくために、一度以下コンソールにアクセスしましょう。

画面の左上にある <walkthrough-spotlight-pointer spotlightId="console-nav-menu">ナビゲーション メニュー</walkthrough-spotlight-pointer> を開きます。

**Monitoring** セクションを開きましょう。

<walkthrough-menu-navigation sectionId="MONITORING_SECTION"></walkthrough-menu-navigation>

## VPC の作成

### **VPC とサブネットの作成**

```bash
gcloud compute networks create {{vpc}} --subnet-mode=custom
gcloud compute networks subnets create {{subnet}} --region={{region}} --range={{subnet-range}} --network={{vpc}}
```

### **ファイアウォールの設定**

[Identity-Aware Proxy](https://cloud.google.com/iap?hl=ja) からの SSH、内部ネットワークから全通信を許可します。

```bash
gcloud compute firewall-rules create allow-from-iap --network={{vpc}} --direction=INGRESS --priority=1000 --action=ALLOW --rules=tcp:22,icmp --source-ranges=35.235.240.0/20
```

```bash
gcloud compute firewall-rules create allow-from-internal --network={{vpc}} --direction=INGRESS --priority=1000 --action=ALLOW --rules=tcp:0-65535,udp:0-65535,icmp --source-ranges=10.0.0.0/8
```

## 仮想マシンの起動

オンプレミス想定の環境を作成するため、仮想マシンを起動していきます。Anthos clusters on Bare Metal の詳細な導入要件は [こちら](https://cloud.google.com/anthos/clusters/docs/bare-metal/1.6/installing/install-prereq?hl=ja) です。

![VM](https://raw.github.com/wiki/pottava/google-cloud-tutorials/anthos-baremetal/1-2.png)

- 管理ワークステーション: **n2-standard-2**
- ハイブリッド クラスタ マスタ兼用 VM: **n2-standard-8**
- ノードプール VM: **n2-standard-2**

の VM 3 台を起動します。

```text
gcloud compute instances create {{vm-workst}} \
    --zone {{zone}} --machine-type "n1-standard-2" \
    --image-family=ubuntu-2004-lts --image-project=ubuntu-os-cloud \
    --min-cpu-platform "Intel Skylake" \
    --boot-disk-size 100G --boot-disk-type pd-standard \
    --network {{vpc}} --subnet {{subnet}} --can-ip-forward \
    --scopes cloud-platform --metadata=enable-oslogin=FALSE
gcloud compute instances create {{vm-hybrid}} \
    --zone {{zone}} --machine-type "n1-standard-8" \
    --image-family=ubuntu-2004-lts --image-project=ubuntu-os-cloud \
    --min-cpu-platform "Intel Skylake" \
    --boot-disk-size 300G --boot-disk-type pd-standard \
    --network {{vpc}} --subnet {{subnet}} --can-ip-forward \
    --scopes cloud-platform --metadata=enable-oslogin=FALSE
gcloud compute instances create {{vm-worker}} \
    --zone {{zone}} --machine-type "n1-standard-2" \
    --image-family=ubuntu-2004-lts --image-project=ubuntu-os-cloud \
    --min-cpu-platform "Intel Skylake" \
    --boot-disk-size 200G --boot-disk-type pd-standard \
    --network {{vpc}} --subnet {{subnet}} --can-ip-forward \
    --scopes cloud-platform --metadata=enable-oslogin=FALSE
```

## 仮想マシンの起動確認

コンソールを移動してみます。

**Compute Engine** セクションを選びます。

<walkthrough-menu-navigation sectionId="COMPUTE_SECTION"></walkthrough-menu-navigation>

左側のメニューから <walkthrough-spotlight-pointer cssSelector="#cfctest-section-nav-item-vm-instances">VM インスタンス</walkthrough-spotlight-pointer> を開きます。

以下のコマンドで SSH ができる状態になるまで待機します。

```text
declare -a VMs=("{{vm-workst}}" "{{vm-hybrid}}" "{{vm-worker}}")
for vm in "${VMs[@]}"; do
    while ! gcloud compute ssh ${vm} --tunnel-through-iap --command "echo Hi from ${vm}"; do
        echo "Trying to SSH into ${vm} failed. Sleeping for 5 seconds."
        sleep 5
    done
done
```

プライベート IP アドレスの一覧を取得します。

```bash
ip1=$(gcloud compute instances describe {{vm-workst}} --format='get(networkInterfaces[0].networkIP)')
ip2=$(gcloud compute instances describe {{vm-hybrid}} --format='get(networkInterfaces[0].networkIP)')
ip3=$(gcloud compute instances describe {{vm-worker}} --format='get(networkInterfaces[0].networkIP)')
declare -a IPs=("${ip1}" "${ip2}" "${ip3}")
echo ${IPs[@]}
```

## VXLAN ネットワークの構築

VM 間で VXLAN ネットワークを構成します。

```text
i=2
for vm in "${VMs[@]}"; do
    gcloud compute ssh ${vm} --tunnel-through-iap << EOF
sudo apt-get -qq update > /dev/null
sudo apt-get -qq install -y jq > /dev/null
set -x
sudo ip link add vxlan0 type vxlan id 42 dev ens4 dstport 0
current_ip=\$(ip --json a show dev ens4 | jq -r '.[0].addr_info[0].local')
for ip in ${IPs[@]}; do
    if [ "\${ip}" != "\${current_ip}" ]; then
        sudo bridge fdb append to 00:00:00:00:00:00 dst \${ip} dev vxlan0
    fi
done
sudo ip addr add 10.200.0.$i/24 dev vxlan0
sudo ip link set up dev vxlan0
sudo systemctl stop apparmor.service
sudo systemctl disable apparmor.service
EOF
    i=$((i+1))
done
```

これにより、VM 間は 10.200.0.0/24 ネットワークで L2 接続性が確立しました。各 VM の IP アドレスは以下のとおりです。

- 管理ワークステーション: 10.200.0.2
- ハイブリッド クラスタ マスタ兼用 VM: 10.200.0.3
- ノードプール VM: 10.200.0.4

## 管理ワークステーションのセットアップ

管理ワークステーションに SSH で入ります。

```bash
gcloud compute ssh {{vm-workst}} --tunnel-through-iap
```

[kubectl](https://kubernetes.io/docs/tasks/tools/#kubectl)、bmctl、[docker](https://www.docker.com/) をインストールします。

```bash
curl -LO "https://storage.googleapis.com/kubernetes-release/release/$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl
sudo mv kubectl /usr/local/sbin/
kubectl version --client=true
```

```bash
mkdir baremetal && cd baremetal
gsutil cp gs://anthos-baremetal-release/bmctl/1.6.1/linux-amd64/bmctl .
chmod a+x bmctl
sudo mv bmctl /usr/local/sbin/
bmctl version
```

```bash
curl -fsSL https://get.docker.com/ | sh
sudo docker version
```

## 公開鍵の配布

**（管理ワークステーション上で実行してください）**

クラスタセットアップにあたり、パスワード認証なしで接続できるよう、管理ワークステーション上で SSH 鍵を生成し、各ノードに配布します。

```bash
sudo su -
```

```bash
ssh-keygen -t rsa -N "" -f /root/.ssh/id_rsa
sed 's/ssh-rsa/root:ssh-rsa/' /root/.ssh/id_rsa.pub > ssh-metadata
gcloud compute instances add-metadata {{vm-hybrid}} --zone {{zone}} --metadata-from-file ssh-keys=ssh-metadata
gcloud compute instances add-metadata {{vm-worker}} --zone {{zone}} --metadata-from-file ssh-keys=ssh-metadata
exit
```

一般ユーザーから、パスワード認証なしで SSH できることを確認します。

```bash
sudo ssh -o IdentitiesOnly=yes -o StrictHostKeyChecking=no 10.200.0.3 hostname
sudo ssh -o IdentitiesOnly=yes -o StrictHostKeyChecking=no 10.200.0.4 hostname
```

## ハイブリッド クラスタ構築準備

**（管理ワークステーション上で実行してください）**

Anthos クラスタと Google Cloud と通信するためのキーの名前を決め、

```bash
export HYBRID_CLUSTER={{cluster}}
export GOOGLE_APPLICATION_CREDENTIALS={{sa}}-creds.json
```

キーを生成します。

```bash
cd ${HOME}
gcloud iam service-accounts keys create "${GOOGLE_APPLICATION_CREDENTIALS}"  --iam-account={{sa}}@{{project-id}}.iam.gserviceaccount.com
```

Anthos clusters on Bare Metal の設定雛形を出力し、中身を眺めてみましょう。

```bash
bmctl create config -c "${HYBRID_CLUSTER}"
cat bmctl-workspace/{{cluster}}/{{cluster}}.yaml
```

`{{cluster}}.yaml` を以下の通りに書き換えます。

```text
cat << EOF >bmctl-workspace/{{cluster}}/{{cluster}}.yaml
gcrKeyPath: ${GOOGLE_APPLICATION_CREDENTIALS}
sshPrivateKeyPath: /root/.ssh/id_rsa
gkeConnectAgentServiceAccountKeyPath: ${GOOGLE_APPLICATION_CREDENTIALS}
gkeConnectRegisterServiceAccountKeyPath: ${GOOGLE_APPLICATION_CREDENTIALS}
cloudOperationsServiceAccountKeyPath: ${GOOGLE_APPLICATION_CREDENTIALS}
---
apiVersion: v1
kind: Namespace
metadata:
  name: cluster-admins
---
apiVersion: baremetal.cluster.gke.io/v1
kind: Cluster
metadata:
  name: ${HYBRID_CLUSTER}
  namespace: cluster-admins
spec:
  type: hybrid
  anthosBareMetalVersion: 1.6.1
  gkeConnect:
    projectID: {{project-id}}
  controlPlane:
    nodePoolSpec:
      nodes:
      - address: 10.200.0.3
  clusterNetwork:
    pods:
      cidrBlocks:
      - 192.168.0.0/16
    services:
      cidrBlocks:
      - 10.96.0.0/12
  loadBalancer:
    mode: bundled
    ports:
      controlPlaneLBPort: 443
    vips:
      controlPlaneVIP: 10.200.0.49
      ingressVIP: 10.200.0.50
    addressPools:
    - name: pool1
      addresses:
      - 10.200.0.50-10.200.0.70
  clusterOperations:
    projectID: {{project-id}}
    location: asia-northeast1
    enableApplication: true
  storage:
    lvpNodeMounts:
      path: /mnt/localpv-disk
      storageClassName: node-disk
    lvpShare:
      path: /mnt/localpv-share
      storageClassName: standard
      numPVUnderSharedPath: 5
---
apiVersion: baremetal.cluster.gke.io/v1
kind: NodePool
metadata:
  name: node-pool-1
  namespace: cluster-admins
spec:
  clusterName: ${HYBRID_CLUSTER}
  nodes:
  - address: 10.200.0.4
EOF
```

## ハイブリッド クラスタの作成

**（管理ワークステーション上で実行してください）**

![Anthos](https://raw.github.com/wiki/pottava/google-cloud-tutorials/anthos-baremetal/1-5.png)

以下コマンドを実行し、ハイブリッド クラスタを作成します。15 分ほどかかります。

```bash
sudo bmctl create cluster -c "${HYBRID_CLUSTER}"
```

## Cloud Shell の再開

### **（Cloud Shell のセッションが切れたりしていなければ、本節はスキップしてください）**

Cloud Shell の環境変数などを再設定しつつ、ワークステーションへ SSH し

```bash
export GOOGLE_CLOUD_PROJECT="{{project-id}}"
gcloud config set project "${GOOGLE_CLOUD_PROJECT}"
gcloud config set compute/region {{region}}
gcloud config set compute/zone {{zone}}
gcloud compute ssh {{vm-workst}} --tunnel-through-iap
```

ワークステーション上の環境変数も再設定しましょう。

```bash
export HYBRID_CLUSTER={{cluster}}
export GOOGLE_APPLICATION_CREDENTIALS={{sa}}-creds.json
```

## ハイブリッド クラスタの確認

**（管理ワークステーション上で実行してください）**

### **ハイブリッド クラスタの起動確認**

ハイブリッド クラスタ作成後、以下コマンドでハイブリッド クラスタのノード情報が取得できることを確認します。

```bash
export KUBECONFIG="bmctl-workspace/${HYBRID_CLUSTER}/${HYBRID_CLUSTER}-kubeconfig"
kubectl get nodes
```

ハイブリッド クラスタは Admin Cluster と User Cluster の両方を兼ねているため、Anthos のコンソールにも情報が連携されています。

**Anthos** セクションを選びます。

<walkthrough-menu-navigation sectionId="ANTHOS_SECTION"></walkthrough-menu-navigation>

左側のメニューから <walkthrough-spotlight-pointer cssSelector="#cfctest-section-nav-item-ANTHOS_CLUSTERS_SECTION">クラスタ</walkthrough-spotlight-pointer> を開きます。

## Kubernetes の動作確認

**（管理ワークステーション上で実行してください）**

テスト用アプリケーションをデプロイし、挙動を確認してみます。

```bash
kubectl create deployment web --image=nginx:1.19.6-alpine
kubectl expose deployment web --name web --type LoadBalancer --port 80
kubectl get svc -w
```

外部アクセス用 IP アドレスがアサインされたら `Ctrl + C` で watch を中断し、実際に HTTP アクセスしてみましょう。

```bash
curl -iXGET $(kubectl get svc -l app=web -o jsonpath="{.items[0].status.loadBalancer.ingress[0].ip}")
```

## Google Cloud コンソールへの権限付与

**（管理ワークステーション上で実行してください）**

**Kubernetes** セクションを選びます。

<walkthrough-menu-navigation sectionId="KUBERNETES_SECTION"></walkthrough-menu-navigation>

クラスタ一覧の通知欄に、警告マークとともに `クラスタにログイン` と表示されているかと思います。

これは Google Cloud 以外で構築された Anthos クラスタの場合、実際のワークロードは追加で権限を付与しない限りコンソールから値を参照できない仕組みとなっているためです。具体的な手順は [こちら](https://cloud.google.com/anthos/multicluster-management/console/logging-in?hl=ja) にもありますが、以下それに従い、クラスタのより詳細な情報を Google Cloud へ連携してみます。

### **Kubernetes クラスタロールの作成**

ロールベースのアクセス制御（RBAC）のためのカスタム ロールを作成します。クラスタのノード、永続ボリューム、ストレージ クラスに対する get、list、watch 権限をユーザーに付与します。

```text
cat <<EOF > cloud-console-reader.yaml
kind: ClusterRole
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: cloud-console-reader
rules:
- apiGroups: [""]
  resources: ["nodes", "persistentvolumes"]
  verbs: ["get", "list", "watch"]
- apiGroups: ["storage.k8s.io"]
  resources: ["storageclasses"]
  verbs: ["get", "list", "watch"]
EOF
kubectl apply -f cloud-console-reader.yaml
```

### **Kubernetes サービス アカウント（KSA）の作成**

サービス アカウントを作成し

```bash
KSA_NAME=abm-console-service-account
kubectl create serviceaccount "${KSA_NAME}"
```

view と先ほど作った cloud-console-reader カスタム ロールを関連付けます。

```bash
kubectl create clusterrolebinding cloud-console-reader-binding --clusterrole cloud-console-reader --serviceaccount "default:${KSA_NAME}"
kubectl create clusterrolebinding cloud-console-view-binding --clusterrole view --serviceaccount "default:${KSA_NAME}"
kubectl create clusterrolebinding cloud-console-cluster-admin-binding --clusterrole cluster-admin --serviceaccount "default:${KSA_NAME}"
```

サービス アカウント（KSA）のトークンを取得しましょう。

```bash
SECRET_NAME=$(kubectl get serviceaccount "${KSA_NAME}" -o jsonpath='{$.secrets[0].name}') 
kubectl get secret "${SECRET_NAME}" -o jsonpath='{$.data.token}' | base64 --decode
echo ''
```

### **クラスタへのログイン**

1. Cloud コンソールにもどり、登録済みクラスタの横にある `ログイン` ボタンをクリックします
2. `トークン` を選択して、フィールドに KSA のトークンを入力し、`ログイン` をクリックします
3. クラスタ名の左側のアイコンが緑色になり `ワークロード` などが参照できるようになります

もしトークンが不正だとエラーがでた場合は、コピーした**トークンに改行文字列が入っている可能性があります**。改行のないように整形してから再度登録をお試しください。

## Cloud Logging & Cloud Monitoring での確認

**Monitoring** セクションを開きましょう。

<walkthrough-menu-navigation sectionId="MONITORING_SECTION"></walkthrough-menu-navigation>

左側のメニューから <walkthrough-spotlight-pointer cssSelector="#cfctest-section-nav-item-dashboards">ダッシュボード</walkthrough-spotlight-pointer> を選びます。

- Anthos cluster control plane status: コントロール プレーンのステータス
- Anthos cluster node status: ノードステータス
- Anthos cluster pod status: Pod ステータス

が確認できます。実際にどんな値がみれるのか、探検してみてください。

## チャレンジ問題: User Cluster の追加

![チャレンジ問題](https://raw.github.com/wiki/pottava/google-cloud-tutorials/anthos-baremetal/challenge.png)

図のように、User Cluster を追加してみましょう！[こちら](https://cloud.google.com/anthos/clusters/docs/bare-metal/1.6/installing/creating-clusters/user-cluster-creation#create-user-config) をヒントに進めてみてくだい。

## これで終わりです

<walkthrough-conclusion-trophy></walkthrough-conclusion-trophy>

すべて完了しました。

次のステップにお進みください。

**（管理ワークステーション上ではなく、Cloud Shell にもどり、以下を実行してください）**

```bash
teachme ~/cloudshell_open/gcp-getting-started-lab-jp/appmod/anthos-baremetal/02-devops.md
```
