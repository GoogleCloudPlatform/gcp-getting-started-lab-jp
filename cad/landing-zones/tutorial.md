# Landing Zones ウォークスルー

<walkthrough-watcher-constant key="region" value="us-central1"></walkthrough-watcher-constant>
<walkthrough-watcher-constant key="config-controller" value="managed-config"></walkthrough-watcher-constant>
<walkthrough-watcher-constant key="namespace" value="config-control"></walkthrough-watcher-constant>
<walkthrough-watcher-constant key="kpt-ver" value="v1.0.0-beta.2"></walkthrough-watcher-constant>

## 始めましょう

Landing Zones をベースに Google Cloud のリソースを管理する手順です。

**所要時間**: 約 45 分

**前提条件**:

- Google Cloud 上にプロジェクトが作成してある
- プロジェクトのオーナー権限をもつアカウントで Cloud Shell にログインしている

**[開始]** ボタンをクリックして次のステップに進みます。

## プロジェクトの設定

この手順の中で実際にリソースを構築する対象のプロジェクトを選択してください。

<walkthrough-project-billing-setup permissions="compute.googleapis.com"></walkthrough-project-billing-setup>

## gcloud 設定 - プロジェクト

gcloud コマンドでは操作の対象とするプロジェクトの設定が必要です。環境変数 `GOOGLE_CLOUD_PROJECT` に Google Cloud プロジェクト ID を設定し、

```bash
export GOOGLE_CLOUD_PROJECT="{{project-id}}"
```

gcloud のデフォルト プロジェクトを設定します。

```bash
gcloud config set project "${GOOGLE_CLOUD_PROJECT}"
```

## API の有効化

Google Cloud では利用したい機能ごとに、有効化を行う必要があります。
ここでは、以降のハンズオンで利用する機能を事前に有効化しておきます。

```bash
gcloud services enable krmapihosting.googleapis.com cloudresourcemanager.googleapis.com container.googleapis.com compute.googleapis.com
```

`Operation 〜 finished successfully.` と表示が出ることを確認します。

## Config Controller の起動

請求アカウントや組織 ID を取得し、

```bash
export CONFIG_CONTROLLER_NAME="{{config-controller}}"
export BILLING_ACCOUNT=$( gcloud beta billing projects describe "${GOOGLE_CLOUD_PROJECT}" \
  '--format=value(billingAccountName)' | sed 's/.*\///' )
export ORG_ID=$( gcloud projects get-ancestors "${GOOGLE_CLOUD_PROJECT}" --format='get(id)' | tail -1 )
export PROJECT_NUMBER=$( gcloud projects list --filter="${GOOGLE_CLOUD_PROJECT}" \
  --format="value(PROJECT_NUMBER)" )
export OWNER_EMAIL=$(gcloud auth list --filter=status:ACTIVE --format='value(account)')
```

