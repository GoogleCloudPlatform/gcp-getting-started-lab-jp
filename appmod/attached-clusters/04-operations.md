# Anthos Attached Clusters ウォークスルー (ログ・メトリクス管理)

<walkthrough-watcher-constant key="region" value="asia-northeast1"></walkthrough-watcher-constant>
<walkthrough-watcher-constant key="zone" value="asia-northeast1-c"></walkthrough-watcher-constant>
<walkthrough-watcher-constant key="cluster" value="anthos"></walkthrough-watcher-constant>
<walkthrough-watcher-constant key="sa" value="anthos-lm-forwarder"></walkthrough-watcher-constant>

## 始めましょう

Anthos Attached Clusters のログ・メトリクスを管理する手順です。

**所要時間**: 約 15 分

**前提条件**:

- Anthos Attached Clusters として Kubernetes クラスタが登録されている。

**[開始]** ボタンをクリックして次のステップに進みます。

## 初期設定

### **Google Cloud のプロジェクト ID を環境変数に設定**

環境変数 `GOOGLE_CLOUD_PROJECT` に Google Cloud プロジェクト ID を設定します。

```bash
export GOOGLE_CLOUD_PROJECT="{{project-id}}"
```

## サービス アカウントの作成

Cloud Monitoring API と Cloud Logging API に指標とログを書き込む権限を持つサービス アカウントを作成します

### **Google Cloud サービスアカウントの作成・権限付与**

```bash
gcloud iam service-accounts create {{sa}}
gcloud projects add-iam-policy-binding ${GOOGLE_CLOUD_PROJECT} \
    --member="serviceAccount:{{sa}}@${GOOGLE_CLOUD_PROJECT}.iam.gserviceaccount.com" \
    --role=roles/logging.logWriter
gcloud projects add-iam-policy-binding ${GOOGLE_CLOUD_PROJECT} \
    --member="serviceAccount:{{sa}}@${GOOGLE_CLOUD_PROJECT}.iam.gserviceaccount.com" \
    --role=roles/monitoring.metricWriter
```

### **JSON キーのダウンロードと Kubernetes Secret の作成**

```text
account=$(gcloud config get-value core/account)
account="${account%%@*}"
```

```bash
gcloud iam service-accounts keys create credentials.json \
    --iam-account {{sa}}@${GOOGLE_CLOUD_PROJECT}.iam.gserviceaccount.com
gcloud beta container hub memberships get-credentials "{{cluster}}-attached-${account}"
kubectl create secret generic google-cloud-credentials \
    -n kube-system --from-file credentials.json
```

## ロギング エージェントの設定

作業ディレクトリを移動しつつ、以下のコマンドを実行し

```bash
cd ~/cloudshell_open/gcp-getting-started-lab-jp/appmod/attached-clusters
gcloud container hub memberships describe "anthos-attached-${account}" | grep name
```

`projects/<project_id>/locations/<cluster_location>/memberships/<cluster_name>` のそれぞれにあたる値を、logging/aggregator.yaml の以下に反映させてください。

```text
project_id [PROJECT_ID]
k8s_cluster_name [CLUSTER_NAME]
k8s_cluster_location [CLUSTER_LOCATION]
```

またコメントアウトされている `storageClassName` についても、[クラウドコンソール](https://console.cloud.google.com/kubernetes/storageclass?project={{project-id}}) から、適切なものを探し、置換してください。

```bash
vim logging/aggregator.yaml
```

### **アグリゲータとフォワーダのデプロイ**

```bash
kubectl apply -f logging/
```

挙動を確認しましょう。

```bash
kubectl get pods -n kube-system | grep stackdriver-log
kubectl logs stackdriver-log-aggregator-0 -n kube-system
```

## モニタリング エージェントの設定

monitoring/prometheus.yaml の以下の設定を適切なものに修正し、

```text
"--stackdriver.project-id=[PROJECT_ID]"
"--stackdriver.kubernetes.location=[CLUSTER_LOCATION]"
"--stackdriver.generic.location=[CLUSTER_LOCATION]"
"--stackdriver.kubernetes.cluster-name=[CLUSTER_NAME]"
```

`storageClassName` をロギング同様に設定します。

```bash
vim monitoring/prometheus.yaml
```

### **StatefulSet のデプロイ**

```bash
kubectl apply -f monitoring/
```

挙動を確認しましょう。

```bash
kubectl get pods -n kube-system | grep stackdriver-prometheus
kubectl logs stackdriver-prometheus-k8s-0 -n kube-system stackdriver-prometheus-sidecar
```

画面の左上にある <walkthrough-spotlight-pointer spotlightId="console-nav-menu">ナビゲーション メニュー</walkthrough-spotlight-pointer> を開き、**Monitoring** セクションを開きましょう。

<walkthrough-menu-navigation sectionId="MONITORING_SECTION"></walkthrough-menu-navigation>

左側のメニューから <walkthrough-spotlight-pointer cssSelector="#cfctest-section-nav-item-stackdriver_metrics_explorer">Metrics Explorer</walkthrough-spotlight-pointer> を開きます。

### **クエリ**

クエリエディタを開き、 ${your-project-id} と ${your-cluster-name} を実際のプロジェクトとクラスタ情報に置き換えて、コピーします。[クエリを実行] をクリックします。

```text
fetch k8s_container
| metric 'kubernetes.io/anthos/up'
| filter
    resource.project_id == '${your-project-id}'
    && (resource.cluster_name =='${your-cluster-name}')
| group_by 1m, [value_up_mean: mean(value.up)]
| every 1m
```

## Congraturations!

<walkthrough-conclusion-trophy></walkthrough-conclusion-trophy>

すべて完了しました。

次のステップにお進みください。

```bash
teachme ~/cloudshell_open/gcp-getting-started-lab-jp/appmod/attached-clusters/09-teardown.md
```
