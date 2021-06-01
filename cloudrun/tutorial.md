# **はじめてみよう Cloud Run ハンズオン**

## **Google Cloud プロジェクトの選択**

ハンズオンを行う Google Cloud プロジェクトを選択し、 **Start** をクリックしてください。

<walkthrough-project-setup>
</walkthrough-project-setup>

<walkthrough-watcher-constant key="region" value="asia-northeast1"></walkthrough-watcher-constant>
<walkthrough-watcher-constant key="repo-name" value="cloudrun-handson"></walkthrough-watcher-constant>
<walkthrough-watcher-constant key="github-repo" value="GoogleCloudPlatform/gcp-getting-started-lab-jp/cloudrun"></walkthrough-watcher-constant>
<walkthrough-watcher-constant key="branch-name" value="master"></walkthrough-watcher-constant>

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
gcloud config set project {{project-id}}
```

承認するかどうかを聞かれるメッセージがでた場合は、`承認` ボタンをクリックします。

### **3. gcloud からの Cloud Run のデフォルト設定**

Cloud Run の利用するリージョン、プラットフォームのデフォルト値を設定します。

```bash
gcloud config set run/region {{region}}
gcloud config set run/platform managed
```

ここではリージョンを東京、プラットフォームをフルマネージドに設定しました。この設定を行うことで、gcloud コマンドから Cloud Run を操作するときに毎回指定する必要がなくなります。

<walkthrough-footnote>CLI（gcloud）で利用するプロジェクトの指定、Cloud Run のデフォルト値の設定が完了しました。次にハンズオンで利用する機能（API）を有効化します。</walkthrough-footnote>

## **Google Cloud 環境設定**

Google Cloud では利用したい機能（API）ごとに、有効化を行う必要があります。
ここでは、以降のハンズオンで利用する機能を事前に有効化しておきます。

```bash
gcloud services enable artifactregistry.googleapis.com run.googleapis.com cloudbuild.googleapis.com sourcerepo.googleapis.com container.googleapis.com
```

**GUI**: [API ライブラリ](https://console.cloud.google.com/apis/library?project={{project-id}})

<walkthrough-footnote>必要な機能が使えるようになりました。次に実際に Cloud Run にアプリケーションをデプロイする方法を学びます。</walkthrough-footnote>

## **Cloud Run への複数のデプロイ手段**

<walkthrough-tutorial-duration duration=15></walkthrough-tutorial-duration>

Cloud Run では様々な方法でデプロイが可能です。ここでは以下の 2 つの方法でサンプルアプリケーションをデプロイします。

- Dockerfile を使い、ローカルでコンテナを作成、レジストリにプッシュしてからデプロイ
- Buildpacks、Cloud Build を使い、Dockerfile 無し、かつリポジトリの指定無しにデプロイ

<walkthrough-footnote>Cloud Run では複数のデプロイ方法があることを学びます。まず、本ハンズオンで利用するサンプルアプリケーションを見てみましょう。</walkthrough-footnote>

## **サンプルアプリケーション**

サンプル アプリケーションは Python で書かれており、HTTP で下記の REST API を公開しています。

このアプリケーションは数字の合計値を返す機能を備えているので以降、`sumservice` と呼びます。

### **Helloworld API**

- パス: /
  - `Hello World!` という文字列を返します。

### **数値合計 API**

- パス: /sum
  - JSON 形式で整数を複数 POST すると JSON 形式で合計値を返します。

例：

Request:

```json
{
  "numbers": [10, 20, 30]
}
```

Response:

```json
{
  "sum": 60
}
```

### **フォルダ、ファイル構成**

```terminal
.
└─ src
    └─ sumservice
        ├─ .dockerignore    # コンテナに含めないファイル群を指定するファイル
        ├─ Dockerfile       # Docker コンテナ作成定義ファイル
        ├─ Procfile         # 起動方法が記載されているファイル、Buildpacks でビルドするときに利用
        ├─ main.py          # メイン関数ソースファイル
        └─ requirements.txt # 利用ライブラリ一覧
