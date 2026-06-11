<walkthrough-metadata>
  <meta name="title" content="Hands-on Agent Platform" />
  <meta name="description" content="Hands-on Agent Platform" />
</walkthrough-metadata>

<walkthrough-disable-features toc></walkthrough-disable-features>

# Gemini Enterprise Agent Platform ハンズオン セキュアなエージェントプラットフォーム

このハンズオンでは、Gemini Enterprise Agent Platform の周辺機能を使って、**社内 IT サポートエージェント**を構築します。

従業員からの問い合わせに対して、AI エージェントが MCP server を経由して Cloud SQL の情報を取得し、回答に利用する構成を作ります。


## このハンズオンで学ぶこと

このハンズオンでは、以下の Google Cloud サービスを利用します。

- Cloud SQL for PostgreSQL: 社内 IT サポート情報を保存するデータベース
- Cloud Run: MCP server をホストする実行環境
- MCP: AI エージェントが外部ツールを呼び出すための共通インターフェース
- Agent Registry: MCP server と tool のカタログ
- Agent Runtime: Agent Identity 付きのエージェント実行環境
- Agent Identity: エージェント単位の専用 ID
- IAM policy: Agent Identity に対する最小権限付与
- Model Armor: MCP tool に渡す入力の安全性チェック
- Cloud Logging : エージェントや MCP server の動作確認


## 作成する構成

このハンズオンでは、以下のような構成を作成します。

```text
利用者
  |
  | 問い合わせ
  v
Agent Runtime
  |
  | Agent Identity
  | roles/run.invoker
  v
Cloud Run MCP Server
  |
  | Model Armor による入力検査
  | Cloud SQL Python Connector
  v
Cloud SQL for PostgreSQL
```

MCP server は Cloud Run にデプロイします。
Cloud Run service は一般公開せず、Agent Identity にだけ `roles/run.invoker` を付与します。


## ハンズオンの流れ

このハンズオンは、以下のラボで構成されています。

- 事前準備: プロジェクト ID、gcloud、API、Python 環境を準備
- Lab00: Cloud SQL for PostgreSQL の作成
- Lab01: 社内 IT サポート用の初期データ投入
- Lab02: Model Armor template の作成
- Lab03: Cloud Run MCP server の実装とデプロイ
- Lab04: MCP server のローカル動作確認
- Lab05: Agent Registry への MCP server 登録
- Lab06: Agent Identity 付き Agent Runtime のデプロイ
- Lab07: IAM policy 付与前後のアクセス制御確認
- Lab08: Logging / Trace の確認
- Optional: Google 管理の Cloud Run remote MCP server の確認
- 後片付け: 作成したリソースの削除


## Google Cloud プロジェクトの設定、確認

#### 1. 対象の Google Cloud プロジェクトを設定

ハンズオンを行う Google Cloud プロジェクトのプロジェクト ID とプロジェクト番号を環境変数に設定し、以降の手順で利用できるようにします。

```bash
export PROJECT_ID="$(gcloud config get-value project)"
export PROJECT_NUMBER="$(gcloud projects describe ${PROJECT_ID} --format='value(projectNumber)')"

echo "${PROJECT_ID}"
echo "${PROJECT_NUMBER}"
```

Cloud Shell の承認という確認メッセージが出た場合は、**承認** をクリックします。

以下のような形式で表示されれば、正常に設定されています。
ID と番号自体は環境ごとに異なります。

```text
qwiklabs-xxx-xx-xxxxxxxx
123456789012
```

`プロジェクト ID` は Google Cloud Console のダッシュボードからも確認できます。

