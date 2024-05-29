# **GKE で始める Platform Engineering -セキュリティガードレール編-**

本ハンズオンでは、GKE のセキュリティ機能を利用してガードレールを構築する方法について学びます。  

## **ハンズオン実施内容**
Lab1.CI/CD セキュリティのハンズオンでは、以下のセキュリティ機能を体験します。
- CI/CD パイプラインでのコンテナイメージのセキュリティスキャン実行
- GKE の継続的脆弱性スキャン
- Policy Controller による利用可能なコンテナリポジトリの制限

Lab2.セキュリティポリシーのハンズオンでは、以下のセキュリティ機能を体験します。
- 不適切な設定の Pod のデプロイ検知
- Policy Controller による不適切な設定のコンテナデプロイの防止
- Cluster-wide Network Policy によるネットワークレベルでの制御

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

### **1. API の有効化**
Google Cloud では利用したい機能（API）ごとに、有効化を行う必要があります。

ここでは、以降のハンズオンで利用する機能を事前に有効化しておきます。

```bash
gcloud services enable container.googleapis.com \
  artifactregistry.googleapis.com \
  cloudbuild.googleapis.com \
  gkehub.googleapis.com \
  containerscanning.googleapis.com \
  containersecurity.googleapis.com \
  containeranalysis.googleapis.com \
  anthos.googleapis.com
```

