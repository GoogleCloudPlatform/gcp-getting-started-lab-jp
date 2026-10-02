# Migration Skills Harness — AWS・Azure → Google Cloud

> AI 駆動の移行アシスタント。AWS **または Azure** ワークロードのスナップショット(Terraform、CloudFormation / Bicep / ARM、アプリケーションソース、課金エクスポート)を、レビュー済み・コスト算出済みで、すぐに適用できる Google Cloud 移行計画に変換します。さらに、それが正しく動くことを証明するテストハーネスも同梱しています。

このリポジトリは 2 つの要素で構成されています:

1. **[Claude Code](https://code.claude.com/docs) プラグイン**(`features/migration-to-gcp/`)— 2 つの移行スキル **`aws-to-gcp`** と **`azure-to-gcp`**、3 つの公式ナレッジ MCP サーバー(Google Developer Knowledge、AWS Knowledge、Microsoft Learn)、ライブ GCP 価格 CLI(`gcp-pricing`)をバンドル。
2. **ユーザージャーニーテストハーネス**(`user-journey-tests/`、`CATALOG.md`、`tools/`)— 13 の架空顧客ワークロード(AWS 5 件、Azure 8 件)、既知の正解となる GCP リファレンス実装、機械検証される答え合わせキー。スキルが実際の環境を正しく発見・設計・見積もりできるかを評価するために使います。

---

## リポジトリの中身

```text
migration-skills-harness/
├── .claude-plugin/marketplace.json       # 下記プラグインを指すマーケットプレイスカタログ
├── .agents/skills/                       # google-agents-cli スキル群のベンダリング(deploy、publish、
│                                         #   adk-code、eval、observability、scaffold、workflow)—
│                                         #   skills-lock.json でピン留め。aws-to-gcp のエージェント
│                                         #   ルーブリックが GCP 側の正典として参照
├── features/
│   └── migration-to-gcp/                 # Claude Code プラグイン本体
│       ├── .claude-plugin/plugin.json    # プラグインマニフェスト(+ API キーフェイルオーバー用 userConfig)
│       ├── .mcp.json                     # バンドル MCP サーバー(awsknowledge、google-developer-knowledge、microsoft-learn)
│       ├── bin/gcp-pricing               # ライブ GCP 価格 CLI(プラグイン有効時に PATH へ)
│       ├── scripts/                      # ADC 注入 MCP プロキシ + 価格 CLI + 共有認証チェーン
│       └── skills/
│           ├── aws-to-gcp/               # AWS → GCP スキル(SKILL.md + フェーズ/設計リファレンス + evals)
│           └── azure-to-gcp/             # Azure → GCP スキル(同じ 5 フェーズ機構、Azure 側の発見 + ゲート)
├── CATALOG.md                            # ジャーニーカタログ:評価手順、トラップ答え合わせキー、
│                                         #   ライブリファレンス環境のデプロイ状況
├── user-journey-tests/
│   ├── CONVENTIONS.md                    # フィクスチャ作成ルール(命名、決定性、答え合わせキーの分離)
│   ├── aws/j1-…j5-<pattern>/             # AWS 移行元ワークロード(サーバーレス API、3 層 Web、イベント
│   │                                     #   ファンアウト、Fargate AI チャットボット、EKS マイクロサービス)
│   ├── azure/j1-…j8-<pattern>/           # Azure 移行元ワークロード(Windows IaaS、PaaS Web、AKS、Durable
│   │                                     #   Functions、VMSS+SQL、ストレージ/メディア、Container Apps RAG、
│   │                                     #   ClickOps 部分 IaC)
│   └── gcp-references/<vendor>/…         # 既知の正解となる移行先(答え合わせキー)— 評価対象のエージェント
│                                         #   が作業ディレクトリから発見できないよう、ジャーニー外に配置
├── tools/                                # 検証ツール:マニフェスト、クロスリファレンス、CATALOG 引用チェッカー
├── INSTALL.md / INSTALL.ja.md            # インストール手順、認証設定、トラブルシューティング
└── README.md                             # 本ドキュメントの英語版
```

---

## 移行スキル

両スキルとも、シニアクラウドアーキテクトが実際の Google Cloud 移行を評価・計画するのと同じ流れを反映した、**決定論的なマルチフェーズワークフロー**で Claude Code を駆動します:

```text
Discover → Clarify → Design → Estimate → Generate
```

各フェーズにはハードゲートがあり、エージェントはフェーズを**スキップできません**。Clarify は Design の前に、Design は Estimate の前に完了している必要があります。これは各フェーズ完了後に書き込まれる `.migration/<run-id>/.phase-status.json` によって強制されます。その結果、計画を幻覚するワンショットのプロンプトではなく、再現可能で再開可能な実行が得られます。

フェーズの裏でエージェントが実際に行うこと:

- **ソースを直接読み取る** — Terraform、CloudFormation / SAM / CDK(AWS)または Bicep / ARM テンプレート(Azure)、SDK 呼び出し箇所を含むアプリケーションソース、課金エクスポートを、モデル組み込みの `Read` / `Grep` / `Glob` ツールで読み取ります。パーサースクリプトは生成しません。
- **非決定的な判断の前には必ずライブリサーチを実行** — 価格、サービス機能、ライフサイクルステージ、最新の GCP プロダクトの適合性を、バンドルされた `gcp-pricing` CLI、ナレッジ MCP サーバー、公式ドキュメントへの `WebFetch` で調査します。コスト数値やサービス推奨における学習データからの想起は明示的に**禁止**されています。
- **推測する前に質問する** — 発見時の曖昧さ、移行の意図(カットオーバー / PoC クローン / ハイブリッド)、クラウド間接続、2 つ以上の有力な GCP 移行先候補がある選択は、選択式の質問としてユーザーに提示されます。
- **自動マッピングすべきでないものは保留する** — Redshift や Synapse 級の分析基盤は常に `Deferred — specialist engagement` としてマークされます。適切な BigQuery / Dataflow / Dataproc の移行先を決めるには、Google Cloud アカウントチームまたはデータ分析パートナーとの専門的な対話が必要だからです。

### フェーズ

| # | フェーズ     | 何をするか                                                                                                                                                                                                                              | 主な出力                                                                                                                                           |
| - | ------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1 | **Discover** | プロジェクトの IaC・アプリケーションソース・課金データをスキャン。リソースを分類・クラスタリングし、AI **およびエージェントフレームワーク**のワークロードを検出、SDK 呼び出し箇所をインベントリ化、HTTP ルーティングマップを抽出。      | `*-resource-inventory.json`、`*-resource-clusters.json`、`ai-workload-profile.json`、`*-sdk-usage.json`、`app-routes.json`、`billing-profile.json` |
| 2 | **Clarify**  | グローバル、設定ギャップ、コンピュート、データベース、AI、ロギング、サイジングの各カテゴリにわたる適応型質問。移行の意図の明示的な選択と、推奨予定の各クラウド間接続の確認を求めます。                                                  | `preferences.json`                                                                                                                                 |
| 3 | **Design**   | すべての移行元リソースを、信頼度スコアと出典付きの根拠とともに GCP の対応サービスへマッピング。インストール済みの [`google/skills`](https://github.com/google/skills) があればそちらに委ね、なければ内部ルーブリックにフォールバック。  | `gcp-design.json`、`gcp-design-ai.json`、`gcp-design-billing.json`、`sdk-migration-plan.json`                                                      |
| 4 | **Estimate** | マッピングされた全サービスを **`gcp-pricing` CLI**(Cloud Billing Catalog API)のライブ SKU 価格で照会し、3 段階の月額コストを算出して移行元の支出と比較。すべての金額に完全な出典が付随します。モデルの記憶による価格は使用しません。    | `estimation-infra.json`、`estimation-ai.json`、`estimation-billing.json`                                                                           |
| 5 | **Generate** | 凍結された設計をデプロイ可能な成果物に変換:モジュール化された Terraform、データ移行スクリプト、AI プロバイダーアダプター、呼び出し箇所ごとのソースパッチ、エージェント再デプロイランブック、パリティテスト、ADR、`MIGRATION_GUIDE.md`。 | `terraform/`、`scripts/`、`code-patches/`、`ai-migration/`、`user-journeys/`、`adrs/`、`MIGRATION_GUIDE.md`、`README.md`、`migration-report.html`  |

すべての成果物は**実行スコープのディレクトリ** `.migration/<MMDD-HHMM>/` に書き込まれます。ソースプロジェクトのファイルには決して触れません — すべての `Write` 前のパス自己チェックで強制されます。

### aws-to-gcp のハイライト

- **エージェントワークロードは Agent Runtime へ。** 環境内で検出された Google ADK、LangGraph、CrewAI、Bedrock Agents / AgentCore のワークロードは、デフォルトで **Gemini Enterprise Agent Platform(GEAP、旧 Vertex AI Agent Engine)の Agent Runtime** に配置されます — `agents-cli` でデプロイし、自己管理セッションストアはマネージド Sessions に置き換えます。周辺の統制は `design-refs/agent-governance.md` に従って GCP のエージェントガバナンス群(Agent Registry、Agent Gateway、Agent Identity、Model Armor)へマッピングされます。
- **AI ワークロード移行** — Bedrock / OpenAI の利用を Agent Platform 上の Gemini へ、モデルごとの機能マッピング・ライブ価格比較・呼び出し箇所ごとの書き換えパッチ付きでマッピング。モデル推奨は設計時のライブ稼働テストで検証され、記憶からの引用は行いません。
- **言語カバレッジ** — Python、JavaScript/TypeScript、Go、Java、および **PHP**(`aws/aws-sdk-php`)。PHP 固有のサポート境界(公式 `google/*` パッケージのみ、公式 PHP サーフェスがない機能への明示的警告)も扱います。

### azure-to-gcp のハイライト

- **Azure 側の発見** — Terraform `azurerm`、Bicep、ARM テンプレート、アプリケーションソース、Azure コストエクスポート(FOCUS または実コスト)、さらに Azure Migrate / `mcdc` のアセスメント出力。
- **7 つの助言・保留ゲート**が Clarify で発動:アイデンティティ隣接(Entra ID フェデレーション — IdP 移行は行わない)、Microsoft ライセンス(Azure ハイブリッド特典は移行先に持ち込めない)、分析基盤の保留(Synapse、Fabric、Databricks など)、VM ごとの M2VM 適格性、Cosmos DB の API フレーバー別リプラットフォームカード、ライブ Azure サイジングの同意(ヘッドレス実行なし)、対象外の拒否。
- 成果物の形式、ゲート、価格出典ルールは AWS スキルと共通です。

### 両スキルに組み込まれた安全策

- 非決定的な判断には**ライブリサーチが必須**。すべての推奨に出典(URL + `fetched_at`)が付き、学習データからの想起は禁止。
- **ハードなフェーズゲート**により Generate への直行を防止。
- **Generate 時点で Design は凍結。** Generate は Design に一致する成果物を出力しなければならず、黙った上書きは禁止。
- **CLI フラグ、IAM ロール、API フィールドの捏造は禁止。** クラウド CLI コマンドを含む出力の前に厳格なファクトチェックが必須。
- **公式 MCP サーバーのみ** — コミュニティ製・サードパーティ製は使用しない。
- **価格にキャッシュへのフォールバックなし。** ライブソースがすべて失敗した場合、スキルは**停止**してギャップを報告。
- **再開可能。** 途中終了しても `.phase-status.json` から再開。

---

## 使いどころ

以下のいずれかが手元にあり、出発点となる具体的な移行計画が欲しいときに使用します:

- AWS(`aws_*`)または Azure(`azurerm_*`)リソースを記述した **Terraform**。
- **CloudFormation / SAM / CDK**(AWS)または **Bicep / ARM**(Azure)のテンプレート。
- `aws-sdk-*`、`boto3`、`@aws-sdk/*`、`aws/aws-sdk-php` のインポートを含む**アプリケーションソース** — 呼び出し箇所ごとの SDK 書き換えパッチが得られます。
- **課金エクスポート** — AWS Cost & Usage Report / Cost Explorer、または Azure FOCUS / 実コストエクスポート。
- Azure 環境では **Azure Migrate / `mcdc`** のアセスメント出力。

典型的なシナリオ:

- クラウドワークロードを引き継ぎ、経営層レビュー向けにコスト算出済みのリプラットフォーム計画が必要。
- GCP での PoC を評価していて、稼働中の IaC から並行デプロイメントを生成したい。
- LLM ワークロードを Bedrock / OpenAI から Agent Platform 上の Gemini へ、あるいは**セルフホストの ADK / LangGraph / CrewAI エージェントを Agent Runtime へ**移行したい。
- 古いレートカードではなく、**ライブの** Cloud Billing Catalog API 価格に基づく月額コスト比較が欲しい。

### 使うべきでないケース

- **オンプレミス → GCP** — 対象外(ソースは AWS と Azure のみ)。
- **GCP → AWS / Azure の逆方向移行** — 対象外。
- **移行の意図を伴わない一般的な GCP アーキテクチャ相談** — [`google/skills`](https://github.com/google/skills) を直接使用してください。
- **同一クラウド内のリファクタリング**(AWS 内、Azure 内)— ツールが違います。
- **Redshift / Synapse 級の分析基盤移行** — `Deferred — specialist engagement` とマークされ、Google Cloud アカウントチームまたはデータ分析移行パートナーへ案内されます。

---

## クイックスタート

Claude Code セッションで次のいずれかを入力します:

- 「migrate from AWS to GCP」/「migrate from Azure to GCP」
- 「AWS migration plan to GCP」
- 「estimate GCP costs」
- 「AWS infrastructure assessment for GCP」

対応するスキルが起動し、プロジェクトをスキャンしてフェーズを案内します。

---

## インストール

詳細な手順(認証設定、検証、トラブルシューティング):[`INSTALL.ja.md`](INSTALL.ja.md)。

### このリポジトリのマーケットプレイスから

```bash
/plugin marketplace add cloud-gtm/gcp-migration-skill
/plugin install migration-to-gcp@migration-skills
```

### ローカル開発

```bash
git clone git@github.com:cloud-gtm/gcp-migration-skill.git
claude --plugin-dir gcp-migration-skill/features/migration-to-gcp
```

---

## 前提条件

- **Node.js** ≥ 18(バンドルされた `gcp-pricing` CLI と Developer Knowledge MCP プロキシの実行に必要)
- **gcloud CLI** がインストール済みで ADC 設定済み:`gcloud auth application-default login` と `gcloud config set project PROJECT_ID`
- そのプロジェクトで **API を有効化**:`gcloud services enable cloudbilling.googleapis.com developerknowledge.googleapis.com`
- **AWS CLI**(AWS 環境)または **Azure CLI**(Azure 環境)が移行元アカウント/サブスクリプションへの読み取りアクセス付きで設定済み
- **Claude Code** ≥ 2.1.119

移行元環境の IaC ファイル、アプリケーションソース、課金エクスポートのうち少なくとも 1 つが必要です。

---

## バンドルされた MCP サーバーとツール

プラグインは**公式 MCP サーバーのみ**を同梱します(設定:`features/migration-to-gcp/.mcp.json`)。

| サーバー                       | URL                                                                                                          | 用途                                                                                   |
| ------------------------------ | ------------------------------------------------------------------------------------------------------------ | -------------------------------------------------------------------------------------- |
| **google-developer-knowledge** | `https://developerknowledge.googleapis.com/mcp`([ドキュメント](https://developers.google.com/knowledge/mcp)) | アーキテクチャ検証・機能確認・価格ページ文脈のための公式 Google Cloud ドキュメント。   |
| **awsknowledge**               | `https://knowledge-mcp.global.api.aws`([awslabs/mcp](https://github.com/awslabs/mcp))                        | 移行元インフラ理解のための AWS ドキュメント。認証不要。                                |
| **microsoft-learn**            | `https://learn.microsoft.com/api/mcp`                                                                        | `azure-to-gcp` スキル向けの Azure 側ドキュメント・サービス機能ルックアップ。認証不要。 |

**Google サーバーの認証**はバンドルされたプロキシ(`scripts/dk-mcp-proxy.mjs`)が担い、優先順位は **gcloud ADC** → gcloud ユーザー認証情報 → **API キーフェイルオーバー**。API キー方式を使う場合は、制限付きキーを作成してプラグイン設定(`google_dev_knowledge_api_key`)に設定します:

```bash
gcloud services api-keys create --display-name="migration-to-gcp" \
  --api-target=service=developerknowledge.googleapis.com \
  --api-target=service=cloudbilling.googleapis.com
```

**`gcp-pricing` CLI** — プラグインはライブ価格ツールも Claude の PATH に配置します(同じ ADC ファースト認証チェーン。フェイルオーバー環境変数 `GCP_PRICING_API_KEY` / `GOOGLE_API_KEY`):

```bash
gcp-pricing services --filter "Cloud Run"          # Cloud Billing サービス ID の解決
gcp-pricing skus --service 152E-C115-5142 \
  --region us-central1 --filter "CPU" --currency USD  # 小数単価付きのライブ SKU レート
```

出力は `retrieved_at`、`auth_mode`、`source_url` 付きの JSON で、見積もり内のすべての価格が監査可能です。

---

## 主要サービスマッピング(aws-to-gcp)

| AWS                                                            | GCP                                    | Terraform プレフィックス               |
| -------------------------------------------------------------- | -------------------------------------- | -------------------------------------- |
| EC2                                                            | Compute Engine                         | `google_compute_*`                     |
| Lambda                                                         | Cloud Run functions / Cloud Run        | `google_cloud_run_v2_*`                |
| ECS Fargate                                                    | Cloud Run                              | `google_cloud_run_v2_*`                |
| EKS                                                            | GKE                                    | `google_container_*`                   |
| S3                                                             | Cloud Storage                          | `google_storage_*`                     |
| RDS(MySQL / Postgres / SQL Server)                             | Cloud SQL                              | `google_sql_*`                         |
| Aurora PostgreSQL                                              | AlloyDB                                | `google_alloydb_*`                     |
| Aurora MySQL                                                   | Cloud SQL MySQL(HA)                    | `google_sql_*`                         |
| DynamoDB                                                       | Firestore / Bigtable                   | `google_firestore_*`                   |
| ElastiCache(Redis)                                             | Memorystore                            | `google_redis_*`                       |
| Redshift                                                       | **Deferred — specialist engagement**   | —                                      |
| SQS / SNS                                                      | Pub/Sub                                | `google_pubsub_*`                      |
| EventBridge                                                    | Eventarc                               | `google_eventarc_*`                    |
| CloudWatch                                                     | Cloud Monitoring / Logging             | `google_monitoring_*`                  |
| Route 53                                                       | Cloud DNS                              | `google_dns_*`                         |
| ALB / NLB                                                      | Cloud Load Balancing                   | `google_compute_*`                     |
| CloudFront                                                     | Cloud CDN                              | `google_compute_*`                     |
| AWS WAF + Shield                                               | Cloud Armor                            | `google_compute_security_*`            |
| Step Functions                                                 | Cloud Workflows                        | `google_workflows_*`                   |
| Kinesis                                                        | Pub/Sub + Dataflow                     | `google_dataflow_*`                    |
| Glue / EMR                                                     | Dataflow / Dataproc                    | `google_dataproc_*`                    |
| ECR                                                            | Artifact Registry                      | `google_artifact_registry_*`           |
| CodePipeline / CodeBuild                                       | Cloud Build + Cloud Deploy             | `google_cloudbuild_*`                  |
| EFS                                                            | Filestore                              | `google_filestore_*`                   |
| Direct Connect                                                 | Cloud Interconnect                     | `google_compute_interconnect_*`        |
| Secrets Manager                                                | Secret Manager                         | `google_secret_manager_*`              |
| KMS                                                            | Cloud KMS                              | `google_kms_*`                         |
| SageMaker                                                      | Agent Platform(GEAP)                   | `google_vertex_ai_*`                   |
| Bedrock                                                        | Agent Platform 上の Gemini             | `google_vertex_ai_*`                   |
| ECS/EC2 上のエージェントフレームワーク(ADK、LangGraph、CrewAI) | Agent Runtime(GEAP)                    | —(agents-cli デプロイ、Terraform なし) |
| Bedrock Agents / AgentCore                                     | Agent Runtime(Google ADK として再構築) | —                                      |
| IAM                                                            | Cloud IAM                              | `google_project_iam_*`                 |

設計ルーブリックの全文は `features/migration-to-gcp/skills/aws-to-gcp/references/design-refs/` に、Azure 版は `features/migration-to-gcp/skills/azure-to-gcp/references/` にあります。

---

## デフォルト

- **リージョン**:`us-central1`(ユーザー指定、または移行元リージョンからのマッピングが別を示す場合を除く)。
- **サイジング**:開発ティア(例:データベースは `db-f1-micro`、Cloud Run は 0.5 vCPU)。ユーザーの指示がある場合のみアップグレード。
- **通貨**:USD。
- **移行モード**:利用可能な入力(インフラ、AI、課金のみ)に応じて適応。
- **人的な一時移行コストは提示しない**:人件費やプロフェッショナルサービスをドル見積もりとして提示することはありません。課金データに基づくベンダー課金(例:データ転送の下り)は許容されます。

---

## テストハーネス

スキルは、実環境のように振る舞う **13 の架空顧客ワークロード**に対して開発されています:

- **`user-journey-tests/aws/`** — 5 ジャーニー:サーバーレスタスク API、3 層 Web、イベント駆動ファンアウト、Fargate AI チャットボット、EKS マイクロサービス。
- **`user-journey-tests/azure/`** — 8 ジャーニー:Windows IaaS リフト、PaaS Web アプリ、AKS マイクロサービス、Durable Functions パイプライン、VMSS + SQL IaaS、ストレージ/メディアパイプライン、Container Apps RAG、ClickOps 部分 IaC。各ジャーニーには現実的なトラップ(アセスメントには載っているが存在しないサーバー、IaC と一致しないライセンス主張、孤児リソースなど)が仕込まれており、答え合わせキーは `CATALOG.md` にあります。
- **`user-journey-tests/gcp-references/`** — AWS ジャーニーの既知の正解となる GCP 移行先。評価対象のエージェントが作業ディレクトリから答えを発見できないよう、意図的にジャーニーディレクトリの外に配置されています。
- **`CATALOG.md`** — 評価の実行方法、ジャーニーごとのトラップ答え合わせキー(`tools/verify-catalog-refs.py` で機械検証)、ライブリファレンス環境のデプロイ状況。
- **`user-journey-tests/CONVENTIONS.md`** — フィクスチャ作成ルール:アーキテクチャパターン命名、sha256 マニフェスト付きの決定論的コストフィクスチャ、答え合わせキーの分離。

---

## 開発

```bash
npx -y dprint@0.51 check                          # フォーマット(markdown + JSON)
npx -y markdownlint-cli2@0.17                     # markdown リント
node tools/validate-manifests.mjs                 # プラグインマニフェスト / MCP 設定の検証
node tools/validate-cross-refs.mjs                # クロスリファレンス検証
python3 tools/verify-catalog-refs.py              # CATALOG 答え合わせキー引用チェッカー
claude plugin validate features/migration-to-gcp  # 助言的警告 1 件:version は意図的に未設定(SHA バージョニング)
features/migration-to-gcp/bin/gcp-pricing services --filter "Cloud Run"   # ライブ価格スモークテスト
```

このリポジトリで作業する AI エージェント向けの規約・注意点・検証ゲートは [`AGENTS.md`](AGENTS.md) を参照してください。

---

## Migration with AI Workshop(TAP)

AWS 移行の検討を AI で加速する — TAP 実事例と Migration Skills の作り方

AWS / Azure から Google Cloud への移行検討は、現状構成の把握・To-Be アーキテクチャー設計・移行方式の検討・IaC 作成など論点が多く、従来は数ヶ月かかっていました。
この検討プロセス全体を AI Agent(Migration Skills)で加速する TAP メニュー「Migration with AI Workshop」を開発・提供し、実顧客事例では通常数週間〜1ヶ月かかる初期検討を、3 日間の TAP で「Google Cloud 上で実際に動く環境の構築」まで前進させ、CSAT 5 を獲得しました。
本セッションでは、
(1) ワークショップの構成(Day 0–3)と実顧客事例、
(2) 構成分析 → 不足情報のヒアリング → 移行設計 → Terraform・移行タスクリスト生成までを Agent Skill としてパッケージ化したハーネス設計
をデモを交えて紹介します
