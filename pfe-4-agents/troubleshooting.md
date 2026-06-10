<walkthrough-metadata>
  <meta name="title" content="Agent Platform Troubleshooting" />
  <meta name="description" content="Troubleshooting for Agent Platform hands-on" />
</walkthrough-metadata>

<walkthrough-disable-features toc></walkthrough-disable-features>

# Agent Platform ハンズオン トラブルシュート

## 1. `gcloud alpha agent-registry` が見つからない

以下を実行してください。

```bash
gcloud components update
gcloud components install alpha beta
```

Cloud Shell では components 操作が制限される場合があります。
その場合は、ローカルの Google Cloud CLI で実行するか、Cloud Shell の gcloud バージョンが更新されるまで待ってください。

## 2. Agent Registry 登録で `invalid interface url format` になる

以下のようなエラーが出る場合があります。

```text
ERROR: (gcloud.alpha.agent-registry.services.create) INVALID_ARGUMENT:
The request was invalid: invalid interface url format
field: service.interfaces[0].url
```

このエラーは、`SERVICE_URL` が空の状態で `url=${SERVICE_URL}/mcp` を渡してしまい、実際には `url=/mcp` のような不正 URL が送信されたときに発生しやすいです。

まず Cloud Run service URL を再取得してください。

```bash
export SERVICE_URL="$(gcloud run services describe "${MCP_SERVICE_NAME}" \
  --region="${REGION}" \
  --format="value(status.url)")"

export REGISTRY_MCP_URL="${SERVICE_URL%/}/mcp"

echo "SERVICE_URL=${SERVICE_URL}"
echo "REGISTRY_MCP_URL=${REGISTRY_MCP_URL}"
```

次に URL 形式を確認します。

```bash
case "${REGISTRY_MCP_URL}" in
  https://*)
    echo "OK: ${REGISTRY_MCP_URL}"
    ;;
  *)
    echo "ERROR: invalid URL: ${REGISTRY_MCP_URL}"
    exit 1
    ;;
esac
```

`SERVICE_URL` が空の場合は、Cloud Run service 名やリージョンが正しいか確認します。

```bash
gcloud run services list --region="${REGION}"

echo "MCP_SERVICE_NAME=${MCP_SERVICE_NAME}"
echo "REGION=${REGION}"
```

その後、`REGISTRY_MCP_URL` を使って再登録してください。

```bash
gcloud alpha agent-registry services create "${MCP_SERVICE_NAME}" \
  --project="${PROJECT_ID}" \
  --location="${REGION}" \
  --display-name="IT Support MCP Server" \
  --mcp-server-spec-type=tool-spec \
  --mcp-server-spec-content=toolspec.json \
  --interfaces="url=${REGISTRY_MCP_URL},protocolBinding=JSONRPC"
```

## 3. Model Armor template 作成で `gcloud` が PERMISSION_DENIED になる

Qwiklabs / Cloud Shell 環境では、以下のように `gcloud model-armor templates create` が `PERMISSION_DENIED` になる場合があります。

```text
ERROR: (gcloud.model-armor.templates.create) PERMISSION_DENIED: Write access to project ... was denied.
```

この場合でも、regional endpoint を明示した REST API では成功することがあります。
このハンズオンでは、Model Armor template の作成・確認・削除は REST API で実施してください。

確認用の REST API です。

```bash
curl -s -i \
  -H "Authorization: Bearer $(gcloud auth print-access-token)" \
  "https://modelarmor.${REGION}.rep.googleapis.com/v1/projects/${PROJECT_ID}/locations/${REGION}/templates/${MODEL_ARMOR_TEMPLATE}"
```

`HTTP/2 200` が返れば、template の参照は成功しています。

参考として、`gcloud` 側で regional endpoint override を設定する場合は以下です。

```bash
gcloud config set api_endpoint_overrides/modelarmor \
  "https://modelarmor.${REGION}.rep.googleapis.com/"

gcloud config get-value api_endpoint_overrides/modelarmor
```

ただし、このハンズオンの手順では REST API を正とします。

## 4. Agent Runtime 起動ログに `No module named 'google.cloud.aiplatform'` が出る

