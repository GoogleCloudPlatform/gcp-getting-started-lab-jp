# Landing Zones ウォークスルー

<walkthrough-watcher-constant key="region" value="us-central1"></walkthrough-watcher-constant>
<walkthrough-watcher-constant key="config-controller" value="managed-config"></walkthrough-watcher-constant>
<walkthrough-watcher-constant key="kpt-ver" value="v1.0.0-beta.1"></walkthrough-watcher-constant>

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
export CONFIG_CONTROLLER_NAME={{config-controller}}
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

Config Controller に、組織レベルのものも含め、Google Cloud のリソースを操作する権限を付与します。

```bash
export SA_EMAIL="$( kubectl get ConfigConnectorContext -n config-control \
  -o jsonpath='{.items[0].spec.googleServiceAccount}' 2> /dev/null )"
gcloud projects add-iam-policy-binding "${GOOGLE_CLOUD_PROJECT}" \
  --member "serviceAccount:${SA_EMAIL}" \
  --role "roles/owner"
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
cat << EOF > gitops/Kptfile
apiVersion: kpt.dev/v1
kind: Kptfile
metadata:
  name: gitops
info:
  description: This blueprint generates a GitOps CI/CD pipeline for use with ACM
pipeline:
  mutators:
    - image: gcr.io/kpt-fn/apply-setters:v0.1
      configMap:
        cluster-name: "${CONFIG_CONTROLLER_NAME}"
        deployment-repo: deployment-repo
        namespace: config-control
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
kubectl wait --for=condition=READY --timeout=300s -n config-control \
    cloudbuildtrigger/source-repo-cicd-trigger
```

ここまでで Config Controller により、主に以下のリソースが作成されます。

- source-repo: インフラの理想状態を人間が相互レビュー、承認、自動テストするための git リポジトリ
- deployment-repo: 実環境が理想状態の Single Source of Truth として参照する git リポジトリ
- Cloud Build トリガー: source-repo への push でテストなどを起動
- Config Management: Config Controller が deployment-repo の master ブランチを監視する設定

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
  name: config-control
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

## リソースの確認

Config Controller が正しくインストールされたことを確認してみましょう。

```bash
kubectl wait -n cnrm-system --for=condition=Ready pod --all
```

Config Controller によって Google Cloud のリソースが正常に作成されたかを確認します。

```bash
kubectl get -n config-control gcp
```

## Landing zone の初期化

Landing zones のブループリントをダウンロードし、

```bash
kpt pkg get https://github.com/GoogleCloudPlatform/gcp-getting-started-lab-jp.git/cad/landing-zones/landing-zone@landing-zones landing-zone
git add landing-zone/
git commit -m "Add landing zone"
```

プロジェクト ID や請求アカウントなどの適切な設定に変更しましょう。

```text
cat << EOF > landing-zone/Kptfile
apiVersion: kpt.dev/v1
kind: Kptfile
metadata:
  name: landing-zone
info:
  description: Foundational landing zone blueprint for Google Cloud
pipeline:
  mutators:
    - image: gcr.io/kpt-fn/apply-setters:v0.1
      configMap:
        billing-account-id: "${BILLING_ACCOUNT}"
        group-billing-admins: "${OWNER_EMAIL}"
        group-org-admins: "${OWNER_EMAIL}"
        management-namespace: config-control
        management-project-id: "${GOOGLE_CLOUD_PROJECT}"
        org-id: "${ORG_ID}"
    - image: gcr.io/config-management-release/policy-controller-validate
EOF
```

## 組織ポリシーの編集

このリポジトリでは以下の組織ポリシーが作成されます。

- compute.disableNestedVirtualization KVM 互換のハイパーバイザが VM 内にインストールされないようにします
- compute.disableSerialPortAccess VM へのシリアルポート アクセスを無効化します
- compute.disableGuestAttributesAccess VM のゲスト属性の読み取る API アクセスを制限します
- compute.vmExternalIpAccess VM の外部 IP アクセスを無効にします
- compute.skipDefaultNetworkCreation デフォルトの自動作成 VPC が作られなくなります
- compute.restrictXpnProjectLienRemoval 共有 VPC を誤って削除されるのを防止します
- sql.restrictPublicIp 外部パブリック IP アドレスを使用する Cloud SQL インスタンスが作成できなくなります
- iam.disableServiceAccountKeyCreation サービス アカウント キーの発行を制限します
- storage.uniformBucketLevelAccess 均一なバケットレベルのアクセスを有効にします

これら制約のいずれかが組織に問題を引き起こしそうであれば、関連する YAML ファイルを削除する必要があります。例えば、シリアルポートアクセスを無効化するポリシーを作りたくない場合、該当のファイルを削除してください。

```bash
git rm landing-zone/policies/disable-serial-port.yaml
```

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
kubectl get gcp --all-namespaces
```

組織ポリシーが正常に生成されたことを確認してみます。

```bash
gcloud resource-manager org-policies list --organization "${ORG_ID}"
```

## リソースの削除

Config Controller 管理下のリソースを GitOps を利用せず "簡易的に" 削除していきます。

```bash
kpt fn render -o unwrap | kubectl delete -f -
```

Config Controller を削除します。

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
