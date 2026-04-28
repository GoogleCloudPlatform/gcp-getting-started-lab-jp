<walkthrough-metadata>
  <meta name="title" content="GKE Dojo Basic" />
  <meta name="description" content="Hands-on Dojo GKE Basic" />
  <meta name="component_id" content="103" />
</walkthrough-metadata>

<walkthrough-disable-features toc></walkthrough-disable-features>

# GKE 道場 入門編

## Google Cloud プロジェクトの設定、確認

### **1. 対象の Google Cloud プロジェクトを設定**

ハンズオンを行う Google Cloud プロジェクトのプロジェクト ID とプロジェクト番号を環境変数に設定し、以降の手順で利用できるようにします。 

プロジェクトIDの設定
```
export PROJECT_ID=$(gcloud projects list --filter="projectId ~ '^qwiklabs-' AND projectId != 'qwiklabs-resources'" --format="value(projectId)" | head -n 1)
export PROJECT_NUMBER=$(gcloud projects describe $PROJECT_ID --format="value(projectNumber)")
echo $PROJECT_ID
echo $PROJECT_NUMBER
```
**Cloud Shell の承認** という確認メッセージが出た場合は **承認** をクリックします。

こちらのような形式で表示されれば、正常に設定されています。（ID と番号自体は環境個別になります）
```
qwiklabs-gcp-01-3c69409e1eb8
180622292206
```

