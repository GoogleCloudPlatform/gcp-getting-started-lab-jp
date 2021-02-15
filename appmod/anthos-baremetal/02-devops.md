# Anthos clusters on Bare Metal での DevOps

<walkthrough-watcher-constant key="region" value="asia-northeast1"></walkthrough-watcher-constant>
<walkthrough-watcher-constant key="zone" value="asia-northeast1-c"></walkthrough-watcher-constant>
<walkthrough-watcher-constant key="sa" value="sa-baremetal"></walkthrough-watcher-constant>
<walkthrough-watcher-constant key="cluster" value="baremetal-trial"></walkthrough-watcher-constant>
<walkthrough-watcher-constant key="vm-workst" value="workstation"></walkthrough-watcher-constant>
<walkthrough-watcher-constant key="repo" value="anthos-sample-app"></walkthrough-watcher-constant>

## 始めましょう

[Anthos clusters on Bare Metal](https://cloud.google.com/anthos/clusters/docs/bare-metal?hl=ja) 上で DevOps を体験する手順です。

**所要時間**: 約 20 分

**前提条件**:

- Anthos clusters on Bare Metal クラスタが起動していること
- プロジェクトのオーナー権限をもつアカウントで Cloud Shell にログインしている

**[開始]** ボタンをクリックして次のステップに進みます。

## プロジェクトの設定

この手順の中で実際にリソースを操作する対象のプロジェクトを選択してください。

<walkthrough-project-billing-setup permissions="compute.googleapis.com"></walkthrough-project-billing-setup>

## Anthos Config Management の有効化

gcloud のデフォルト プロジェクトを設定します。

```bash
export GOOGLE_CLOUD_PROJECT="{{project-id}}"
gcloud config set project "${GOOGLE_CLOUD_PROJECT}"
```

Anthos Config Management (ACM) を初めて使用する場合、次の手順で機能を有効にします。

```bash
gcloud alpha container hub config-management enable
```

## API の有効化

以降のハンズオンで利用する機能を事前に有効化します。

```bash
gcloud services enable connectgateway.googleapis.com sourcerepo.googleapis.com
```

## Cloud Source Repositories の準備

ソースコードを配置するための Git リポジトリを Cloud Source Repository（CSR）に作成します。

```bash
gcloud source repos create {{repo}}
```

実際に作られたリポジトリを確認してみましょう。**Source Repositories** セクションを選びます。

<walkthrough-menu-navigation sectionId="CLOUDDEV_SECTION"></walkthrough-menu-navigation>

## CSR へ接続するための SSH 鍵生成

SSH 認証鍵ペアを作成します。

```bash
ssh-keygen -t rsa -b 4096 -C "$(whoami)" -N "" -f "$HOME/.ssh/csr_rsa"
cat "$HOME/.ssh/csr_rsa.pub"
```

ブラウザから、生成した公開鍵をアップロードします。キー名は任意、鍵は直前で出力された結果のうち **ssh-rsa** で始まる文字列をコピーしてください。

[https://source.cloud.google.com/user/ssh_keys?register=true](https://source.cloud.google.com/user/ssh_keys?register=true)

CSR への接続方法を SSH の設定として保存し

```text
logined_account=$(gcloud config get-value core/account)
cat << EOF >~/.ssh/config
Host csr
    Hostname source.developers.google.com
    User ${logined_account}
    IdentityFile $HOME/.ssh/csr_rsa
EOF
```

git の設定をしつつ、ローカルにリポジトリが clone してみましょう。

```bash
git config --global user.name "$(whoami)"
git config --global user.email "${logined_account}"
cd $HOME
git clone "ssh://csr:2022/p/{{project-id}}/r/{{repo}}"
```

中身はまだ空なので、`warning: You appear to have cloned an empty repository.` と表示されれば OK です。

## Anthos Config Management へ CSR へのアクセスを許可

管理ワークステーションへ SSH 秘密鍵を転送した後、中に入ります。

```bash
gcloud config set compute/region {{region}}
gcloud config set compute/zone {{zone}}
gcloud compute scp --tunnel-through-iap $HOME/.ssh/csr_rsa {{vm-workst}}:$HOME/.ssh/
gcloud compute ssh {{vm-workst}} --tunnel-through-iap
```

ワークステーション上の環境変数を再設定して、

```bash
export HYBRID_CLUSTER={{cluster}}
export GOOGLE_APPLICATION_CREDENTIALS={{sa}}-creds.json
export KUBECONFIG="bmctl-workspace/${HYBRID_CLUSTER}/${HYBRID_CLUSTER}-kubeconfig"
```

秘密鍵をクラスタ内の新しい Secret に追加します。

```bash
kubectl create ns config-management-system
kubectl create secret generic git-creds --namespace=config-management-system --from-file=ssh=$HOME/.ssh/csr_rsa
rm -rf $HOME/.ssh/csr_rsa
```

## Anthos Config Management の構成

**（前項から引き続き、管理ワークステーション上で実行してください）**

次のコマンドを使用して Operator CustomResourceDefinition（CRD）の最新バージョンをダウンロードし、Operator をクラスタへデプロイします。

```bash
gsutil cp gs://config-management-release/released/latest/config-management-operator.yaml config-management-operator.yaml
kubectl apply -f config-management-operator.yaml
```

Google Cloud へログインしているユーザーのメールアドレスを `logined_account` に設定してください。

```bash
logined_account=
```

Config Management リソースを作成します。

```text
cat << EOF >config-management.yaml
apiVersion: configmanagement.gke.io/v1
kind: ConfigManagement
metadata:
  name: config-management
spec:
  clusterName: {{cluster}}
  git:
    syncRepo: ssh://${logined_account}@source.developers.google.com:2022/p/{{project-id}}/r/{{repo}}
    syncBranch: master
    secretType: ssh
EOF
kubectl apply -f config-management.yaml
```

インストールされたかを確認してみましょう。

```bash
kubectl -n kube-system get pods | grep config-management
kubectl get ns | grep 'config-management-system'
kubectl get pods -n config-management-system
```

以下のような応答があれば正常です。

- config-management-operator-6f988f5fdd-4r7tr 1/1 Running 0 26s
- config-management-system Active 1m

## git へのリソース変更

**（管理ワークステーション上ではなく、Cloud Shell にもどり、以下を実行してください）**

ACM と連携した git リポジトリに、サンプルプロジェクトをコピーします。

```bash
git clone https://github.com/GoogleCloudPlatform/csp-config-management.git ~/sample
cd $HOME/{{repo}}
cp -rf $HOME/sample/foo-corp/* ./
```

CSR へ変更を送信しましょう。

```bash
git add .
git commit -m 'init'
git push origin master
```

ブラウザから変更が反映されていることを確認してみましょう。

[https://source.cloud.google.com/{{project-id}}/{{repo}}](https://source.cloud.google.com/{{project-id}}/{{repo}})

### リソースの確認

CSR で実際の定義を見ながら、該当のリソースが作成されたかを確かめてみましょう。

```bash
gcloud compute ssh {{vm-workst}} --tunnel-through-iap --command "KUBECONFIG=bmctl-workspace/{{cluster}}/{{cluster}}-kubeconfig kubectl get rolebinding --all-namespaces | grep sre"
```

## チャレンジ問題: ACM を使いこなす

- すでにある定義を変更してみましょう
- CSR に定義のある k8s リソースを手動で削除してみましょう

## これで終わりです

<walkthrough-conclusion-trophy></walkthrough-conclusion-trophy>

すべて完了しました。リソースの削除にお進みください。

```bash
teachme ~/cloudshell_open/gcp-getting-started-lab-jp/appmod/anthos-baremetal/09-teardown.md
```
