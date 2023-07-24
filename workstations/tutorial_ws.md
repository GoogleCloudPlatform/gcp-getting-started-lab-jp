# **Cloud Workstations ハンズオン**

本ハンズオンでは、Google Cloud でカスタマイズ可能で安全なマネージド開発環境を提供する [Cloud Workstations](https://cloud.google.com/workstations?hl=ja) の様々な機能を体験します。

- ワークステーション用ネットワークの設定
- 基本のワークステーション構成からワークステーションを作成する
- 開発者としてワークステーションを利用する
  - 拡張機能 (Extensions) をインストール
  - アプリケーションをクローンする
  - アプリケーションを実行する
  - Cloud Code を使い Cloud Run にデプロイする
- 管理者としてワークステーションを利用する
  - コンテナイメージのカスタマイズ
  - ワークステーション構成の新規作成
  - ホームディレクトリのカスタマイズ
- 本番で Cloud Workstations を利用する
  - 開発者個別にワークステーションを払い出す
  - カスタムコンテナイメージをセキュアに保つ
  - 無駄な費用がかからないようにする

## Google Cloud プロジェクトの設定、確認

### **1. 対象の Google Cloud プロジェクトを設定**

ハンズオンを行う Google Cloud プロジェクトのプロジェクト ID を環境変数に設定し、以降の手順で利用できるようにします。 (右辺の `testproject` を手動で置き換えてコマンドを実行します)

```bash
export PROJECT_ID=testproject
```

`プロジェクト ID` は [ダッシュボード](https://console.cloud.google.com/home/dashboard) に進み、左上の **プロジェクト情報** から確認します。

### **2. プロジェクトの課金が有効化されていることを確認する**

```bash
gcloud beta billing projects describe ${PROJECT_ID} \
  | grep billingEnabled
```

**Cloud Shell の承認** という確認メッセージが出た場合は **承認** をクリックします。

出力結果の `billingEnabled` が **true** になっていることを確認してください。

**false** の場合は、こちらのプロジェクトではハンズオンが**進められません**。別途、課金を有効化したプロジェクトを用意し、本ページの #1 の手順からやり直してください。

## **環境準備**

最初に、ハンズオンを進めるための環境準備を行います。

下記の設定を進めていきます。

- gcloud コマンドラインツール設定
- Google Cloud 機能（API）有効化設定

## **gcloud コマンドラインツール**

Google Cloud は、コマンドライン（CLI）、GUI から操作が可能です。ハンズオンでは作業の自動化を目的に主に CLI を使い作業を行います。

### **1. gcloud コマンドラインツールとは?**

gcloud コマンドライン インターフェースは、Google Cloud でメインとなる CLI ツールです。これを使用すると、多くの一般的なプラットフォーム タスクを様々なツールと組み合わせて実行することができます。

たとえば、gcloud CLI を使用して、以下のようなものを作成、管理できます。

- Google Compute Engine 仮想マシン
- Google Kubernetes Engine クラスタ

**ヒント**: gcloud コマンドラインツールについての詳細は[こちら](https://cloud.google.com/sdk/gcloud?hl=ja)をご参照ください。

### **2. gcloud から利用する Google Cloud のデフォルトプロジェクトを設定**

gcloud コマンドでは操作の対象とするプロジェクトの設定が必要です。操作対象のプロジェクトを設定します。

```bash
gcloud config set project ${PROJECT_ID}
```

承認するかどうかを聞かれるメッセージがでた場合は、`承認` ボタンをクリックします。

## **Google Cloud 環境設定**

Google Cloud では利用したい機能（API）ごとに、有効化を行う必要があります。

ここでは、以降のハンズオンで利用する機能を事前に有効化しておきます。

```bash
gcloud services enable workstations.googleapis.com \
  artifactregistry.googleapis.com \
  cloudbuild.googleapis.com \
  run.googleapis.com
```

<walkthrough-info-message>アプリケーションを Cloud Run にデプロイする手順を試すため、Cloud Run を有効化しています。Cloud Workstations の利用には必要ありません。</walkthrough-info-message>

**GUI**: [API ライブラリ](https://console.cloud.google.com/apis/library)

## **ワークステーション用ネットワークの設定**

ワークステーション用のネットワークを作成します。

<walkthrough-info-message>デフォルトでは `default` ネットワークが使わるため、好ましくありません。また今回はセキュリティを高めるため、ワークステーションに Public IP を付与しない設定とします。そのため、ここで Router, NAT も合わせて作成します</walkthrough-info-message>

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
  --network "projects/$PROJECT_ID/global/networks/ws-network" \
  --subnetwork "projects/$PROJECT_ID/regions/asia-northeast1/subnetworks/ws-subnet" \
  --region asia-northeast1 \
  --async
```

<walkthrough-info-message>クラスタの作成完了まで最大 20 分程度かかります</walkthrough-info-message>

## **参考: Cloud Shell の接続が途切れてしまったときは?**

一定時間非アクティブ状態になる、またはブラウザが固まってしまったなどで `Cloud Shell` が切れてしまいブラウザのリロードが必要になる場合があります。その場合は再接続、リロードなどを実施後、以下の対応を行い、チュートリアルを再開してください。

### **1. チュートリアル資材があるディレクトリに移動する**

```bash
cd ~/gcp-getting-started-lab-jp/workstations/
```

### **2. チュートリアルを開く**

```bash
teachme tutorial_ws.md
```

### **3. プロジェクト ID を設定する**

ハンズオンを行う Google Cloud プロジェクトのプロジェクト ID を環境変数に設定し、以降の手順で利用できるようにします。 (右辺の `testproject` を手動で置き換えてコマンドを実行します)

```bash
export PROJECT_ID=testproject
```

### **4. gcloud のデフォルト設定**

```bash
gcloud config set project ${PROJECT_ID}
```

途中まで進めていたチュートリアルのページまで `Next` ボタンを押し、進めてください。

## **基本のワークステーション構成からワークステーションを作成する**

### **1. ワークステーション構成の作成**

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

### **2. ワークステーションの作成**

```bash
gcloud workstations create ws01 \
  --region asia-northeast1 \
  --cluster cluster-handson \
  --config codeoss-default
```

**GUI**: [ワークステーション](https://console.cloud.google.com/workstations/list)

## **開発者としてワークステーションを利用する**

本セクションは前セクションで作成したワークステーションに対して GUI から作業を行います。

配布した資料の **開発者としてワークステーションを利用する** のセクションを見ながら作業を行ってください。

## **管理者としてワークステーションを利用する**

本ハンズオンでは、管理者として以下のようなステップを試します。

- コンテナイメージのカスタマイズ
  - Dockerfile を使ったカスタマイズ (共通領域)
  - スクリプトを使ったカスタマイズ (ホームディレクトリ)

### **稼働しているワークステーションを停止する**

無駄なコストがかかるのを避けるため稼働している `ws01` を STOP しておきます。

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
RUN wget https://open-vsx.org/api/esbenp/prettier-vscode/9.19.0/file/esbenp.prettier-vscode-9.19.0.vsix && \
  unzip esbenp.prettier-vscode-9.19.0.vsix "extension/*" && \
  mv extension /opt/code-oss/extensions/prettier

# Install Node 18.x
RUN curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
RUN apt update && apt install -y \
    nodejs \
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
  --tag asia-northeast1-docker.pkg.dev/${PROJECT_ID}/ws-repo/codeoss-customized:v1.0.0 \
  --machine-type e2-highcpu-8
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
  --member serviceAccount:codeoss-customized-sa@${PROJECT_ID}.iam.gserviceaccount.com \
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
  --service-account codeoss-customized-sa@${PROJECT_ID}.iam.gserviceaccount.com \
  --container-custom-image asia-northeast1-docker.pkg.dev/${PROJECT_ID}/ws-repo/codeoss-customized:v1.0.0
```

### **2. ワークステーションの作成**

```bash
gcloud workstations create ws-customized \
  --region asia-northeast1 \
  --cluster cluster-handson \
  --config codeoss-customized
```

### **3. カスタマイズしたワークステーションの動作確認**

GUI から作成したワークステーション `ws-customized` を `START`, `LAUNCH` し、ブラウザからアクセスします。その後、以下のカスタマイズが入っていることを確認します。

- `Prettier` の拡張機能がインストール済みなこと

  Extensions の一覧から Prettier を検索し確認します

- `Node.js` の 18.x がインストール済みなこと

  Terminal から下記のコマンドを実行します

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

## **ホームディレクトリのカスタマイズ**

### **1. カスタマイズスクリプトの作成**

<walkthrough-info-message>コピー&ペーストして実行してください</walkthrough-info-message>

```shell
mkdir -p codeoss-customized/
cat << EOF > codeoss-customized/200_clone_nodejs_samples.sh
#!/bin/bash

cd /home/user
if [ ! -d "nodejs-doc-samples" ]; then
  git clone https://github.com/GoogleCloudPlatform/nodejs-docs-samples.git
fi
EOF
chmod +x codeoss-customized/200_clone_nodejs_samples.sh
```

### **2. Dockerfile の更新**

<walkthrough-info-message>コピー&ペーストして実行してください</walkthrough-info-message>

```shell
cat << EOF > codeoss-customized/Dockerfile
FROM asia-northeast1-docker.pkg.dev/cloud-workstations-images/predefined/code-oss:latest

# Install prettier
RUN wget https://open-vsx.org/api/esbenp/prettier-vscode/9.19.0/file/esbenp.prettier-vscode-9.19.0.vsix && \
  unzip esbenp.prettier-vscode-9.19.0.vsix "extension/*" && \
  mv extension /opt/code-oss/extensions/prettier

# Install Node 18.x
RUN curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
RUN apt update && apt install -y \
    nodejs \
 && rm -rf /var/lib/apt/lists/*

COPY 200_clone_nodejs_samples.sh /etc/workstation-startup.d/
EOF
```

### **3. コンテナのビルド、プッシュ**

```bash
gcloud builds submit codeoss-customized/ \
  --tag asia-northeast1-docker.pkg.dev/${PROJECT_ID}/ws-repo/codeoss-customized:v2.0.0 \
  --machine-type e2-highcpu-8
```

### **4. ワークステーション構成の更新**

今回は新規作成ではなく、カスタムコンテナイメージを新しいバージョン (v2.0.0) に更新しています。

```bash
gcloud workstations configs update codeoss-customized \
  --region asia-northeast1 \
  --cluster cluster-handson \
  --container-custom-image asia-northeast1-docker.pkg.dev/${PROJECT_ID}/ws-repo/codeoss-customized:v2.0.0
```

### **5. カスタマイズの動作確認**

GUI から更新したワークステーション構成に紐づいているワークステーション `ws-customized` を `START`, `LAUNCH` し、ブラウザからアクセスします。その後、以下のカスタマイズが入っていることを確認します。

- Home ディレクトリ配下に `nodejs-docs-samples` がクローンされている

  Terminal から `ls` コマンドを実行し確認します

## **チャレンジ問題**

### **Python 用拡張機能をプリインストールする**

Python が社内の公式開発言語の１つになっているとします。

ワークステーションの利用ユーザーから Python 用の拡張機能 (ms-python) をプリインストールしておいてほしいと要望があがりました。

今まで学んできたカスタマイズの手順を参考に、作成済みのワークステーション構成 (codeoss-customized) に Python 用拡張機能をプリインストールしてみましょう。

## **本番で Cloud Workstations を利用する**

ここまで Cloud Workstations を開発者、管理者目線から利用する方法を学んできました。

しかし、本番で Cloud Workstations を利用する際に検討、意識すべき事項があります。ここからは以下のようなポイントをそれぞれ説明します。

- 開発者個別にワークステーションを払い出す
- カスタムコンテナイメージをセキュアに保つ
- 無駄な費用がかからないようにする

## **開発者個別にワークステーションを払い出す**

<walkthrough-info-message>本手順は作業している Google アカウントとは**別の** Google アカウントを擬似的に開発者のアカウントとして利用します。アカウントがない場合、こちらのステップはスキップしてください</walkthrough-info-message>

### **1. 開発者にどのような権限を与えるか検討する**

今回は管理者がワークステーションクラスタ、ワークステーション構成を管理し、開発者は個別に割り当てられたワークステーション構成を使いワークステーションを自身で作成、管理することとします。

- 管理者
  - ワークステーションクラスタを作成、編集、削除
  - ワークステーション構成を作成、編集、削除
  - ワークステーションを作成、編集、削除
  - 開発者にワークステーションを作成する権限を付与
- 開発者
  - 割り当てられたワークステーション構成を使い、ワークステーションを作成、編集、削除

### **2. 開発者に Cloud Workstations 作成者 の権限を付与する**

こちらは GUI から設定します。

1. Cloud Workstations の UI にアクセスします。
1. `ワークステーションの構成` をクリックします。
1. 一覧から `codeoss-customized` をクリックします。
1. `編集` をクリックします。
1. `Basic information`, `Machine settings`, `Environment settings` は何も修正せず、最下部の `続行` をクリックします。
1. `IAM Policy` の `ユーザー` に開発者のメールアドレスを入力し、`保存` ボタンをクリックします。

### **3. 開発者に Cloud Workstations Operation 閲覧者 の権限を付与する**

`test-developer@gmail.com` を開発者アカウントのメールアドレスに置き換えて実行してください。

```bash
gcloud projects add-iam-policy-binding ${PROJECT_ID} \
  --member "user:test-developer@gmail.com" \
  --role "roles/workstations.operationViewer"
```

### **4. (開発者) ワークステーションの管理コンソールにアクセスする**

下記コマンドで出力された URL に **開発者アカウント** でアクセスします。

```bash
echo "https://console.cloud.google.com/workstations/list?project=$PROJECT_ID"
```

### **5. (開発者) ワークステーションを作成、アクセスする**

1. `+ 作成` をクリックします。
1. `名前` に `developer-ws` と入力します。

   ```shell
   ws-developer
   ```

1. `Configuration` から `codeoss-customized` を選択します。
1. `作成` をクリックします。
1. 作成が完了したら、`START`, `LAUNCH` からアクセスできることを確認します。

管理者は本手順を繰り返すことで、開発者に安全にワークステーションを利用させることができます。

## **カスタムコンテナイメージをセキュアに保つ**

カスタムコンテナイメージをセキュアに保つには、定期的にビルドをし直す必要があります。

Google が提供している [事前構成されたベースイメージ](https://cloud.google.com/workstations/docs/preconfigured-base-images?hl=ja) は、定期的にセキュリティ更新を含むアップデートが行われています。

そのため、これらのイメージ (の latest) をそのまま使い続ける場合、ワークステーションが停止、起動するときに自動的に最新のイメージが使われます。

しかし、今回行った手順のように、コンテナをカスタマイズした場合、ビルドした段階でのベースイメージで固定されてしまうため、カスタムイメージも定期的にビルド (ベースイメージの更新を取り込む) 必要があります。

詳細は [コンテナ イメージの再ビルドを自動化してベースイメージの更新を同期する](https://cloud.google.com/workstations/docs/tutorial-automate-container-image-rebuild?hl=ja) を参照してください。

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

ワークステーションが一定時間アイドル状態になったときに、自動的にストップする機能があります。デフォルトで `20分 (1200s)` が設定されています。

## **Congraturations!**

<walkthrough-conclusion-trophy></walkthrough-conclusion-trophy>

これにて Cloud Workstations を利用した開発者目線でのアプリケーション実行、デプロイ、管理者目線でのカスタマイズ、本番提供の Tips 学習が完了しました。

デモで使った資材が不要な方は、次の手順でクリーンアップを行って下さい。

## **クリーンアップ（プロジェクトを削除）**

ハンズオン用に利用したプロジェクトを削除し、コストがかからないようにします。

### **1. Google Cloud のデフォルトプロジェクト設定の削除**

```bash
gcloud config unset project
```

### **2. プロジェクトの削除**

```bash
gcloud projects delete ${PROJECT_ID}
```

### **3. ハンズオン資材の削除**

```bash
cd $HOME && rm -rf gcp-getting-started-lab-jp gopath
```