**GUI**: [API ライブラリ](https://console.cloud.google.com/apis/library)

## **Lab0. GKE クラスタのデプロイ**
まず最初に本ハンズオンで利用する GKE クラスタを事前に構築します。  

### **0-1. 環境変数の設定**

クラスタ構築に必要となる環境変数を設定します。  

以下コマンドを実行してください。
```bash
export CLUSTER_NAME=gke-cluster
export REGION=asia-northeast1
export ZONE=asia-northeast1-c
export PROJECT_NUMBER=$(gcloud projects describe ${PROJECT_ID} --format="value(projectNumber)")
```

### **0-2. VPC の作成**

今回の Lab 用 VPC を作成します。

```bash
gcloud compute networks create ws-network \
  --subnet-mode custom
```

### **0-3. サブネットの作成**

作成した VPC にサブネットを作成します。

```bash
gcloud compute networks subnets create ws-subnet \
  --network ws-network \
  --region asia-northeast1 \
  --range "192.168.1.0/24"
```

### **0-4. GKE クラスタのデプロイ**

本ハンズオンで利用する GKE クラスタをデプロイします。デプロイ完了まで十数分かかります。  
今回はセキュリティ機能の重要性を確認するため、構成の自由度の高い GKE Standard クラスタを利用します。  

```bash
gcloud container clusters create ${CLUSTER_NAME} --project ${PROJECT_ID} \
  --location ${ZONE} \
  --release-channel "regular" \
  --cluster-version "1.28.8" \
  --network "ws-network" \
  --subnetwork "ws-subnet" \
  --enable-ip-alias \
  --enable-private-nodes \
  --master-ipv4-cidr "172.16.0.0/28" \
  --no-enable-master-authorized-networks \
  --enable-dataplane-v2 \
  --enable-cilium-clusterwide-network-policy \
  --enable-fleet \
  --security-posture=standard \
  --workload-vulnerability-scanning=enterprise
```

## **参考: Cloud Shell の接続が途切れてしまったときは?**

一定時間非アクティブ状態になる、またはブラウザが固まってしまったなどで `Cloud Shell` が切れてしまいブラウザのリロードが必要になる場合があります。その場合は再接続、リロードなどを実施後、以下の対応を行い、チュートリアルを再開してください。

### **1. チュートリアル資材があるディレクトリに移動する**

```bash
cd ~/gcp-getting-started-lab-jp/platform-engineering/security/
```

### **2. チュートリアルを開く**

```bash
teachme tutorial.md
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

### **5. 環境変数の設定**

環境構築に必要となる環境変数を設定します。 

以下コマンドを実行してください。  

```bash
export CLUSTER_NAME=gke-cluster
export REGION=asia-northeast1
export ZONE=asia-northeast1-c
export PROJECT_NUMBER=$(gcloud projects describe ${PROJECT_ID} --format="value(projectNumber)")
```

途中まで進めていたチュートリアルのページまで `Next` ボタンを押し、進めてください。


## **Lab1. CI/CD セキュリティ**
本ハンズオンラボでは、CI/CDを中心としたソフトウェアサプライチェーンでのセキュリティ対策・機能を体験します。　　

### **1-1. アプリケーションコンテナ保管用レポジトリの作成**

まず `lab1` ディレクトリに移動します。  

```bash
cd lab1
```

Artifact Registry に CI で作成する成果物であるコンテナイメージを保管するためのレポジトリを作成しておきます。

```bash
gcloud artifacts repositories create app-repo \
  --repository-format docker \
  --location asia-northeast1 \
  --description="Docker repository for python app"
```

### **1-2. CI/CD パイプラインでの脆弱性スキャン**
Cloud Build を利用してサンプルアプリケーションのソースコードからコンテナイメージをビルドします。  
サンプルアプリケーションは Flask を利用した Python のアプリケーションです。  

事前準備として、以下のコマンドを実行しマニフェスト内の設定値を書き換えます。  

```bash
sed -i "s/PROJECT_ID/$PROJECT_ID/g" kubernetes-manifests/allow-myrepo.yaml
sed -i "s/PROJECT_ID/$PROJECT_ID/g" kubernetes-manifests/deployment.yaml
sed -i "s/PROJECT_ID/$PROJECT_ID/g" kubernetes-manifests/deployment-alpine.yaml
```

Cloud Build ではビルド中のステップとして、静的解析(PEP8)と簡単なユニットテストに加えて、OSS の [Trivy](https://trivy.dev/) による Dockerfile の構成スキャンとコンテナイメージの脆弱性スキャンを実装しています。  
Dockerfile の構成スキャンでは重大度 `HIGH` 以上の脆弱性、コンテナイメージ脆弱性スキャンでは重大度 `CRITICAL` 以上の脆弱性を検出するように構成しています。  
コンテナイメージスキャンでは引数に　`--exit-code 1` を設定しており、コンテナイメージの脆弱性が検出された場合はパイプラインが異常終了するようになっています。  
全てのステップが正常終了すると最終的には GKE クラスタにサンプルアプリケーションをデプロイする CI/CD パイプラインとなっていますす。  

```yaml
# cloudbuild.yaml 抜粋
steps:
~~~
- id: 'dockerfile-scan'
  name: 'aquasec/trivy'
  entrypoint: '/bin/sh'
  args:
    - '-c'
    - | 
      trivy config ./Dockerfile --severity HIGH
~~~
- id: 'image-scan'
  name: 'aquasec/trivy'
  entrypoint: '/bin/sh'
  args:
    - '-c'
    - | 
      trivy image --severity CRITICAL ${_REPO_REGION}-docker.pkg.dev/${PROJECT_ID}/${_REPO_NAME}/${_IMAGE_NAME}:${_TAG} --exit-code 1
```

Cloud Build から GKE クラスタへデプロイを行うため、Cloud Build のサービスアカウントに対して `Kubernetes Engine 開発者` のロールを付与します。  

```bash
gcloud projects add-iam-policy-binding ${PROJECT_ID} \
    --member "serviceAccount:${PROJECT_NUM}@cloudbuild.gserviceaccount.com" \
    --role "roles/container.developer"
```

Cloud Build パイプラインを実行します。今回は Git レポジトリを用意していないため、ローカルのソースコードから手動トリガーとして実行します。  

```bash
gcloud builds submit --config cloudbuild.yaml .
```

実行した CI/CD パイプラインが異常終了します。これはサンプルアプリケーションで利用しているベースイメージ `FROM python:3.12` には重大な脆弱性が含まれており、Trivy の脆弱性スキャンで検知することができたためです。  
本来であればこの脆弱性の対処を行うべきですが、 Artifact Registry の脆弱性スキャンでも同様に脆弱性を検知できるか確認するため、今度は CI/CD パイプラインを通さずに Artifact Registry に直接コンテナイメージを Push します。  

```bash
gcloud builds submit --tag asia-northeast1-docker.pkg.dev/${PROJECT_ID}/app-repo/pets:v1.0
```

ここから GUI 操作に切り替えます。  
Artifact Registry の脆弱性スキャン結果を確認するため、以下コマンドの実行結果として出力された URL をクリックします。  

```bash
echo https://console.cloud.google.com/artifacts/docker/${PROJECT_ID}/asia-northeast1/app-repo/pets
```
コンソール上に先ほど直接 Push したコンテナイメージ `v1.0` で440程度の脆弱性が検知されていることがわかります。  
これにより、CI/CD パイプラインとコンテナリポジトリの２箇所で脆弱性スキャンが動くことが確認できました。Artifact Registry での脆弱性スキャンは Push 後 30 日間は継続的にスキャンが行われるため、CI 実行時は発見されていない脆弱性を拾うことも期待できます。  

### **1-3. 軽量なベースイメージの利用**
Cloud Shell での操作に戻ります。  
続いてコンテナのベースイメージを alpine という軽量なベースイメージに変更して同じパイプラインを流してみましょう。  
利用する Dockerfile の違いは以下のみです。  

```patch
- FROM python:3.12
+ FROM python:3.12-alpine
```

ベースイメージとして alpine を指定した Dockerfile を利用する CI/CD パイプラインを実行します。  

```bash
gcloud builds submit --config cloudbuild-alpine.yaml .
```

結果として trivy のイメージスキャンで重大な脆弱性は発見されず、GKE へのデプロイまで実行することができたかと思います。  
alpine のような軽量ベースイメージは最低限のパッケージしか入っておらずアタックサーフェスが小さいため、脆弱性自体を持ちにくいというのが特徴の一つです。  
軽量なベースイメージとしては他にも Distroless や slim 系などが存在します。それぞれ特徴が異なるため要件に応じてご利用を検討ください。  

### **1-4. GKE クラスタ上での継続的脆弱性スキャン**

せっかくセキュアな CI/CD パイプラインを用意しても、OSS をデプロイする場合や直接 Kubectl でデプロイされてしまう場合など、CI/CD 上の脆弱性スキャンがバイパスされてしまう可能性があります。  
また、あまり頻繁にデプロイしないようなアプリケーションでは、CI 実行時には発見されなかった脆弱性が後から発見される可能性もあります。  
そのようなケースでは、GKE Security Posture の機能の一つである、継続的脆弱性スキャンが有効です。  
この機能により、GKE 上で動いているワークロードに対して継続的に脆弱性スキャンを実行することができるため、CI/CD パイプラインや Artifact Regsitry を通っていないようなワークロードの脆弱性の検知が可能となります。  

本機能を試すために CI/CD を通さずに直接 kubectl を使って Maven の脆弱性が含まれた Pod をデプロイしてみます。  

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

### **1-5. 利用可能なリポジトリを制限する**

インターネット上で公開されているコンテナイメージには、脆弱性やマルウェアが含まれているものも存在するため無闇にプロダクション環境等にデプロイしてしまうのは危険です。  
対策としては、スキャンが実装されたセキュアな CI/CD パイプラインを通したコンテナイメージのみデプロイを許可する方法や、実行可能なコンテナリポジトリを制限する方法などがあります。  

今回は、Policy Controller の制約を活用し、自分のプロジェクト配下の特定リポジトリのコンテナイメージのみ GKE 上で実行可能としてみます。  

以下のコマンドを実行し、GKE クラスタに Policy Controller をインストールします。  
```bash
gcloud container fleet policycontroller enable \
    --memberships=${CLUSTER_NAME}
```

以下のコマンドを実行し、コンポーネントのインストール状況を確認します。  

```bash
gcloud container fleet policycontroller describe --memberships=${CLUSTER_NAME}
```

数分後、以下の例のように `admission`, `audit`, `templateLibraryState` が `ACTIVE` となることを確認します。  

```
membershipStates:
  projects/924402902969/locations/asia-northeast1/memberships/prod-cluster:
    policycontroller:
      componentStates:
        admission:
          details: 1.18.1
          state: ACTIVE
        audit:
          details: 1.18.1
          state: ACTIVE
~~~
        templateLibraryState:
          state: ACTIVE
      state: ACTIVE
    state:
      code: OK
```

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
以下のように制約テンプレートを Kind にしていした制約リソースを作成し、自分のプロジェクトの `app-repo` からのみコンテナイメージを Pull できるようにします。  
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

その後、手順 1-4 でデプロイした Pod を再度デプロイしてみます(以前デプロイしたものが残っている場合は事前に当該 Pod を削除しておいてください)。  

```bash
kubectl apply -f kubernetes-manifests/maven-vulns.yaml
```

そうすると以下のように Policy Controller の制約違反によりデプロイが拒否されます。  
理由としてはデプロイしようとした `maven-vulns-app` という Pod のコンテナイメージは `us-docker.pkg.dev/google-samples/containers/gke/security/maven-vulns` という別プロジェクト上のリポジトリに保管されており、今回の制約ではこのリポジトリを許可していないためです。  
```
Error from server (Forbidden): error when creating "kubernetes-manifests/maven-vulns.yaml": admission webhook "validation.gatekeeper.sh" denied the request: [repo-is-openpolicyagent] container <maven-vulns-app> has an invalid image repo <us-docker.pkg.dev/google-samples/containers/gke/security/maven-vulns>, allowed repos are ["asia-northeast1-docker.pkg.dev/kkuchima-2405282/app-repo/"]
```

以上で Lab1 は終了です。  
以下のコマンドを実行し、後続の Lab に影響しないように不要なリソースは削除しておきます。  
```bash
kubectl delete -f kubernetes-manifests/allow-myrepo.yaml
```

## **Lab2. セキュリティポリシー**
本ハンズオンラボでは、Network Policy や Policy Controller 制約等を活用した GKE 上でのガードレール構築を体験します。　　

### **2-1. 不適切な設定の Pod のデプロイ**

まず `lab2` ディレクトリに移動します。  

```bash
cd lab2
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

実行されているプロセスから kubelet が利用している kubeconfig も確認できます。  
```bash
ps -ef | grep kubelet
```

実際に kubeconfig を使って情報取得も可能です。  
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

### **2-2. 不適切な設定の Pod の検知**

ここから GUI での操作に切り替えます。  
まず [GKE Security Posture](https://console.cloud.google.com/kubernetes/security/concerns) に移動し、 `ホストのファイルまたはディレクトリをマウントする Pod` という構成の懸念事項が出力されていることを確認します。  
`ホストのファイルまたはディレクトリをマウントする Pod` リンクをクリックし、脅威の内容を確認します。  
また、`影響を受けるワークロード` タブからこの懸念事項を持っている Pod を特定することもできます。今回利用した `bad-pod` が表示されていると思います。  

確認を終えたら Cloud Shell 画面に戻ります。　　

一度 `bad-pod` はクラスタから削除しておきます。  

```bash
kubectl delete -f kubernetes-manifests/bad-pod.yaml 
```

### **2-3. 不適切な設定の Pod の防止**

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
kubectl apply -f kubernetes-manifests/bad-pod.yaml 
```

うまくいけば以下のように Policy Controller の制約により、デプロイが阻止されていることが分かります。  

```
Error from server (Forbidden): error when creating "kubernetes-manifests/bad-pod.yaml": admission webhook "validation.gatekeeper.sh" denied the request: [allow-hostpath] HostPath volume {"hostPath": {"path": "/", "type": ""}, "name": "host-fs"} is not allowed, pod: bad-pod. Allowed path: [{"pathPrefix": "/var/log", "readOnly": true}]
```

Policy Controller ではこれら以外にも特権コンテナのデプロイを禁止したり、root ユーザーで実行可能にすることを防ぐための制約テンプレートなどが最初から用意されています。  
セキュリティリスクのある構成を禁止するだけでなく、いわゆる Kubernetes のベストプラクティスを強制させるための制約テンプレートもあるため、興味があれば他にも試してみてください。  
制約テンプレートの一覧は以下のドキュメントから確認できます。  
https://cloud.google.com/kubernetes-engine/enterprise/policy-controller/docs/latest/reference/constraint-template-library

### **2-4. Cluster-wide Network Policy による通信制御**

歳後に Cluster-wide Network Policy の機能により、GKE クラスタレベルでのトラフィック制御を試してみます。  
Cluster-wide Network Policy は通常の Namespace スコープの Network Policy とは異なり、クラスタスコープのポリシーを適用することができます。  
これにより、クラスタ全体で強制させたい通信制御を定義することが可能です。  

今回は以下のように `role: backend` というラベルを持った　Pod が `role: frontend` というラベルを持った Pod からのみ port:80,5000 で通信できるという制御を設定します。  

```yaml
apiVersion: "cilium.io/v2"
kind: CiliumClusterwideNetworkPolicy
metadata:
  name: "l4-rule-ingress"
spec:
  endpointSelector:
    matchLabels:
      role: backend
  ingress:
    - fromEndpoints:
        - matchLabels:
            role: frontend
      toPorts:
        - ports:
            - port: "80"
              protocol: TCP
            - port: "5000"
              protocol: TCP
```

以下コマンドを実行し、Cluster-wide Network Policy を適用します。  

```bash
kubectl apply -f cluster-network-policy.yaml
```

以前の手順でデプロイした `pets-deployment` というアプリケーションには `role: backend` というラベルが付与されている状態なので、Frontend 相当の Pod をデプロイして動作を確認します。  

```bash
kubectl apply -f service.yaml
kubectl apply -f frontend.yaml
```

```yaml
apiVersion: v1
kind: Pod
metadata:
  labels:
    app: frontend
    role: frontend
  name: frontend
spec:
  containers:
  - image: curlimages/curl
    name: frontend
    command: ["/bin/sh", "-c", "sleep infinity"]
  restartPolicy: Never
```

デプロイが完了したら `frontend` Pod から `pets-service` に向けて curl を発行し、アクセスできることを確認します。  

```bash
kubectl exec frontend -- curl pets-service/random-pets -s
```

また、`bad-pod-curl` という当該ラベルが付与されていない Pod もデプロイし動作を確認します。  

```bash
kubectl apply -f bad-pod-curl.yaml
```

デプロイが完了したら `bad-pod-curl` Pod から `pets-service` に向けて curl を発行し、アクセスできないことを確認します。  
```bash
kubectl exec bad-pod-curl -- curl pets-service/random-pets -s
```

一向にレスポンスが返らずタイムアウトします。タイムアウトまで待てない場合は Ctrl + C で終了します。  
Cluster-wide Network Policy が正常に動作し、通信制御できることを確認しました。  

以上で Lab2 は終了です。  

## **Congraturations!**

<walkthrough-conclusion-trophy></walkthrough-conclusion-trophy>

これにて GKE のセキュリティ機能を利用してガードレールを構築する方法を学習しました。  

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
cd $HOME && rm -rf gcp-getting-started-lab-jp/
```