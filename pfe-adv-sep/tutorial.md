<walkthrough-metadata>
  <meta name="title" content="PFE Basic" />
  <meta name="description" content="Hands-on Platform Engineering Advanced 2024-09" />
  <meta name="component_id" content="110" />
</walkthrough-metadata>

<walkthrough-disable-features toc></walkthrough-disable-features>

# 実践編: Google Cloud で始める Platform Engineering

## Google Cloud プロジェクトの設定、確認

### **1. 対象の Google Cloud プロジェクトを設定**

ハンズオンを行う Google Cloud プロジェクトのプロジェクト ID を環境変数に設定し、以降の手順で利用できるようにします。

```bash
export PROJECT_ID=$(gcloud config get-value project)
```

`プロジェクト ID` は [ダッシュボード](https://console.cloud.google.com/home/dashboard) に進み、左上の **プロジェクト情報** から確認することも可能です。

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
ここでは、以降のハンズオンで利用する機能を事前に有効化しておきます。（4,5分ほどかかります）
〜finished successfully というメッセージが出たら正常に終了しています。

```bash
gcloud services enable container.googleapis.com \
  artifactregistry.googleapis.com \
  cloudbuild.googleapis.com \
  clouddeploy.googleapis.com \
  gkehub.googleapis.com \
  containerscanning.googleapis.com \
  containersecurity.googleapis.com \
  containeranalysis.googleapis.com \
  anthos.googleapis.com
```

**GUI**: [API ライブラリ](https://console.cloud.google.com/apis/library?project={{project-id}})

## **4. gcloud コマンドラインツール設定 - リージョン、ゾーン**

コンピュートリソースを作成するデフォルトのリージョン、ゾーンとして、東京 (asia-northeast1/asia-northeast1-c）を指定します。

```bash
gcloud config set compute/region asia-northeast1 && gcloud config set compute/zone asia-northeast1-c
```

## **参考: Cloud Shell の接続が途切れてしまったときは?**

一定時間非アクティブ状態になる、またはブラウザが固まってしまったなどで `Cloud Shell` が切れてしまう、またはブラウザのリロードが必要になる場合があります。その場合は以下の対応を行い、チュートリアルを再開してください。

### **01. チュートリアル資材があるディレクトリに移動する**

```bash
cd ~/gcp-getting-started-lab-jp/pfe-adv-sep
```

### **02. チュートリアルを開く**

```bash
teachme tutorial.md
```

### **03. プロジェクト ID を設定する**

```bash
export PROJECT_ID=$(gcloud config get-value project)
```

### **4. gcloud のデフォルト設定**

```bash
gcloud config set project ${PROJECT_ID} && gcloud config set compute/region asia-northeast1 && gcloud config set compute/zone asia-northeast1-c
```

## **Lab-00.Lab 向けクラスタの準備**
<walkthrough-tutorial-duration duration=20></walkthrough-tutorial-duration>


### **Lab-00-01. VPC の作成**

今回の Lab 用 VPC を作成します。

```bash
gcloud compute networks create ws-network \
  --subnet-mode custom
```

### **Lab-00-02. サブネットの作成**

作成した VPC にサブネットを作成します。

```bash
gcloud compute networks subnets create ws-subnet \
  --network ws-network \
  --region asia-northeast1 \
  --range "192.168.1.0/24"
```

### **Lab-00-03. Cloud Router の作成**

Cloud NAT を設定するため、Cloud Router を作成しておきます。


```bash
gcloud compute routers create \
  ws-router \
  --network ws-network \
  --region asia-northeast1
```

### **Lab-00-04. Cloud NAT の作成**

GKE Cluster や Cloud Workstations は外部 IP を持たせない設定となるため、Cloud NAT を設定しておきます。

```bash
gcloud compute routers nats create ws-nat \
  --router ws-router \
  --auto-allocate-nat-external-ips \
  --nat-all-subnet-ip-ranges \
  --region asia-northeast1
```

### **Lab-00-05. GKE クラスタ の作成**

以下のコマンドを実行し、GKE クラスタを作成します。

```bash
gcloud container --project "$PROJECT_ID" clusters create "dev-cluster" \
  --region "asia-northeast1" \
  --release-channel "regular" \
  --network "ws-network" \
  --subnetwork "ws-subnet" \
  --enable-private-nodes \
  --enable-ip-alias \
  --disk-type pd-standard \
  --num-nodes 2 \
  --no-enable-master-authorized-networks \ 
  --enable-dataplane-v2 \
  --enable-cilium-clusterwide-network-policy \
  --enable-fleet \
  --security-posture=standard \
  --workload-vulnerability-scanning=enterprise \
  --async
```

クラスタの作成には10分〜20分程度の時間がかかります。
同様に Production 用のクラスタも作っておきます。

```bash
gcloud container --project "$PROJECT_ID" clusters create "prod-cluster" \
  --region "asia-northeast1" \
  --release-channel "regular" \
  --network "ws-network" \
  --subnetwork "ws-subnet" \
  --enable-private-nodes \
  --enable-ip-alias \
  --disk-type pd-standard \
  --num-nodes 2 \
  --no-enable-master-authorized-networks \ 
  --enable-dataplane-v2 \
  --enable-cilium-clusterwide-network-policy \
  --enable-fleet \
  --security-posture=standard \
  --workload-vulnerability-scanning=enterprise \
  --async
```

以上で事前準備は完了です。

## **Lab-01 Google Cloud での CI/CD**
GKE 上のワークロードに対して CI/CD を実現するための Cloud Build や Cloud Deploy の機能を試してみます。

### **Lab-01-01 アプリケーションコンテナ保管用レポジトリの作成**

Artifact Registry に CI で作成する成果物であるコンテナイメージを保管するためのレポジトリを作成しておきます。

```bash
gcloud artifacts repositories create app-repo \
  --repository-format docker \
  --location asia-northeast1 \
  --description="Docker repository for python app"
```

### **Lab-01-02 Cloud Build による CI**
Cloud Build を利用してサンプルアプリケーションのソースコードからコンテナイメージをビルドします。
サンプルアプリケーションは Flask を利用した Python のアプリケーションです。
カレントディレクトリを、`lab-01` に移動します。

```bash
cd $HOME/gcp-getting-started-lab-jp/pfe-adv-sep/lab-01
```

```bash
cat app.py
```

リクエストを受けると、ランダムに犬の品種を JSON 形式で返す API を提供しています。
また、ビルド中のステップとして、静的解析(PEP8)と簡単なユニットテストを実装しています。

```bash
cat cloudbuild.yaml
```

Cloud Build で実行します。今回は Git レポジトリを用意していないため、ローカルのソースコードから手動トリガーとして実行します。

```bash
gcloud builds submit --config cloudbuild.yaml .
```

各ステップが順に行われているのが、出力をみてわかります。
5分ほど正常に完了します。
その後、正しくソースコードがコンテナ化されているのか、Cloud Shell 上でコンテナを動作させて確認します。
まず、以下のコマンドで Cloud Shell に先ほど作成したイメージをダウンロードしてきます。

```bash
docker pull asia-northeast1-docker.pkg.dev/$PROJECT_ID/app-repo/pets:v1
```

続いて、以下のコマンドでCloud Shell 上でコンテナを動作させます。

```bash
 docker run -d -p 5000:5000 asia-northeast1-docker.pkg.dev/$PROJECT_ID/app-repo/pets:v1
```

正しく動作しているか、curl アクセスして確認してみます。JSON 形式でレスポンスがあれば成功です。
```bash
curl http://localhost:5000/random-pets
```

### **Lab-01-02 Cloud Deploy によるCD**
続いて、Cloud Deploy を活用して、複数のクラスタに順番にデプロイしていきます。
dev-cluster に対しては、トリガーと共にデプロイがされますが、
prod-cluster に対しては、UI 上でプロモートという操作をするまではデプロイが行われません。

早速そのようなパイプラインを設定していきます。
設定は `clouddeploy.yaml` に記述されています。
(接続切れなどでカレントディレクトリが変更されている場合、`lab-01` にします)

```bash
cd $HOME/gcp-getting-started-lab-jp/pfe-adv-sep/lab-01
```

```bash
cat clouddeploy.yaml
```

以下のファイルは`PROJECT_ID`がプレースホルダーになっていますので、各自の環境に合わせて置換します。

```bash
sed -i "s|\${PROJECT_ID}|$PROJECT_ID|g" clouddeploy.yaml
```

まずは、パイプラインとターゲットを Cloud Deploy に登録します。これによりアプリケーションをデプロイするための
Cluster および、dev / prod という順序性が定義されます。

```bash
gcloud deploy apply --file clouddeploy.yaml --region=asia-northeast1 --project=$PROJECT_ID
```

続いて、リリースを作成して、実際のデプロイを実行します。
デプロイ方法は、`skaffold.yaml`に定義されています。ここには、デプロイに利用するマニフェスト、およびデプロイに対応する成果物が定義されています。

```bash
cat skaffold.yaml
```

続いて以下のコマンドで実際に GKE の dev-cluster にデプロイします。

```bash
gcloud deploy releases create \
    release-$(date +%Y%m%d%H%M%S) \
    --delivery-pipeline=pfe-cicd \
    --region=asia-northeast1 \
    --project=$PROJECT_ID \
    --images=pets=asia-northeast1-docker.pkg.dev/$PROJECT_ID/app-repo/pets:v1
```

デプロイ中の様子を見るため、GUI で確認していきます。
数分の経過後、[Cloud Deploy コンソール](https://console.cloud.google.com/deploy)に最初のリリースの詳細が表示され、それが最初のクラスタに正常にデプロイされたことが確認できます。

[Kubernetes Engine コンソール](https://console.cloud.google.com/kubernetes)に移動して、アプリケーションのエンドポイントを探します。
左側のメニューバーより Gateway、Service、Ingress を選択し`サービス`タブに遷移します。表示される一覧から `pets-service` という名前のサービスを見つけます。
Endpoints 列に IP アドレスが表示され、リンクとなっているため、それをクリックして、IPアドレスの最後に`/random-pets`をつけて移動します。
アプリケーションが期待どおりに動作していることを確認します。

ステージングでテストしたので、本番環境に昇格する準備が整いました。
[Cloud Deploy コンソール](https://console.cloud.google.com/deploy)に戻ります。
デリバリーパイプラインの一覧から、`pfe-cicd` をクリックします。
すると、`プロモート` という青いリンクが表示されています。リンクをクリックし、内容を確認した上で、下部の`プロモート`ボタンをクリックします。すると本番環境へのデプロイを実施されます。

数分後にデプロイが完了されましたら、この手順は完了となります。

### **Lab-01-03 Cloud Build から Cloud Deploy の実行**
ここまでで、CI と CD を別々に行うことができました。
次の手順としては、アプリケーションを更新し、ビルドを実行します。
ビルドの最後の手順として、Cloud Deploy を実行するように設定しておき、一気通貫で CI と CD が実行されるようにします。

まずはアプリケーションを更新します。今回は簡単にするために事前に用意した app.txt を app.py に置き換えることで更新を完了します。
(接続切れなどでカレントディレクトリが変更されている場合、`lab-01` にします)

```bash
cd $HOME/gcp-getting-started-lab-jp/pfe-adv-sep/lab-01
```

```bash
mv app.py app.bak
```

```bash
mv app.txt app.py
```

必要に応じて更新後のソースコードをご確認ください。

続いて、`cloudbuild.yaml` についても変更を加え、ビルドステップの最後に、Cloud Deploy を実行するように編集する必要があります。
ただし、今回は先ほどと同様に `cloudbuild-2.yaml`というファイルで更新ずみのものを用意しておりますので、こちらを利用します。

```bash
cat cloudbuild-2.yaml
```
確認するとステップが追加されていることがわかります。
同様に Cloud Deploy 側にも変更を加えています。今回は、プロモートのボタンを押さずに一気に prod-cluster にデプロイするため、
デプロイの自動化機能を有効化しています。

```bash
cat clouddeploy-2.yaml
```

先ほど同様に`PROJECT_ID`および`PROJECT_NUMBER`がプレースホルダーになっていますので、各自の環境に合わせて置換します。

```bash
sed -i "s|\${PROJECT_ID}|$PROJECT_ID|g" clouddeploy-2.yaml
PROJECT_NUMBER=$(gcloud projects describe $PROJECT_ID --format='value(projectNumber)')
sed -i "s|\${PROJECT_NUMBER}|$PROJECT_NUMBER|g" clouddeploy-2.yaml
```

```bash
gcloud deploy apply --file clouddeploy-2.yaml --region=asia-northeast1 --project=$PROJECT_ID
```

Cloud Build から Cloud Deploy を利用するにあたっていくつか権限が必要になるため、サービスアカウントに付与します。

```bash
PROJECT_NUMBER=$(gcloud projects describe $PROJECT_ID --format="value(projectNumber)")
CLOUD_BUILD_SA="${PROJECT_NUMBER}@cloudbuild.gserviceaccount.com"
COMPUTE_SA="${PROJECT_NUMBER}-compute@developer.gserviceaccount.com"
```

```bash
gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:${PROJECT_NUMBER}@cloudbuild.gserviceaccount.com" \
    --role="roles/clouddeploy.admin"
```

```bash
gcloud iam service-accounts add-iam-policy-binding $COMPUTE_SA \
    --member="serviceAccount:${CLOUD_BUILD_SA}" \
    --role="roles/iam.serviceAccountUser" \
    --project=$PROJECT_ID
```
それでは実行します。

```bash
gcloud builds submit --config cloudbuild-2.yaml .
```
もし、エラーが出てしまいましたら、`app.py`の最終行にある空白行を削除もしくは、改行を行いもう一度、上のコマンドを試してください。
これは PEP8 による構文解析で、空行の有無を判定しているためです。
しばらくすると先ほどの CI のステップが順に行われた後、デリバリーパイプラインでデプロイが開始されるのが確認できます。

デプロイ中の様子を見るため、GUI で確認していきます。
数分の経過後、[Cloud Deploy コンソール](https://console.cloud.google.com/deploy)に今回のリリースの詳細が表示され、それが最初のクラスタに正常にデプロイされたことが確認できます。

[Kubernetes Engine コンソール](https://console.cloud.google.com/kubernetes)に移動して、アプリケーションのエンドポイントを探します。
左側のメニューバーより Gateway、Service、Ingress を選択し`サービス`タブに遷移します。表示される一覧から `pets-service` という名前のサービスを見つけます。
Endpoints 列に IP アドレスが表示され、リンクとなっているため、それをクリックして、IPアドレスの最後に`/random-pets`をつけて移動します。
再びアプリケーションが期待どおりに動作していることを確認します。今回は先ほどとは異なる出力となるのが確認できるようになっています。

今回は、dev-cluster へのデプロイの1分経過後に自動的に本番環境(prod-cluster)までリリースされるように動作が変更されています。
これは[デプロイの自動化](https://cloud.google.com/deploy/docs/deploy-app-automation?hl=ja)という機能を利用しています。

数分後にデプロイが完了されましたら、この手順は完了となります。

こちらで Lab-01 は完了となります。

## **Lab-02 GKE セキュリティ**
### **Lab-02-01 脆弱性スキャンの導入**
Artifact Registry 上での脆弱性スキャン機能を試してみます。OSS や 3rd party 製品などを活用して、
CI/CD パイプライン上で脆弱性の検査を行うケースがあります。しかし、それだけでは不十分なケースも存在しています。
例えば、デプロイされたイメージにあとから重大な脆弱性が見つかってしまう場合などがあります。
ここでは、Artifact Registry の脆弱性スキャンおよび、GKE 上の動作しているコンテナの脆弱性を検知することで、ライフサイクル全体で
セキュリティを強化できる仕組みを構築します。

カレントディレクトリを、lab-02 にします。
```bash
cd $HOME/gcp-getting-started-lab-jp/pfe-adv-sep/lab-02
```
ここで脆弱性のあるイメージをあえてビルドします。
このアプリケーションは、先ほどのアプリケーションから一部だけ変更を加えております。
変更点はベースイメージを`python:3.12-alpine`から`python:3.12`に変えた部分です。こちらはさまざまな脆弱性が見つかっているイメージとなります。

```bash
gcloud builds submit --tag asia-northeast1-docker.pkg.dev/${PROJECT_ID}/app-repo/pets:v2
```

ここから GUI 操作に切り替えます。  
Artifact Registry の脆弱性スキャン結果を確認するため、以下コマンドの実行結果として出力された URL をクリックします。  

```bash
echo https://console.cloud.google.com/artifacts/docker/${PROJECT_ID}/asia-northeast1/app-repo/pets
```
Push されたあとスキャンが数分のうちに実行されます。
結果として、コンソール上に先ほど直接 Push したコンテナイメージタグ `v2` で800以上の脆弱性が検知されていることがわかります。  
Artifact Registry での脆弱性スキャンは Push 後 30 日間は継続的にスキャンが行われるため、CI 実行時に発見されていない脆弱性を拾うことも期待できます。  

### **Lab-02-02 GKE 上でのセキュリティ対策**

せっかくセキュアな CI/CD パイプラインを用意しても、OSS をデプロイする場合や直接 Kubectl でデプロイされてしまう場合など、CI/CD 上の脆弱性スキャンがバイパスされてしまう可能性があります。  
また、あまり頻繁にデプロイしないようなアプリケーションでは、CI 実行時には発見されなかった脆弱性が後から発見される可能性もあります。  
そのようなケースでは、GKE Security Posture の機能の一つである、継続的脆弱性スキャンが有効です。  
この機能により、GKE 上で動いているワークロードに対して継続的に脆弱性スキャンを実行することができるため、CI/CD パイプラインや Artifact Registry を通っていないようなワークロードの脆弱性の検知が可能となります。 

本機能を試すために CI/CD を通さずに直接 kubectl を使って Maven の脆弱性が含まれた Pod をデプロイしてみます。  
カレントディレクトリを、`lab-02` にします。
```bash
cd $HOME/gcp-getting-started-lab-jp/pfe-adv-sep/lab-02
```

dev-cluster へ接続します。
```bash
gcloud container clusters get-credentials dev-cluster --region asia-northeast1 --project $PROJECT_ID
```
マニフェストよりデプロイします。
```bash
kubectl apply -f kubernetes-manifests/maven-vulns.yaml
```

ここから GUI での操作に切り替えます。  
[GKE Security Posture](https://console.cloud.google.com/kubernetes/security/dashboard) に移動し、画面下部の `高度な脆弱性` にクリティカルな脆弱性が表示されていることを確認します。(初回は表示されるまで十数分程度時間がかかる可能性があります)  
表示された脆弱性をクリックし、脆弱性の詳細や影響を受けるワークロードを確認します。  

以上より、GKE 上での動いているワークロードに対しても継続的スキャンを実行することにより、脆弱性を検知することができました。  
Cloud Shell での操作に戻り、デプロイした Pod は一度クラスタから削除します。  

```bash
kubectl delete -f kubernetes-manifests/maven-vulns.yaml
```

### **Lab-02-04 レポジトリを制限する**

インターネット上で公開されているコンテナイメージには、脆弱性やマルウェアが含まれているものも存在するため無闇にプロダクション環境等にデプロイしてしまうのは危険です。  
対策としては、スキャンが実装されたセキュアな CI/CD パイプラインを通したコンテナイメージのみデプロイを許可する方法や、実行可能なコンテナリポジトリを制限する方法などがあります。  

今回は、Policy Controller の制約を活用し、自分のプロジェクト配下の特定リポジトリのコンテナイメージのみ GKE 上で実行可能としてみます。  

ここから GUI 操作に切り替えます。 
[ポリシー](hhttps://console.cloud.google.com/kubernetes/policy_controller)へ移動します。
一度目のアクセスでは、うまく構成メニューが表示されないため、画面全体を一度更新します。

そうすると`Policy Controller の概要`が表示されます。
青いボタンの `POLICY CONTROLLER を構成`をクリックしてください。
画面下までスクロールし、青いボタンの `構成`をクリックしてください。

ポリシー のフリートレベルの設定を定義します。次の API は、現在無効になっている場合、プロジェクトで有効になります:
- anthospolicycontroller.googleapis.com
フリートに登録した新しいクラスタには、このフリート設定が継承されます。この設定はいつでも変更できます。フリート内の既存のクラスタとそのホスト プロジェクトは変わりませんが、後でフリートの設定と同期できます。この操作はオプションです。
この操作には数分かかることがあります。

と表示されますので、`確認`をクリックしてください。


その後、画面が切り替わりますので、`フリートの設定と同期`をクリックしてください。
両方のクラスターにチェックをいれ、青いボタンの`フリートの設定に同期`をクリックし、`確認`をクリックします。

15分程度すると 機能ステータスが`有効`になります。

ここからは Cloud Shell での操作に戻ります。
以下のコマンドを実行し、制約テンプレートが利用可能になっていることを確認します。  
制約テンプレートは各種制約のロジックを定義するリソースです。  

```bash
kubectl get constrainttemplates
```

以下の例のように、多くの制約テンプレートが GKE クラスタ内にインストールされているはずです。  

```text
NAME                                        AGE
allowedserviceportname                      9m35s
~~~
noupdateserviceaccount                      9m57s
policystrictonly                            9m44s
restrictnetworkexclusions                   9m51s
sourcenotallauthz                           9m47s
verifydeprecatedapi                         9m48s
```

今回利用する制約テンプレートは `K8sAllowedRepos` という、GKE から Pull 可能なリポジトリを allowlist 方式で定義する制約です。  
以下のように制約テンプレートを Kind に指定した制約リソースを作成し、自分のプロジェクトの `app-repo` からのみコンテナイメージを Pull できるようにします。  
制約リソースでは制約の適用対象や内容を定義します。  

```yaml
# allow-myrepo.yaml
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sAllowedRepos
metadata:
  name: allow-my-app-repo
spec:
  match:
    kinds:
    - apiGroups:
      - ""
      kinds:
      - Pod
    namespaces:
    - default
  parameters:
    repos:
    - asia-northeast1-docker.pkg.dev/PROJECT_ID/app-repo/
```

では実際に制約を適用します。
```bash
kubectl apply -f kubernetes-manifests/allow-myrepo.yaml
```

前項番 Lab-02-03 でデプロイした Pod を再度デプロイしてみます(以前デプロイしたものが残っている場合は事前に当該 Pod を削除しておいてください)。  

```bash
kubectl apply -f kubernetes-manifests/maven-vulns.yaml
```

そうすると以下のように Policy Controller の制約違反によりデプロイが拒否されます。  
理由としてはデプロイしようとした `maven-vulns-app` という Pod のコンテナイメージは `us-docker.pkg.dev/google-samples/containers/gke/security/maven-vulns` という別プロジェクト上のリポジトリに保管されており、今回の制約ではこのリポジトリを許可していないためです。  
```
Error from server (Forbidden): error when creating "kubernetes-manifests/maven-vulns.yaml": admission webhook "validation.gatekeeper.sh" denied the request: [repo-is-openpolicyagent] container <maven-vulns-app> has an invalid image repo <us-docker.pkg.dev/google-samples/containers/gke/security/maven-vulns>, allowed repos are ["asia-northeast1-docker.pkg.dev/kkuchima-2405282/app-repo/"]
```

以上で Lab-02 は終了です。  

以下のコマンドを実行し、後続の Lab に影響しないように不要なリソースは削除しておきます。  
```bash
kubectl delete -f kubernetes-manifests/allow-myrepo.yaml
```
## **Lab-03 セキュリティ ポリシー**
### **Lab-03-01. 不適切な設定の Pod のデプロイ**

カレントディレクトリを、`lab-03` に移動します。

```bash
cd $HOME/gcp-getting-started-lab-jp/pfe-adv-sep/lab-03
```
GKE クラスタに以下の不適切な設定の Pod をデプロイします。  
一見して普通の Pod のようにみえますが、hostpath を使ってホストのルートディレクトリをマウントしようとしています。  

```yaml
# bad-pod.yaml
apiVersion: v1
kind: Pod
metadata:
  labels:
    app: bad-pod
  name: bad-pod
spec:
  volumes:
  - name: host-fs
    hostPath:
      path: /
  containers:
  - image: ubuntu
    imagePullPolicy: Always
    name: bad-pod
    command: ["/bin/sh", "-c", "sleep infinity"]
    volumeMounts:
      - name: host-fs
        mountPath: /root
  restartPolicy: Never
```

では実際にデプロイしてみます。  

```bash
kubectl apply -f bad-pod.yaml
```

以下コマンドを実行し `bad-pod` に入ってみます。  
```bash
kubectl exec bad-pod -it -- bash
```

ホストの `/` にルートディレクトリを変更します。  
```bash
chroot /root /bin/bash
```

bad-pod から以下コマンドを実行します。  
```bash
id
ls
```

以下のようにホストの領域に root ユーザーとして入れていることが分かります。  
```
bad-pod / # id
uid=0(root) gid=0(root) groups=0(root)
bad-pod / # ls
bin  boot  dev  etc  home  lib  lib64  lost+found  mnt  opt  postinst  proc  root  run  sbin  sys  tmp  usr  var
```

実行されているプロセスの情報から Node 上の kubelet が利用している kubeconfig も確認できます。  
```bash
ps -ef | grep kubelet
```

実際に kubeconfig を使って GKE 環境の情報取得も可能です。  
```bash
kubectl --kubeconfig=/var/lib/kubelet/kubeconfig get pods
```

ホストの領域から抜けるため以下を実行します。  
```bash
exit
```

bad-pod コンテナから抜けるため以下を実行します。  
```bash
exit
```
hostpath をマウントした Pod から簡単にホストへエスケープすることができました。  

### **Lab-03-02 不適切な設定の Pod の検知**

ここから GUI での操作に切り替えます。  
まず [GKE Security Posture](https://console.cloud.google.com/kubernetes/security/dashboard) に移動し、 画面中部左側の`ワークロードの構成`に`ホストのファイルまたはディレクトリをマウントする Pod` という構成の懸念事項が出力されていることを確認します。  
出力されていない場合は数分待機します。  
出力されている場合は`ホストのファイルまたはディレクトリをマウントする Pod` リンクをクリックし、脅威の内容を確認します。  
また、`影響を受けるワークロード` タブからこの懸念事項を持っている Pod を特定することもできます。今回利用した `bad-pod` が表示されています。  

確認を終えたら Cloud Shell 画面に戻ります。　　

一度 `bad-pod` はクラスタから削除しておきます。  

```bash
kubectl delete -f bad-pod.yaml
```

### **Lab-03-03 不適切な設定の Pod の防止**

先ほどデプロイした `bad-pod` のような Pod を検知はできましたが、そもそもデプロイさせないためにはどうしたら良いでしょうか。  
1つの方法として、Lab1 でも利用した Policy Controller が活用できます。  

今回は以下のように`K8sPSPHostFilesystem` という制約テンプレートを利用し、HostPath を `/var/log` のみ Read-Only でマウントできる制約を用意します。  

```yaml
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sPSPHostFilesystem
metadata:
  name: allow-hostpath
spec:
  match:
    kinds:
    - apiGroups:
      - ""
      kinds:
      - Pod
  parameters:
    allowedHostPaths:
    - pathPrefix: /var/log
      readOnly: true
```

この制約を適用します。  

```bash
kubectl apply -f allow-hostpath.yaml
```

では、`bad-pod` をデプロイしてみましょう。  

```bash
kubectl apply -f bad-pod.yaml
```

うまくいけば以下のように Policy Controller の制約により、デプロイが阻止されていることが分かります。  

```
Error from server (Forbidden): error when creating "kubernetes-manifests/bad-pod.yaml": admission webhook "validation.gatekeeper.sh" denied the request: [allow-hostpath] HostPath volume {"hostPath": {"path": "/", "type": ""}, "name": "host-fs"} is not allowed, pod: bad-pod. Allowed path: [{"pathPrefix": "/var/log", "readOnly": true}]
```

Policy Controller ではこれら以外にも特権コンテナのデプロイを禁止したり、root ユーザーで実行可能にすることを防ぐための制約テンプレートなどが最初から用意されています。  
セキュリティリスクのある構成を禁止するだけでなく、いわゆる Kubernetes のベストプラクティスを強制させるための制約テンプレートもあるため、興味があれば他にも試してみてください。  
制約テンプレートの一覧は[こちらのドキュメント](https://cloud.google.com/kubernetes-engine/enterprise/policy-controller/docs/latest/reference/constraint-template-library)から確認できます。  

## **Configurations!**
おめでとうございます。実践編のハンズオンは完了となります。
次回の Google Cloud のハンズオンシリーズもご参加をお待ちしております。
