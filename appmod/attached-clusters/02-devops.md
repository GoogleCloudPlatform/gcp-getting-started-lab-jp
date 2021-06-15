# Anthos Attached Clusters ウォークスルー (DevOps)

<walkthrough-watcher-constant key="region" value="asia-northeast1"></walkthrough-watcher-constant>
<walkthrough-watcher-constant key="zone" value="asia-northeast1-c"></walkthrough-watcher-constant>
<walkthrough-watcher-constant key="cluster" value="anthos"></walkthrough-watcher-constant>

## 始めましょう

Anthos Attached Clusters へソフトウェアをデプロイする手順です。

**所要時間**: 約 30 分

**前提条件**:

- Anthos Attached Clusters として Kubernetes クラスタが登録されている。

**[開始]** ボタンをクリックして次のステップに進みます。

## API の有効化

Google Cloud では利用したい機能ごとに、有効化を行う必要があります。
ここでは、以降のハンズオンで利用する機能を事前に有効化しておきます。

```bash
gcloud services enable connectgateway.googleapis.com cloudbuild.googleapis.com sourcerepo.googleapis.com cloudresourcemanager.googleapis.com container.googleapis.com stackdriver.googleapis.com cloudtrace.googleapis.com cloudprofiler.googleapis.com logging.googleapis.com iamcredentials.googleapis.com artifactregistry.googleapis.com
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

## サンプルアプリケーションのコンテナ化

### **Google Cloud のプロジェクト ID を環境変数に設定**

環境変数 `GOOGLE_CLOUD_PROJECT` に Google Cloud プロジェクト ID を設定します。

```bash
export GOOGLE_CLOUD_PROJECT="{{project-id}}"
```

### コンテナを作成する

Go 言語で作成されたサンプル Web アプリケーションをコンテナ化します。
ここで作成したコンテナはローカルディスクに保存されます。

```bash
cd appmod/attached-clusters/
docker build -t asia-northeast1-docker.pkg.dev/$GOOGLE_CLOUD_PROJECT/gcp-getting-started-lab-jp/devops-handson:v1 .
```

**ヒント**: `docker build` コマンドを叩くと、Dockerfile が読み込まれ、そこに記載されている手順通りにコンテナが作成されます。

### Cloud Shell 上でコンテナを起動する

上の手順で作成したコンテナを Cloud Shell 上で起動します。

```bash
docker run -d -p 8080:8080 \
--name devops-handson \
asia-northeast1-docker.pkg.dev/$GOOGLE_CLOUD_PROJECT/gcp-getting-started-lab-jp/devops-handson:v1
```

**ヒント**: Cloud Shell 環境の 8080 ポートを、コンテナの 8080 ポートに紐付け、バックグラウンドで起動します。

<walkthrough-footnote>アプリケーションをコンテナ化し、起動することができました。次に実際にアプリケーションにアクセスしてみます。</walkthrough-footnote>

## 作成したコンテナの動作確認

### CloudShell の機能を利用し、起動したアプリケーションにアクセスする

画面右上にあるアイコン <walkthrough-web-preview-icon></walkthrough-web-preview-icon> をクリックし、"プレビューのポート: 8080"を選択します。
これによりブラウザで新しいタブが開き、Cloud Shell 上で起動しているコンテナにアクセスできます。

正しくアプリケーションにアクセスできると "Hello World!" と表示されます。

## コンテナのレジストリへの登録

先程作成したコンテナはローカルに保存されているため、他の場所から参照ができません。
他の場所から利用できるようにするために、GCP 上のプライベートなコンテナ置き場（コンテナレジストリ）に登録します。

### Docker リポジトリの作成

```bash
gcloud artifacts repositories create gcp-getting-started-lab-jp --repository-format=docker \
--location=asia-northeast1 --description="Docker repository for DevOps Handson"
```

### Docker に対する認証の設定

```bash
gcloud auth configure-docker asia-northeast1-docker.pkg.dev
```

### 作成したコンテナをコンテナレジストリ（Artifact Registry）へ登録（プッシュ）する

```bash
docker push asia-northeast1-docker.pkg.dev/$GOOGLE_CLOUD_PROJECT/gcp-getting-started-lab-jp/devops-handson:v1
```

## Anthos クラスタのへのデプロイ

### Anthos クラスタへのアクセス設定を行う

自分のログイン名を変数として使う準備をします。

```text
account=$(gcloud config get-value core/account)
account="${account%%@*}"
```

認証情報を取得し、Anthos クラスタを操作できるようにします。

```bash
gcloud container hub memberships get-credentials "{{cluster}}-gke-${account}"
```
## Congraturations!

<walkthrough-conclusion-trophy></walkthrough-conclusion-trophy>

すべて完了しました。

次のステップにお進みください。

```bash
teachme 09-teardown.md
```
