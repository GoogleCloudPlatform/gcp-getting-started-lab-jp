# Anthos Attached Clusters ウォークスルー (DevOps)

<walkthrough-watcher-constant key="region" value="asia-northeast1"></walkthrough-watcher-constant>
<walkthrough-watcher-constant key="zone" value="asia-northeast1-c"></walkthrough-watcher-constant>
<walkthrough-watcher-constant key="cluster" value="anthos"></walkthrough-watcher-constant>
<walkthrough-watcher-constant key="ar-repo" value="anthos-handson"></walkthrough-watcher-constant>
<walkthrough-watcher-constant key="ar-sec" value="google-artifactregistry"></walkthrough-watcher-constant>
<walkthrough-watcher-constant key="app-ns" value="devops-handson-ns"></walkthrough-watcher-constant>

## 始めましょう

Anthos Attached Clusters へソフトウェアをデプロイする手順です。

**所要時間**: 約 15 分

**前提条件**:

- Anthos Attached Clusters として Kubernetes クラスタが登録されている。

**[開始]** ボタンをクリックして次のステップに進みます。

## API の有効化

Google Cloud では利用したい機能ごとに、有効化を行う必要があります。
ここでは、以降のハンズオンで利用する機能を事前に有効化しておきます。

```bash
gcloud services enable cloudbuild.googleapis.com sourcerepo.googleapis.com iamcredentials.googleapis.com artifactregistry.googleapis.com
```

`Operation 〜 finished successfully.` と表示が出ることを確認します。

## サンプルアプリケーションのコンテナ化

### **Google Cloud のプロジェクト ID を環境変数に設定**

環境変数 `GOOGLE_CLOUD_PROJECT` に Google Cloud プロジェクト ID を設定します。

```bash
export GOOGLE_CLOUD_PROJECT="{{project-id}}"
```

### コンテナを作成する

Go 言語で作成されたサンプル Web アプリケーションをコンテナ化します。

```bash
cd appmod/attached-clusters/
docker build -t "{{region}}-docker.pkg.dev/${GOOGLE_CLOUD_PROJECT}/{{ar-repo}}/devops:v1" .
```

### Cloud Shell 上でコンテナを起動する

上の手順で作成したコンテナを Cloud Shell 上で起動します。

```bash
docker run -d -p 8080:8080 --name devops-handson \
    "{{region}}-docker.pkg.dev/${GOOGLE_CLOUD_PROJECT}/{{ar-repo}}/devops:v1"
```

**ヒント**: Cloud Shell 環境の 8080 ポートを、コンテナの 8080 ポートに紐付け、バックグラウンドで起動します。

## 作成したコンテナの動作確認

### CloudShell の機能を利用し、起動したアプリケーションにアクセスする

画面右上にあるアイコン <walkthrough-web-preview-icon></walkthrough-web-preview-icon> をクリックし **"プレビューのポート: 8080"** を選択します。
これによりブラウザで新しいタブが開き、Cloud Shell 上で起動しているコンテナにアクセスできます。

正しくアプリケーションにアクセスできると "Hello World!" と表示されます。

## コンテナのレジストリへの登録

先程作成したコンテナはローカルに保存されているため、他の場所から参照ができません。
他の場所から利用できるようにするために、GCP 上のプライベートなコンテナ置き場（コンテナレジストリ）に登録します。

### Docker リポジトリの作成

```bash
gcloud artifacts repositories create {{ar-repo}} \
    --repository-format docker --location {{region}} \
    --description "Docker repository for DevOps Handson"
```

### Docker に対する認証の設定

```bash
gcloud auth configure-docker {{region}}-docker.pkg.dev
```

### 作成したコンテナをコンテナレジストリ（Artifact Registry）へ登録（プッシュ）する

```bash
docker push "{{region}}-docker.pkg.dev/${GOOGLE_CLOUD_PROJECT}/{{ar-repo}}/devops:v1"
```

## Anthos クラスタのへのデプロイ

### Anthos クラスタへのアクセス設定を行う

自分のログイン名を変数として使う準備をします。

```text
account=$(gcloud config get-value core/account)
account="${account%%@*}"
```

認証情報を取得し、Anthos クラスタを操作できるようにします。ここまでの手順で、**[権限借用ポリシーがすでに設定](https://cloud.google.com/anthos/multicluster-management/gateway/setup?hl=ja#configure_role-based_access_control_rbac_policies)されている** Kind クラスタを利用します。

```bash
gcloud beta container hub memberships get-credentials "{{cluster}}-attached-${account}"
```

Kind クラスタのノード情報を見てみましょう。

```bash
kubectl get nodes -o wide
```

API エンドポイントが Anthos を経由している様子は以下で確認できます。

```bash
kubectl cluster-info
```

## コンテナレジストリへの権限付与

Google Cloud 外部にある Kubernetes クラスタから、コンテナレジストリへアクセスする権限を付与します。

### **Google サービスアカウントの作成・権限付与**

```bash
SA_EMAIL=$(gcloud iam service-accounts create k8s-gcr-auth-ro --format='value(email)')
gcloud projects add-iam-policy-binding ${GOOGLE_CLOUD_PROJECT} \
    --member="serviceAccount:${SA_EMAIL}" \
    --role="roles/artifactregistry.reader"
gcloud iam service-accounts keys create k8s-gcr-auth-ro.json --iam-account "${SA_EMAIL}"
```

### **アプリケーションを配置する名前空間を作成**

```bash
kubectl create namespace {{app-ns}}
```

### **Kubernetes Secret の設定**

```bash
kubectl -n {{app-ns}} create secret docker-registry {{ar-sec}} \
    --docker-server=https://{{region}}-docker.pkg.dev \
    --docker-email="${SA_EMAIL}" \
    --docker-username=_json_key \
    --docker-password="$(cat k8s-gcr-auth-ro.json)"
```

### **Kubernetes デフォルトサービスアカウントの修正**

```bash
kubectl -n {{app-ns}} patch serviceaccount default \
    -p "{\"imagePullSecrets\":[{\"name\":\"{{ar-sec}}\"}]}"
```

## コンテナのデプロイ

### **ハンズオン用の設定ファイルを修正する**

Kubernetes のデプロイ用設定ファイルを、コンテナレジストリに登録済みのコンテナを使うように修正します。

```bash
sed -ie "s|FIXME|{{region}}-docker.pkg.dev/${GOOGLE_CLOUD_PROJECT}/{{ar-repo}}/devops:v1|g" gke-config/deployment.yaml
```

### **コンテナを Kubernetes クラスタへデプロイする**

```bash
kubectl apply -f gke-config/deployment.yaml
```

このコマンドにより、Kubernetes の 2 リソースが作成されます。

- [Deployment](https://cloud.google.com/kubernetes-engine/docs/concepts/deployment?hl=ja)
- [Service](https://cloud.google.com/kubernetes-engine/docs/concepts/service?hl=ja)

**GUI**: [Deployment](https://console.cloud.google.com/kubernetes/workload?project={{project-id}}), [Service](https://console.cloud.google.com/kubernetes/discovery?project={{project-id}})

## Congraturations!

<walkthrough-conclusion-trophy></walkthrough-conclusion-trophy>

すべて完了しました。

次のステップにお進みください。

```bash
teachme ~/cloudshell_open/gcp-getting-started-lab-jp/appmod/attached-clusters/03-configurations.md
```