```

<walkthrough-footnote>次に実際にアプリケーションを Cloud Run にデプロイします。</walkthrough-footnote>

## **Dockerfile を使い、ローカルでコンテナを作成、レジストリにプッシュしてからデプロイ**

[アーキテクチャ図](https://raw.githubusercontent.com/{{github-repo}}/{{branch-name}}/images/step_by_step_deployment.png)

### **準備**

また下記のボタンから Cloud Run の GUI を開いておきましょう。

<walkthrough-menu-navigation sectionId="CLOUD_RUN_SECTION"></walkthrough-menu-navigation>

### **1. リポジトリを作成（Artifact Registory）**

```bash
gcloud artifacts repositories create {{repo-name}} --repository-format=docker --location={{region}} --description="Docker repository for Cloud Run hands-on"
```

### **2. docker コマンドの認証設定**

```bash
gcloud auth configure-docker {{region}}-docker.pkg.dev
```

設定ファイルを更新してよいか聞かれた場合は、そのまま Enter を押します。

### **3. ローカル（Cloud Shell 上）にコンテナを作成**

```bash
(cd src/sumservice && docker build -t {{region}}-docker.pkg.dev/{{project-id}}/{{repo-name}}/sumservice:v1 .)
```

**ヒント**: カレントディレクトリを変えずに実行するために、カッコでくくっています。

### **4. 作成したコンテナをコンテナレジストリ（Artifact Registry）へ登録（プッシュ）する**

```bash
docker push {{region}}-docker.pkg.dev/{{project-id}}/{{repo-name}}/sumservice:v1
```

### **5. Cloud Run にデプロイ**

```bash
gcloud run deploy sumservice --image={{region}}-docker.pkg.dev/{{project-id}}/{{repo-name}}/sumservice:v1 --allow-unauthenticated
```

### **6. 動作確認**

```bash
SUM_URL=$(gcloud run services describe sumservice --format json | jq -r '.status.address.url')
curl -H "Content-Type: application/json" -d '{"numbers": [10, 20, 30, 300, 100]}' ${SUM_URL}/sum
```

次のように返ってくれば、正しくアプリケーションが動作しています。

```terminal
{
    "sum": 460
}
```

<walkthrough-footnote>コンテナレジストリ、コンテナの作成、プッシュなど一つ一つの手順をマニュアルで実行し、Cloud Run にデプロイすることができました。次により簡易にデプロイする方法を試します。</walkthrough-footnote>

## **Buildpacks、Cloud Build を使い、Dockerfile 無し、かつリポジトリの指定無しにデプロイ**

[アーキテクチャ図](https://raw.githubusercontent.com/{{github-repo}}/{{branch-name}}/images/single_step_deployment.png)

### **1. Dockerfile の削除（移動）**

Dockerfile 無しでデプロイできることを確かめるために、Dockerfile を退避します。

```bash
mv src/sumservice/Dockerfile /tmp/
```

**ヒント**: Buildpacks というソフトウェアを使い、Dockerfile 無しでのデプロイを実現しています。詳細は[こちら](https://cloud.google.com/blog/ja/products/containers-kubernetes/google-cloud-now-supports-buildpacks)を参照してください。

### **2. 一括でデプロイ**

```bash
gcloud beta run deploy sumservice --source src/sumservice/ --allow-unauthenticated
```

### **3. 動作確認**

```bash
SUM_URL=$(gcloud run services describe sumservice --format json | jq -r '.status.address.url')
curl -H "Content-Type: application/json" -d '{"numbers": [10, 20, 30, 300, 100]}' ${SUM_URL}/sum
```

先程と同様に、次のように返ってくることを確認します。

```terminal
{
    "sum": 460
}
```

前項の手順と比べ、以下の部分が簡略化できたことがわかります。

- Dockerfile の用意
- コンテナレジストリの作成
- コンテナをローカルで作成

以降のデプロイでは、主に簡易なこの手順を利用します。

<walkthrough-footnote>gcloud コマンドを使い、ソースコードから Cloud Run へのデプロイが 1 コマンドでできることを学びました。次に本番のユースケースに合わせた、Cloud Run でのより進んだデプロイ方法を学びます。</walkthrough-footnote>

## **様々なリリース構成、トラフィックのコントロール**

<walkthrough-tutorial-duration duration=15></walkthrough-tutorial-duration>

Cloud Run ではリリースの構成、トラフィックのコントロールが簡単に行えます。以下のユースケースを Cloud Run で実現します。

- カナリアリリース

  新リビジョン、旧リビジョンへのアクセスを割合（%）でコントロールし、徐々に新リビジョンへのアクセス割合を増やしていく

- 新リビジョンの限定公開

  新リビジョンを特定 URL でのみ公開し、動作確認の後、本番リリースする

## **カナリアリリース**

カナリアリリースは新リビジョンをトラフィックを流さない状態でデプロイし、徐々にトラフィックを流すように設定することで実現します。

[アーキテクチャ図](https://raw.githubusercontent.com/{{github-repo}}/{{branch-name}}/images/canary_release.png)

### **1. アプリケーションの修正**

```bash
sed -i -e "s/World/New World/" src/sumservice/main.py
```

### **2. 新リビジョンのデプロイ**

```bash
gcloud beta run deploy sumservice --source src/sumservice/ --allow-unauthenticated --no-traffic
```

**ヒント**: 新リビジョンにトラフィックを流さないよう、`--no-traffic` のオプションをつけています。これがない場合、デプロイされた瞬間にすべてのトラフィックが新リビジョンに流れます。

### **3. 新リビジョンに 10 %, 旧リビジョンに 90 % のアクセスを割り振り**

```bash
NEW_REV=$(gcloud run revisions list --format json | jq -r '.[].metadata.name' | grep 'sumservice-' | sort -r | sed -n 1p)
OLD_REV=$(gcloud run revisions list --format json | jq -r '.[].metadata.name' | grep 'sumservice-' | sort -r | sed -n 2p)
gcloud run services update-traffic sumservice --to-revisions=${NEW_REV}=10,${OLD_REV}=90
```

ターミナルに出力された URL をクリックするとブラウザが開きます。そこでリロードを繰り返してみます。まれに `Hello New World!` と表示されます。

### **4. すべてのアクセスを新リビジョンに割り振り**

```bash
gcloud run services update-traffic sumservice --to-latest
```

再度ブラウザからアクセスすると、何度アクセスしてもすべてのレスポンスが `Hello New World!` となっていることを確認します。

<walkthrough-footnote>リビジョン、トラフィックをコントロールし、カナリアリリースを実現しました。次に、新リビジョンを特定の URL でのみデプロイする方法を学びます。</walkthrough-footnote>

## **新リビジョンの限定公開**

デプロイ時にタグを付与することで、リビジョンに特定の URL をもたせることが可能です。ここではタグと、前のページで出てきた --no-traffic を組み合わせ、新リビジョンを限定公開します。

[アーキテクチャ図](https://raw.githubusercontent.com/{{github-repo}}/{{branch-name}}/images/limited_release.png)

### **1. アプリケーションの修正**

```bash
sed -i -e 's/New World/New Normal/' src/sumservice/main.py
```

**ヒント**: 前ページの更新で、すべてのアクセスに `New World` と返すようになっていました。

### **2. タグを付けて、新リビジョンをデプロイ**

```bash
gcloud beta run deploy sumservice --source src/sumservice/ --allow-unauthenticated --no-traffic --tag abcdefg
```

### **3. 新リビジョンへアクセス**

ターミナルに出力されたタグ付き URL をクリックします。
新リビジョンの `Hello New Normal!` が返ってくることを確認します。

今回デプロイしたリビジョンはこの URL でのみ稼働しています。そして、タグがない URL は旧バージョンが稼働しています。つまりこれを使うことで、事前に限定ユーザによるテストが可能です。

### **4. 本番リリース（すべてのアクセスを新リビジョンに割り振り）**

```bash
gcloud run services update-traffic sumservice --to-latest
```

### **5. サービスの削除**

次にここまで実施してきた手続きを自動化する方法を学びます。そのため、現在稼働している手動でデプロイしたサービスを削除します。

```bash
gcloud run services delete sumservice --quiet
```

<walkthrough-footnote>タグ、トラフィックのコントロール機能を使うことで特定の URL でのみリリースする方法を実現しました。次はここまで手動で実施してきた手続きを自動化する方法を学びます。</walkthrough-footnote>

## **CI / CD パイプラインの構築**

<walkthrough-tutorial-duration duration=20></walkthrough-tutorial-duration>

ここまで、ビルド、デプロイなどを手動で実施してきました。

Cloud Run ではソースコード リポジトリ（Cloud Source Repositories, GitHub など）、Cloud Build と連携させ、ソースコードが Push されたことを検知してデプロイするというパイプラインを簡単に構築できます。

ここで構築するパイプラインのアーキテクチャは下記になります。

[アーキテクチャ図](https://raw.githubusercontent.com/{{github-repo}}/{{branch-name}}/images/cicd_pipeline.png)

## **Git クライアント設定**

ソースコードを Google Cloud のマネージドなプライベート Git リポジトリである、Cloud Source Repositories（CSR） に格納します。

そのため、リポジトリを操作するため git コマンドの設定を行います。

### **1. 認証設定**

Git クライアントで CSR と認証するための設定を行います。

```bash
git config --global credential.'https://source.developers.google.com'.helper gcloud.sh
```

**ヒント**: git コマンドと gcloud で利用している IAM アカウントを紐付けるための設定です。

### **2. ユーザ、メールアドレス設定**

USERNAME, USERNAME@EXAMPLE.com を自身のユーザ名、メールアドレスに置き換えて実行し、利用者を設定します。

`USERNAME` と `USERNAME@EXAMPLE.com` そのままでも問題ありません。ここで入力した情報は今操作している Google Cloud プロジェクト上でのみ保存されているため、最後の環境のクリーンアップとともに削除されます。

```bash
git config --global user.name "USERNAME"
git config --global user.email "USERNAME@EXAMPLE.com"
```

## **Cloud Source Repositories（CSR）に資材を配置**

### **1. CSR に Git レポジトリを作成**

今回利用しているソースコードを配置するためのプライベート Git リポジトリを、Cloud Source Repository（CSR）に作成します。

```bash
gcloud source repos create cloudrun-handson
```

### **2. CSR を Git のリポジトリと紐付け**

CSR を Git のリモートレポジトリとして登録します。
これで git コマンドを使い Cloud Shell 上にあるファイル群を管理することができます。

```bash
git remote add google https://source.developers.google.com/p/{{project-id}}/r/cloudrun-handson
```

### **3. CSR への資材の転送（プッシュ）**

以前の手順で作成した CSR は空の状態です。
今まで修正していた内容をコミット、確定し、git push コマンドを使い、CSR に資材を転送（プッシュ）します。

```bash
git add . && git commit -m "Fix a message for sumservice" && git push google {{branch-name}}
```

**GUI**: [Source Repository](https://source.cloud.google.com/{{project-id}}/cloudrun-handson/+/{{branch-name}}:) から資材がプッシュされたことを確認できます。

<walkthrough-footnote>Cloud Shell 上にある資材を CSR のリポジトリにプッシュしました。次にこのリポジトリを参照先として、Cloud Run をデプロイします。</walkthrough-footnote>

## **Cloud Run の CI / CD 設定を合わせたデプロイ**

CI / CD 設定を含めたデプロイは GUI を利用して行います。

### **1. Cloud Run GUI に移動**

下記のボタンから Cloud Run の GUI に移動します。

<walkthrough-menu-navigation sectionId="CLOUD_RUN_SECTION"></walkthrough-menu-navigation>

### **2. サービスの作成を開始**

<walkthrough-spotlight-pointer spotlightId="run-create-service">サービスの作成</walkthrough-spotlight-pointer> ボタンをクリックし作成を開始します。

### **3. サービスの設定** [![screenshot](https://raw.githubusercontent.com/{{github-repo}}/{{branch-name}}/images/link_image.png)](https://raw.githubusercontent.com/{{github-repo}}/{{branch-name}}/images/create_a_cloud_run_service.png)

1. サービス名に `sumservice` と入力します
1. リージョンは `asia-northeast1 (Tokyo)` を選択します
1. `次へ` ボタンをクリックします

### **4. サービスの最初のリビジョンの構成** [![screenshot](https://raw.githubusercontent.com/{{github-repo}}/{{branch-name}}/images/link_image.png)](https://raw.githubusercontent.com/{{github-repo}}/{{branch-name}}/images/configure_the_first_revision_of_the_service.png)

1. `ソース リポジトリから新しいリビジョンを継続的にデプロイする` をチェックします
1. `SET UP WITH CLOUD BUILD` ボタンをクリックします

### **5. Cloud Build の設定** [![screenshot](https://raw.githubusercontent.com/{{github-repo}}/{{branch-name}}/images/link_image.png)](https://raw.githubusercontent.com/{{github-repo}}/{{branch-name}}/images/configure_source_repository.png) [![screenshot](https://raw.githubusercontent.com/{{github-repo}}/{{branch-name}}/images/link_image.png)](https://raw.githubusercontent.com/{{github-repo}}/{{branch-name}}/images/configure_build.png) [![screenshot](https://raw.githubusercontent.com/{{github-repo}}/{{branch-name}}/images/link_image.png)](https://raw.githubusercontent.com/{{github-repo}}/{{branch-name}}/images/move_to_trigger_configuration.png)

1. リポジトリ プロバイダで `Cloud Source Repositories` を選択します
1. リポジトリで `cloudrun-handson` を選択します
1. `次へ` ボタンをクリックします
1. ブランチで `^master$` を選択します
1. Build Type で `Go、Node.js、Python、Java、または .NET Core` をチェックします
1. ビルド コンテキストのディレクトリに `/cloudrun/src/sumservice` と入力します
1. `保存` ボタンをクリックします
1. `次へ` ボタンをクリックします

### **6. このサービスをトリガーする方法の構成** [![screenshot](https://raw.githubusercontent.com/{{github-repo}}/{{branch-name}}/images/link_image.png)](https://raw.githubusercontent.com/{{github-repo}}/{{branch-name}}/images/configure_trigger.png)

1. 認証の項目で `未認証の呼び出しを許可` をチェックします
1. `作成` ボタンをクリックします

`リポジトリからのビルドとデプロイを実行しています` の処理が終わるまで待ちます。

デプロイが完了するまでに数分時間がかかります。完了すると自動的に画面がリロードされます。

### **7. 動作確認** [![screenshot](https://raw.githubusercontent.com/{{github-repo}}/{{branch-name}}/images/link_image.png)](https://raw.githubusercontent.com/{{github-repo}}/{{branch-name}}/images/access_deployed_service.png)

GUI に表示されている URL のリンクをクリックし、`Hello New Normal!` と表示されていれば成功です。

<walkthrough-footnote>これで Cloud Run と Git リポジトリを紐付けて、ソースコードの変更から Cloud Run へのデプロイを自動化することができました。次にこのパイプラインの動作を確認します。</walkthrough-footnote>

## **CI / CD パイプラインの動作確認**

### **1. アプリケーションの修正**

`Hello New Normal!` と修正していたメッセージを `Hello World!` に戻します。

```bash
sed -i -e 's/New Normal/World/' src/sumservice/main.py
```

### **2. リポジトリへのプッシュ**

```bash
git add . && git commit -m "Update the message to test CI/CD deployment" && git push google {{branch-name}}
```

Cloud Build の GUI から履歴を選び、ビルドの進行状況が確認できます。

<walkthrough-menu-navigation sectionId="CLOUD_BUILD_SECTION"></walkthrough-menu-navigation>

### **3. 動作確認** [![screenshot](https://raw.githubusercontent.com/{{github-repo}}/{{branch-name}}/images/link_image.png)](https://raw.githubusercontent.com/{{github-repo}}/{{branch-name}}/images/confirm_cicd_pipeline.png)

Cloud Run の GUI に表示されている URL のリンクをクリックし、`Hello World!` と表示されていれば成功です。

**ヒント**: GUI から新しいリビジョンがデプロイ完了したことを確認した後に、アクセスしてください。

<walkthrough-footnote>作成したパイプラインがちゃんと動いていることが確認できました。以降は修正する場合、できる限りこのパイプラインを活用します。</walkthrough-footnote>

## **チャレンジ問題：デプロイの手動化**

先程設定した CI / CD 設定はコードがプッシュされると、新しいリビジョンがデプロイされそちらでアクセスを受けるようになります。

本番の環境では、デプロイは問題がないか確認後、手動で行うことが多いと思います。

先の手順で実施した「新リビジョンの限定公開」を参考に、今存在しているビルドトリガー設定を、新リビジョンをデプロイしたとしても、アクセスは割り振らず、自動で付与されたランダム URL でのみアクセスを受け付けるよう修正してみましょう。

### **ヒント**

- 自動で作成されている Cloud Build トリガーを修正します。Inline でビルドステップが書かれているので、見てみましょう。
- TAG は自動で割り振られるランダム値を使ってみましょう。ここでは commit ID の短縮文字列を使ってみましょう。Cloud Build の設定内で使える環境変数名は[こちら](https://cloud.google.com/build/docs/configuring-builds/substitute-variable-values)に記載されています。
- Cloud Build の GUI は下記ボタンをクリックして開きます。

<walkthrough-menu-navigation sectionId="CLOUD_BUILD_SECTION"></walkthrough-menu-navigation>

### **できた方は**

うまく設定できた方は以降のハンズオンで手間がかかってしまうため、トリガーを元の状態に戻しておきましょう。

## **サンプルアプリケーションの拡張**

<walkthrough-tutorial-duration duration=15></walkthrough-tutorial-duration>

サンプルアプリケーションは与えられた数字を足し算するだけの簡単なものでした。これに新しい機能を追加します。

それは通貨情報も含めて足し算をし、結果を日本円に換算して返す機能です。

[アーキテクチャ図](https://raw.githubusercontent.com/{{github-repo}}/{{branch-name}}/images/enhance_sample_application.png)

### **インターフェース（sumservice の拡張 API）**

- パス: /sumcurrency
  - JSON 形式で、通貨ごとの数字を複数 POST すると JSON 形式で合計金額を整数で返します。（小数点以下切り捨て）

例：

Request:

```json
{
  "amounts": ["JPY100", "USD20", "EUR30"]
}
```

Response:

```json
{
  "sum": 6184
}
```

このアプリケーションはマイクロサービス アーキテクチャを採用することとし、通貨ごとの情報は別サービス（currencyservice）が管理することとします。

## **currencyservice**

### **日本円への換算 API**

currencyservice は他のマイクロサービスからのみリクエストを受け付ける想定です。

- パス: /convert
  - JSON 形式でレスポンス時の通貨、通貨情報付きの文字列を POST すると JSON 形式で日本円に換算した値を整数で返します。（小数点以下切り捨て）

例：

Request:

```json
{
  "value": "USD10"
}
```

Response:

```json
{
  "answer": 1098
}
```

### **フォルダ、ファイル構成**

```terminal
.
└─ src
    └─ currencyservice
        ├─ go.mod : モジュール定義ファイル
        └─ main.go : メイン関数ソースファイル