以下のようなログが出て、Agent Runtime が `failed to start and cannot serve traffic` になる場合があります。

```text
ModuleNotFoundError: No module named 'google.cloud.aiplatform'
Assembly Service failed to initialize.
```

これは、Agent Runtime 側に `google-cloud-aiplatform` パッケージが入っていない状態で、telemetry setup が `google.cloud.aiplatform` を import しようとして失敗している状態です。

Cloud Shell の仮想環境に `google-cloud-aiplatform` が入っていても、Agent Runtime には自動では反映されません。
`client.agent_engines.create()` の `config.requirements` に明示する必要があります。

`deploy_it_support_agent.py` の requirements を以下のように修正してください。

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

シンプル Agent 版を使う場合でも、telemetry を有効にしているなら以下を含めます。

```python
"requirements": [
    "google-cloud-aiplatform",
    "cloudpickle",
    "pydantic",
],
```

修正後、再度デプロイします。

```bash
python deploy_it_support_agent.py
```

古い失敗済み Reasoning Engine は残っていても、ハンズオンを続ける上では新しく作成された Engine ID を使えば問題ありません。
不要であれば後で Console から削除してください。

## 5. Agent Runtime デプロイで `metadata server: service account info is missing 'email' field` になる

以下のようなエラーが出る場合があります。

```text
google.auth.exceptions.RefreshError:
Unexpected response from metadata server: service account info is missing 'email' field.
```

これは、Python SDK が Application Default Credentials、ADC を見つけられず、Cloud Shell の metadata server 認証にフォールバックしている状態です。
`gcloud` コマンドの認証と Python SDK が利用する ADC は別です。

以下を実行して ADC を作成してください。

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

ADC の確認です。

```bash
python -c 'import google.auth; from google.auth.transport.requests import Request; credentials, project = google.auth.default(scopes=["https://www.googleapis.com/auth/cloud-platform"]); print("credentials class:", credentials.__class__.__name__); print("project:", project); print("quota project:", getattr(credentials, "quota_project_id", None)); credentials.refresh(Request()); print("token refresh: OK")' 
```

`token refresh: OK` が出たら、再度 Agent Runtime をデプロイします。

```bash
python deploy_it_support_agent.py
```

## 6. Cloud Run MCP server に 403 が返る

Cloud Run service の IAM policy を確認します。

```bash
gcloud run services get-iam-policy "${MCP_SERVICE_NAME}" \
  --region="${REGION}"
```

Cloud Shell から呼ぶ場合は、Cloud Shell のユーザーに `roles/run.invoker` が必要です。

```bash
gcloud run services add-iam-policy-binding "${MCP_SERVICE_NAME}" \
  --region="${REGION}" \
  --member="user:${USER_EMAIL}" \
  --role="roles/run.invoker"
```

Agent Runtime から呼ぶ場合は、Agent Identity principal に `roles/run.invoker` が必要です。

```bash
gcloud run services add-iam-policy-binding "${MCP_SERVICE_NAME}" \
  --region="${REGION}" \
  --member="${AGENT_PRINCIPAL}" \
  --role="roles/run.invoker"
```

## 7. Agent Runtime から Cloud Run に接続できない

以下を確認してください。

```bash
echo "SERVICE_URL=${SERVICE_URL}"
echo "AGENT_PRINCIPAL=${AGENT_PRINCIPAL}"

gcloud run services get-iam-policy "${MCP_SERVICE_NAME}" \
  --region="${REGION}" \
  --format=json | python -m json.tool
```

Cloud Run の認証では、ID token の audience が Cloud Run service URL と一致する必要があります。
このハンズオンでは、Agent Runtime 側で以下を使っています。

```python
id_token.fetch_id_token(Request(), self.audience)
```

`self.audience` は Cloud Run service URL です。

## 8. Cloud SQL 接続で失敗する

MCP server のサービスアカウントに `roles/cloudsql.client` が付与されているか確認します。

```bash
gcloud projects get-iam-policy "${PROJECT_ID}" \
  --flatten="bindings[].members" \
  --filter="bindings.members:serviceAccount:${MCP_SA}" \
  --format="table(bindings.role)"
```

Cloud Run の環境変数も確認します。

