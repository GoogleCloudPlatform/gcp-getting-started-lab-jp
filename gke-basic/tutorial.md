<walkthrough-metadata>
  <meta name="title" content="GKE Dojo Basic" />
  <meta name="description" content="Hands-on Dojo GKE Basic" />
  <meta name="component_id" content="103" />
</walkthrough-metadata>

<walkthrough-disable-features toc></walkthrough-disable-features>

# GKE 道場 入門編

## Google Cloud プロジェクトの設定、確認

### **1. 対象の Google Cloud プロジェクトを設定**

ハンズオンを行う Google Cloud プロジェクトのプロジェクト ID を環境変数に設定し、以降の手順で利用できるようにします。 (右辺の [PROJECT_ID] を手動で置き換えてコマンドを実行します)

```bash
export PROJECT_ID=[PROJECT_ID]
```

`プロジェクト ID` は [ダッシュボード](https://console.cloud.google.com/home/dashboard) に進み、左上の **プロジェクト情報** から確認します。

### **2. プロジェクトの課金が有効化されていることを確認する**

```bash
gcloud beta billing projects describe ${PROJECT_ID} | grep billingEnabled
```

**Cloud Shell の承認** という確認メッセージが出た場合は **承認** をクリックします。

出力結果の `billingEnabled` が **true** になっていることを確認してください。**false** の場合は、こちらのプロジェクトではハンズオンが進められません。別途、課金を有効化したプロジェクトを用意し、本ページの #1 の手順からやり直してください。

## **環境準備**

<walkthrough-tutorial-duration duration=10></walkthrough-tutorial-duration>

最初に、ハンズオンを進めるための環境準備を行います。

下記の設定を進めていきます。

- gcloud コマンドラインツール設定
- Google Cloud 機能（API）有効化設定

## **gcloud コマンドラインツール**

Google Cloud は、コマンドライン（CLI）、GUI から操作が可能です。ハンズオンでは主に CLI を使い作業を行いますが、GUI で確認する URL も合わせて掲載します。

### **1. gcloud コマンドラインツールとは?**

gcloud コマンドライン インターフェースは、Google Cloud でメインとなる CLI ツールです。このツールを使用すると、コマンドラインから、またはスクリプトや他の自動化により、多くの一般的なプラットフォーム タスクを実行できます。

たとえば、gcloud CLI を使用して、以下のようなものを作成、管理できます。

- Google Compute Engine 仮想マシン
- Google Kubernetes Engine クラスタ
- Google Cloud SQL インスタンス

**ヒント**: gcloud コマンドラインツールについての詳細は[こちら](https://cloud.google.com/sdk/gcloud?hl=ja)をご参照ください。

### **2. gcloud から利用する Google Cloud のデフォルトプロジェクトを設定**

gcloud コマンドでは操作の対象とするプロジェクトの設定が必要です。操作対象のプロジェクトを設定します。

```bash
gcloud config set project ${PROJECT_ID}
```

承認するかどうかを聞かれるメッセージがでた場合は、`承認` ボタンをクリックします。

### **3. ハンズオンで利用する Google Cloud の API を有効化する**

Google Cloud では利用したい機能ごとに、有効化を行う必要があります。
ここでは、以降のハンズオンで利用する機能を事前に有効化しておきます。


```bash
gcloud services enable cloudbuild.googleapis.com container.googleapis.com artifactregistry.googleapis.com clouddeploy.googleapis.com
```

**GUI**: [API ライブラリ](https://console.cloud.google.com/apis/library?project={{project-id}})

## **4. gcloud コマンドラインツール設定 - リージョン、ゾーン**

コンピュートリソースを作成するデフォルトのリージョン、ゾーンとして、東京 (asia-northeast1/asia-northeast1-c）を指定します。

```bash
gcloud config set compute/region asia-northeast1 && gcloud config set compute/zone asia-northeast1-c
```

## **参考: Cloud Shell の接続が途切れてしまったときは?**

一定時間非アクティブ状態になる、またはブラウザが固まってしまったなどで `Cloud Shell` が切れてしまう、またはブラウザのリロードが必要になる場合があります。その場合は以下の対応を行い、チュートリアルを再開してください。

### **1. チュートリアル資材があるディレクトリに移動する**

```bash
cd ~/gcp-getting-started-lab-jp/gke-basic
```

### **2. チュートリアルを開く**

```bash
teachme tutorial.md
```

### **3. プロジェクト ID を設定する**

```bash
export PROJECT_ID=[PROJECT_ID]
```

### **4. gcloud のデフォルト設定**

```bash
gcloud config set project ${PROJECT_ID} && gcloud config set compute/region asia-northeast1 && gcloud config set compute/zone asia-northeast1-c
```


## Lab00.GKE Autopilot クラスタの作成
<walkthrough-tutorial-duration duration=20></walkthrough-tutorial-duration>

GKE 以下のコマンドを実行し、GKE Autopilot クラスタを作成します。
```bash
gcloud container --project "$PROJECT_ID" clusters create-auto "gke-dojo-cluster" \
--region "asia-northeast1" --release-channel "regular"
```

クラスタの作成には10分〜20分程度の時間がかかります。

## Lab01.サンプルアプリケーションのデプロイ

<walkthrough-tutorial-duration duration=20></walkthrough-tutorial-duration>

クラスタの作成が完了しましたら、サンプルアプリケーションをデプロイします。 [Online Boutique microservices demo](https://github.com/GoogleCloudPlatform/microservices-demo)アプリケーションは、EC サイトをモチーフにしたマイクロサービスアプリケーションとなっています。kuberenetes のマニフェストについては、`lab-01-deploy-sample-app` フォルダのファイルをご確認ください。

### **1. Deployment/Service マニフェストの適用**
以下のコマンドで、マニフェストの適用を行ってください。
実行時 Warning が複数出力されますが、デプロイ自体には問題ございません。

```bash
kubectl apply -f lab-01-deploy-sample-app/
```
以下のコマンドで、現在の Pod および Node のステータスを取得を継続して行います。
Pod の作成に伴い、Node が複製され、Pod がデプロイされる様子が確認できます。
デプロイには3-5分程度の時間がかかります。
```bash
watch -d kubectl get pods,nodes
```

数分後、すべての Pod の Status が Running となることを確認できたら、 `Ctrl-C` でコマンドの実行を終了します。

### **2. 外部 IP アドレスの予約**

アプリケーションの外部公開用 IP アドレスを予約します。

```bash
gcloud compute addresses create gatewayip --global --ip-version IPV4
```

取得した IP アドレスを確認します。

```bash
gcloud compute addresses list
```

出力例
```bash
NAME: gatewayip
ADDRESS/RANGE: [こちらに IPアドレスが記載されます]
TYPE: EXTERNAL
PURPOSE: 
NETWORK: 
REGION: 
SUBNET: 
STATUS: RESERVED
```

### **3. IP アドレスとドメインの設定**

アプリケーションの公開に使用するドメインは、`nip.io`を利用します。以下のコマンドで環境変数として保存しておきます。
`nip.io`はサブドメインに記載した任意の IP アドレスに合わせたレコードを返す DNS サービスです。
今回はこのサービスを利用して、簡易的にドメインを用意します。
本番環境においては、別途ドメインを用意して利用ください。 

```bash
IP_ADDR=$(gcloud compute addresses list --format='value(ADDRESS)' --filter="NAME:gatewayip")
DOMAIN="${IP_ADDR//./-}.nip.io"
```

### **4. Gateway マニフェストの適用**

前の手順で予約した IP アドレスに合わせて、マニフェストファイルの編集が必要です。
以下のコマンドのコマンドを実行してください。

```bash
sed -i "s/x-x-x-x.nip.io/$DOMAIN/g" lab-01-gateway/httproute.yaml
```

編集した Gateway マニフェストを適用し、アプリケーションを外部公開します。

```bash
kubectl apply -f lab-01-gateway/gateway.yaml
kubectl apply -f lab-01-gateway/httproute.yaml
```

### **5. Demo サイトの確認**
Gateway の設定が完了するまで数分かかります。数分後、以下のコマンドでアプリケーションの URL を確認します。
確認した URL をコピーして Chrome などの Web ブラウザのアドレスバーに貼り付けアプリケーションを確認します。

```bash
kubectl get httproutes
```

以下が出力例です。HOSTNAMES に記載されているのが、アプリケーションの URL になります。
```bash
admin_@cloudshell:~ (projectname)$ kubectl get httproutes
NAME             HOSTNAMES                  AGE
frontend-route   ["xxx-xxx-xxx-xxx.nip.io"]   43h
```
Lab01 はこちらで完了となります。

## **Lab02.Balloon Pod の利用による高速なスケーリング**
<walkthrough-tutorial-duration duration=10></walkthrough-tutorial-duration>


手動または HPA 経由でスケールアップすると、新しい Pod がプロビジョニングされますが、予備容量がない場合は、新しいノードがプロビジョニングされるために遅延が発生する可能性があります。
Autopilot モードで迅速にスケールアップするためには、Balloon Pod を利用します。

### **1. Priority Class と Balloon Pod の作成**
まずは、Priority の定義リソースである Priority Class と Balloon Pod を作成します。

```bash
kubectl apply -f lab-02-spare-capacity-balloon/balloon-priority.yaml 
kubectl apply -f lab-02-spare-capacity-balloon/balloon-deploy.yaml 
```

Balloon Pod の作成により、ノードがスケールすることを watch コマンドで動的に確認します。
完了までに数分かかります。

```bash
watch -d kubectl get pods,nodes
```
数分後、すべての Pod と Node の Status が Running となることを確認できたら、 `Ctrl-C` でコマンドの実行を終了します。

### **2. 迅速なスケールアウトの確認**

次に frontend の pod を 1 から 8 へスケールアウトします。

```bash
kubectl scale --replicas=8 deployment frontend
```

Balloon Pod を先に作成していたため、目的の Pod のスケールアウトはスピーディに完了します。一方　Balloon Pod　は優先度が低いため、ノードから削除され、さらなるノードのスケールアウトが始まります。Balloon Pod は追加されたノードに配置されます。
以下のコマンドで一連の流れを確認しましょう。

```bash
watch -n 1 kubectl get pods,nodes
```

数分後、すべての Pod と Node の Status が Running となることを確認できたら、 `Ctrl-C` でコマンドの実行を終了します。

Lab02 はこちらで完了となります。

## **Ex01.Google Cloud サービスによる CI/CD**
<walkthrough-tutorial-duration duration=30></walkthrough-tutorial-duration>

### **0. ２つ目のクラスター作成**
後続で使う 2 つ目のクラスターを作成しておきます。

```bash
gcloud container --project "$PROJECT_ID" clusters create-auto "gke-dojo-cluster-prod" \
--region "asia-northeast1" --release-channel "regular"
```
このクラスタは、本番環境向けクラスタとして扱います。
開発環境クラスタで動作を確認したアプリケーションを本番環境にデプロイするという流れを Cloud Build と Cloud Deploy で実装します。

### **1. 対象のアプリケーション確認**

ローカルにある python アプリケーションを出力して確認してください。
こちらはテキストを出力するシンプルな Flask アプリケーションです。

```bash
cat ex01-cicd/main.py
```

### **2. レポジトリ作成**

以下のコマンドで Flask アプリケーションのコンテナイメージを配置するための Artifact Registry のレポジトリを作成します。
```bash
gcloud artifacts repositories create gke-dojo --repository-format=docker --location=asia-northeast1
```

### **3. Cloud Build によるコンテナイメージの作成**

Cloud Build を利用して、クラウド上でコンテナイメージのビルドを行います。
Cloud Build に含まれている Buildpacks により Dockerfile を書かなくとも、アプリケーションの構成を認識して適切なコンテナイメージを作成することができます。

以下のコマンドで、ビルドを実行します。

```bash
gcloud builds submit --config ex01-cicd/cloudbuild.yaml
```
最終的に`STATUS: SUCCESS`と表示されましたら、ビルド成功です。

### **4. Cloud Deploy による デプロイ**

前の手順で用意した Flask アプリケーションを Kubernetes マニフェストを確認します。

```bash
cat ex01-cicd/k8s/deployment.yaml
```

```bash
cat ex01-cicd/k8s/service.yaml
```

続いて Cloud Deploy にてターゲットとなる GKE クラスタにデプロイするための定義ファイルを確認します。
```bash
cat ex01-cicd/clouddeploy.yaml
```

以下のコマンドで `clouddeploy.yaml` 内の`PROJECT_ID`を実際の環境変数(プロジェクトID)へ置き換えます。
```
sed -i 's/PROJECT_ID/'"$PROJECT_ID"'/g' ex01-cicd/clouddeploy.yaml
```

このファイルを利用して、アプリケーションをデプロイするためのパイプラインを用意します。
```bash
gcloud deploy apply --file=ex01-cicd/clouddeploy.yaml --region asia-northeast1 --project=$PROJECT_ID
```

Cloud Deploy ではテンプレートとなる Kubernetes のマニフェストを環境に合わせてレンダリングするために、Skaffold を利用します。
ここでは、コンテナイメージを今回のアプリケーションに書き換えるのみのため、シンプルなコンフィグを作成しています。

```bash
cat ex01-cicd/skaffold.yaml
```
それでは、デプロイを開始します。以下のコマンドでリリースを作成します。

```bash
cd ex01-cicd/
gcloud deploy releases create release01 \
    --delivery-pipeline=gke-dojo \
    --region=asia-northeast1 \
    --skaffold-file=skaffold.yaml \
    --source=./ \
    --images=gke-dojo="asia-northeast1-docker.pkg.dev/$PROJECT_ID/gke-dojo/gke-dojo-app:v1"
```
数分の経過後、[Cloud Deploy コンソール](https://console.cloud.google.com/deploy)に最初のリリースの詳細が表示され、それが最初のクラスタに正常にデプロイされたことが確認できます。

[Kubernetes Engine コンソール](https://console.cloud.google.com/kubernetes)に移動して、アプリケーションのエンドポイントを探します。
左側のメニューバーより Services & Ingress を選択し、gke-dojo-service という名前のサービスを見つけます。
Endpoints 列に IP アドレスが表示され、リンクとなっているため、それをクリックして、アプリケーションが期待どおりに動作していることを確認します。

ステージングでテストしたので、本番環境に昇格する準備が整いました。
[Cloud Deploy コンソール](https://console.cloud.google.com/deploy)に戻ります。
デリバリーパイプラインの一覧から、`gke-dojo` をクリックします。
すると、`プロモート` という青いリンクが表示されています。リンクをクリックし、内容を確認した上で、下部の`プロモート`ボタンをクリックします。すると本番環境へのデプロイを実施されます。

先ほどの手順と同様に本番環境のアプリケーションの動作を確認できましたら、本ハンズオンは終了です。

## Configurations!
これで、GKE での基本的なアプリケーションのデプロイと操作、Autopilot Mode におけるスケールの方法、CI/CD の操作を学ぶことができました。引き続き応用編もお楽しみ下さい。