Config Controller を起動します。15 分ほどかかります。Config Controller は [Config Sync](https://cloud.google.com/kubernetes-engine/docs/add-on/config-sync/overview?hl=ja)、[Policy Controller](https://cloud.google.com/anthos-config-management/docs/concepts/policy-controller?hl=ja)、[Config connector](https://cloud.google.com/config-connector/docs/overview?hl=ja) を Google マネージドでご提供するサービスです。Landing zones を管理する制御層として利用します。

```bash
gcloud alpha anthos config controller create "${CONFIG_CONTROLLER_NAME}" --location {{region}}
```

## Config Controller へ権限の付与

Config Controller が起動したことを確認しつつ、クレデンシャルを取得します。

```bash
gcloud alpha anthos config controller list --location {{region}}
gcloud alpha anthos config controller get-credentials "${CONFIG_CONTROLLER_NAME}" \
  --location {{region}}
```

Config Controller が正しくインストールされたことを kubectl から確認してみましょう。

```bash
kubectl wait -n cnrm-system --for=condition=Ready pod --all
```

Config Controller に Google Cloud のリソースを操作する権限を付与します。

```bash
export SA_EMAIL="$( kubectl get ConfigConnectorContext -n {{namespace}} \
  -o jsonpath='{.items[0].spec.googleServiceAccount}' 2> /dev/null )"
gcloud projects add-iam-policy-binding "${GOOGLE_CLOUD_PROJECT}" \
  --member "serviceAccount:${SA_EMAIL}" \
  --role "roles/owner"
```

組織レベルの変更も許可する場合、組織管理者ロールも付与します。

```bash
gcloud organizations add-iam-policy-binding "${ORG_ID}" \
  --member="serviceAccount:${SA_EMAIL}" \
  --role "roles/resourcemanager.organizationAdmin" \
  --condition=None
```

## GitOps パイプラインの設定

Google Cloud のインフラを [Configuration as Data](https://cloud.google.com/blog/ja/products/containers-kubernetes/understanding-configuration-as-data-in-kubernetes) の思想で管理する第一歩として、理想状態をバージョン管理し、master ブランチへの push で「テスト & Config Controller が参照するリポジトリへ連携」を自動化するパイプラインを作成します。

まず、[kpt](https://kpt.dev/) をインストール / または v1 系に更新します。

```bash
sudo curl -Lo /usr/bin/kpt https://github.com/GoogleContainerTools/kpt/releases/download/{{kpt-ver}}/kpt_linux_amd64
```

GitOps パイプラインのテンプレートをダウンロードし、

```bash
cd ~
kpt pkg get https://github.com/GoogleCloudPlatform/gcp-getting-started-lab-jp.git/cad/landing-zones/gitops@landing-zones gitops
```

プロジェクト ID やプロジェクト番号を修正します。

```text
cat << EOF > gitops/setters.yaml
apiVersion: v1
kind: ConfigMap
metadata: # kpt-merge: /setters-config
  name: setters-config
data:
  namespace: {{namespace}}
  cluster-name: "${CONFIG_CONTROLLER_NAME}"
  deployment-repo: deployment-repo
  project-id: "${GOOGLE_CLOUD_PROJECT}"
  project-number: "${PROJECT_NUMBER}"
  source-repo: source-repo
EOF
```

## GitOps パイプラインの構築

Config Controller にパイプラインの作成を指示し

```bash
kpt fn render gitops/ -o unwrap | kubectl apply -f -
```

ソースリポジトリの準備が整うまで 5 分ほど待機します。`error: timed out` が表示される場合は繰り返し実行し、リソースが作成されるのをお待ち下さい。

```bash
kubectl wait --for=condition=READY --timeout=300s -n {{namespace}} \
    cloudbuildtrigger/source-repo-cicd-trigger
```

作成されたリソースを確認してみます。

```bash
kubectl get -n {{namespace}} gcp
```

ここまでで主に、以下のリソースが作成されています。

- source-repo: インフラの理想状態を人間が相互レビュー、承認、自動テストするための git リポジトリ
- deployment-repo: 実環境が理想状態の Single Source of Truth として参照する git リポジトリ
- Cloud Build トリガー: source-repo への push でテストなどを起動
- Config Management: Config Controller が deployment-repo の master ブランチを監視する設定

実運用において `source-repo` をお使いの GitHub や GitLab とする場合は [こちらの設定](https://github.com/GoogleCloudPlatform/gcp-getting-started-lab-jp/blob/landing-zones/cad/landing-zones/gitops/hydration-trigger.yaml) を参考に Cloud Build トリガーをそれに併せて設定し、ビルドステップの中で、適用すべきリソースを `deployment-repo` に git push することで同様のパイプラインが構成できます。

## パイプラインそのものを GitOps 管理下へ

ローカルの git の設定を行います。

```bash
git config --global user.name "$(whoami)"
git config --global user.email "${OWNER_EMAIL}"
```

ソースリポジトリをローカルに clone し、初期コミットします。

```text
gcloud source repos clone source-repo
cd ~/source-repo
cat << EOF > Kptfile
apiVersion: kpt.dev/v1
kind: Kptfile
metadata:
  name: {{namespace}}
EOF
git add Kptfile
git commit -m "init"
git push -u origin master
```

資材を commit、リモートリポジトリに push します。

```bash
mv ~/gitops ./
git add gitops/
git commit -m "Add GitOps blueprint"
git push
```

これにより先に構築したパイプラインが起動し、パイプラインそのものが Config Controller 管理下に入ります。実環境の Single Source of Truth となるテンプレートは、変数が Kpt によりレンダリングされた実際の値と置換され [`deployment-repo`](https://source.cloud.google.com/{{project-id}}/) へ連携されています。

## Landing zone の初期化

Landing zones のブループリントをダウンロードし、

```bash
kpt pkg get https://github.com/GoogleCloudPlatform/gcp-getting-started-lab-jp.git/cad/landing-zones/landing-zone@landing-zones landing-zone
git add landing-zone/
git commit -m "Add landing zone"
```

プロジェクト ID や請求アカウントなどの適切な設定に変更しましょう。

```text
cat << EOF > landing-zone/setters.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: setters-config
data:
  billing-account-id: "${BILLING_ACCOUNT}"
  group-billing-admins: "user:${OWNER_EMAIL}"
  group-org-admins: "user:${OWNER_EMAIL}"
  management-namespace: {{namespace}}
  management-project-id: "${GOOGLE_CLOUD_PROJECT}"
  org-id: "${ORG_ID}"
EOF
```

このブループリントには namespaces 以下に次のリソース定義が含まれています。

- 組織管理するためのサービスアカウント
- ログを分析するためのサービスアカウント
- ネットワークを管理するためのサービスアカウント
- 組織のポリシー管理権限をもつサービスアカウント
- プロジェクトを管理するためのサービスアカウント

## 組織ポリシーの編集

Landing zones では[組織ポリシー](https://cloud.google.com/resource-manager/docs/organization-policy/overview?hl=ja)も管理できます。[GitHub リポジトリ](https://github.com/GoogleCloudPlatform/blueprints/tree/main/catalog/landing-zone/policies) には以下のような制限サンプルがあります。

- compute.disableNestedVirtualization KVM 互換のハイパーバイザが VM 内にインストールされないようにします
- compute.disableSerialPortAccess VM へのシリアルポート アクセスを無効化します
- compute.disableGuestAttributesAccess VM のゲスト属性の読み取る API アクセスを制限します
- compute.vmExternalIpAccess VM の外部 IP アクセスを無効にします
- compute.skipDefaultNetworkCreation デフォルトの自動作成 VPC が作られなくなります
- compute.restrictXpnProjectLienRemoval 共有 VPC を誤って削除されるのを防止します
- sql.restrictPublicIp 外部パブリック IP アドレスを使用する Cloud SQL インスタンスが作成できなくなります
- iam.disableServiceAccountKeyCreation サービス アカウント キーの発行を制限します
- storage.uniformBucketLevelAccess 均一なバケットレベルのアクセスを有効にします

試しにこれらも Landing zones で試される場合は landing-zone/policies 以下に YAML をコピーしてください。

## Landing zone の作成・確認

変更内容を push し、Config Controller にリコンサイルさせます。

```bash
git add landing-zone/Kptfile
git commit -a -m "Customize landing zone blueprint"
git push
```

左上のメニューから **Cloud Build** セクションを選びます。

<walkthrough-menu-navigation sectionId="CLOUD_BUILD_SECTION"></walkthrough-menu-navigation>

履歴から、テストが通り、デプロイメント リポジトリにリソース定義が連携されるのを待ちましょう。

その後、`hierarchy` / `projects` / `policies` / `logging` そして `networking` というネームスペースが作成されたことを確認します。

```bash
kubectl get ns
```

ここまでに生成されたリソースの一覧を取得します。

```bash
kubectl get -n {{namespace}} gcp
```

実際に作られたリソースの一つを確認してみましょう。

```bash
kubectl describe -n {{namespace}} iampolicymember/org-admins-ia
```

組織ポリシーを指定した方は、それが正常に生成されたことを確認してみます。

```bash
gcloud resource-manager org-policies list --organization "${ORG_ID}"
```

## リソース階層の設定

組織下に環境フォルダを配置するシンプルなブループリントを取得し

```bash
cd ~/source-repo
kpt pkg get https://github.com/GoogleCloudPlatform/gcp-getting-started-lab-jp.git/cad/landing-zones/resources/org@landing-zones landing-zone/org
```

プロジェクト ID や請求アカウントなどの適切な設定に変更しましょう。

```text
cat << EOF > landing-zone/org/setters.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: setters-config
data:
  namespace: hierarchy
  org-id: "${ORG_ID}"
EOF
```

資材を commit、リモートリポジトリに push します。

```bash
git add landing-zone/org/
git commit -m "Add resource hierarchy and update folder naming convention."
git push
```

フォルダが作成されるまで待機します。

```bash
kubectl wait -n hierarchy --for=condition=Ready --timeout=300s folders --all
```

Landing zones によりフォルダが生成されたことを確認しましょう。

```bash
gcloud resource-manager folders list --organization="${ORG_ID}"
```

## 共有 VPC ホストプロジェクトの作成

Landing zone の一部として、[共有 VPC ネットワーク](https://cloud.google.com/architecture/best-practices-vpc-design?hl=ja#single-host-project-multiple-service-projects-single-shared-vpc) の管理を推奨しています。

開発環境フォルダ (dev) に共有 VPC ホスト プロジェクトを作りましょう。名前を決め、

```bash
export HOST_PROJECT_ID="dev-sharedvpc-${ORG_ID}"
```

`projects` フォルダ以下にプロジェクトの雛形をダウンロードします。

```bash
mkdir -p ~/source-repo/landing-zone/projects
kpt pkg get https://github.com/GoogleCloudPlatform/blueprints.git/catalog/project@kpt-v1 landing-zone/projects/${HOST_PROJECT_ID}
```

さらに一つブループリントを追加して、プロジェクトを `共有 VPC ホスト プロジェクト` にします。

```bash
kpt pkg get https://github.com/GoogleCloudPlatform/blueprints.git/catalog/networking/shared-vpc@kpt-v1 landing-zone/projects/${HOST_PROJECT_ID}/host-project
```

プロジェクト ID や請求アカウントなどの適切な設定に変更しましょう。

```text
cat << EOF > landing-zone/projects/${HOST_PROJECT_ID}/setters.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: setters
data:
  folder-name: dev
  folder-namespace: hierarchy
  networking-namespace: networking
  project-id: "${HOST_PROJECT_ID}"
EOF
cat << EOF > landing-zone/projects/${HOST_PROJECT_ID}/host-project/setters.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: setters
data:
  namespace: networking
  project-id: "${HOST_PROJECT_ID}"
EOF
```

資材を commit、リモートリポジトリに push します。

```bash
git add landing-zone/projects/
git commit -m "Add networking host project"
git push
```

ホスト プロジェクトが作成されるのを待機します。

```bash
kubectl wait --for=condition=READY --timeout=300s -n projects \
    project "${HOST_PROJECT_ID}"
```

## 共有 VPC の作成

開発環境フォルダ (dev) に共有 VPC を作りましょう。VPC のブループリントを取得し、

```bash
kpt pkg get https://github.com/GoogleCloudPlatform/blueprints.git/catalog/networking/network@kpt-v1 landing-zone/network/dev/
```

プロジェクト ID や請求アカウントなどの適切な設定に変更しましょう。

```text
cat << EOF > landing-zone/network/dev/setters.yaml
apiVersion: v1
kind: ConfigMap
metadata: # kpt-merge: /setters
  name: setters
data:
  namespace: networking
  network-name: dev-network-shared
  project-id: "${HOST_PROJECT_ID}"
  region: asia-northeast1
  vpn-secret-key: vpn-shared-secret
  vpn-secret-name: vpn-shared-secret
  prefix: ""
EOF
```

ここで [Cloud VPN で使用される事前共有キー](https://cloud.google.com/network-connectivity/docs/vpn/how-to/generating-pre-shared-key?hl=ja) を作成するのすが、機密性が高いため Config Controller に直接送信しておきます。

```bash
SECRET_VALUE=$(openssl rand -base64 24)
kubectl create secret generic vpn-shared-secret \
    --from-literal=vpn-shared-secret="${SECRET_VALUE}" \
    -n networking
echo "SECRET_VALUE: ${SECRET_VALUE}"
```

資材を commit、リモートリポジトリに push します。

```bash
git add landing-zone/network/
git commit -m "Add network setup"
git push
```

共有 VPC トンネルが作成されるのを待ちましょう。

```bash
kubectl wait --for=condition=READY --timeout=300s -n networking \
    computevpntunnel dev-network-shared-vpn-tunnel
```

## トラブルシュート

### テンプレートの不整合

**Cloud Build** コンソールから、履歴をご確認ください。

<walkthrough-menu-navigation sectionId="CLOUD_BUILD_SECTION"></walkthrough-menu-navigation>

### Config Sync の同期エラー

[nomos コマンド](https://cloud.google.com/anthos-config-management/docs/how-to/nomos-command?hl=ja)により、状況を把握できます。

```bash
nomos status
```

## リソースの削除

依存するリソースから段階的に削除します。まずは最後に作った共有 VPC などを消し、

```bash
git rm -rf landing-zone/network
git commit -m "Delete downstream resources"
git push
```

プロジェクトを削除します。

```bash
git rm -rf landing-zone/projects
git commit -m "Delete projects"
git push
```

フォルダなど組織リソースを削除します。

```bash
git rm -rf landing-zone/org
git commit -m "Delete hierarchy"
git push
```

組織をまたいだサービスアカウントなどを削除します。

```bash
git rm -rf landing-zone
git commit -m "Delete hierarchy"
git push
```

Config Controller を使った CI/CD パイプラインを削除し、

```bash
kpt fn render gitops/ -o unwrap | kubectl delete -f -
```

最後に Config Controller を削除します。

```bash
gcloud alpha anthos config controller delete \
   "${CONFIG_CONTROLLER_NAME}" --location {{region}}
```

## プロジェクトの削除

もしこの手順のためにプロジェクトを作成していた場合は、不要な料金の発生を避けるためにプロジェクトを削除してください。

```bash
gcloud projects delete {{project-id}}
```

## これで終わりです

<walkthrough-conclusion-trophy></walkthrough-conclusion-trophy>

すべて完了しました。
