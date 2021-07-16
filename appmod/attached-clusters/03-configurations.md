# Anthos Attached Clusters ウォークスルー (設定管理)

<walkthrough-watcher-constant key="region" value="asia-northeast1"></walkthrough-watcher-constant>
<walkthrough-watcher-constant key="zone" value="asia-northeast1-c"></walkthrough-watcher-constant>
<walkthrough-watcher-constant key="cluster" value="anthos"></walkthrough-watcher-constant>
<walkthrough-watcher-constant key="repo" value="anthos-sample-app"></walkthrough-watcher-constant>

## 始めましょう

Anthos Attached Clusters の設定群を管理する手順です。

**所要時間**: 約 20 分

**前提条件**:

- Anthos Attached Clusters として Kubernetes クラスタが登録されている。

**[開始]** ボタンをクリックして次のステップに進みます。

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
git clone "ssh://csr:2022/p/{{project-id}}/r/{{repo}}" $HOME/csr
```

中身はまだ空なので、`warning: You appear to have cloned an empty repository.` と表示されれば OK です。

## Anthos Config Management へ CSR へのアクセスを許可

自分のログイン名を変数として使う準備をします。

```text
account="${logined_account%%@*}"
```

Kind クラスタの認証情報を取得し、

```bash
gcloud beta container hub memberships get-credentials "{{cluster}}-attached-${account}"
```

秘密鍵をクラスタ内の新しい Secret に追加します。

```bash
kubectl create ns config-management-system
kubectl create secret generic git-creds --namespace=config-management-system --from-file=ssh=$HOME/.ssh/csr_rsa
```

## Anthos Config Management の構成

次のコマンドを使用して Operator の最新バージョンをダウンロードし、クラスタへデプロイします。

```bash
gsutil cp gs://config-management-release/released/latest/config-management-operator.yaml .
kubectl apply -f config-management-operator.yaml
```

Config Management リソースを作成します。

```text
cat << EOF > config-management.yaml
apiVersion: configmanagement.gke.io/v1
kind: ConfigManagement
metadata:
  name: config-management
spec:
  clusterName: {{cluster}}
  git:
    syncRepo: ssh://$(gcloud config get-value core/account)@source.developers.google.com:2022/p/{{project-id}}/r/{{repo}}
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

ACM と連携した git リポジトリに、サンプルプロジェクトをコピーします。

```bash
git clone https://github.com/GoogleCloudPlatform/anthos-config-management-samples.git $HOME/acm-samples
cp -rf $HOME/acm-samples/foo-corp/* $HOME/{{repo}}/
```

CSR へ変更を送信しましょう。

```bash
cd $HOME/{{repo}}
git add .
git commit -m 'init'
git push origin master
```

ブラウザから変更が反映されていることを確認してみましょう。

[https://source.cloud.google.com/{{project-id}}/{{repo}}](https://source.cloud.google.com/{{project-id}}/{{repo}})

### リソースの確認

CSR で実際の定義を見ながら、該当のリソースが作成されたかを確かめてみましょう。

```bash
kubectl get rolebinding --all-namespaces | grep sre
```

## Congraturations!

<walkthrough-conclusion-trophy></walkthrough-conclusion-trophy>

すべて完了しました。

次のステップにお進みください。

```bash
teachme ~/cloudshell_open/gcp-getting-started-lab-jp/appmod/attached-clusters/04-operations.md
```
