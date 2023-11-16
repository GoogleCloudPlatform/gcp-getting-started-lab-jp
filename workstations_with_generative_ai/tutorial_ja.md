# **次世代の開発スタイルを体験してみよう / Cloud Workstations を使ったクラウドでの開発環境構築**

## **作業概要**

本ハンズオンでは、Google Cloud でカスタマイズ可能で安全なマネージド開発環境を提供する [Cloud Workstations](https://cloud.google.com/workstations?hl=ja) の様々な機能を体験します。

- ワークステーション用ネットワークの設定
- 基本のワークステーション構成からワークステーションを作成する
- 開発者としてワークステーションを利用する
  - 拡張機能 (Extensions) をインストール
  - Cloud Code を利用しアプリケーションをローカル開発する
  - Duet AI 機能を活用しコーディングする
- 管理者としてワークステーションを利用する
  - コンテナイメージのカスタマイズ
  - ワークステーション構成の新規作成
- 本番で Cloud Workstations を利用する
  - 開発者個別にワークステーションを払い出す
  - カスタムコンテナイメージをセキュアに保つ
  - 無駄な費用がかからないようにする

## **環境準備**

最初に、ハンズオンを進めるための環境準備を行います。

下記の設定を進めていきます。

- Google Cloud 機能（API）有効化

## **gcloud コマンドラインツール**

Google Cloud は、コマンドライン（CLI）、GUI から操作が可能です。ハンズオンでは作業の自動化を目的に主に CLI を使い作業を行います。

gcloud コマンドライン インターフェースは、Google Cloud でメインとなる CLI ツールです。これを使用すると、多くの一般的なプラットフォーム タスクを様々なツールと組み合わせて実行することができます。

たとえば、gcloud CLI を使用して、以下のようなものを作成、管理できます。

- Google Compute Engine 仮想マシン
- Google Kubernetes Engine クラスタ

**ヒント**: gcloud コマンドラインツールについての詳細は[こちら](https://cloud.google.com/sdk/gcloud?hl=ja)をご参照ください。

## **Google Cloud 機能（API）有効化**

Google Cloud では利用したい機能（API）ごとに、有効化を行う必要があります。

ここでは、以降のハンズオンで利用する機能を事前に有効化しておきます。

```bash
gcloud services enable workstations.googleapis.com \
  artifactregistry.googleapis.com \
  cloudbuild.googleapis.com \
  cloudaicompanion.googleapis.com
```

承認するかどうかを聞かれるメッセージがでた場合は、`承認` ボタンをクリックします。

**GUI**: [API ライブラリ](https://console.cloud.google.com/apis/library)

## **ワークステーション用ネットワークの設定**

ワークステーション専用のネットワークを作成します。

<walkthrough-info-message>デフォルトでは `default` ネットワークが使われるため好ましくありません。また今回はセキュリティを高めるために、ワークステーションに Public IP を付与しない設定とします。そのため、ここで Router, NAT も合わせて作成します</walkthrough-info-message>

### **1. VPC ネットワークの作成**

```bash
gcloud compute networks create ws-network \
  --subnet-mode custom
```

### **2. サブネットの作成**

```bash
gcloud compute networks subnets create ws-subnet \
  --network ws-network \
  --region asia-northeast1 \
  --range "192.168.1.0/24"
```

### **3. Cloud Router の作成**

```bash
gcloud compute routers create \
  ws-router \
  --network ws-network \
  --region asia-northeast1
```

### **4. Cloud NAT の作成**

```bash
gcloud compute routers nats create ws-nat \
  --router ws-router \
  --auto-allocate-nat-external-ips \
  --nat-all-subnet-ip-ranges \
  --region asia-northeast1
```

### **5. ワークステーションクラスタの作成**

```bash
gcloud workstations clusters create cluster-handson \
  --network "projects/$GOOGLE_CLOUD_PROJECT/global/networks/ws-network" \
  --subnetwork "projects/$GOOGLE_CLOUD_PROJECT/regions/asia-northeast1/subnetworks/ws-subnet" \
  --region asia-northeast1 \
  --async
```

以下のリンクをクリックし、ワークステーションのクラスタが作成開始 (更新中ステータス) したことを確認します。

**GUI**: [ワークステーションのクラスタ](https://console.cloud.google.com/workstations/clusters)

<walkthrough-info-message>クラスタの作成完了まで最大 20 分程度かかります</walkthrough-info-message>

## **参考: Cloud Shell の接続が途切れてしまったときは?**

一定時間非アクティブ状態になる、またはブラウザが固まってしまったなどで `Cloud Shell` の接続が切れてしまう場合があります。

その場合は `再接続` をクリックした後、以下の対応を行い、チュートリアルを再開してください。

![再接続画面](https://raw.githubusercontent.com/GoogleCloudPlatform/gcp-getting-started-lab-jp/master/workstations_with_generative_ai/images/reconnect_cloudshell.png)

### **1. チュートリアル資材があるディレクトリに移動する**

```bash
cd ~/gcp-getting-started-lab-jp/workstations_with_generative_ai/
```

### **2. チュートリアルを開く**

```bash
teachme tutorial_ja.md
```

途中まで進めていたチュートリアルのページまで `次へ` ボタンを押し、進めてください。

## **基本のワークステーション構成からワークステーションを作成する**

### **1. ワークステーションクラスタ作成完了の確認**

以下のリンクを開き、`cluster-handson` クラスタのステータスが `準備完了` になっていることを確認します。既に開いている場合は `更新` ボタンをクリックします。

**GUI**: [ワークステーションのクラスタ](https://console.cloud.google.com/workstations/clusters)

### **2. ワークステーション構成の作成**

```bash
gcloud workstations configs create codeoss-default \
  --machine-type e2-standard-4 \
  --region asia-northeast1 \
  --cluster cluster-handson \
  --disable-public-ip-addresses \
  --shielded-secure-boot \
  --shielded-vtpm \
  --shielded-integrity-monitoring \
  --container-predefined-image codeoss
```

それぞれ以下の設定を適用しています。

- 仮想マシンタイプ: [e2-standard-4](https://cloud.google.com/compute/docs/general-purpose-machines?hl=ja#e2_machine_types_table)
- disable-public-ip-addresses: ワークステーションに Public IP アドレスを付与しない
- container-predefined-image: Code OSS (Visual Studio Code の OSS 版) のベースイメージを指定
- [Shielded VM](https://cloud.google.com/compute/shielded-vm/docs/shielded-vm?hl=ja) 関連設定: セキュリティ向上に有効

  - shielded-secure-boot
  - shielded-vtpm
  - shielded-integrity-monitoring

**GUI**: [ワークステーションの構成](https://console.cloud.google.com/workstations/configurations)

### **3. ワークステーションの作成**

```bash
gcloud workstations create ws01 \
  --region asia-northeast1 \
  --cluster cluster-handson \
  --config codeoss-default
```

**GUI**: [ワークステーション](https://console.cloud.google.com/workstations/list)

## **開発者としてワークステーションを利用する**

本セクションは前セクションで作成したワークステーションに対して GUI から作業を行います。

Qwiklabs 手順の **開発者としてワークステーションを利用する** のセクションを見ながら作業を行ってください。

## **管理者としてワークステーションを利用する**

本ハンズオンでは、管理者として以下のようなステップを試します。

- コンテナイメージのカスタマイズ
  - Dockerfile を使ったカスタマイズ (共通領域)
  - スクリプトを使ったカスタマイズ (ホームディレクトリ)

### **稼働しているワークステーションを停止する**

無駄なコストがかかるのを避けるため稼働している `ws01` を停止しておきます。

```bash
gcloud workstations stop ws01 \
  --region asia-northeast1 \
  --cluster cluster-handson \
  --config codeoss-default
```

## **コンテナイメージのカスタマイズ**

Dockerfile を使い、カスタムコンテナイメージを作ることで、開発環境のカスタマイズが可能です。

以下が Dockerfile を使ったカスタマイズのポイントです。

- /home 配下 **以外** をカスタマイズできる
- ワークステーション利用中に行った /home 以外の変更は、**再起動でリセットされる** (保存されない)

### **1. Dockerfile の作成**

- Prettier (拡張機能) の組み込み
- Node.js のデフォルトバージョンを 18.x に更新

<walkthrough-info-message>コピー&ペーストして実行してください</walkthrough-info-message>

```shell
mkdir -p codeoss-customized/
cat << EOF > codeoss-customized/Dockerfile
FROM asia-northeast1-docker.pkg.dev/cloud-workstations-images/predefined/code-oss:latest

# Install prettier
RUN wget https://open-vsx.org/api/esbenp/prettier-vscode/10.1.0/file/esbenp.prettier-vscode-10.1.0.vsix \
  && unzip esbenp.prettier-vscode-10.1.0.vsix "extension/*" \
  && mv extension /opt/code-oss/extensions/prettier

# Install Node 18.x
RUN apt-get update \
  && apt-get install -y ca-certificates curl gnupg \
  && mkdir -p /etc/apt/keyrings \
  && curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key \
  | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg \
  && echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_18.x nodistro main" \
  | tee /etc/apt/sources.list.d/nodesource.list \
  && apt update \
  && apt install -y nodejs \
  && rm -rf /var/lib/apt/lists/*
EOF
```

### **2. Docker リポジトリ (Artifact Registry) の作成**

```bash
gcloud artifacts repositories create ws-repo \
  --repository-format docker \
  --location asia-northeast1 \
  --description="Docker repository for Cloud workstations"
```

### **3. コンテナのビルド、プッシュ**

```bash
gcloud builds submit codeoss-customized/ \
  --tag asia-northeast1-docker.pkg.dev/${GOOGLE_CLOUD_PROJECT}/ws-repo/codeoss-customized:v1.0.0
```

## **サービスアカウントの設定**

プライベートなカスタムイメージを利用するには、Docker リポジトリから Pull できる権限を持つサービスアカウントが必要です。

事前構成済みのベースイメージはパブリック公開されているため、サービスアカウントがなしでも利用できました。

### **1. サービスアカウントの作成**

```bash
gcloud iam service-accounts create codeoss-customized-sa \
  --display-name "Service Account for codeoss-customized config"
```

### **2. サービスアカウントへの Docker リポジトリ読み取り権限付与**

```bash
gcloud artifacts repositories add-iam-policy-binding ws-repo \
  --location asia-northeast1 \
  --member serviceAccount:codeoss-customized-sa@${GOOGLE_CLOUD_PROJECT}.iam.gserviceaccount.com \
  --role=roles/artifactregistry.reader
```

## **カスタムイメージ (Dockerfile 利用) を使ったワークステーションの利用**

### **1. ワークステーション構成の新規作成**

カスタマイズしたコンテナイメージと一緒に、サービスアカウントも指定しているところがポイントです。

```bash
gcloud workstations configs create codeoss-customized \
  --machine-type e2-standard-4 \
  --region asia-northeast1 \
  --cluster cluster-handson \
  --disable-public-ip-addresses \
  --shielded-integrity-monitoring \
  --shielded-secure-boot \
  --shielded-vtpm \
  --service-account codeoss-customized-sa@${GOOGLE_CLOUD_PROJECT}.iam.gserviceaccount.com \
  --container-custom-image asia-northeast1-docker.pkg.dev/${GOOGLE_CLOUD_PROJECT}/ws-repo/codeoss-customized:v1.0.0
```

### **2. ワークステーションの作成**

```bash
gcloud workstations create ws-customized \
  --region asia-northeast1 \
  --cluster cluster-handson \
  --config codeoss-customized
```

### **3. カスタマイズしたワークステーションの動作確認**

GUI から作成したワークステーション `ws-customized` を `起動`、立ち上がった後に `開始` し、ブラウザからアクセスします。その後、以下のカスタマイズが入っていることを確認します。

- `Prettier` の拡張機能がインストール済みなこと

  Extensions の一覧から Prettier を検索し確認します

- `Node.js` の 18.x がインストール済みなこと

  ターミナルから下記のコマンドを実行します。ターミナルは Explorer (左上の三本線) > Terminal > New Terminal の順にクリックします。

  ```shell
  node --version
  ```

### **4. ワークステーションの停止**

次のカスタマイズに備え、ワークステーションを停止しておきます。

```bash
gcloud workstations stop ws-customized \
  --region asia-northeast1 \
  --cluster cluster-handson \
  --config codeoss-customized
```

## **チャレンジ問題**

### **Go 言語用拡張機能をプリインストールする**

Go 言語が社内の公式開発言語の１つになっているとします。

ワークステーションの利用ユーザーから Go 言語用の拡張機能 (golang) をプリインストールしておいてほしいと要望があがりました。

今まで学んできたカスタマイズの手順を参考に、作成済みのワークステーション構成 (codeoss-customized) に Go 言語用拡張機能をプリインストールしてみましょう。

**ヒント**

- Dockerfile 内に Go 言語の拡張機能をダウンロードする手続きを記述します
- ダウンロード先は [Go 言語拡張機能ページ](https://open-vsx.org/extension/golang/Go) の DOWNLOAD ボタンのリンクを利用します

## **本番で Cloud Workstations を利用する**

ここまで Cloud Workstations を開発者、管理者目線から利用する方法を学んできました。

しかし、本番で Cloud Workstations を利用する際に検討、意識すべき事項があります。ここからは以下のようなポイントをそれぞれ説明します。

- 開発者個別にワークステーションを払い出す
- 無駄な費用がかからないようにする

## **開発者個別にワークステーションを払い出す**

<walkthrough-info-message>本手順は Qwiklabs から払い出されたアカウントとは**別の** Google アカウント (gmail アカウント) を擬似的に開発者のアカウントとして利用します。アカウントがない場合、こちらのステップはスキップしてください</walkthrough-info-message>

### **1. 開発者にどのような権限を与えるか検討する**

権限を制御することで、ワークステーションを開発者にどのように利用させるかを制御することが可能です。

一般的に以下 2 つの提供形態のいずれかが選ばれます。

1. 管理者がワークステーションを払い出し、開発者はそれを利用する
1. 開発者自身がワークステーションを作成し、利用する

本ステップでは `1. 管理者がワークステーションを払い出し、開発者はそれを利用する` の手順を説明します。`2. 開発者自身がワークステーションを作成し、利用する` を試す場合は次のステップに進んでください。

### **2. 専用のカスタムロールを作成する**

開発者がワークステーションを削除できないようにするためには、専用のカスタムロールが必要です。

<walkthrough-info-message>コピー&ペーストして実行してください</walkthrough-info-message>

```shell
cat << EOF > workstationDeveloper.yaml
title: "Workstations Developer"
description: "Developer who only uses workstations"
stage: "GA"
includedPermissions:
- workstations.operations.get
- workstations.workstations.get
- workstations.workstations.start
- workstations.workstations.stop
- workstations.workstations.update
- workstations.workstations.use
EOF
gcloud iam roles create workstationDeveloper \
  --project ${GOOGLE_CLOUD_PROJECT} \
  --file workstationDeveloper.yaml
```

### **2. 開発者に作成したカスタムロールを付与する**

こちらは GUI から設定します。

1. Cloud Workstations の UI にアクセスします。
1. `ワークステーション` をクリックします。
1. 一覧から `ws-customized` をクリックします。
1. 上のメニューから `ユーザーを追加する` をクリックします。
1. 新しいプリンシパルに開発者のメールアドレスを入力します。
1. ロールにカスタム -> `Workstations Developer` を選択します。
1. `保存` ボタンをクリックします。

### **3. 開発者に Cloud Workstations Operation 閲覧者 の権限を付与する**

`test-developer@gmail.com` を開発者アカウントのメールアドレスに置き換えて実行してください。

```bash
gcloud projects add-iam-policy-binding ${GOOGLE_CLOUD_PROJECT} \
  --member "user:test-developer@gmail.com" \
  --role "roles/workstations.operationViewer"
```

### **4. (開発者) ワークステーションの管理コンソールにアクセスする**

下記コマンドで出力された URL に **開発者アカウント** でアクセスします。

```bash
echo "https://console.cloud.google.com/workstations/list?project=$GOOGLE_CLOUD_PROJECT"
```

先程権限を付与したワークステーションのみが見え、以下の操作ができれば問題なく設定ができています。

- 起動
- 停止

管理者は本手順を繰り返すことで、開発者に安全にワークステーションを利用させることができます。

## **開発者自身がワークステーションを作成し、利用する**

### **1. 開発者に Cloud Workstations 作成者 の権限を付与する**

こちらは GUI から設定します。

1. Cloud Workstations の UI にアクセスします。
1. `ワークステーションの構成` をクリックします。
1. 一覧から `codeoss-customized` をクリックします。
1. 上のメニューから `ユーザーを追加する` をクリックします。
1. 新しいプリンシパルに開発者のメールアドレスを入力します。
1. ロールが `Cloud Workstations Creator` になっていることを確認します。
1. `保存` ボタンをクリックします。

### **2. 開発者に Cloud Workstations Operation 閲覧者 の権限を付与する**

`test-developer@gmail.com` を開発者アカウントのメールアドレスに置き換えて実行してください。

```bash
gcloud projects add-iam-policy-binding ${GOOGLE_CLOUD_PROJECT} \
  --member "user:test-developer@gmail.com" \
  --role "roles/workstations.operationViewer"
```

### **3. (開発者) ワークステーションの管理コンソールにアクセスする**

下記コマンドで出力された URL に **開発者アカウント** でアクセスします。

```bash
echo "https://console.cloud.google.com/workstations/list?project=$GOOGLE_CLOUD_PROJECT"
```

### **4. (開発者) ワークステーションを作成、アクセスする**

1. `+ 作成` をクリックします。
1. `名前` に `my-workstation` と入力します。

   ```shell
   my-workstation
   ```

1. `Configuration` から `codeoss-customized` を選択します。
1. `作成` をクリックします。
1. 作成が完了したら、`START`, `開始` からアクセスできることを確認します。

管理者は本手順を繰り返すことで、開発者に安全にワークステーションを利用させることができます。

## **無駄な費用がかからないようにする**

ワークステーション構成を見直すことで、トータルのコストをおさえる事が可能です。

ここではいくつか有用な設定を示します。

**参考**: [開発環境をカスタマイズする](https://cloud.google.com/workstations/docs/customize-workstation-configurations?hl=ja)

### **1. 仮想マシンのタイプ**

ワークステーション構成作成後に**更新可能**です。

利用可能な仮想マシンタイプは [使用可能なマシンタイプ](https://cloud.google.com/workstations/docs/available-machine-types?hl=ja) を参照してください。

### **2. ブートディスクのサイズ**

**注**: ワークステーション構成作成後は**更新できません**。

ブートディスクのサイズです。デフォルトは 50GB で、最小で 30GB の指定が可能です。

### **3. 永続ディスクのタイプ、サイズ**

**注**: ワークステーション構成作成後は**更新できません**。

永続ディスク (ホームディレクトリ) のディスクタイプ、サイズです。デフォルトは `pd-standard` タイプ、`200GB` が指定されています。

200GB 未満に指定するときは、ディスクタイプに `pd-balanced`, `pd-ssd` のいずれかを指定しなければなりません。

### **4. アイドル時の自動停止時間**

ワークステーション構成作成後に**更新可能**です。

ワークステーションが一定時間アイドル状態になったときに、自動的にストップする機能があります。デフォルトで `120分 (7200s)` が設定されています。

## **Congraturations!**

<walkthrough-conclusion-trophy></walkthrough-conclusion-trophy>

これにて Cloud Workstations, Duet AI を利用した開発者目線でのアプリケーション実行、デプロイ、管理者目線でのカスタマイズ、本番提供にむけたプラクティスの学習が完了しました。

Qwiklabs に戻り、`ラボを終了` ボタンをクリックしハンズオンを終了します。
