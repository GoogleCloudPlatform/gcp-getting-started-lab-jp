# Anthos Attached Clusters ウォークスルー

<walkthrough-watcher-constant key="region" value="asia-northeast1"></walkthrough-watcher-constant>
<walkthrough-watcher-constant key="zone" value="asia-northeast1-c"></walkthrough-watcher-constant>
<walkthrough-watcher-constant key="sa" value="sa-anthos-ac"></walkthrough-watcher-constant>
<walkthrough-watcher-constant key="cluster" value="anthos"></walkthrough-watcher-constant>
<walkthrough-watcher-constant key="gke" value="1.18.19-gke.1700"></walkthrough-watcher-constant>

## 始めましょう

2 つの Kubernetes クラスタを Anthos Attached Clusters として一括管理する手順です。

**所要時間**: 約 30 分

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
gcloud services enable anthos.googleapis.com anthosgke.googleapis.com gkeconnect.googleapis.com gkehub.googleapis.com connectgateway.googleapis.com cloudresourcemanager.googleapis.com compute.googleapis.com container.googleapis.com stackdriver.googleapis.com monitoring.googleapis.com logging.googleapis.com
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

Anthos クラスタとして管理する上で、Google Cloud と通信するための [サービス アカウント](https://cloud.google.com/iam/docs/service-accounts?hl=ja) を用意します。

```bash
gcloud iam service-accounts create {{sa}}
```

### 権限の付与

Kubernetes クラスタを Anthos へ登録するための権限を付与します。

```bash
gcloud projects add-iam-policy-binding ${GOOGLE_CLOUD_PROJECT} --member="serviceAccount:{{sa}}@${GOOGLE_CLOUD_PROJECT}.iam.gserviceaccount.com" --role="roles/gkehub.connect"
```

### クレデンシャルの取得

Kubernetes クラスタを Anthos へ登録するための権限を付与します。

```bash
export GOOGLE_APPLICATION_CREDENTIALS={{sa}}-creds.json
gcloud iam service-accounts keys create "${GOOGLE_APPLICATION_CREDENTIALS}" --iam-account="{{sa}}@${GOOGLE_CLOUD_PROJECT}.iam.gserviceaccount.com"
```

## クラスタの作成

自分のログイン名を変数化しておき、

```text
account=$(gcloud config get-value core/account)
account="${account%%@*}"
```

それを使いつつ GKE クラスタを 1 つ作ります。

```bash
gcloud container clusters create \
    "{{cluster}}-gke-${account}" \
    --cluster-version "{{gke}}" \
    --machine-type "e2-medium" \
    --num-nodes 2 --enable-ip-alias --async
```

もう一つ Kubernetes クラスタを起動します。まず kind を内部で起動するための VM を起動し

```bash
gcloud compute instances create \
    "{{cluster}}-attached-${account}" \
    --zone {{zone}} --machine-type "n2-standard-2" \
    --metadata=enable-oslogin=TRUE \
    --scopes cloud-platform
```

[Identity-Aware Proxy](https://cloud.google.com/iap?hl=ja) からの SSH を許可しつつ、秘密鍵を転送し、中に入ります。

```bash
gcloud compute firewall-rules create allow-from-iap --network=default --direction=INGRESS --priority=1000 --action=ALLOW --rules=tcp:22,icmp --source-ranges=35.235.240.0/20
gcloud compute scp {{sa}}-creds.json "{{cluster}}-attached-${account}":~ --tunnel-through-iap
gcloud compute ssh "{{cluster}}-attached-${account}" --tunnel-through-iap
```

Kind をインストールし、

```bash
sudo apt-get update
sudo apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release
curl -fsSL https://download.docker.com/linux/debian/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
echo \
  "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/debian \
  $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io
sudo gpasswd -a $USER docker
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl
sudo mv kubectl /usr/local/bin/
curl -Lo kind https://kind.sigs.k8s.io/dl/v0.11.1/kind-linux-amd64
chmod +x kind
sudo mv kind /usr/local/bin/
```

一度ログアウトした後、改めて VM に入り Kubernetes クラスタを起動します。

```bash
kind create cluster --name anthos-kind
```

## Anthos への登録（クラスタの追加）

（kind ではなく OpenShift クラスタを追加する場合は SCC (Security Context Constraints) で gke-connect を privileged グループに追加しておきましょう）

```bash
oc adm policy add-scc-to-group privileged system:serviceaccounts:gke-connect
```

Attached Clusters として、Kubernetes クラスタを Anthos に参加させます。

```bash
gcloud container hub memberships \
    register "$(hostname)" \
    --kubeconfig=$HOME/.kube/config \
    --context="$(kubectl config current-context)" \
    --service-account-key-file={{sa}}-creds.json
```

正常にエージェントが稼働することが確認できたら Cloud Shell に戻りましょう。

```bash
kubectl get all -n gke-connect
exit
```

GKE クラスタも Anthos に登録します。GKE の場合は `--gke-cluster` オプションでクラスタを指定します。

```bash
gcloud container hub memberships \
    register "{{cluster}}-gke-${account}" \
    --gke-cluster "{{zone}}/{{cluster}}-gke-${account}" \
    --service-account-key-file={{sa}}-creds.json
```

## Google Cloud コンソールへの権限付与

**Kubernetes** セクションを選びます。

<walkthrough-menu-navigation sectionId="KUBERNETES_SECTION"></walkthrough-menu-navigation>

クラスタ一覧の通知欄に、警告マークとともに `クラスタにログイン` と表示されているかと思います。

これは Google Cloud 以外で構築された Anthos クラスタの場合、実際のワークロードは追加で権限を付与しない限りコンソールから値を参照できない仕組みとなっているためです。具体的な手順は [こちら](https://cloud.google.com/anthos/multicluster-management/console/logging-in?hl=ja) にもありますが、以下それに従い、クラスタのより詳細な情報を Google Cloud へ連携してみます。

### **ユーザへの権限付与**

いまみなさんはオーナー権限でログインされているかと思いますが、自分自身ではなく特定のユーザーやサービスアカウントの設定をする場合は、該当リソースに対して以下を参考に `gcloud projects add-iam-policy-binding` で権限を付与してください。

- roles/gkehub.gatewayAdmin : Connect Gateway API にアクセスできるようになります
- roles/gkehub.viewer : GKE コンソール ページでクラスタを表示できます
- roles/container.viewer : Cloud Console でコンテナ リソースを表示できます

### **Kind ノードへ再度 SSH**

```text
account=$(gcloud config get-value core/account)
account="${account%%@*}"
```

```bash
gcloud compute ssh "{{cluster}}-attached-${account}" --tunnel-through-iap
```

## Kubernetes 権限借用ポリシーの作成

各クラスタに配置される Anthos の Connect エージェントが指定されたユーザーまたはサービス アカウントに代わって API サーバーにリクエストを送信することを承認します。コンソールの右上、自分のアイコンをクリックし、ログインに利用しているメールアドレスを変数にセットし、

```bash
USER_ACCOUNT=
```

クラスタロールを作成しましょう。

```text
cat << EOF > impersonate.yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: gateway-impersonate
rules:
- apiGroups:
  - ""
  resourceNames:
  - ${USER_ACCOUNT}
  resources:
  - users
  verbs:
  - impersonate
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: gateway-impersonate
roleRef:
  kind: ClusterRole
  name: gateway-impersonate
  apiGroup: rbac.authorization.k8s.io
subjects:
- kind: ServiceAccount
  name: connect-agent-sa
  namespace: gke-connect
EOF
kubectl apply -f impersonate.yaml
```

## Kubernetes 権限ポリシーの作成

クラスタに対し、ユーザーに付与する権限を指定します。ここではかなり強力ですが、cluster-admin 権限を付与します。

```text
cat << EOF > admin-permission.yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: gateway-cluster-admin
subjects:
- kind: User
  name: ${USER_ACCOUNT}
roleRef:
  kind: ClusterRole
  name: cluster-admin
  apiGroup: rbac.authorization.k8s.io
EOF
kubectl apply -f admin-permission.yaml
```

### **クラスタへのログイン**

1. Cloud コンソールにもどり、登録済みクラスタの横にある `ログイン` ボタンをクリックします
2. `Use your Google identity to log-in` が選択されていることを確認して `ログイン`
3. クラスタ名の左側のアイコンが緑色になり `ワークロード` などが参照できるようになります

## Kubernetes としてのクラスタ確認

ログインに成功すると、クラスタの詳細が確認できるようになります。

- コントロール プレーンのバージョン
- クラスタサイズ, 合計コア数, 合計メモリなど

## Anthos クラスタの確認

Anthos として登録されたクラスタから何が見えるかを確認してみます。

画面の左上にある <walkthrough-spotlight-pointer spotlightId="console-nav-menu">ナビゲーション メニュー</walkthrough-spotlight-pointer> を開き、**Anthos** セクションを開きましょう。

<walkthrough-menu-navigation sectionId="ANTHOS_SECTION"></walkthrough-menu-navigation>

左側のメニューから <walkthrough-spotlight-pointer cssSelector="#cfctest-section-nav-item-ANTHOS_CLUSTERS_SECTION">クラスタ</walkthrough-spotlight-pointer> を開きます。

クラスタを選択すると、画面の右側に詳細が見えます。

- コントロール プレーンのバージョン
- クラスタサイズ, 合計コア数, 合計メモリなど

## これで終わりです

<walkthrough-conclusion-trophy></walkthrough-conclusion-trophy>

すべて完了しました。

次のステップにお進みください。

**（Kind ノード上ではなく、Cloud Shell にもどり、以下を実行してください）**

```bash
teachme ~/cloudshell_open/gcp-getting-started-lab-jp/appmod/attached-clusters/02-devops.md
```
