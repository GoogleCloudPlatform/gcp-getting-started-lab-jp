# `migration-to-gcp` プラグインのインストール

AWS から GCP への移行スキル、2 つの公式ナレッジ MCP サーバー（AWS Knowledge / Google Developer Knowledge）、およびライブ料金取得 CLI（`gcp-pricing`）をまとめて提供する Claude Code プラグインです。

> English version: [`INSTALL.md`](INSTALL.md)

## 前提条件

| 要件            | バージョン / 設定                                                                                      |
| --------------- | ------------------------------------------------------------------------------------------------------ |
| **Claude Code** | 2.1.119 以上（`claude --version` で確認）                                                              |
| **Node.js**     | 18 以上（`gcp-pricing` CLI と MCP プロキシの実行に使用）                                               |
| **gcloud CLI**  | インストール済みで PATH が通っていること（[インストールガイド](https://cloud.google.com/sdk/install)） |
| **AWS CLI**     | 移行元 AWS アカウントへの読み取りアクセスで設定済み（ディスカバリー用）                                |

## 1. プラグインのインストール

### 方法 A — マーケットプレイスから（推奨）

Claude Code セッション内で実行します。

```text
/plugin marketplace add cloud-gtm/migration-skills
/plugin install migration-to-gcp@migration-skills
```

ターミナルから実行する場合:

```bash
claude plugin marketplace add cloud-gtm/migration-skills
claude plugin install migration-to-gcp@migration-skills          # ユーザースコープ（全プロジェクトで利用可能）
claude plugin install migration-to-gcp@migration-skills --scope project   # .claude/settings.json 経由でチーム共有
```

プラグインはコミット SHA でバージョン管理されます。`/plugin update migration-to-gcp` を実行すると新しいコミットを取り込めます。

### 方法 B — ローカルチェックアウト（開発用・そのセッション限りの読み込み）

```bash
git clone git@github.com:cloud-gtm/migration-skills.git
claude --plugin-dir migration-skills/features/migration-to-gcp
```

## 2. Google 認証の設定（ADC を優先）

Developer Knowledge MCP サーバーと `gcp-pricing` CLI は、次の優先順位で認証します: **gcloud ADC → gcloud ユーザー認証情報 → API キー（フェイルオーバー）**。

```bash
gcloud auth application-default login
gcloud config set project PROJECT_ID
gcloud services enable cloudbilling.googleapis.com developerknowledge.googleapis.com
```

**API キーによるフェイルオーバー（任意 / gcloud ADC が使えない環境向け）:**

```bash
gcloud services api-keys create --display-name="migration-to-gcp" \
  --api-target=service=developerknowledge.googleapis.com \
  --api-target=service=cloudbilling.googleapis.com
```

作成したキーはプラグイン設定に保存します。Claude Code で `/plugin configure migration-to-gcp@migration-skills` を実行するか（`google_dev_knowledge_api_key` フィールド。セキュアストレージに保存されます）、インストール時に `--config google_dev_knowledge_api_key=KEY` を渡します。料金 CLI を単体で使う場合は、環境変数 `GCP_PRICING_API_KEY` で指定することもできます。

## 3. インストールの確認

```bash
claude plugin details migration-to-gcp   # 期待値: Skills (1) aws-to-gcp, MCP servers (2)
claude mcp list                          # 両方のプラグインサーバーが "✔ Connected" になること
```

続いて、対象プロジェクト内の Claude Code セッションで次のように入力します。

```text
> migrate from AWS to GCP
```

`aws-to-gcp` スキルが起動し、5 フェーズのワークフロー（Discover → Clarify → Design → Estimate → Generate）が始まります。料金ツールの動作確認をするには、Claude に `gcp-pricing services --filter "Cloud Run"` を実行させてください。出力は `auth_mode` と `retrieved_at` の来歴情報を含む JSON です。

## 4. 更新 / アンインストール

```bash
claude plugin update migration-to-gcp
claude plugin uninstall migration-to-gcp
claude plugin marketplace remove migration-skills
```

## トラブルシューティング

- **`google-developer-knowledge` が "failed to connect" と表示される** — プロキシの標準エラー出力（`claude --debug` または `/mcp` で確認可能）に、必要な設定手順が表示されます。よくある原因: ADC 未設定（`gcloud auth application-default login`）、対象プロジェクトで Developer Knowledge API が未有効化、フェイルオーバー用 API キーが未設定。
- **`gcp-pricing` が HTTP 403 `SERVICE_DISABLED` で終了する** — エラー本文に、プロジェクト用の `gcloud services enable ...` 有効化 URL が含まれます。Cloud Billing API を有効化してから再実行してください。
- **Claude の Bash で `gcp-pricing: command not found` になる** — プラグインの `bin/` 実行ファイルには Claude Code 2.1.91 以上が必要です。アップグレードしてセッションを再起動してください。
- **サービス名が曖昧** — `gcp-pricing skus --service "Cloud SQL"` のような指定は、複数一致した場合に候補の serviceId を列挙します。正確な ID で再実行してください。