```

## **currencyservice のデプロイ**

まず sumservice からアクセスを受け付ける、currencyservice をデプロイします。
sumservice と同様に CI / CD 設定を含めたデプロイを GUI から行います。

### **1. Cloud Run GUI に移動**

Cloud Run の GUI が開いていない方は、下記のボタンから Cloud Run の GUI に移動します。

<walkthrough-menu-navigation sectionId="CLOUD_RUN_SECTION"></walkthrough-menu-navigation>

### **2. サービスの作成を開始**

<walkthrough-spotlight-pointer spotlightId="run-create-service">サービスの作成</walkthrough-spotlight-pointer> ボタンをクリックし作成を開始します。

### **3. サービスの設定** [![screenshot](https://raw.githubusercontent.com/{{github-repo}}/{{branch-name}}/images/link_image.png)](https://raw.githubusercontent.com/{{github-repo}}/{{branch-name}}/images/create_a_cloud_run_service_currency.png)

1. サービス名に `currencyservice` と入力します
1. リージョンは `asia-northeast1 (Tokyo)` を選択します
1. `次へ` ボタンをクリックします

### **4. サービスの最初のリビジョンの構成** [![screenshot](https://raw.githubusercontent.com/{{github-repo}}/{{branch-name}}/images/link_image.png)](https://raw.githubusercontent.com/{{github-repo}}/{{branch-name}}/images/configure_the_first_revision_of_the_service.png)

1. `ソース リポジトリから新しいリビジョンを継続的にデプロイする` をチェックします
1. `SET UP WITH CLOUD BUILD` ボタンをクリックします

### **5. Cloud Build の設定** [![screenshot](https://raw.githubusercontent.com/{{github-repo}}/{{branch-name}}/images/link_image.png)](https://raw.githubusercontent.com/{{github-repo}}/{{branch-name}}/images/configure_source_repository.png) [![screenshot](https://raw.githubusercontent.com/{{github-repo}}/{{branch-name}}/images/link_image.png)](https://raw.githubusercontent.com/{{github-repo}}/{{branch-name}}/images/configure_build_currency.png) [![screenshot](https://raw.githubusercontent.com/{{github-repo}}/{{branch-name}}/images/link_image.png)](https://raw.githubusercontent.com/{{github-repo}}/{{branch-name}}/images/move_to_trigger_configuration.png)

1. リポジトリ プロバイダで `Cloud Source Repositories` を選択します
1. リポジトリで `cloudrun-handson` を選択します
1. `次へ` ボタンをクリックします
1. ブランチで `^master$` を選択します
1. Build Type で `Go、Node.js、Python、Java、または .NET Core` をチェックします
1. ビルド コンテキストのディレクトリに `/cloudrun/src/currencyservice` と入力します
1. `保存` ボタンをクリックします
1. `次へ` ボタンをクリックします

### **6. このサービスをトリガーする方法の構成** [![screenshot](https://raw.githubusercontent.com/{{github-repo}}/{{branch-name}}/images/link_image.png)](https://raw.githubusercontent.com/{{github-repo}}/{{branch-name}}/images/configure_trigger.png)

1. 認証の項目で `未認証の呼び出しを許可` をチェックします
1. `作成` ボタンをクリックします

`リポジトリからのビルドとデプロイを実行しています` の処理が終わるまで待ちます。

デプロイが完了するまでに数分時間がかかります。完了すると自動的に画面がリロードされます。

### **7. 動作確認**

```bash
CURRENCY_URL=$(gcloud run services describe currencyservice --format json | jq -r '.status.address.url')
curl -H "Content-Type: application/json" -d '{ "value": "USD10" }' ${CURRENCY_URL}/convert
```

下記のように返ってくれば正しくデプロイできています。

```terminal
{
    "answer": 1098
}
```

<walkthrough-footnote>これで currencyservice もパイプラインを使ってデプロイできました。次に sumservice がこのサービスを呼び出すように修正します。</walkthrough-footnote>

## **sumservice の更新、デプロイ**

### **1. sumservice に 新しい API を追加**

sumservice に currencyservice と連携する API（sumcurrency）の API を追加します。
`src/sumservice/main.py` にコメントアウトされた状態で記載されているので、コメントを削除します。

```bash
sed -i -e '31,71s/^#//g' src/sumservice/main.py
```

追加したコードは下記のコマンドで表示できます。

```bash
sed -n 31,71p src/sumservice/main.py
```

### **2. デプロイ**

更新した内容をデプロイします。

```bash
git add . && git commit -m "Add integration to currencyservice" && git push google {{branch-name}}
```

### **3. 環境変数の設定**

sumservice に currencyservice の URL を環境変数を通じて設定します。

```bash
CURRENCY_URL=$(gcloud run services describe currencyservice --format json | jq -r '.status.address.url')
gcloud run services update sumservice --set-env-vars=CURRENCY_SERVICE_URL=${CURRENCY_URL}
```

### **4. 動作確認**

```bash
SUM_URL=$(gcloud run services describe sumservice --format json | jq -r '.status.address.url')
curl -H "Content-Type: application/json" -d '{ "amounts": ["USD10", "EUR20", "AUD30"] }' ${SUM_URL}/sumcurrency
```

以下のように返ってくれば、正しく稼働しています。

```terminal
{
    "sum": 6306
}
```

<walkthrough-footnote>これで currencyservice と sumservice を連携させ、通貨情報も含めた足し算が行えるようになりました。次に Cloud Run のセキュリティ機能を学びます。</walkthrough-footnote>

## **セキュリティ**

<walkthrough-tutorial-duration duration=15></walkthrough-tutorial-duration>

Cloud Run では様々なセキュリティを向上させる機能、プラクティスがあります。
今回はそのうち下記の 3 つを実施します。

- Container Analysis と脆弱性スキャン
- サービス個別の権限設定
- sumservice + currencyservice のセキュアな連携

[アーキテクチャ図](https://raw.githubusercontent.com/{{github-repo}}/{{branch-name}}/images/security.png)

## **Container Analysis と脆弱性スキャン**

Container Registry と Artifact Registry では格納されているコンテナイメージに対して、脆弱性スキャンを行えます。

ここまで Artifact Registry を使ってきたため、そちらで機能を試します。

### **1. Artifact Registry GUI への移動**

下記ボタンから Artifact Registry の画面に移動します。

<walkthrough-menu-navigation sectionId="ARTIFACT_REGISTRY_SECTION"></walkthrough-menu-navigation>

### **2. Container Analysis の有効化** [![screenshot](https://raw.githubusercontent.com/{{github-repo}}/{{branch-name}}/images/link_image.png)](https://raw.githubusercontent.com/{{github-repo}}/{{branch-name}}/images/enable_container_analysis.png)

Container Analysis を有効化するにはプロジェクト単位で機能を有効化します。

左メニューの `設定` をクリックし、次のページで脆弱性スキャンを `オン` にします。

### **3. コンテナの再アップロード** [![screenshot](https://raw.githubusercontent.com/{{github-repo}}/{{branch-name}}/images/link_image.png)](https://raw.githubusercontent.com/{{github-repo}}/{{branch-name}}/images/click_cloudrun_handson.png) [![screenshot](https://raw.githubusercontent.com/{{github-repo}}/{{branch-name}}/images/link_image.png)](https://raw.githubusercontent.com/{{github-repo}}/{{branch-name}}/images/click_sumservice.png)

左メニューの `リポジトリ` をクリック、次に `cloudrun-handson` 、`sumservice` の順にクリックし、コンテナイメージ一覧が見えるようにします。

スキャンはコンテナイメージがプッシュされた段階で実行されます。そのためコンテナを再度プッシュします。

```bash
gcloud builds submit src/sumservice/ --pack image={{region}}-docker.pkg.dev/{{project-id}}/cloudrun-handson/sumservice:v2
```

### **4. スキャン結果の確認** [![screenshot](https://raw.githubusercontent.com/{{github-repo}}/{{branch-name}}/images/link_image.png)](https://raw.githubusercontent.com/{{github-repo}}/{{branch-name}}/images/container_analysis_result.png)

脆弱性列の数字をクリックし、どのような脆弱性がコンテナイメージに残っているかを確認します。

<walkthrough-footnote>コンテナの脆弱性スキャン機能を試しました。近年コンテナについてのセキュリティが注目されています。このような機能を使い、インターネットからダウンロードすることが多いコンテナについて重大な問題がないかを確認すると良いでしょう。</walkthrough-footnote>

## **サービス個別の権限設定**

デプロイ済みの 2 サービス（sumservice、currencyservice）では権限に関して特別な設定をせずにデプロイしたため、デフォルトのサービスアカウント、つまり広い権限がついている状態です。

そこで、最小権限の原則に従い、個々のサービスごとに必要な権限を付与するため、個別にサービスアカウントを用意し権限を付与します。

### **1. サービスアカウントの作成**

sumservice, currecyservice それぞれ固有のサービスアカウントを作成します。

```bash
gcloud iam service-accounts create sumservice-sa --display-name "Service Account for sumservice"
```

```bash
gcloud iam service-accounts create currencyservice-sa --display-name "Service Account for currencyservice"
```

### **2. サービスアカウントを適用**

作成したサービスアカウントを、それぞれのサービスに適用します。

```bash
gcloud run services update sumservice --service-account=sumservice-sa
```

```bash
gcloud run services update currencyservice --service-account=currencyservice-sa
```

<walkthrough-footnote>これで sumservice、currencyservice はそれぞれ最小の権限のみでアプリケーションが稼働するようになりました。次にこの権限を利用し、それぞれのサービスをセキュアに連携するようにします。</walkthrough-footnote>

## **sumservice + currencyservice のセキュアな連携**

currencyservice は他サービスからのみ呼び出される想定ですが、今の設定では誰でもアクセスができてしまっています。

そこで現在連携している sumservice からのみアクセスが可能なように設定します。

### **1. currencyservice の sumservice からの呼び出し許可**

sumservice から currencyservice を呼び出せるように sumservice のサービスアカウントに権限を付与します。

```bash
gcloud run services add-iam-policy-binding currencyservice --member='serviceAccount:sumservice-sa@{{project-id}}.iam.gserviceaccount.com' --role='roles/run.invoker'
```

### **2. sumservice の修正、デプロイ**

sumservice のソースコードを修正し、currencyservice を呼び出すときにトークンを取得し、それを利用するように修正します。

```bash
sed -i -e '44s/#//' src/sumservice/main.py
```

修正した内容をデプロイします。

```bash
git add . && git commit -m "Update to use a token accessing currencyservice" && git push google {{branch-name}}
```

### **3. currencyservice の全利用者呼び出し許可設定削除**

最後に currencyservice の呼び出し許可設定を変更し、権限を持っているアカウントのみ呼び出せるようにします。

```bash
gcloud run services remove-iam-policy-binding currencyservice --member="allUsers" --role="roles/run.invoker"
```

### **4. 動作確認**

sumservice からは引き続き連携ができていることを確認します。

```bash
SUM_URL=$(gcloud run services describe sumservice --format json | jq -r '.status.address.url')
curl -H "Content-Type: application/json" -d '{ "amounts": ["USD10", "EUR20", "AUD30"] }' ${SUM_URL}/sumcurrency
```

currencyservice へ直接アクセスをすると、エラーが出るようになったことを確認します。

```bash
CURRENCY_URL=$(gcloud run services describe currencyservice --format json | jq -r '.status.address.url')
curl -H "Content-Type: application/json" -d '{ "value": "USD10" }' ${CURRENCY_URL}/convert
```

直接アクセスができてしまっている場合は、少し待ってみてください。

<walkthrough-footnote>これで sumservice、currencyservice はそれぞれ最小の権限のみで稼働し、さらにマイクロサービス群がセキュアに連携できるようになりました。次に Cloud Run のパフォーマンスについて学びましょう。</walkthrough-footnote>

## **パフォーマンス・チューニング**

<walkthrough-tutorial-duration duration=15></walkthrough-tutorial-duration>

Cloud Run では、負荷に応じて自動的にスケールします。
サンプルアプリケーションに負荷をかけてみて、実際にスケールが行われる様子、そしてリソース状況、ログ、テレメトリ情報を見てみましょう。

下記に示す手順で作業を進めます。

- 負荷ツールの導入
- アプリケーションへの負荷テスト
- スケーリング、リソース状況、ログの確認
- 設定値を修正し、挙動の確認

## **負荷ツールの導入**

負荷を掛けるツールとして [Locust](https://github.com/locustio/locust) を利用します。これは Python で書かれたオープンソースのツールで、独自の UI を持っている、また分散構成で負荷を掛けることができるなどの特長があります。

ここでは Locust を GKE Autopilot 上に導入します。

### **1. Autopilot クラスタの作成**

```bash
gcloud container clusters create-auto loadtest-{{region}} --region {{region}}
```

作成完了まで数分かかります。

### **2. Locust のデプロイ**

Kubernetes 上で動かすため、[helm](https://helm.sh/ja/) を使い Locust を導入します。

helm チャートの追加:

```bash
helm repo add deliveryhero https://charts.deliveryhero.io/
```

locust file の読み込み:

```bash
kubectl create configmap loadtest-sumservice-locustfile --from-file src/locust/main.py
```

locust のインストール:

```bash
SUM_URL=$(gcloud run services describe sumservice --format json | jq -r '.status.address.url')
helm install locust deliveryhero/locust --set loadtest.locust_locustfile_configmap=loadtest-sumservice-locustfile --set loadtest.name=loadtest-sumservice --set worker.replicas=2 --set loadtest.locust_host=${SUM_URL}
```

次のコマンドを実行し、Pod が稼働状態（Running）になるまで待ちます。すべてが稼働状態になったら、Ctrl+C で抜けます。

```bash
kubectl get pods -w
```

### **3. Web UI の確認**

Locust にはポートフォワードを通して UI にアクセスします。Cloud Shell への 8080 ポートへのアクセスを、Locust のポート 8089 に転送する設定を行います。

```bash
kubectl --namespace default port-forward service/locust 8080:8089
```

プレビューボタン <walkthrough-web-preview-icon></walkthrough-web-preview-icon> をクリックし、ポート 8080 でプレビューをクリックします。

無事、Locust の UI が見えれば成功です。

<walkthrough-footnote>負荷ツールの Locust を GKE Autopilot 上に構築しました。次にこのツールを使い、デプロイ済みのマイクロサービスに負荷をかけてみます。</walkthrough-footnote>

## **アプリケーションへの負荷テスト**

### **1. Locust からの負荷テスト** [![screenshot](https://raw.githubusercontent.com/{{github-repo}}/{{branch-name}}/images/link_image.png)](https://raw.githubusercontent.com/{{github-repo}}/{{branch-name}}/images/locust_ui.png)

Locust からアプリケーションに負荷をかけ、スケーリング、エラー、負荷の状況を確認します。

Locust の UI にて下記の数値を入力後、`Start swarming` をクリックします。

- `Number of total users to simulate`: 1500
- `Spawn rate`: 10

### **2. Cloud Run UI, Locust UI からの負荷状況の確認**

コンテナインスタンスの数、レイテンシ、CPU、メモリなどのメトリクスが負荷に応じてどのように変化するかを見てみましょう。

- [sumservice UI](https://console.cloud.google.com/run/detail/{{region}}/sumservice/metrics?project={{project-id}})
- [currencyservice UI](https://console.cloud.google.com/run/detail/{{region}}/currencyservice/metrics?project={{project-id}})

## **チャレンジ問題：設定値を修正し、挙動の確認**

Cloud Run では、パフォーマンスをチューニングするための様々な設定があります。それらを変更し、より高いパフォーマンスが出せるか試してみてください。

下記のページを参考にしましょう。

- [メモリ上限の構成](https://cloud.google.com/run/docs/configuring/memory-limits)
- [CPU の割り当て](https://cloud.google.com/run/docs/configuring/cpu)
- [最大同時実行の設定](https://cloud.google.com/run/docs/configuring/concurrency)

**完了後、Locust からの負荷テストは止めましょう。Locust UI のメニュー内の STOP ボタンをクリックします。**

<walkthrough-footnote>負荷ツールを利用し、Cloud Run に負荷をかけ、UI から挙動を確認しました。次に展開しているマイクロサービスをグローバルに展開する方法を学びます。</walkthrough-footnote>

## **サンプルアプリケーションのグローバル展開**

<walkthrough-tutorial-duration duration=15></walkthrough-tutorial-duration>

Cloud Run は Load balancer と組み合わせることで、簡単にアプリケーションをグローバルで展開することが可能です。

今は東京リージョンのみ稼働しているアプリケーションを、アメリカにも配置してみましょう。

[アーキテクチャ図](https://raw.githubusercontent.com/{{github-repo}}/{{branch-name}}/images/global_deployment.png)

この設定を行うことで、利用者から見ると同じサービスにアクセスしていながら、自動的に利用者により近い Cloud Run にルーティングされ、ユーザ体験が向上します。

グローバル展開をするには下記の手順を実施します。

- HTTPS ロードバランサの作成
- アメリカにアプリケーションをデプロイ
- 動作確認

**ヒント**: 本ハンズオンでは手順をスクリプトにまとめて実行しています。詳しい手順を知りたい方は [複数のリージョンからのトラフィックの処理](https://cloud.google.com/run/docs/multiple-regions) を参照ください。

## **HTTPS ロードバランサの作成**

### **1. 自己署名証明書の作成**

HTTPS ロードバランサに SSL 証明書を紐付ける必要があります。そのためにまず自己署名証明書を作成します。

```bash
bash scripts/create_self-cert.sh
```

それぞれ質問された項目に、値を入力します。（下記はサンプルです。）

- Country Name: JP
- State or Province Name: Tokyo
- Locality Name: Minato
- Organization Name: Sugoi Cloud G.K.
- Organizational Unit Name: Cloud
- Common Name: sugoicloud.com
- Email Address: admin@sugoicloud.com

カレントディレクトリに以下の 2 ファイルが作成されます。

- private.key: 秘密鍵ファイル
- sumservice.crt: 証明書ファイル

### **2. HTTPS ロードバランサの作成**

先程作成した証明書などのファイルも使い、ロードバランサを作成します。

```bash
bash scripts/setup_loadbalancer.sh
```

<walkthrough-footnote>自己署名証明書を使い、HTTPS ロードバランサを作成しました。次にアメリカに sumservice, currencyservice をデプロイします。</walkthrough-footnote>

## **アメリカ（us-central1）にアプリケーションをデプロイ**

アメリカにも sumservice、currencyservice をデプロイしましょう。ここでは簡略化のため、パイプラインを通じてではなく、マニュアルでデプロイします。

### **1. currencyservice のデプロイ**

```bash
gcloud beta run deploy currencyservice --source src/currencyservice/ --no-allow-unauthenticated --region us-central1 --service-account currencyservice-sa@{{project-id}}.iam.gserviceaccount.com
```

### **2. sumservice からのアクセス許可設定**

```bash
gcloud run services add-iam-policy-binding currencyservice --member='serviceAccount:sumservice-sa@{{project-id}}.iam.gserviceaccount.com' --role='roles/run.invoker' --region us-central1
```

### **3. sumservice のデプロイ**

```bash
gcloud beta run deploy sumservice --source src/sumservice/ --allow-unauthenticated --region us-central1 --service-account sumservice-sa@{{project-id}}.iam.gserviceaccount.com
```

### **4. sumservice へ currencyservice の URL を設定**

```bash
CURRENCY_URL=$(gcloud run services describe currencyservice --format json --region us-central1 | jq -r '.status.address.url')
gcloud run services update sumservice --set-env-vars=CURRENCY_SERVICE_URL=${CURRENCY_URL} --region us-central1
```

### **5. 動作確認**

sumservice 単体の API: /sum

```bash
SUM_URL=$(gcloud run services describe sumservice --format json --region us-central1 | jq -r '.status.address.url')
curl -H "Content-Type: application/json" -d '{"numbers": [10, 20, 30, 300, 100]}' ${SUM_URL}/sum
```

sumservice + currencyservice が連携している API: /sumcurrency

```bash
SUM_URL=$(gcloud run services describe sumservice --format json --region us-central1 | jq -r '.status.address.url')
curl -H "Content-Type: application/json" -d '{ "amounts": ["USD10", "EUR20", "AUD30"] }' ${SUM_URL}/sumcurrency
```

<walkthrough-footnote>アメリカに sumservice, currencyservice をデプロイしました。次に先程作成したロードバランサに日本、アメリカで稼働しているアプリケーションを紐付けます。</walkthrough-footnote>

## **リージョンバックエンドの構成、動作確認**

### **1. NEG の作成、バックエンドサービスへの追加**

東京、アメリカで稼働しているアプリケーションを HTTPS ロードバランサに紐付けます。

```bash
bash scripts/add_sumservice_to_backend.sh asia-northeast1
bash scripts/add_sumservice_to_backend.sh us-central1
```

### **2. 動作確認**

ロードバランサにアクセスをし、正しく結果が返ってくることを確認します。

```bash
LB_IP=$(gcloud compute addresses describe --global sumservice-ip --format='value(address)')
curl -k -H "Content-Type: application/json" -d '{"numbers": [10, 20, 30, 300, 100]}' https://${LB_IP}/sum
curl -k -H "Content-Type: application/json" -d '{ "amounts": ["USD10", "EUR20", "AUD30"] }' https://${LB_IP}/sumcurrency
```

エラーが返ってくる場合は、少し待ってみてから再度アクセスをしてみてください。

<walkthrough-footnote>ロードバランサに Cloud Run を連携させることができました。これで日本、アメリカそれぞれの利用者が高いユーザ体験を得ることが可能です。次に、ロードバランサを使った、より本番で必要になる設定を導入します。</walkthrough-footnote>

## **sumservice をロードバランサと内部からのアクセスに制限**

currencyservice は権限を持った方のみがアクセスできる状態ですが、sumservice は誰でもインターネットを通してアクセスできる状態です。

ロードバランサを前段に配置したので、インターネットからはロードバランサを経由したアクセスのみを許可するように設定をしましょう。

こうすることで、セキュリティの向上、Cloud Armor と組み合わせた DDoS 対策、Cloud CDN を利用したパフォーマンスの向上といった恩恵が得られます。

### **1. アクセスができる状態の確認**

東京:

```bash
SUM_URL=$(gcloud run services describe sumservice --format json --region asia-northeast1 | jq -r '.status.address.url')
curl -H "Content-Type: application/json" -d '{"numbers": [10, 20, 30, 300, 100]}' ${SUM_URL}/sum
```

アメリカ:

```bash
SUM_URL=$(gcloud run services describe sumservice --format json --region us-central1 | jq -r '.status.address.url')
curl -H "Content-Type: application/json" -d '{"numbers": [10, 20, 30, 300, 100]}' ${SUM_URL}/sum
```

### **2. アクセス許可設定（ingress）を修正**

オプションの `--ingress internal-and-cloud-load-balancing` がポイントです。

東京の sumservice:

```bash
gcloud run services update sumservice --ingress internal-and-cloud-load-balancing --region asia-northeast1
```

アメリカの sumservice:

```bash
gcloud run services update sumservice --ingress internal-and-cloud-load-balancing --region us-central1
```

### **3. 再度直接アクセスを試してみる**

東京:

```bash
SUM_URL=$(gcloud run services describe sumservice --format json --region asia-northeast1 | jq -r '.status.address.url')
curl -H "Content-Type: application/json" -d '{"numbers": [10, 20, 30, 300, 100]}' ${SUM_URL}/sum
```

アメリカ:

```bash
SUM_URL=$(gcloud run services describe sumservice --format json --region us-central1 | jq -r '.status.address.url')
curl -H "Content-Type: application/json" -d '{"numbers": [10, 20, 30, 300, 100]}' ${SUM_URL}/sum
```

### **4. ロードバランサ経由でのアクセス**

```bash
LB_IP=$(gcloud compute addresses describe --global sumservice-ip --format='value(address)')
curl -k -H "Content-Type: application/json" -d '{"numbers": [10, 20, 30, 300, 100]}' https://${LB_IP}/sum
curl -k -H "Content-Type: application/json" -d '{ "amounts": ["USD10", "EUR20", "AUD30"] }' https://${LB_IP}/sumcurrency
```

<walkthrough-footnote>無事、アクセスをロードバランサからのみに制限することができました。</walkthrough-footnote>

## **Congraturations!**

<walkthrough-conclusion-trophy></walkthrough-conclusion-trophy>

これにて Cloud Run を利用したアプリケーションのデプロイ、簡易な CI / CD パイプラインの作成、セキュリティ向上策の導入、パフォーマンス・チューニング、そしてロードバランサを使ったグローバル展開が完了しました。

デモで使った資材が不要な方は、次の手順でクリーンアップを行って下さい。

## **クリーンアップ（プロジェクトを削除）**

ハンズオン用に利用したプロジェクトを削除し、コストがかからないようにします。

### **1. Google Cloud のデフォルトプロジェクト設定の削除**

```bash
gcloud config unset project
```

### **2. プロジェクトの削除**

```bash
gcloud projects delete {{project-id}}
```

### **3. ハンズオン資材の削除**

```bash
cd $HOME && rm -rf gcp-getting-started-lab-jp gopath
```