```bash
gcloud run services describe "${MCP_SERVICE_NAME}" \
  --region="${REGION}" \
  --format="yaml(spec.template.spec.containers[0].env)"
```

## 9. Agent query で metadata server の `identity` endpoint エラーになる

以下のようなレスポンスが返る場合があります。

```text
Failed to retrieve http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/identity?...
Compute Engine Metadata server unavailable.
```

これは、Cloud Run 用 ID token を `google.oauth2.id_token.fetch_id_token()` で取得しようとして、Agent Runtime の metadata server identity endpoint が使えないために発生します。

Cloud Run の認証には ID token が必要です。
ただし、metadata server から ID token を取得できるサービスは限られています。
このハンズオンでは、Agent Identity に `roles/iam.serviceAccountTokenCreator` を付与し、専用サービスアカウントを IAM Credentials API の `generateIdToken` で impersonate して Cloud Run 用 ID token を発行する構成に変更します。

`deploy_it_support_agent.py` の `_get_cloud_run_id_token()` が以下のように IAM Credentials API を呼ぶ実装になっていることを確認してください。

```python
def _get_cloud_run_id_token(self) -> str:
    import requests
    import google.auth
    from google.auth.transport.requests import Request

    credentials, _ = google.auth.default(
        scopes=["https://www.googleapis.com/auth/cloud-platform"]
    )
    credentials.refresh(Request())

    url = (
        "https://iamcredentials.googleapis.com/v1/"
        f"projects/-/serviceAccounts/{self.invoker_sa}:generateIdToken"
    )

    response = requests.post(
        url,
        headers={
            "Authorization": f"Bearer {credentials.token}",
            "Content-Type": "application/json",
        },
        json={
            "audience": self.audience,
            "includeEmail": True,
        },
        timeout=30,
    )
    response.raise_for_status()
    return response.json()["token"]
```

必要な IAM は以下です。

```bash
gcloud run services add-iam-policy-binding "${MCP_SERVICE_NAME}" \
  --region="${REGION}" \
  --member="serviceAccount:${RUN_INVOKER_SA}" \
  --role="roles/run.invoker"

case "${AGENT_PRINCIPAL}" in
  principal://*)
    export AGENT_MEMBER="${AGENT_PRINCIPAL}"
    ;;
  *)
    export AGENT_MEMBER="principal://${AGENT_PRINCIPAL}"
    ;;
esac

gcloud iam service-accounts add-iam-policy-binding "${RUN_INVOKER_SA}" \
  --member="${AGENT_MEMBER}" \
  --role="roles/iam.serviceAccountTokenCreator"
```

修正後、Agent Runtime を再デプロイし、新しい Agent Engine ID を使ってください。

```bash
python deploy_it_support_agent.py
```

## 10. Agent query で `asyncio.run() cannot be called from a running event loop` になる

以下のようなレスポンスが返る場合があります。

```json
{
  "output": {
    "ok": false,
    "error": "asyncio.run() cannot be called from a running event loop"
  }
}
```

これは、Agent Runtime 側で既に asyncio event loop が動いている状態で、Agent の `query()` メソッド内から `asyncio.run()` を直接呼んだことが原因です。

`deploy_it_support_agent.py` の `_call_mcp()` を以下に修正してください。

```python
def _call_mcp(self, tool_name: str, args: dict):
    import asyncio
    from concurrent.futures import ThreadPoolExecutor

    def runner():
        return asyncio.run(self._call_mcp_async(tool_name, args))

    with ThreadPoolExecutor(max_workers=1) as executor:
        future = executor.submit(runner)
        return future.result()
```

修正後、Agent Runtime を再デプロイします。

```bash
python deploy_it_support_agent.py
```

新しく作成された Agent Engine ID を読み込みます。

```bash
export AGENT_ENGINE_ID="$(cat agent_engine_id.txt)"
export AGENT_ENGINE_NAME="$(cat agent_engine_name.txt)"
export AGENT_PRINCIPAL="$(cat agent_principal.txt)"

echo "AGENT_ENGINE_ID=${AGENT_ENGINE_ID}"
echo "AGENT_PRINCIPAL=${AGENT_PRINCIPAL}"
```