`プロジェクト ID` は [ダッシュボード](https://console.cloud.google.com/home/dashboard) に進み、左上の **プロジェクト情報** から確認します。


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
cd ~/gcp-getting-started-lab-jp/gke-basics-2026
```

### **2. チュートリアルを開く**

```bash
teachme tutorial.md
```

### **3. プロジェクト ID とプロジェクト番号を設定する**

```
export PROJECT_ID=$(gcloud projects list --filter="projectId ~ '^qwiklabs-' AND projectId != 'qwiklabs-resources'" --format="value(projectId)" | head -n 1)
export PROJECT_NUMBER=$(gcloud projects describe $PROJECT_ID --format="value(projectNumber)")
echo $PROJECT_ID
echo $PROJECT_NUMBER
```

### **4. gcloud のデフォルト設定**

```bash
gcloud config set project ${PROJECT_ID} && gcloud config set compute/region asia-northeast1 && gcloud config set compute/zone asia-northeast1-c
```


## **Lab00.GKE Autopilot クラスタの作成**
<walkthrough-tutorial-duration duration=20></walkthrough-tutorial-duration>

以下のコマンドを実行し、GKE Autopilot クラスタを作成します。
```bash
gcloud container --project "$PROJECT_ID" clusters create-auto "gke-dojo-cluster" \
--region "asia-northeast1" --release-channel "regular"
```

クラスタの作成には10分〜20分程度の時間がかかります。

## **Lab01.サンプルアプリケーションのデプロイ**

<walkthrough-tutorial-duration duration=20></walkthrough-tutorial-duration>

クラスタの作成が完了しましたら、サンプルアプリケーションをデプロイします。

### **1. Deployment/Service マニフェストの適用**
まず、クラスタへの接続情報を取得します。
```bash
gcloud container clusters get-credentials gke-dojo-cluster --region asia-northeast1 --project ${PROJECT_ID}
```

以下のコマンドで、マニフェストの適用を行ってください。
実行時 Warning が複数出力されますが、デプロイ自体には問題ございません。

```bash
kubectl apply -f lab-01/app/
```
以下のコマンドで、現在の Pod および Node のステータスを取得を継続して行います。
Pod の作成に伴い、Node が複製され、Pod がデプロイされる様子が確認できます。
デプロイには 2,3 分程度の時間がかかります。
```bash
watch -d kubectl get pods,nodes,svc
```

数分後、Pod の Status が Running となることを確認できたら、 `Ctrl-C` でコマンドの実行を終了します。

### **2. Demo サイトの確認**
ロードバランサーの設定が完了するまで数分かかります。数分後、以下のコマンドでアプリケーションの URL を確認します。
確認した URL をコピーして Chrome などの Web ブラウザのアドレスバーに貼り付けアプリケーションを確認します。
なお、設定が完了するまでの数分間（場合によってはそれ以上）は、Connection reset by peer のエラーが出力されます。
その場合は、さらにしばらくお待ちください。

```bash
kubectl get svc | grep LoadBalancer | awk '{print "http://"$4}'
```

Lab01 はこちらで完了となります。

## **Lab02.Balloon Pod の利用による高速なスケーリング**
<walkthrough-tutorial-duration duration=10></walkthrough-tutorial-duration>


手動または HPA 経由でスケールアップすると、新しい Pod がプロビジョニングされますが、予備容量がない場合は、新しいノードがプロビジョニングされるために遅延が発生する可能性があります。
Autopilot モードで迅速にスケールアップするためには、Balloon Pod を利用します。

### **1. Priority Class と Balloon Pod の作成**
まずは、Priority の定義リソースである Priority Class と Balloon Pod を作成します。

```bash
kubectl apply -f lab-02/balloon-priority.yaml 
kubectl apply -f lab-02/balloon-deploy.yaml 
```

Balloon Pod の作成により、ノードがスケールすることを watch コマンドで動的に確認します。
完了までに数分かかります。

```bash
watch -d kubectl get pods,nodes
```
数分後、すべての Pod と Node の Status が Running となることを確認できたら、 `Ctrl-C` でコマンドの実行を終了します。

### **2. 迅速なスケールアウトの確認**

次に frontend の pod を 1 から 4 へスケールアウトします。

```bash
kubectl scale --replicas=4 deployment helloweb
```

Balloon Pod を先に作成していたため、目的の Pod のスケールアウトはスピーディに完了します。一方　Balloon Pod　は優先度が低いため、ノードから削除され、さらなるノードのスケールアウトが始まります。Balloon Pod は追加されたノードに配置されます。
以下のコマンドで一連の流れを確認しましょう。

```bash
watch -n 1 kubectl get pods,nodes
```

数分後、すべての Pod と Node の Status が Running となることを確認できたら、 `Ctrl-C` でコマンドの実行を終了します。

Lab02 はこちらで完了となります。

次の内容に入る前に不要なリソースを削除します。
```bash
kubectl delete -f lab-02/balloon-priority.yaml 
kubectl delete -f lab-02/balloon-deploy.yaml 
kubectl delete deployment helloweb
kubectl delete svc helloweb-lb
```

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
cat ~/gcp-getting-started-lab-jp/gke-basics-2026/lab-ex01/main.py
```

### **2. レポジトリ作成**

以下のコマンドで Flask アプリケーションのコンテナイメージを配置するための Artifact Registry のレポジトリを作成します。
```bash
gcloud artifacts repositories create gke-dojo --repository-format=docker --location=asia-northeast1
```

### **3. Cloud Build によるコンテナイメージの作成**

Cloud Build を利用して、クラウド上でコンテナイメージのビルドを行います。
Cloud Build に含まれている Buildpacks により Dockerfile を書かなくとも、アプリケーションの構成を認識して適切なコンテナイメージを作成することができます。

以下のコマンドで、ディレクトリを移動します。

```bash
cd ~/gcp-getting-started-lab-jp/gke-basics-2026/lab-ex01
```
移動後、ビルドを実行します。

```bash
gcloud builds submit --config cloudbuild.yaml
```
最終的に`STATUS: SUCCESS`と表示されましたら、ビルド成功です。


### **4. Cloud Deploy による デプロイ**

前の手順で用意した Flask アプリケーションを Kubernetes マニフェストを確認します。

```bash
cat ~/gcp-getting-started-lab-jp/gke-basics-2026/lab-ex01/k8s/deployment.yaml
```

```bash
cat ~/gcp-getting-started-lab-jp/gke-basics-2026/lab-ex01/k8s/service.yaml
```

続いて Cloud Deploy にてターゲットとなる GKE クラスタにデプロイするための定義ファイルを確認します。
```bash
cat ~/gcp-getting-started-lab-jp/gke-basics-2026/lab-ex01/clouddeploy.yaml
```

以下のコマンドで `clouddeploy.yaml` 内の`PROJECT_ID`を実際の環境変数(プロジェクトID)へ置き換えます。
```
sed -i 's/PROJECT_ID/'"$PROJECT_ID"'/g' ~/gcp-getting-started-lab-jp/gke-basics-2026/lab-ex01/clouddeploy.yaml
```

このファイルを利用して、アプリケーションをデプロイするためのパイプラインを用意します。
```
cd ~/gcp-getting-started-lab-jp/gke-basics-2026/lab-ex01;
gcloud deploy apply --file=clouddeploy.yaml --region asia-northeast1 --project=$PROJECT_ID
```

Cloud Deploy ではテンプレートとなる Kubernetes のマニフェストを環境に合わせてレンダリングするために、Skaffold を利用します。
ここでは、コンテナイメージを今回のアプリケーションに書き換えるのみのため、シンプルなコンフィグを作成しています。

```bash
cat ~/gcp-getting-started-lab-jp/gke-basics-2026/lab-ex01/skaffold.yaml
```
それでは、デプロイを開始します。以下のコマンドでリリースを作成します。

```
cd ~/gcp-getting-started-lab-jp/gke-basics-2026/lab-ex01;
gcloud deploy releases create release01 \
    --delivery-pipeline=gke-dojo \
    --region=asia-northeast1 \
    --skaffold-file=skaffold.yaml \
    --source=./ \
    --images=gke-dojo="asia-northeast1-docker.pkg.dev/$PROJECT_ID/gke-dojo/gke-dojo-app:v1"
```
数分の経過後、[Cloud Deploy コンソール](https://console.cloud.google.com/deploy)に最初のリリースの詳細が表示され、それが最初のクラスタに正常にデプロイされたことが確認できます。

[Kubernetes Engine コンソール](https://console.cloud.google.com/kubernetes)に移動して、アプリケーションのエンドポイントを探します。
左側のメニューバーより Gateways, Services & Ingress を選択し、Services のタブ中の gke-dojo-service という名前のサービスを見つけます。
Endpoints 列に IP アドレスが表示され、リンクとなっているため、それをクリックして、アプリケーションが期待どおりに動作していることを確認します。

ステージングでテストしたので、本番環境に昇格する準備が整いました。
[Cloud Deploy コンソール](https://console.cloud.google.com/deploy)に戻ります。
デリバリーパイプラインの一覧から、`gke-dojo` をクリックします。
すると、`プロモート` という青いリンクが表示されています。リンクをクリックし、内容を確認した上で、下部の`プロモート`ボタンをクリックします。すると本番環境へのデプロイを実施されます。

先ほどの手順と同様に本番環境のアプリケーションの動作を確認できましたら、本ハンズオンは終了です。

## **Ex02. KEDA によるイベント駆動スケーリングと Scale-to-Zero**

<walkthrough-tutorial-duration duration=30></walkthrough-tutorial-duration>

このラボでは、KEDA (Kubernetes Event-Driven Autoscaling) を GKE Autopilot クラスタにインストールし、Pub/Sub のメッセージ数に応じた自動スケーリングと **Scale-to-Zero** を体験します。

このラボで学ぶこと:
- KEDA のインストールと Workload Identity 連携
- Pub/Sub ベースの Scale-to-Zero

### **0. 事前準備 — API の有効化**

KEDA が利用する Pub/Sub と Cloud Monitoring の API を有効化します。

```bash
gcloud services enable pubsub.googleapis.com monitoring.googleapis.com
```

GKE クラスタへの接続を確認します（Lab00 で作成したクラスタを使用します）。

```bash
gcloud container clusters get-credentials gke-dojo-cluster --region asia-northeast1 --project ${PROJECT_ID}
```

### **1. KEDA のインストール**

Helm を使用して KEDA をインストールします。

```bash
helm repo add kedacore https://kedacore.github.io/charts
helm repo update
helm install keda kedacore/keda --create-namespace --namespace keda
```

インストールが完了するまで待ちます。

```bash
kubectl get pods -n keda -w
```

`keda-operator` と `keda-operator-metrics-apiserver` の 2 つの Pod が Running になったら `Ctrl-C` で終了します。

### **2. Workload Identity の設定**

KEDA Operator が Cloud Monitoring API にアクセスするための IAM バインディングを設定します。Autopilot では Workload Identity がデフォルトで有効なので、クラスタ側の追加設定は不要です。

```bash
gcloud projects add-iam-policy-binding projects/${PROJECT_ID} \
  --role roles/monitoring.viewer \
  --member=principal://iam.googleapis.com/projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${PROJECT_ID}.svc.id.goog/subject/ns/keda/sa/keda-operator \
  --condition=None
```

### **3. Pub/Sub トピックとサブスクリプションの作成**

KEDA がスケーリング判断に使用する Pub/Sub リソースを作成します。

```bash
gcloud pubsub topics create keda-echo
gcloud pubsub subscriptions create keda-echo-read --topic=keda-echo
```

ワーカー Pod が Pub/Sub メッセージを読み取るための IAM バインディングも設定します。

```bash
gcloud projects add-iam-policy-binding projects/${PROJECT_ID} \
  --role=roles/pubsub.subscriber \
  --member=principal://iam.googleapis.com/projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${PROJECT_ID}.svc.id.goog/subject/ns/keda-pubsub/sa/keda-pubsub-sa \
  --condition=None
```

### **4. ワーカー Deployment のデプロイ**

Pub/Sub からメッセージを取得して処理するサンプルワーカーをデプロイします。

まず、ワーカーアプリケーションのコンテナイメージをビルドします。このアプリは Pub/Sub サブスクリプションからメッセージを取得し、3 秒かけて処理した後に確認応答（Ack）を送信するシンプルな Python プログラムです。

```bash
cat ~/gcp-getting-started-lab-jp/gke-basics-2026/lab-ex02/app/main.py
```

Artifact Registry にイメージをビルド＆プッシュします（Ex01 で作成したリポジトリを使用します）。

```
cd ~/gcp-getting-started-lab-jp/gke-basics-2026/lab-ex02;
gcloud builds submit app/ \
  --tag asia-northeast1-docker.pkg.dev/${PROJECT_ID}/gke-dojo/keda-pubsub-worker:v1
```

ビルドが完了したら、マニフェスト内の `PROJECT_ID` を実際のプロジェクト ID に置き換えます。

```bash
cd ~/gcp-getting-started-lab-jp/gke-basics-2026/lab-ex02;
sed -i 's/PROJECT_ID/'"$PROJECT_ID"'/g' pubsub-workload.yaml
```

マニフェストを確認します。

```bash
cat ~/gcp-getting-started-lab-jp/gke-basics-2026/lab-ex02/pubsub-workload.yaml
```

Namespace `keda-pubsub`、ServiceAccount `keda-pubsub-sa` が作成され、先ほどビルドした Pub/Sub ワーカーの Deployment がデプロイされます。

デプロイを実行します。

```
cd ~/gcp-getting-started-lab-jp/gke-basics-2026/lab-ex02;
kubectl apply -f pubsub-workload.yaml
```

Pod が Running になるまで待ちます。

```bash
kubectl get pods -n keda-pubsub -w
```

Running になったら `Ctrl-C` で終了します。

### **5. ScaledObject の作成 — Pub/Sub による Scale-to-Zero**

ここが KEDA の核心部分です。ScaledObject を作成し、Pub/Sub のメッセージ数に応じたスケーリングと Scale-to-Zero を設定します。

まず、マニフェスト内の `PROJECT_ID` を実際のプロジェクト ID に置き換えます。

```
cd ~/gcp-getting-started-lab-jp/gke-basics-2026/lab-ex02;
sed -i 's/PROJECT_ID/'"$PROJECT_ID"'/g' keda-scaledobject.yaml
```

マニフェストの内容を確認しましょう。

```bash
cat ~/gcp-getting-started-lab-jp/gke-basics-2026/lab-ex02/keda-scaledobject.yaml
```

注目すべきポイント:
- `minReplicaCount: 0` — **Scale-to-Zero を有効化**
- `maxReplicaCount: 5` — 最大 5 Pod まで
- `pollingInterval: 10` — 10 秒ごとにメッセージ数をチェック
- `cooldownPeriod: 60` — メッセージがなくなって 60 秒後に 0 にスケールダウン（ハンズオン用に短めに設定）
- `type: gcp-pubsub` — Pub/Sub Scaler を使用
- `podIdentity: provider: gcp` — Workload Identity で認証

ScaledObject を適用します。

```
cd ~/gcp-getting-started-lab-jp/gke-basics-2026/lab-ex02;
kubectl apply -f keda-scaledobject.yaml
```

<walkthrough-caution>
gcp-pubsub Scaler の制限事項

KEDA の gcp-pubsub Scaler は、Pub/Sub API を直接参照するのではなく **Cloud Monitoring（Stackdriver）API** を経由してメッセージ数を取得しています。このため、以下の制限があります:

1. **メトリクス伝播に 2〜5 分かかる**: メッセージが Pub/Sub に到着してから Cloud Monitoring に反映されるまでにラグがあります。そのため、メッセージ送信後すぐにはスケールアップしません。

2. **メトリクスが存在しない間はエラーログが出力される**: サブスクリプションにメッセージが流れていない期間が長いと、Cloud Monitoring にデータポイントが存在せず、KEDA Operator のログに `could not find stackdriver metric` というエラーが繰り返し出力されます。これはメッセージが流れ始めると自動的に解消されます。

3. **MQL 非推奨化**: gcp-pubsub Scaler は MQL（Monitoring Query Language）に依存しており、GCP は MQL を PromQL に移行中です。今後のバージョンで非推奨化が予定されています。本番環境では `prometheus` Scaler + Google Managed Prometheus（GMP）の組み合わせへの移行を推奨します。

これらの理由から、このハンズオンではスケーリングの反応に **数分の遅延** が発生することがあります。これは正常な動作です。
</walkthrough-caution>

### **6. Scale-to-Zero の確認**

KEDA が自動的に HPA を作成したことを確認します。

```bash
kubectl get hpa -n keda-pubsub
```

`keda-hpa-keda-pubsub` という HPA が自動生成されているはずです。

しばらく待つと、メッセージがないため **Pod が 0 にスケールダウン**します。以下のコマンドで監視しましょう。

```bash
watch -n 5 kubectl get pods,hpa -n keda-pubsub
```

約 1 分後、Pod が Terminating → 消滅し、`REPLICAS` が `0` になることを確認してください。
確認できたら `Ctrl-C` で終了します。

<walkthrough-caution>
これが HPA だけでは実現できない Scale-to-Zero です。HPA の minReplicas は最小 1 ですが、KEDA を使うと 0 まで下げられます。アイドル時のコストがゼロになります。
</walkthrough-caution>

### **7. メッセージ送信によるスケールアップの確認**

Pub/Sub にメッセージを送信して、KEDA が自動的に Pod をスケールアップすることを確認します。

まず、Pod の監視を開始します（別ターミナルか、バックグラウンドで実行）。

```bash
watch -n 2 kubectl get pods -n keda-pubsub
```

別のターミナル（または `Ctrl-C` で一度停止してから）で、メッセージを 20 件送信します。

```bash
for i in $(seq 1 20); do
  gcloud pubsub topics publish keda-echo --project=${PROJECT_ID} --message="Message ${i}"
done
```

送信後、watch コマンドの出力を確認してください。

Cloud Monitoring のメトリクス伝播に **2〜5 分**かかるため、メッセージ送信後すぐにはスケールしません。数分お待ちください。

メトリクスが反映されると:
1. Pod が 0 → 1 にスケールアップ（KEDA が 0→1 を制御）
2. メッセージ数に応じて 1 → N にスケールアップ（HPA が制御）

Pod が起動したら、ログを確認してメッセージが正しく処理されていることを確認しましょう。

```bash
kubectl logs -n keda-pubsub -l app=keda-pubsub --tail=20
```

以下のようなログが出力されていれば、Pod が Pub/Sub からメッセージを取得し、処理・確認応答（Ack）していることが確認できます。

```
Pulling messages from projects/qwiklabs-gcp-xxxxx/subscriptions/keda-echo-read...
[2026-04-28 09:15:01] Received: Message 1
[2026-04-28 09:15:04] Acked: 19292238311290381
[2026-04-28 09:15:04] Received: Message 2
[2026-04-28 09:15:07] Acked: 19478692411110001
```

Pub/Sub 側でも未確認メッセージ数が減っていることを確認できます。

```bash
gcloud pubsub subscriptions pull keda-echo-read --project=${PROJECT_ID} --limit=5
```

メッセージが残っていなければ `Listed 0 items.` と表示されます。すべてのメッセージが処理済みです。

すべてのメッセージが処理されると、cooldownPeriod（60 秒）後に再び 0 にスケールダウンします。

```bash
kubectl get pods -n keda-pubsub
```

この一連の流れ（0 → N → 0）が KEDA のイベント駆動スケーリングです。

### **8. [オプショナル] Cloud Monitoring でスケーリング挙動を可視化**

kubectl だけでなく、Cloud Monitoring のダッシュボードを使うと、Pod の CPU 使用率と Pub/Sub のメッセージ数を**並べて可視化**でき、スケーリングの因果関係が一目で分かります。

[Cloud Monitoring コンソール](https://console.cloud.google.com/monitoring) を開き、左メニューから **ダッシュボード** → **ダッシュボードを作成** → **ウィジェットを追加** をクリックします。

以下の 2 つのグラフを追加します:

**グラフ 1: Pod の CPU 使用率**
- リソースタイプ: `Kubernetes Container`
- メトリクス: `CPU usage time`
- フィルタ: `namespace_name = keda-pubsub`

**グラフ 2: Pub/Sub 未確認メッセージ数**
- リソースタイプ: `Cloud Pub/Sub Subscription`
- メトリクス: `Unacked messages count`
- フィルタ: `subscription_id = keda-echo-read`

ダッシュボードを作成したら、再度メッセージを送信してスケーリングの動作を確認してみましょう。

```bash
for i in $(seq 1 30); do
  gcloud pubsub topics publish keda-echo --project=${PROJECT_ID} --message="Dashboard test ${i}"
done
```

ダッシュボード上で、メッセージ数の増加 → Pod の起動 → CPU 使用率の上昇 → メッセージ消化 → Pod の停止という一連の流れが可視化されます。

<walkthrough-caution>
本番運用では、このダッシュボードに加えてアラートポリシーを設定することを推奨します。例えば「未確認メッセージが 1000 件を超えたらアラート」のように設定すれば、KEDA のスケーリングが追いついていない場合に早期に検知できます。
</walkthrough-caution>

### **9. 【参考】Spot Pods との組み合わせによるさらなるコスト削減**

KEDA で Scale-to-Zero を実現した上で、さらにコストを削減したい場合は **Spot Pods** と組み合わせることができます。Spot Pods は通常の 60-91% 引きで利用できますが、GKE がリソースを必要とした際に中断される可能性があります。

Pub/Sub キューワーカーのように**中断されても再処理可能な（べき等性のある）ワークロード**では、Spot Pods が非常に有効です。

Spot Pods を利用するには、Deployment の Pod spec に以下を追加します:

```yaml
spec:
  template:
    spec:
      terminationGracePeriodSeconds: 25
      nodeSelector:
        cloud.google.com/gke-spot: "true"
```

<walkthrough-caution>
Spot Pods は中断される可能性があるため、ステートフルなワークロードや長時間のバッチジョブには適しません。また terminationGracePeriodSeconds は Spot Pods では最大 25 秒に制限されます。
</walkthrough-caution>

### **10. クリーンアップ**

ハンズオンで作成したリソースを削除します。Cloud Monitoring ダッシュボードはコンソールから手動で削除してください。

```bash
kubectl delete -f lab-ex02/pubsub-workload.yaml
helm uninstall keda -n keda
kubectl delete namespace keda keda-pubsub
gcloud pubsub subscriptions delete keda-echo-read
gcloud pubsub topics delete keda-echo
```

IAM バインディングも削除します。

```bash
gcloud projects remove-iam-policy-binding projects/${PROJECT_ID} \
  --role roles/monitoring.viewer \
  --member=principal://iam.googleapis.com/projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${PROJECT_ID}.svc.id.goog/subject/ns/keda/sa/keda-operator \
  --condition=None

gcloud projects remove-iam-policy-binding projects/${PROJECT_ID} \
  --role=roles/pubsub.subscriber \
  --member=principal://iam.googleapis.com/projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${PROJECT_ID}.svc.id.goog/subject/ns/keda-pubsub/sa/keda-pubsub-sa \
  --condition=None
```

Ex02 はこちらで完了となります。

## **Congratulations!**
これで、GKE での基本的なアプリケーションのデプロイと操作、Autopilot Mode におけるスケールの方法、CI/CD の操作、そして KEDA によるイベント駆動スケーリングと Scale-to-Zero を学ぶことができました。