[GUI](https://console.cloud.google.com/home/dashboard)


## 環境準備

最初に、ハンズオンを進めるための環境準備を行います。

下記の設定を進めていきます。

- gcloud コマンドラインツールの設定
- リージョンの設定
- Google Cloud API の有効化
- 作業ディレクトリの作成
- Python 仮想環境の作成


## gcloud コマンドラインツール

Google Cloud は、CLI と GUI の両方から操作できます。
このハンズオンでは主に CLI を使いますが、確認に便利な GUI の URL も合わせて掲載します。

#### 1. gcloud コマンドラインツールとは?

gcloud コマンドライン インターフェースは、Google Cloud の主要な CLI ツールです。
このツールを使用すると、コマンドラインから Google Cloud のリソースを作成、更新、削除できます。

たとえば、gcloud CLI を使用して以下のようなものを作成、管理できます。

- Cloud Run service
- Cloud SQL instance
- IAM policy
- API の有効化
- Agent Registry の登録

ヒント: gcloud コマンドラインツールについての詳細は以下をご参照ください。

(https://cloud.google.com/sdk/gcloud?hl=ja)

#### 2. gcloud から利用する Google Cloud のデフォルトプロジェクトを設定

gcloud コマンドでは、操作対象のプロジェクト設定が必要です。
以下のコマンドで、操作対象のプロジェクトを設定します。

```bash
gcloud config set project "${PROJECT_ID}"
```

承認するかどうかを聞かれるメッセージが出た場合は、**承認** をクリックします。

#### 3. リージョンを設定

このハンズオンでは、リージョンとして `us-west1` を利用します。

```bash
export REGION="us-west1"
gcloud config set run/region "${REGION}"
gcloud config set compute/region "${REGION}"

echo "${REGION}"
```


#### 4. ハンズオンで利用する Google Cloud API を有効化する

Google Cloud では、利用したい機能ごとに API の有効化が必要です。
ここでは、以降のハンズオンで利用する機能を事前に有効化しておきます。

```bash
gcloud services enable \
  aiplatform.googleapis.com \
  agentregistry.googleapis.com \
  modelarmor.googleapis.com \
  run.googleapis.com \
  cloudbuild.googleapis.com \
  artifactregistry.googleapis.com \
  sqladmin.googleapis.com \
  cloudtrace.googleapis.com \
  logging.googleapis.com \
  iam.googleapis.com \
  iamcredentials.googleapis.com
```

(https://console.cloud.google.com/apis/library)


## ハンズオン共通の環境変数

このハンズオンで利用するリソース名を環境変数として設定します。

```bash
export DB_INSTANCE="it-support-db"
export DB_NAME="company_data"
export DB_USER="postgres"
export DB_PASS="SecurePass123!"

export BUCKET_NAME="${PROJECT_ID}-agent-bucket"
export MODEL_ARMOR_TEMPLATE="it-support-template-secure"

export MCP_SERVICE_NAME="it-support-mcp"
export MCP_SA_NAME="it-support-mcp-sa"
export MCP_SA="${MCP_SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"

export RUN_INVOKER_SA_NAME="it-support-agent-invoker"
export RUN_INVOKER_SA="${RUN_INVOKER_SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"

export AGENT_DISPLAY_NAME="it-support-agent-with-identity"

echo "PROJECT_ID=${PROJECT_ID}"
echo "PROJECT_NUMBER=${PROJECT_NUMBER}"
echo "REGION=${REGION}"
echo "BUCKET_NAME=${BUCKET_NAME}"
```


## Cloud Storage バケットの作成

Agent Runtime のデプロイ時に利用する staging bucket を作成します。

```bash
gcloud storage buckets create "gs://${BUCKET_NAME}" \
  --location="${REGION}" \
  --uniform-bucket-level-access || true
```


## 作業ディレクトリの作成

ハンズオン用の作業ディレクトリを作成します。

```bash
mkdir -p "${HOME}/agent-platform-it-support-handson"
cd "${HOME}/agent-platform-it-support-handson"
export HANDSON_HOME="${HOME}/agent-platform-it-support-handson"
export HANDSON_ASSETS_DIR="${HOME}/gcp-getting-started-lab-jp/pfe-4-agents/assets"

pwd
```


## Python 仮想環境の作成

Cloud Shell 上に Python 仮想環境を作成します。

```bash
cd "${HOME}/agent-platform-it-support-handson"

python3 -m venv agent-env
source agent-env/bin/activate

pip install --upgrade pip
```

必要な Python パッケージをインストールします。

```bash
pip install \
  "google-cloud-aiplatform[adk,agent_engines]" \
  "google-adk[a2a]>=1.9.0" \
  "google-cloud-logging" \
  "cloud-sql-python-connector[pg8000]" \
  "sqlalchemy>=2.0.0" \
  "pg8000" \
  "fastmcp==2.13.1" \
  "mcp" \
  "google-auth" \
  "requests" \
  "httpx" \
  "cloudpickle" \
  "pydantic"
```

インストールが完了したら、Python が仮想環境を参照していることを確認します。

```bash
which python
python --version
pip list | grep -E "google-cloud-aiplatform|fastmcp|mcp|sqlalchemy"
```


## Python SDK 用の Application Default Credentials を設定する

Teachme の実行ボタンでは `python - << EOF` のような heredoc が `;` 連結で壊れることがあります。以降の Python 確認コマンドは、1 行の `python -c` 形式で実行します。

このハンズオンでは、Python SDK から Vertex AI Agent Runtime / Agent Engine API を呼び出します。
`gcloud` コマンドでログイン済みでも、Python SDK が利用する **Application Default Credentials、ADC** は別途設定が必要です。

ADC が未設定の場合、Python SDK が Cloud Shell の metadata server 認証を拾ってしまい、以下のようなエラーになることがあります。

```text
google.auth.exceptions.RefreshError:
Unexpected response from metadata server: service account info is missing 'email' field.
```

以下を実行して、ADC を作成します。

```bash
unset GOOGLE_APPLICATION_CREDENTIALS

gcloud auth application-default revoke --quiet || true

gcloud auth application-default login \
  --no-launch-browser \
  --scopes=https://www.googleapis.com/auth/cloud-platform

gcloud auth application-default set-quota-project "${PROJECT_ID}"

export GOOGLE_CLOUD_PROJECT="${PROJECT_ID}"
export GCLOUD_PROJECT="${PROJECT_ID}"
```

表示された URL を開き、Qwiklabs の student アカウントで認証してください。
認証後に表示されるコードを Cloud Shell に貼り付けます。

## 参考: Cloud Shell の接続が途切れてしまったときは?

一定時間非アクティブ状態になる、またはブラウザが固まるなどで Cloud Shell の接続が切れてしまう場合があります。
その場合は、以下の手順で再開してください。

#### 1. 作業ディレクトリに移動する

```bash
cd "${HOME}/agent-platform-it-support-handson"
```

#### 2. Python 仮想環境を再度有効化する

```bash
source agent-env/bin/activate
```

#### 3. プロジェクト ID とプロジェクト番号を再設定する

```bash
export PROJECT_ID="$(gcloud config get-value project)"
export PROJECT_NUMBER="$(gcloud projects describe ${PROJECT_ID} --format='value(projectNumber)')"
export REGION="us-west1"

gcloud config set project "${PROJECT_ID}"
gcloud config set run/region "${REGION}"
gcloud config set compute/region "${REGION}"
```

#### 4. 共通の環境変数を再設定する

以下のコマンドはコピー＆ペーストしてください。

```
export DB_INSTANCE="it-support-db"
export DB_NAME="company_data"
export DB_USER="postgres"
export DB_PASS="SecurePass123!"

export BUCKET_NAME="${PROJECT_ID}-agent-bucket"
export MODEL_ARMOR_TEMPLATE="it-support-template-secure"

export MCP_SERVICE_NAME="it-support-mcp"
export MCP_SA_NAME="it-support-mcp-sa"
export MCP_SA="${MCP_SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"

export RUN_INVOKER_SA_NAME="it-support-agent-invoker"
export RUN_INVOKER_SA="${RUN_INVOKER_SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"

export SERVICE_URL="$(gcloud run services describe ${MCP_SERVICE_NAME} \
  --region=${REGION} \
  --format='value(status.url)' 2>/dev/null || true)"

export AGENT_ENGINE_ID="$(cat agent_engine_id.txt 2>/dev/null || true)"
export AGENT_PRINCIPAL="$(cat agent_principal.txt 2>/dev/null || true)"
```


## Lab00. Cloud SQL for PostgreSQL の作成

このラボでは、エージェントが回答の根拠として利用するデータベースを作成します。

今回は、社内 IT サポート情報を保持する Cloud SQL for PostgreSQL を利用します。
Cloud SQL は Google Cloud のマネージドデータベースサービスで、データベースのバックアップ、パッチ適用、高可用性構成などを Google Cloud 側で管理できます。

### 1. Cloud SQL インスタンスを作成する

以下のコマンドを実行し、PostgreSQL インスタンスを作成します。

```bash
cd "${HOME}/agent-platform-it-support-handson"

gcloud sql instances create "${DB_INSTANCE}" \
  --database-version=POSTGRES_15 \
  --region="${REGION}" \
  --tier=db-f1-micro \
  --edition=ENTERPRISE \
  --availability-type=ZONAL
```

Cloud SQL インスタンスの作成には数分かかります。
コマンドが成功すると、指定したリージョンに PostgreSQL インスタンスが作成されます。

GUI: https://console.cloud.google.com/sql/instances

### 2. postgres ユーザーのパスワードを設定する

```bash
gcloud sql users set-password "${DB_USER}" \
  --instance="${DB_INSTANCE}" \
  --password="${DB_PASS}"
```

### 3. データベースを作成する

```bash
gcloud sql databases create "${DB_NAME}" \
  --instance="${DB_INSTANCE}" || true
```

### 4. 作成結果を確認する

```bash
gcloud sql instances describe "${DB_INSTANCE}" \
  --format="table(name,region,databaseVersion,state)"
```

`state` が `RUNNABLE` になっていれば、Cloud SQL インスタンスは利用可能です。


## Lab01. 社内 IT サポート用データを投入する

このラボでは、Cloud SQL に社内 IT サポート用のサンプルデータを投入します。

投入するデータは以下です。

- 社内システムの稼働状況
- 従業員の部署とメールアドレス

### 1. 初期データ投入スクリプトを作成する

```bash
cd "${HOME}/agent-platform-it-support-handson"

python -c 'from pathlib import Path; import os, shutil; src=Path(os.environ.get("HANDSON_ASSETS_DIR","assets"))/"setup_db.py"; dst=Path("setup_db.py"); dst.parent.mkdir(parents=True, exist_ok=True); shutil.copyfile(src,dst); print(f"copied {src} -> {dst}")'
```

### 2. 初期データ投入スクリプトを実行する

```bash
cd $HOME/gcp-getting-started-lab-jp/pfe-4-agents/assets
python setup_db.py
```

以下のようなメッセージが表示されれば成功です。

```text
Cloud SQL への初期データ投入が完了しました。
```


## Lab02. Model Armor template の作成

このラボでは、MCP tool に渡される入力を検査するための Model Armor template を作成します。

Model Armor は、AI アプリケーションに渡されるプロンプトやモデル応答を検査し、危険な入力や望ましくない出力を検出するためのサービスです。
今回は MCP server の中から Model Armor を呼び出し、危険な入力を Cloud SQL に到達させない構成を作ります。


### 1. 利用する template 名を確認する

このハンズオンでは、以下の template 名を利用します。

```bash
export MODEL_ARMOR_TEMPLATE="it-support-template-secure"

echo "${MODEL_ARMOR_TEMPLATE}"
```

### 2. Model Armor template を REST API で作成する

以下の REST API 呼び出しで、RAI filter、Sensitive Data Protection、Prompt Injection / Jailbreak filter、Malicious URI filter を有効にした template を作成します。Teachme では複数行 JSON を inline の `-d '{...}'` として実行すると改行が `;` に変換されることがあるため、JSON は一度ファイルに保存してから `--data-binary @model_armor_template.json` で送信します。

```bash
cd $HOME/agent-platform-it-support-handson
```

```bash
python -c 'from pathlib import Path; import os, shutil; src=Path(os.environ.get("HANDSON_ASSETS_DIR","assets"))/"model_armor_template.json"; dst=Path("model_armor_template.json"); dst.parent.mkdir(parents=True, exist_ok=True); shutil.copyfile(src,dst); print(f"copied {src} -> {dst}")'

python -m json.tool model_armor_template.json >/dev/null && echo "JSON OK"

curl -s -i -X POST \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $(gcloud auth print-access-token)" \
  "https://modelarmor.${REGION}.rep.googleapis.com/v1/projects/${PROJECT_ID}/locations/${REGION}/templates?templateId=${MODEL_ARMOR_TEMPLATE}" \
  --data-binary @model_armor_template.json
```

以下のように `HTTP/2 200` と template の JSON が返れば成功です。

```text
HTTP/2 200
{
  "name": "projects/.../locations/us-west1/templates/it-support-template-secure",
  "filterConfig": {
    ...
  }
}
```

既に同じ template が存在する場合は、`ALREADY_EXISTS` のエラーになることがあります。
その場合は、次の確認手順に進んでください。

### 3. 作成した template を確認する

```bash
curl -s \
  -H "Authorization: Bearer $(gcloud auth print-access-token)" \
  "https://modelarmor.${REGION}.rep.googleapis.com/v1/projects/${PROJECT_ID}/locations/${REGION}/templates/${MODEL_ARMOR_TEMPLATE}" \
  | python -m json.tool
```

以下のフィルタが表示されることを確認します。

```text
raiSettings
sdpSettings
piAndJailbreakFilterSettings
maliciousUriFilterSettings
```

### 4. 正常な入力を検査する

```bash
python -c 'from pathlib import Path; import os, shutil; src=Path(os.environ.get("HANDSON_ASSETS_DIR","assets"))/"sanitize_normal.json"; dst=Path("sanitize_normal.json"); dst.parent.mkdir(parents=True, exist_ok=True); shutil.copyfile(src,dst); print(f"copied {src} -> {dst}")'

curl -s -X POST \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $(gcloud auth print-access-token)" \
  --data-binary @sanitize_normal.json \
  "https://modelarmor.${REGION}.rep.googleapis.com/v1/projects/${PROJECT_ID}/locations/${REGION}/templates/${MODEL_ARMOR_TEMPLATE}:sanitizeUserPrompt" \
  | python -m json.tool
```

期待される結果です。

```text
filterMatchState: NO_MATCH_FOUND
invocationResult: SUCCESS
```

### 5. Prompt Injection / Jailbreak 系の入力を検査する

```bash
python -c 'from pathlib import Path; import os, shutil; src=Path(os.environ.get("HANDSON_ASSETS_DIR","assets"))/"sanitize_prompt_injection.json"; dst=Path("sanitize_prompt_injection.json"); dst.parent.mkdir(parents=True, exist_ok=True); shutil.copyfile(src,dst); print(f"copied {src} -> {dst}")'

curl -s -X POST \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $(gcloud auth print-access-token)" \
  --data-binary @sanitize_prompt_injection.json \
  "https://modelarmor.${REGION}.rep.googleapis.com/v1/projects/${PROJECT_ID}/locations/${REGION}/templates/${MODEL_ARMOR_TEMPLATE}:sanitizeUserPrompt" \
  | python -m json.tool
```

期待される結果です。

```text
filterMatchState: MATCH_FOUND
pi_and_jailbreak.matchState: MATCH_FOUND
```

環境やフィルタバージョンによっては、`rai.dangerous` 側でも `MATCH_FOUND` になる場合があります。

### 6. 危険操作系の入力を検査する

```bash
python -c 'from pathlib import Path; import os, shutil; src=Path(os.environ.get("HANDSON_ASSETS_DIR","assets"))/"sanitize_dangerous.json"; dst=Path("sanitize_dangerous.json"); dst.parent.mkdir(parents=True, exist_ok=True); shutil.copyfile(src,dst); print(f"copied {src} -> {dst}")'

curl -s -X POST \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $(gcloud auth print-access-token)" \
  --data-binary @sanitize_dangerous.json \
  "https://modelarmor.${REGION}.rep.googleapis.com/v1/projects/${PROJECT_ID}/locations/${REGION}/templates/${MODEL_ARMOR_TEMPLATE}:sanitizeUserPrompt" \
  | python -m json.tool
```

期待される結果です。

```text
filterMatchState: MATCH_FOUND
rai.dangerous.matchState: MATCH_FOUND
```

この結果により、Model Armor template が危険な入力を検出できることを確認できます。

なお、業務固有の禁止事項、たとえば「全テーブルを dump する」「パスワードを表示する」といった要求は、Model Armor の判定だけに依存せず、MCP server 側の business guard でもブロックします。
このハンズオンでは、Model Armor と business guard の二段構えにしています。


## Lab03. Cloud Run MCP server の実装とデプロイ

このラボでは、Cloud SQL にアクセスする MCP server を作成し、Cloud Run にデプロイします。

MCP server には以下の tool を実装します。

- `get_system_status`: 社内システムの稼働状況を取得
- `get_employee_info`: 従業員の部署とメールアドレスを取得

MCP server は Cloud SQL に直接接続します。
AI エージェントから Cloud SQL に直接接続させるのではなく、MCP server 経由にすることで、DB アクセスの入口を制御できます。

このハンズオンでは、Model Armor は検知ログとして扱い、`dump` や `password` などの業務禁止操作は MCP server 側の business guard で hard block します。Model Armor は環境やフィルタ更新により正常な日本語入力でも `MATCH_FOUND` になる場合があるためです。

### 1. MCP server 用サービスアカウントを作成する

Cloud Run MCP server が Cloud SQL と Model Armor にアクセスするためのサービスアカウントを作成します。

```bash
gcloud iam service-accounts create "${MCP_SA_NAME}" \
  --display-name="IT Support MCP Cloud Run service account" || true
```

Cloud SQL に接続するための権限を付与します。

```bash
gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
  --member="serviceAccount:${MCP_SA}" \
  --role="roles/cloudsql.client" \
  --condition=None
```

Model Armor を利用するための権限を付与します。

```bash
gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
  --member="serviceAccount:${MCP_SA}" \
  --role="roles/modelarmor.user" \
  --condition=None

gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
  --member="serviceAccount:${MCP_SA}" \
  --role="roles/modelarmor.viewer" \
  --condition=None
```

### 2. MCP server のディレクトリを作成する

```bash
cd "${HOME}/agent-platform-it-support-handson"

rm -rf mcp-server
mkdir -p mcp-server
cd mcp-server
```

### 3. requirements.txt を作成する

```bash
python -c 'from pathlib import Path; import os, shutil; src=Path(os.environ.get("HANDSON_ASSETS_DIR","assets"))/"requirements.txt"; dst=Path("requirements.txt"); dst.parent.mkdir(parents=True, exist_ok=True); shutil.copyfile(src,dst); print(f"copied {src} -> {dst}")'
```

### 4. Dockerfile を作成する

```bash
python -c 'from pathlib import Path; import os, shutil; src=Path(os.environ.get("HANDSON_ASSETS_DIR","assets"))/"Dockerfile"; dst=Path("Dockerfile"); dst.parent.mkdir(parents=True, exist_ok=True); shutil.copyfile(src,dst); print(f"copied {src} -> {dst}")'
```

### 5. MCP server の Python コードを作成する

```bash
python -c 'from pathlib import Path; import os, shutil; src=Path(os.environ.get("HANDSON_ASSETS_DIR","assets"))/"server.py"; dst=Path("server.py"); dst.parent.mkdir(parents=True, exist_ok=True); shutil.copyfile(src,dst); print(f"copied {src} -> {dst}")'
```

### 6. Cloud Run に MCP server をデプロイする

Cloud Run service は未認証公開せず、`--no-allow-unauthenticated` を指定します。

```bash
cd "${HOME}/agent-platform-it-support-handson/mcp-server"

gcloud run deploy "${MCP_SERVICE_NAME}" \
  --source . \
  --region="${REGION}" \
  --service-account="${MCP_SA}" \
  --no-allow-unauthenticated \
  --set-env-vars="PROJECT_ID=${PROJECT_ID},REGION=${REGION},INSTANCE_CONNECTION_NAME=${PROJECT_ID}:${REGION}:${DB_INSTANCE},DB_NAME=${DB_NAME},DB_USER=${DB_USER},DB_PASS=${DB_PASS},MODEL_ARMOR_TEMPLATE=${MODEL_ARMOR_TEMPLATE},MODEL_ARMOR_FAIL_OPEN=false"
```
デプロイを続けるために y を入力します。
デプロイには数分かかることがあります。

### 7. Cloud Run service URL を取得する

```bash
export SERVICE_URL="$(gcloud run services describe "${MCP_SERVICE_NAME}" \
  --region="${REGION}" \
  --format="value(status.url)")"

echo "SERVICE_URL=${SERVICE_URL}"
echo "MCP endpoint=${SERVICE_URL}/mcp"
```

以下のように URL が表示されれば、Cloud Run service のデプロイは完了です。

```text
SERVICE_URL=https://it-support-mcp-xxxxx-uw.a.run.app
MCP endpoint=https://it-support-mcp-xxxxx-uw.a.run.app/mcp
```

GUI: https://console.cloud.google.com/run


## Lab04. Cloud Run MCP server のローカル動作確認

このラボでは、Cloud Run にデプロイした MCP server を Cloud Shell から呼び出して確認します。

Cloud Run service は private なので、Cloud Shell のユーザーに `roles/run.invoker` を付与します。

### 1. Cloud Shell ユーザーに Cloud Run Invoker を付与する

```bash
export USER_EMAIL="$(gcloud config get-value account)"

gcloud run services add-iam-policy-binding "${MCP_SERVICE_NAME}" \
  --region="${REGION}" \
  --member="user:${USER_EMAIL}" \
  --role="roles/run.invoker"
```

### 2. Cloud Run proxy を起動する

`gcloud run services proxy` を使うと、認証付き Cloud Run service をローカルポートに転送できます。

```
cd "${HOME}/agent-platform-it-support-handson/mcp-server"

gcloud run services proxy "${MCP_SERVICE_NAME}" \
  --region="${REGION}" \
  --port=8080 > proxy.log 2>&1 &

echo $! > proxy.pid
sleep 8

cat proxy.log
```

### 3. MCP client を作成する

```bash
python -c 'from pathlib import Path; import os, shutil; src=Path(os.environ.get("HANDSON_ASSETS_DIR","assets"))/"test_mcp_local.py"; dst=Path("test_mcp_local.py"); dst.parent.mkdir(parents=True, exist_ok=True); shutil.copyfile(src,dst); print(f"copied {src} -> {dst}")'
```

### 4. MCP client を実行する

```bash
python test_mcp_local.py
```

以下のような結果が表示されれば成功です。

```text
=== tools/list ===
- get_system_status: 社内システムの現在の稼働状況を取得します。
- get_employee_info: 指定された従業員の部署とメールアドレスを取得します。

=== get_system_status: 正常系 ===
経費精算システム: 障害発生中。復旧見込みは 15:00 です。 最終更新: ...

=== get_employee_info: 正常系 ===
佐藤花子: 部署=ITシステム部, Email=sato@example.com, 最終更新: ...

=== get_system_status: 危険入力のブロック確認 ===
❌ セキュリティポリシーによりブロックしました。検出キーワード: dump
```

Cloud Run logs では、正常入力に対して Model Armor が `MATCH_FOUND` を出す場合があります。  
このハンズオンでは false positive による停止を避けるため、Model Armor は検知ログとして扱い、業務禁止操作の hard block は business guard で行います。

### 5. proxy を停止する

```bash
kill "$(cat proxy.pid)" || true
```


## Lab05. Agent Registry に MCP server を登録する

このラボでは、作成した MCP server を Agent Registry に登録します。

Agent Registry は、組織内の agent や MCP server をカタログ化するためのサービスです。
ここでは、MCP server の URL と tool spec を登録します。

> 重要: Qwiklabs / Cloud Shell では、セッション再接続や別ラボ環境への切り替えにより、`SERVICE_URL` 環境変数が空になることがあります。
> `SERVICE_URL` が空のまま登録コマンドを実行すると、Agent Registry には `url=/mcp` のような不正な URL が渡され、`invalid interface url format` になります。
> このラボでは、登録前に必ず `SERVICE_URL` を再取得し、URL の形式を確認します。

### 1. Cloud Run service URL を再取得する

Cloud Shell の接続が切れた場合や、新しいターミナルで作業している場合に備えて、Cloud Run service URL を再取得します。

```bash
export SERVICE_URL="$(gcloud run services describe "${MCP_SERVICE_NAME}" \
  --region="${REGION}" \
  --format="value(status.url)")"

export REGISTRY_MCP_URL="${SERVICE_URL%/}/mcp"

echo "SERVICE_URL=${SERVICE_URL}"
echo "REGISTRY_MCP_URL=${REGISTRY_MCP_URL}"
```

`SERVICE_URL` は以下のような形式になります。

```text
https://it-support-mcp-xxxxx-uw.a.run.app
```

`REGISTRY_MCP_URL` は以下のような形式になります。

```text
https://it-support-mcp-xxxxx-uw.a.run.app/mcp
```

### 2. URL が空ではないことを検証する

Agent Registry に登録する前に、URL が空ではないことを確認します。

```bash
python -c 'import os,sys; service_url=os.getenv("SERVICE_URL",""); registry_url=os.getenv("REGISTRY_MCP_URL",""); print(f"SERVICE_URL={service_url}"); print(f"REGISTRY_MCP_URL={registry_url}"); errors=[]; errors += ["SERVICE_URL is empty"] if not service_url else []; errors += ["REGISTRY_MCP_URL is empty"] if not registry_url else []; errors += ["REGISTRY_MCP_URL must start with https://"] if registry_url and not registry_url.startswith("https://") else []; [print("ERROR:", e) for e in errors]; sys.exit(1 if errors else 0)'

echo "OK: REGISTRY_MCP_URL format looks valid: ${REGISTRY_MCP_URL}"
```

もしここで `SERVICE_URL is empty` と表示された場合は、以下を確認してください。

```bash
gcloud run services list --region="${REGION}"

echo "MCP_SERVICE_NAME=${MCP_SERVICE_NAME}"
echo "REGION=${REGION}"
```

Cloud Run service 名やリージョンが違う場合は、正しい値に修正してから再度 `SERVICE_URL` を取得してください。

### 3. tool spec を作成する

Agent Registry 登録コマンドと同じディレクトリで実行できるように、`toolspec.json` は `mcp-server` ディレクトリに作成します。

```bash
cd "${HOME}/agent-platform-it-support-handson/mcp-server"

python -c 'from pathlib import Path; import os, shutil; src=Path(os.environ.get("HANDSON_ASSETS_DIR","assets"))/"toolspec.json"; dst=Path("toolspec.json"); dst.parent.mkdir(parents=True, exist_ok=True); shutil.copyfile(src,dst); print(f"copied {src} -> {dst}")'
```

### 4. Agent Registry に MCP server を登録する

`REGISTRY_MCP_URL` を使って Agent Registry に登録します。

```bash
cd "${HOME}/agent-platform-it-support-handson/mcp-server"
test -f toolspec.json && echo "OK: toolspec.json found"

gcloud alpha agent-registry services create "${MCP_SERVICE_NAME}" \
  --project="${PROJECT_ID}" \
  --location="${REGION}" \
  --display-name="IT Support MCP Server" \
  --mcp-server-spec-type=tool-spec \
  --mcp-server-spec-content=toolspec.json \
  --interfaces="url=${REGISTRY_MCP_URL},protocolBinding=JSONRPC"
```

成功すると、Agent Registry に MCP server と tool spec が登録されます。

> 補足: Agent Registry の MCP server 登録では、公式ドキュメントでも `SERVER_URL` の例として `https://api.example.com/mcp` のような MCP endpoint URL を指定しています。
> そのため、`https://.../mcp` という形式自体は正しいです。`invalid interface url format` が出た場合は、まず `SERVICE_URL` が空でないかを確認してください。

### 5. 既に登録済みの場合

同じ service 名で既に登録済みの場合は、作成コマンドが失敗します。
その場合は、一度削除してから再作成します。

```bash
gcloud alpha agent-registry services delete "${MCP_SERVICE_NAME}" \
  --project="${PROJECT_ID}" \
  --location="${REGION}" \
  --quiet || true

gcloud alpha agent-registry services create "${MCP_SERVICE_NAME}" \
  --project="${PROJECT_ID}" \
  --location="${REGION}" \
  --display-name="IT Support MCP Server" \
  --mcp-server-spec-type=tool-spec \
  --mcp-server-spec-content=toolspec.json \
  --interfaces="url=${REGISTRY_MCP_URL},protocolBinding=JSONRPC"
```

### 6. 登録結果を確認する

```bash
gcloud alpha agent-registry services list \
  --project="${PROJECT_ID}" \
  --location="${REGION}"
```

`IT Support MCP Server` が表示されれば、Agent Registry への登録は成功です。

詳細を確認します。

```bash
gcloud alpha agent-registry services describe "${MCP_SERVICE_NAME}" \
  --project="${PROJECT_ID}" \
  --location="${REGION}" \
  --format=json | python -m json.tool
```

GUI: https://console.cloud.google.com/agent-registry


## Lab06. Agent Identity 付き Agent Runtime をデプロイする

このラボでは、Agent Identity 付きの Agent Runtime をデプロイします。

Agent Identity は、エージェント単位で発行される専用 ID です。
この ID に IAM policy を付与することで、エージェントごとに最小権限を設定できます。

> 補足: Agent Identity は環境やリージョンによって利用条件が変わる可能性があります。ハンズオン環境で利用できない場合は、最新の公式ドキュメントを確認してください。

### 1. ADC と環境変数を確認する

Agent Runtime のデプロイでは、Python SDK が Application Default Credentials、ADC を使います。
まず ADC と環境変数を確認します。

```bash
cd "${HOME}/agent-platform-it-support-handson"
source agent-env/bin/activate

export PROJECT_ID="$(gcloud config get-value project)"
export PROJECT_NUMBER="$(gcloud projects describe ${PROJECT_ID} --format='value(projectNumber)')"
export REGION="us-west1"

export BUCKET_NAME="${PROJECT_ID}-agent-bucket"
export MCP_SERVICE_NAME="it-support-mcp"

export SERVICE_URL="$(gcloud run services describe "${MCP_SERVICE_NAME}" \
  --region="${REGION}" \
  --format="value(status.url)")"

export GOOGLE_CLOUD_PROJECT="${PROJECT_ID}"
export GCLOUD_PROJECT="${PROJECT_ID}"

echo "PROJECT_ID=${PROJECT_ID}"
echo "REGION=${REGION}"
echo "SERVICE_URL=${SERVICE_URL}"
echo "GOOGLE_CLOUD_PROJECT=${GOOGLE_CLOUD_PROJECT}"
```

次に、ADC が metadata server ではなく、ユーザー ADC として取得できることを確認します。

```bash
python -c 'import google.auth; from google.auth.transport.requests import Request; credentials, project = google.auth.default(scopes=["https://www.googleapis.com/auth/cloud-platform"]); print("credentials class:", credentials.__class__.__name__); print("project:", project); print("quota project:", getattr(credentials, "quota_project_id", None)); credentials.refresh(Request()); print("token refresh: OK")' 
```

`credentials class: Credentials` と `token refresh: OK` が出ていれば問題ありません。
Qwiklabs / Cloud Shell では ADC ファイルが `/tmp/tmp...` 配下に保存される場合がありますが、上記確認が成功していればそのまま進めます。

もし以下のようなエラーが出る場合は、事前準備の **Python SDK 用の Application Default Credentials を設定する** を再実行してください。

```text
Unexpected response from metadata server: service account info is missing 'email' field
```

### 2. Agent Runtime デプロイスクリプトを作成する

Agent Runtime 内で Cloud Run 用の ID token を発行するため、`google-cloud-iam` の `IAMCredentialsClient.generate_id_token()` を使います。
補足: `from google.cloud import iam_credentials_v1` を使うための Python パッケージは `google-cloud-iam` です。  
Agent Identity の認証情報は Google Cloud クライアントライブラリ経由で使う前提のため、IAMCredentials API を raw `requests.post()` で直接呼ぶ実装は避けます。

```bash
cd "${HOME}/agent-platform-it-support-handson"

python -c 'from pathlib import Path; import os, shutil; src=Path(os.environ.get("HANDSON_ASSETS_DIR","assets"))/"deploy_it_support_agent.py"; dst=Path("deploy_it_support_agent.py"); dst.parent.mkdir(parents=True, exist_ok=True); shutil.copyfile(src,dst); print(f"copied {src} -> {dst}")'
```

### 3. Agent Runtime の Runtime 依存パッケージを確認する

Agent Runtime では、Cloud Shell の仮想環境に入っているパッケージではなく、`client.agent_engines.create()` の `config.requirements` に指定したパッケージが Runtime 側にインストールされます。

このハンズオンでは telemetry を有効化しているため、Runtime 起動時に `google.cloud.aiplatform` が必要です。
`requirements` に `google-cloud-aiplatform` が含まれていない場合、Reasoning Engine のログに以下のようなエラーが出て、Agent Runtime が起動できません。

```text
ModuleNotFoundError: No module named 'google.cloud.aiplatform'
Assembly Service failed to initialize.
```

`deploy_it_support_agent.py` の `requirements` に以下が含まれていることを確認してください。

```python
"requirements": [
    "google-cloud-aiplatform",
    "mcp",
    "google-auth",
    "requests",
    "httpx",
    "cloudpickle",
    "pydantic",
],
```

もし telemetry を使わない場合は、`GOOGLE_CLOUD_AGENT_ENGINE_ENABLE_TELEMETRY` の設定を削除しても構いません。
この資料では、ログ・トレース確認をしやすくするため、`google-cloud-aiplatform` を追加する方針にします。

### 4. Agent Runtime をデプロイする

```bash
python deploy_it_support_agent.py
```

デプロイには数分かかります。

コマンドが成功すると、以下のような情報が表示されます。

```text
Agent Runtime created.
ENGINE_NAME=projects/.../locations/us-west1/reasoningEngines/...
ENGINE_ID=...
AGENT_PRINCIPAL=principal://...
```

### 5. Agent Identity principal を環境変数に設定する

```bash
export AGENT_ENGINE_ID="$(cat agent_engine_id.txt)"
export AGENT_ENGINE_NAME="$(cat agent_engine_name.txt)"
export AGENT_PRINCIPAL="$(cat agent_principal.txt)"

echo "AGENT_ENGINE_ID=${AGENT_ENGINE_ID}"
echo "AGENT_PRINCIPAL=${AGENT_PRINCIPAL}"
```


## Lab07. Agent Identity policy の確認

このラボでは、Agent Identity に対する IAM policy の効果を確認します。

最初に、Agent Identity に Cloud Run Invoker を付与していない状態で呼び出し、失敗することを確認します。
その後、Agent Identity に `roles/run.invoker` を付与し、同じエージェントから Cloud Run MCP server を呼べるようになることを確認します。

### 1. Agent Runtime 呼び出し用スクリプトを作成する

Cloud Shell / Qwiklabs では `google.auth.default()` が metadata server 側の ADC を拾って失敗する場合があります。  
この呼び出し用スクリプトでは、Cloud Shell で安定して動くように `gcloud auth print-access-token` でアクセストークンを取得します。

```bash
cd "${HOME}/agent-platform-it-support-handson"

python -c 'from pathlib import Path; import os, shutil; src=Path(os.environ.get("HANDSON_ASSETS_DIR","assets"))/"query_it_support_agent.py"; dst=Path("query_it_support_agent.py"); dst.parent.mkdir(parents=True, exist_ok=True); shutil.copyfile(src,dst); print(f"copied {src} -> {dst}")'
```


### 2. IAM policy 付与前の失敗を確認する

まだ Agent Identity には Cloud Run Invoker を付与していません。

```bash
python query_it_support_agent.py
```

この時点では、Cloud Run に到達する前に IAM Credentials API で拒否されることが期待されます。

確認ポイントは以下です。

```text
Agent Runtime は作成されている。
しかし、Agent Identity に `roles/iam.serviceAccountTokenCreator` がないため、Private Cloud Run MCP server を呼べない。
```

### 3. Cloud Run 呼び出し用サービスアカウントを作成する

Cloud Run の認証には ID token が必要です。
Agent Runtime では metadata server の identity endpoint が利用できない場合があるため、このハンズオンでは専用のサービスアカウントを作成し、IAM Credentials API の `generateIdToken` で Cloud Run 用 ID token を発行します。

```bash
gcloud iam service-accounts create "${RUN_INVOKER_SA_NAME}" \
  --display-name="IT Support Agent Cloud Run invoker" || true
```

Cloud Run service には、このサービスアカウントを Invoker として許可します。

```bash
gcloud run services add-iam-policy-binding "${MCP_SERVICE_NAME}" \
  --region="${REGION}" \
  --member="serviceAccount:${RUN_INVOKER_SA}" \
  --role="roles/run.invoker"
```

### 4. Agent Identity に Token Creator を付与する

次に、Cloud Run service に対して Agent Identity principal だけを Invoker として許可します。

```bash
export AGENT_MEMBER="$(python -c 'import os,sys; p=os.environ.get("AGENT_PRINCIPAL","").strip(); sys.exit("ERROR: AGENT_PRINCIPAL is empty") if not p else None; print(p if p.startswith("principal://") else "principal://" + p)')"

echo "AGENT_MEMBER=${AGENT_MEMBER}"

gcloud iam service-accounts add-iam-policy-binding "${RUN_INVOKER_SA}" \
  --member="${AGENT_MEMBER}" \
  --role="roles/iam.serviceAccountTokenCreator"
```

IAM policy を確認します。

```bash
gcloud run services get-iam-policy "${MCP_SERVICE_NAME}" \
  --region="${REGION}" \
  --format=json | python -m json.tool
```

### 5. IAM policy 付与後の成功を確認する

```bash
python query_it_support_agent.py
```

期待される結果は以下です。

```text
get_system_status:
  経費精算システムの障害状況が返る

get_employee_info:
  佐藤花子の部署とメールアドレスが返る

危険入力:
  Model Armor または business guard によってブロックされる
```

このラボで確認できたことは以下です。

- Agent Identity は IAM principal として扱える
- Cloud Run service に Agent Identity principal を指定して `roles/run.invoker` を付与できる
- IAM policy 付与前後で、同じ Agent Runtime からのアクセス可否が変わる
- MCP server 内で Model Armor を使い、危険な入力を DB 到達前にブロックできる


## Lab08. Logging / Trace の確認

このラボでは、Cloud Run MCP server と Agent Runtime のログを確認します。

### 1. Cloud Run logs を確認する

Cloud Run MCP server 側のログを確認します。

```
export LOG_FILTER="resource.type=\"cloud_run_revision\" AND resource.labels.service_name=\"${MCP_SERVICE_NAME}\""

gcloud logging read "${LOG_FILTER}" \
  --project="${PROJECT_ID}" \
  --limit=50 \
  --format="table(timestamp,severity,textPayload)"
```

### 2. Model Armor の判定ログを確認する

MCP server のコードでは、Model Armor の判定結果を Cloud Run logs に出力しています。

```
export LOG_FILTER_ARMOR="resource.type=\"cloud_run_revision\" AND resource.labels.service_name=\"${MCP_SERVICE_NAME}\" AND textPayload:\"Model Armor result\""

gcloud logging read "${LOG_FILTER_ARMOR}" \
  --project="${PROJECT_ID}" \
  --limit=20 \
  --format="table(timestamp,severity,textPayload)"
```

`Model Armor result` というログが表示されれば、MCP server から Model Armor を呼び出せています。


## Optional. Google 管理の Cloud Run remote MCP server

Cloud Run には、自作 MCP server とは別に、Google 管理の remote MCP server もあります。

```text
https://run.googleapis.com/mcp
```

これは Cloud Run 管理操作用の MCP server です。

代表的な用途は以下です。

- Cloud Run services の一覧取得
- Cloud Run service の詳細取得
- コンテナイメージから Cloud Run service をデプロイ

MCP client 側に設定する場合の例です。

```json
{
  "mcpServers": {
    "cloud-run": {
      "url": "https://run.googleapis.com/mcp",
      "transport": "http"
    }
  }
}
```

必要な IAM の例です。

```bash
gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
  --member="${AGENT_PRINCIPAL}" \
  --role="roles/mcp.toolUser" \
  --condition=None

gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
  --member="${AGENT_PRINCIPAL}" \
  --role="roles/run.viewer" \
  --condition=None
```

この Optional では、Google 管理 MCP server の実行は行いません。
本ハンズオンの主目的は、自作 Cloud Run MCP server と Agent Identity / Model Armor / Agent Registry の連携です。

## まとめ

トラブルシュートは別ファイル `troubleshooting.md` として分離しています。


このハンズオンでは、以下の構成を作成しました。

```text
Agent Identity
  + IAM policy
  + Private Cloud Run
  + MCP server
  + Agent Registry
  + Model Armor
  + Cloud SQL
  + Cloud Logging / Trace
```

確認できたことは以下です。

- Cloud Run 上に private MCP server を作成できる
- MCP server から Cloud SQL を安全に参照できる
- Model Armor で MCP tool input を検査できる
- Agent Registry に MCP server と tool spec を登録できる
- Agent Runtime に Agent Identity 付き agent をデプロイできる
- Agent Identity principal に Cloud Run Invoker を付与できる
- IAM policy 付与前後で、アクセス制御の違いを確認できる
- Cloud Run logs / Agent Runtime traces で動作を確認できる

Cloud Run IAM、Agent Identity、Model Armor、Agent Registry を組み合わせることで、エンタープライズ向け AI エージェントの基本的なセキュリティ構成を体験できます。


## 参考リンク

- Cloud Run service-to-service authentication
  https://docs.cloud.google.com/run/docs/authenticating/service-to-service

- IAM Credentials generateIdToken
  https://docs.cloud.google.com/iam/docs/reference/credentials/rest/v1/projects.serviceAccounts/generateIdToken

- Application Default Credentials の設定
  https://docs.cloud.google.com/docs/authentication/provide-credentials-adc

- gcloud auth application-default login
  https://docs.cloud.google.com/sdk/gcloud/reference/auth/application-default/login

- Host MCP servers on Cloud Run
  https://docs.cloud.google.com/run/docs/host-mcp-servers

- Build and deploy a remote MCP server on Cloud Run
  https://docs.cloud.google.com/run/docs/tutorials/deploy-remote-mcp-server

- Use Agent Identity with Agent Runtime
  https://docs.cloud.google.com/gemini-enterprise-agent-platform/scale/runtime/agent-identity

- Register MCP servers in Agent Registry
  https://docs.cloud.google.com/agent-registry/register-mcp-servers

- Sanitize prompts and responses with Model Armor
  https://docs.cloud.google.com/model-armor/sanitize-prompts-responses

- Model Armor REST API reference
  https://docs.cloud.google.com/model-armor/docs/reference/rest

- Use the Cloud Run remote MCP server
  https://docs.cloud.google.com/run/docs/use-cloud-run-mcp




## 付録. このチュートリアルで使う別ファイル

以下のファイルは `assets/` に通常のテキストファイルとして入っています。処理内容を確認したい場合は、Cloud Shell で `sed -n '1,200p' assets/<file>` のように読めます。

- `assets/Dockerfile`
- `assets/check_01.py`
- `assets/deploy_it_support_agent.py`
- `assets/model_armor_template.json`
- `assets/query_it_support_agent.py`
- `assets/requirements.txt`
- `assets/sanitize_dangerous.json`
- `assets/sanitize_normal.json`
- `assets/sanitize_prompt_injection.json`
- `assets/server.py`
- `assets/setup_db.py`
- `assets/test_mcp_local.py`
- `assets/toolspec.json`

例:

```bash
sed -n '1,200p' "${HANDSON_ASSETS_DIR}/deploy_it_support_agent.py"
```

## 付録. Cloud Run ログ確認

Cloud Run のログ確認では、filter 全体を 1 つの文字列として渡します。  
`'...' ${MCP_SERVICE_NAME} '...'` のように分割すると、`unrecognized arguments` になります。

```bash
export LOG_FILTER="resource.type=\"cloud_run_revision\" AND resource.labels.service_name=\"${MCP_SERVICE_NAME}\""

echo "${LOG_FILTER}"

gcloud logging read "${LOG_FILTER}" \
  --project="${PROJECT_ID}" \
  --limit=50 \
  --format="table(timestamp,severity,textPayload)"
```

Model Armor や business guard のログだけ見たい場合は以下を使います。

```bash
gcloud logging read "resource.type=\"cloud_run_revision\" AND resource.labels.service_name=\"${MCP_SERVICE_NAME}\" AND (textPayload:\"Model Armor\" OR textPayload:\"business guard\" OR textPayload:\"blocked\" OR textPayload:\"dump\")" \
  --project="${PROJECT_ID}" \
  --limit=50 \
  --format="table(timestamp,severity,textPayload)"
```