Agent Identity principal が `principal://` なしで出力される場合があるため、Cloud Run IAM 付与時は以下のように正規化してください。

```bash
case "${AGENT_PRINCIPAL}" in
  principal://*)
    export AGENT_MEMBER="${AGENT_PRINCIPAL}"
    ;;
  *)
    export AGENT_MEMBER="principal://${AGENT_PRINCIPAL}"
    ;;
esac

gcloud run services add-iam-policy-binding "${MCP_SERVICE_NAME}" \
  --region="${REGION}" \
  --member="${AGENT_MEMBER}" \
  --role="roles/run.invoker"
```

## 11. 危険入力が Model Armor ではなく business guard でブロックされる

このハンズオンでは、デモの再現性を高めるために 2 段構成にしています。

```text
1. business guard
   - dump
   - password
   - 全テーブル
   - パスワード
   などの明示的に危険なキーワードをブロック

2. Model Armor
   - prompt injection
   - dangerous content
   - sensitive data
   などを template に基づいて検査
```

Model Armor の判定を重点的に見たい場合は、`server.py` の `BLOCKED_KEYWORDS` を一時的に空にして再デプロイしてください。


## 正常系まで Model Armor でブロックされる

正常入力でも以下のように返る場合があります。

```text
❌ Model Armor により危険な入力としてブロックしました。
```

Cloud Run logs で以下のように出ていれば、Model Armor の false positive です。

```text
Model Armor result: tool=get_system_status match_state=MATCH_FOUND invocation_result=SUCCESS
```

このハンズオンでは、Model Armor は検知ログとして扱い、業務禁止操作は MCP server 側の business guard で hard block します。  
`server.py` の `_model_armor_guard()` で `MATCH_FOUND` を `PermissionError` にしない実装に修正し、Cloud Run を再デプロイしてください。


## Agent Registry 登録で toolspec.json が見つからない

以下のエラーが出る場合は、`toolspec.json` を作成したディレクトリと登録コマンドを実行しているディレクトリがズレています。

```text
argument --mcp-server-spec-content: Unable to read file [toolspec.json]
```

このハンズオンでは、`toolspec.json` は `mcp-server` ディレクトリに作成します。

```bash
cd "${HOME}/agent-platform-it-support-handson/mcp-server"
ls -l toolspec.json
```

存在しない場合は、Lab05 の「tool spec を作成する」を再実行してください。


## Agent query で generateIdToken が 401 Unauthorized になる

以下のエラーは、Cloud Run に到達する前に IAM Credentials API で拒否されている状態です。

```text
401 Client Error: Unauthorized for url: https://iamcredentials.googleapis.com/v1/projects/-/serviceAccounts/...:generateIdToken
```

この場合、Agent Runtime 自体は動いています。  
不足しているのは、Agent Identity が Cloud Run 呼び出し用サービスアカウントの ID token を発行するための権限です。

確認ポイント:

- 外側の Agent Runtime 呼び出しが `HTTP 200` で返る
- `output.ok` が `false`
- `error` に `generateIdToken` と `401 Unauthorized` が含まれる

対応:

```bash
gcloud iam service-accounts add-iam-policy-binding "${RUN_INVOKER_SA}" \
  --member="${AGENT_MEMBER}" \
  --role="roles/iam.serviceAccountTokenCreator"
```

この権限付与前の段階では、正常入力も危険入力もすべて `generateIdToken` で失敗します。  
`dump` などの business guard の確認は、Token Creator 付与後に MCP server まで到達できるようになってから確認します。


## AGENT_MEMBER の正規化で principal:// が壊れる

Teachme の実行ボタンで `case ... esac` を実行すると、コメントや `principal://` の行が壊れて以下のようなエラーが出る場合があります。

```text
-bash: principal://: No such file or directory
```

ただし、その後に以下が表示されていれば Token Creator 付与は成功しています。

```text
Updated IAM policy for serviceAccount [...]
role: roles/iam.serviceAccountTokenCreator
```

安全な正規化コマンドは以下です。

```bash
export AGENT_MEMBER="$(python -c 'import os,sys; p=os.environ.get("AGENT_PRINCIPAL","").strip(); sys.exit("ERROR: AGENT_PRINCIPAL is empty") if not p else None; print(p if p.startswith("principal://") else "principal://" + p)')"

echo "AGENT_MEMBER=${AGENT_MEMBER}"
```


## Token Creator 付与後も generateIdToken が 401 のまま残る

`AGENT_ENGINE_ID`、`agent_engine_id.txt`、`AGENT_PRINCIPAL` の Reasoning Engine ID が一致し、サービスアカウント側 IAM policy に `roles/iam.serviceAccountTokenCreator` が付与されているのに、以下が続く場合があります。

```text
401 Client Error: Unauthorized for url: https://iamcredentials.googleapis.com/v1/projects/-/serviceAccounts/...:generateIdToken
```

この場合は、Agent Runtime 内で IAMCredentials API を raw `requests.post()` で呼んでいる実装が原因の可能性があります。  
Agent Identity の認証情報は Google Cloud クライアントライブラリ経由で使う前提のため、`google-cloud-iam` の `IAMCredentialsClient.generate_id_token()` に変更してください。

必要な Runtime requirement:

```text
google-cloud-iam
```

ID token 発行処理の例:

```python
from google.cloud import iam_credentials_v1

client = iam_credentials_v1.IAMCredentialsClient()
response = client.generate_id_token(
    name=f"projects/-/serviceAccounts/{RUN_INVOKER_SA}",
    audience=SERVICE_URL,
    include_email=True,
)
token = response.token
```


## query_it_support_agent.py で metadata server: service account info is missing 'email' field

以下のエラーは、Agent Runtime 側ではなく、Cloud Shell で `query_it_support_agent.py` を実行しているローカル側の認証問題です。

```text
google.auth.exceptions.RefreshError: Unexpected response from metadata server: service account info is missing 'email' field.
```

Cloud Shell / Qwiklabs では `google.auth.default()` が metadata server 側の ADC を拾って失敗する場合があります。  
このハンズオンでは、`query_it_support_agent.py` は `google.auth.default()` ではなく、`gcloud auth print-access-token` を使って Vertex AI Agent Runtime API を呼び出します。

該当部分の考え方:

```python
import subprocess

access_token = subprocess.check_output(
    ["gcloud", "auth", "print-access-token"],
    text=True,
).strip()
```


## Agent Runtime build failed after adding IAM Credentials dependency

`from google.cloud import iam_credentials_v1` を使うための Python パッケージは `google-cloud-iam` です。

誤り:

```text
google-cloud-iam-credentials
```

正しい依存関係:

```text
google-cloud-iam
```

`deploy_it_support_agent.py` の requirements に誤ったパッケージ名が入っている場合は、以下で修正します。

```bash
python -c 'from pathlib import Path; p=Path("deploy_it_support_agent.py"); s=p.read_text(); s=s.replace("google-cloud-iam-credentials", "google-cloud-iam"); p.write_text(s); print("patched dependency to google-cloud-iam")'
```


## gcloud logging read で unrecognized arguments が出る

以下のように filter のクォートを分割すると、`${MCP_SERVICE_NAME}` が別引数として扱われ、`unrecognized arguments` になります。

```bash
gcloud logging read 'resource.type="cloud_run_revision" AND resource.labels.service_name="' ${MCP_SERVICE_NAME}'"'
```

filter 全体を 1 つの文字列として渡します。

```bash
export LOG_FILTER="resource.type=\"cloud_run_revision\" AND resource.labels.service_name=\"${MCP_SERVICE_NAME}\""

echo "${LOG_FILTER}"

gcloud logging read "${LOG_FILTER}" \
  --project="${PROJECT_ID}" \
  --limit=50 \
  --format="table(timestamp,severity,textPayload)"
```

Model Armor や business guard のログだけ見る場合:

```bash
gcloud logging read "resource.type=\"cloud_run_revision\" AND resource.labels.service_name=\"${MCP_SERVICE_NAME}\" AND (textPayload:\"Model Armor\" OR textPayload:\"business guard\" OR textPayload:\"blocked\" OR textPayload:\"dump\")" \
  --project="${PROJECT_ID}" \
  --limit=50 \
  --format="table(timestamp,severity,textPayload)"
```
