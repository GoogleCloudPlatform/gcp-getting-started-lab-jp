# Migration Skills Harness — AWS & Azure → Google Cloud

> AI-driven migration assistants that turn a snapshot of your AWS **or Azure** workload — Terraform, CloudFormation / Bicep / ARM, application source, or billing exports — into a reviewed, costed, and ready-to-apply Google Cloud migration plan. Plus the test harness that proves they work.

This repository contains two things:

1. **A [Claude Code](https://code.claude.com/docs) plugin** (`features/migration-to-gcp/`) bundling two migration skills — **`aws-to-gcp`** and **`azure-to-gcp`** — three official knowledge MCP servers (Google Developer Knowledge, AWS Knowledge, Microsoft Learn), and a live GCP pricing CLI (`gcp-pricing`).
2. **A user-journey test harness** (`user-journey-tests/`, `CATALOG.md`, `tools/`) — 13 fictional-customer source workloads (5 AWS, 8 Azure) with known-good GCP reference implementations and machine-checked answer keys, used to evaluate that the skills discover, design, and price real estates correctly.

---

## What's in this repository

```text
migration-skills-harness/
├── .claude-plugin/marketplace.json       # Marketplace catalog pointing at the plugin below
├── .agents/skills/                       # Vendored google-agents-cli skill suite (deploy, publish,
│                                         #   adk-code, eval, observability, scaffold, workflow) —
│                                         #   pinned by skills-lock.json; the aws-to-gcp agent rubric
│                                         #   cites these as the canonical GCP-side guidance
├── features/
│   └── migration-to-gcp/                 # The Claude Code plugin
│       ├── .claude-plugin/plugin.json    # Plugin manifest (+ userConfig for the API-key failover)
│       ├── .mcp.json                     # Bundled MCP servers (awsknowledge, google-developer-knowledge, microsoft-learn)
│       ├── bin/gcp-pricing               # Live GCP pricing CLI (on PATH while plugin is enabled)
│       ├── scripts/                      # ADC-injecting MCP proxy + pricing CLI + shared auth chain
│       └── skills/
│           ├── aws-to-gcp/               # AWS → GCP skill (SKILL.md + phase/design references + evals)
│           └── azure-to-gcp/             # Azure → GCP skill (same 5-phase machine, Azure-side discovery + gates)
├── CATALOG.md                            # Journey catalog: evaluation instructions, trap answer keys,
│                                         #   deployment status of live reference environments
├── user-journey-tests/
│   ├── CONVENTIONS.md                    # Fixture authoring rules (naming, determinism, answer-key separation)
│   ├── aws/j1-…j5-<pattern>/             # AWS source workloads (serverless API, three-tier web, event fan-out,
│   │                                     #   Fargate AI chatbot, EKS microservices)
│   ├── azure/j1-…j8-<pattern>/           # Azure source workloads (Windows IaaS, PaaS web, AKS, Durable Functions,
│   │                                     #   VMSS+SQL, storage/media, Container Apps RAG, ClickOps partial-IaC)
│   └── gcp-references/<vendor>/…         # Known-good migration targets (answer keys) — deliberately outside
│                                         #   the journey dirs so agents under test cannot find them
├── tools/                                # Validators: manifests, cross-refs, CATALOG citation checker
├── INSTALL.md / INSTALL.ja.md            # Step-by-step install, auth setup, troubleshooting
└── README.ja.md                          # This document in Japanese
```

---

## The migration skills

Both skills drive Claude Code through the same **deterministic, multi-phase workflow** that mirrors how a senior cloud architect assesses and plans a real move to Google Cloud:

```text
Discover → Clarify → Design → Estimate → Generate
```

Each phase has a hard gate: the agent **cannot** skip ahead. Clarify must finish before Design, Design before Estimate, and so on — enforced by `.migration/<run-id>/.phase-status.json`, written after every phase. The result is a reproducible, resumable run instead of a one-shot prompt that hallucinates a plan.

What the agent actually does behind those phases:

- **Reads your sources directly** — Terraform, CloudFormation / SAM / CDK (AWS) or Bicep / ARM templates (Azure), application source for SDK call sites, and billing exports — using the model's built-in `Read` / `Grep` / `Glob` tools. No parser scripts are emitted.
- **Runs live research before every non-deterministic decision** — pricing, service capabilities, lifecycle stage, latest GCP product fit — through the bundled `gcp-pricing` CLI, the knowledge MCP servers, and `WebFetch` on official docs. Training-data recall is explicitly **not allowed** for cost figures or service recommendations.
- **Asks before guessing** — discovery ambiguities, migration intent (cutover / PoC clone / hybrid), cross-cloud connections, and any 2+ viable GCP target choice are surfaced as multiple-choice questions, not silently resolved.
- **Defers what it shouldn't auto-map** — Redshift and Synapse-class analytics platforms are always marked `Deferred — specialist engagement`: a sound BigQuery / Dataflow / Dataproc target requires a specialist conversation with your Google Cloud account team or a data analytics partner.

### The phases

| # | Phase        | What it does                                                                                                                                                                                                                                                             | Key outputs                                                                                                                                        |
| - | ------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1 | **Discover** | Scans the project for IaC, application source, and billing data. Classifies and clusters resources, detects AI **and agent-framework** workloads, inventories SDK call sites, extracts HTTP routing maps.                                                                | `*-resource-inventory.json`, `*-resource-clusters.json`, `ai-workload-profile.json`, `*-sdk-usage.json`, `app-routes.json`, `billing-profile.json` |
| 2 | **Clarify**  | Adaptive questions across global, config-gap, compute, database, AI, logging, and sizing categories. Requires an explicit migration-intent choice and confirmation of every cross-cloud connection it plans to recommend.                                                | `preferences.json`                                                                                                                                 |
| 3 | **Design**   | Maps every source resource to its GCP counterpart with a confidence score and cited rationale. Defers to installed [`google/skills`](https://github.com/google/skills) when present; falls back to the internal rubrics. Presents trade-off cards for 2+ viable targets. | `gcp-design.json`, `gcp-design-ai.json`, `gcp-design-billing.json`, `sdk-migration-plan.json`                                                      |
| 4 | **Estimate** | Prices every mapped service with **live** Cloud Billing Catalog SKU rates via the bundled `gcp-pricing` CLI; three-tier monthly projection compared against current source-cloud spend. Every dollar carries full provenance. No model-recalled prices.                  | `estimation-infra.json`, `estimation-ai.json`, `estimation-billing.json`                                                                           |
| 5 | **Generate** | Translates the frozen design into deployable artifacts: modular Terraform, data-migration scripts, AI provider adapters, per-call-site source patches, agent-redeploy runbook, user-journey parity tests, ADRs, and `MIGRATION_GUIDE.md`.                                | `terraform/`, `scripts/`, `code-patches/`, `ai-migration/`, `user-journeys/`, `adrs/`, `MIGRATION_GUIDE.md`, `README.md`, `migration-report.html`  |

Every artifact is written into a **run-scoped directory** `.migration/<MMDD-HHMM>/`; the source project's own files are never touched — enforced by a path self-check before every `Write`.

### aws-to-gcp highlights

- **Agent workloads land on Agent Runtime.** Google ADK, LangGraph, CrewAI, and Bedrock Agents / AgentCore workloads detected in the estate are placed on **Agent Runtime on the Gemini Enterprise Agent Platform** (GEAP; formerly Vertex AI Agent Engine) by default — deployed via `agents-cli`, with managed Sessions replacing self-managed session stores. The rubric maps the estate's surrounding controls to GCP's agent-governance suite (Agent Registry, Agent Gateway, Agent Identity, Model Armor) per `design-refs/agent-governance.md`.
- **AI workload migration** — Bedrock / OpenAI usage maps to Gemini on the Agent Platform with per-model capability mapping, live price comparison, and per-call-site rewrite patches. Model recommendations are verified by live serving tests at design time, never recalled.
- **Language coverage** — Python, JavaScript/TypeScript, Go, Java, and **PHP** (`aws/aws-sdk-php`) estates, including PHP-specific support boundaries (official `google/*` packages only; explicit warnings where no official PHP surface exists).

### azure-to-gcp highlights

- **Azure-side discovery** — Terraform `azurerm`, Bicep, and ARM templates, application source, and Azure cost exports (FOCUS or actual-cost), alongside Azure Migrate / `mcdc` assessment output.
- **Seven advisory-and-deferral gates** fire in Clarify: identity adjacency (Entra ID federation — never IdP migration), Microsoft licensing (Azure Hybrid Benefit does not travel; Google is a Listed Provider), analytics-platform deferral (Synapse, Fabric, Databricks, …), per-VM M2VM eligibility, Cosmos DB re-platform cards by API flavor, live-Azure sizing consent (never headless), and out-of-scope refusal.
- Same artifact shapes, gates, and pricing-provenance rules as the AWS skill.

### Safeguards built into both skills

- **Live research is mandatory** for any non-deterministic decision. Every recommendation carries a citation (URL + `fetched_at`); recall from training data is explicitly forbidden.
- **Hard phase gates** prevent the agent from jumping straight to Generate.
- **Design is frozen at Generate-time.** Generate must emit artifacts that match Design — never silently override it; re-running Design is the only legitimate path to change a decision.
- **No fabricated CLI flags, IAM roles, or API fields.** A strict factcheck pass is required before any output containing cloud CLI commands is shown.
- **Only official MCP servers** — no community or third-party servers.
- **Pricing has no cache fallback.** If all live sources fail for a service, the skill **stops** and reports the gap rather than emit a fabricated number.
- **Resumable.** Kill the agent mid-run and re-invoke; it resumes from the last completed phase.

---

## When to use it

Use it when you have at least one of these in hand and want a concrete migration plan to start from:

- **Terraform** describing AWS (`aws_*`) or Azure (`azurerm_*`) resources.
- **CloudFormation / SAM / CDK-synthesized** templates (AWS) or **Bicep / ARM** templates (Azure).
- **Application source** with `aws-sdk-*`, `boto3`, `@aws-sdk/*`, or `aws/aws-sdk-php` imports — gets you per-call-site SDK rewrite patches.
- **Billing exports** — AWS Cost & Usage Report / Cost Explorer, or Azure FOCUS / actual-cost exports.
- **Azure Migrate / `mcdc`** assessment output for Azure estates.

Typical scenarios:

- You inherited a cloud workload and need a costed re-platform plan for a leadership review.
- You're evaluating a PoC on GCP and need a parallel deployment generated from live IaC.
- You're migrating LLM workloads from Bedrock / OpenAI to Gemini on the Gemini Enterprise Agent Platform, or **self-hosted ADK / LangGraph / CrewAI agents to Agent Runtime**, and want the runbook and rewrite patches.
- You want a defensible monthly-cost comparison based on **live** Cloud Billing Catalog API prices, not stale rate cards.

### When NOT to use it

- **On-prem → GCP** — out of scope (AWS and Azure sources only).
- **GCP → AWS / Azure reverse migration** — out of scope.
- **General GCP architecture advice without migration intent** — use the underlying [`google/skills`](https://github.com/google/skills) directly.
- **Intra-cloud refactoring** (AWS-to-AWS, Azure-to-Azure) — wrong tool.
- **Redshift / Synapse-class analytics migration** — marked `Deferred — specialist engagement`; you're directed to your Google Cloud account team or a data analytics migration partner.

---

## Quick start

Say one of the following in your Claude Code session:

- "migrate from AWS to GCP" / "migrate from Azure to GCP"
- "AWS migration plan to GCP"
- "estimate GCP costs"
- "AWS infrastructure assessment for GCP"

The matching skill activates, scans your project, and walks you through the phases.

---

## Installation

Full step-by-step guide (auth setup, verification, troubleshooting): [`INSTALL.md`](INSTALL.md).

### From this repo's marketplace

```bash
/plugin marketplace add cloud-gtm/gcp-migration-skill
/plugin install migration-to-gcp@migration-skills
```

### Local development

```bash
git clone git@github.com:cloud-gtm/gcp-migration-skill.git
claude --plugin-dir gcp-migration-skill/features/migration-to-gcp
```

---

## Prerequisites

- **Node.js** ≥ 18 (runs the bundled `gcp-pricing` CLI and the Developer Knowledge MCP proxy)
- **gcloud CLI** installed, with ADC configured: `gcloud auth application-default login` and `gcloud config set project PROJECT_ID`
- **APIs enabled** on that project: `gcloud services enable cloudbilling.googleapis.com developerknowledge.googleapis.com`
- **AWS CLI** (AWS estates) or **Azure CLI** (Azure estates) configured with read access to the source account/subscription
- **Claude Code** ≥ 2.1.119

At least one of: IaC files, application source, or billing exports for the source estate.

---

## Bundled MCP servers and tools

The plugin ships **only official MCP servers** — no community or third-party servers. All register automatically when the plugin is enabled (config: `features/migration-to-gcp/.mcp.json`).

| Server                         | URL                                                                                                   | Purpose                                                                                              |
| ------------------------------ | ----------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------- |
| **google-developer-knowledge** | `https://developerknowledge.googleapis.com/mcp` ([docs](https://developers.google.com/knowledge/mcp)) | Official Google Cloud docs for architecture validation, capability checks, and pricing-page context. |
| **awsknowledge**               | `https://knowledge-mcp.global.api.aws` ([awslabs/mcp](https://github.com/awslabs/mcp))                | AWS documentation and service reference for understanding source infrastructure. No auth.            |
| **microsoft-learn**            | `https://learn.microsoft.com/api/mcp`                                                                 | Azure-side documentation and service-capability lookups for the `azure-to-gcp` skill. No auth.       |

**Auth for the Google server** is handled by a bundled proxy (`scripts/dk-mcp-proxy.mjs`) with this priority: **gcloud ADC** → gcloud user credentials → **API key failover**. ADC needs the Developer Knowledge API enabled on your quota project. If you prefer the API key path, create a restricted key and set it in the plugin config when prompted (`google_dev_knowledge_api_key`):

```bash
gcloud services api-keys create --display-name="migration-to-gcp" \
  --api-target=service=developerknowledge.googleapis.com \
  --api-target=service=cloudbilling.googleapis.com
```

**`gcp-pricing` CLI** — the plugin also puts a live pricing tool on Claude's PATH (same ADC-first auth chain; failover env vars `GCP_PRICING_API_KEY` / `GOOGLE_API_KEY`):

```bash
gcp-pricing services --filter "Cloud Run"          # resolve Cloud Billing service IDs
gcp-pricing skus --service 152E-C115-5142 \
  --region us-central1 --filter "CPU" --currency USD  # live SKU rates with decimal unit prices
```

Output is JSON with `retrieved_at`, `auth_mode`, and `source_url` so every price in an estimate is auditable.

---

## Key service mappings (aws-to-gcp)

| AWS                                                  | GCP                                   | Terraform prefix                    |
| ---------------------------------------------------- | ------------------------------------- | ----------------------------------- |
| EC2                                                  | Compute Engine                        | `google_compute_*`                  |
| Lambda                                               | Cloud Run functions / Cloud Run       | `google_cloud_run_v2_*`             |
| ECS Fargate                                          | Cloud Run                             | `google_cloud_run_v2_*`             |
| EKS                                                  | GKE                                   | `google_container_*`                |
| S3                                                   | Cloud Storage                         | `google_storage_*`                  |
| RDS (MySQL / Postgres / SQL Server)                  | Cloud SQL                             | `google_sql_*`                      |
| Aurora PostgreSQL                                    | AlloyDB                               | `google_alloydb_*`                  |
| Aurora MySQL                                         | Cloud SQL MySQL (HA)                  | `google_sql_*`                      |
| DynamoDB                                             | Firestore / Bigtable                  | `google_firestore_*`                |
| ElastiCache (Redis)                                  | Memorystore                           | `google_redis_*`                    |
| Redshift                                             | **Deferred — specialist engagement**  | —                                   |
| SQS / SNS                                            | Pub/Sub                               | `google_pubsub_*`                   |
| EventBridge                                          | Eventarc                              | `google_eventarc_*`                 |
| CloudWatch                                           | Cloud Monitoring / Logging            | `google_monitoring_*`               |
| Route 53                                             | Cloud DNS                             | `google_dns_*`                      |
| ALB / NLB                                            | Cloud Load Balancing                  | `google_compute_*`                  |
| CloudFront                                           | Cloud CDN                             | `google_compute_*`                  |
| AWS WAF + Shield                                     | Cloud Armor                           | `google_compute_security_*`         |
| Step Functions                                       | Cloud Workflows                       | `google_workflows_*`                |
| Kinesis                                              | Pub/Sub + Dataflow                    | `google_dataflow_*`                 |
| Glue / EMR                                           | Dataflow / Dataproc                   | `google_dataproc_*`                 |
| ECR                                                  | Artifact Registry                     | `google_artifact_registry_*`        |
| CodePipeline / CodeBuild                             | Cloud Build + Cloud Deploy            | `google_cloudbuild_*`               |
| EFS                                                  | Filestore                             | `google_filestore_*`                |
| Direct Connect                                       | Cloud Interconnect                    | `google_compute_interconnect_*`     |
| Secrets Manager                                      | Secret Manager                        | `google_secret_manager_*`           |
| KMS                                                  | Cloud KMS                             | `google_kms_*`                      |
| SageMaker                                            | Agent Platform (GEAP)                 | `google_vertex_ai_*`                |
| Bedrock                                              | Gemini on Agent Platform              | `google_vertex_ai_*`                |
| Agent frameworks on ECS/EC2 (ADK, LangGraph, CrewAI) | Agent Runtime (GEAP)                  | — (agents-cli deploy, no Terraform) |
| Bedrock Agents / AgentCore                           | Agent Runtime (rebuild as Google ADK) | —                                   |
| IAM                                                  | Cloud IAM                             | `google_project_iam_*`              |

Full design rubrics live under `features/migration-to-gcp/skills/aws-to-gcp/references/design-refs/`; the Azure equivalents under `features/migration-to-gcp/skills/azure-to-gcp/references/`.

---

## Defaults

- **Region**: `us-central1` (unless the user specifies, or the source-region → GCP-region mapping suggests otherwise).
- **Sizing**: Development tier (e.g. `db-f1-micro` for databases, 0.5 vCPU for Cloud Run). Upgrade only on user direction.
- **Cost currency**: USD.
- **Migration mode**: Adapts based on available inputs (infrastructure, AI, or billing-only).
- **No human one-time migration costs**: The skill never presents human labor or professional services as dollar estimates. Vendor charges grounded in billing data (e.g. data-transfer egress) are allowed.

---

## The test harness

The skills are developed against **13 fictional-customer workloads** that behave like real estates:

- **`user-journey-tests/aws/`** — 5 journeys: serverless task API, three-tier web, event-driven fan-out, Fargate AI chatbot, EKS microservices.
- **`user-journey-tests/azure/`** — 8 journeys: Windows IaaS lift, PaaS web app, AKS microservices, Durable Functions pipeline, VMSS + SQL IaaS, storage/media pipeline, Container Apps RAG, ClickOps partial-IaC — each seeded with realistic traps (assessed-but-absent servers, licensing claims that don't match IaC, orphaned resources) whose answer keys live in `CATALOG.md`.
- **`user-journey-tests/gcp-references/`** — hand-made, known-good GCP migration targets for the AWS journeys; deliberately kept outside the journey directories so an agent under evaluation cannot discover the answers from its working directory.
- **`CATALOG.md`** — how to run an evaluation, per-journey trap answer keys (machine-checked by `tools/verify-catalog-refs.py`), and the deployment status of live reference environments.
- **`user-journey-tests/CONVENTIONS.md`** — fixture authoring rules: architecture-pattern naming, deterministic cost fixtures with sha256 manifests, answer-key separation.

---

## Development

```bash
npx -y dprint@0.51 check                          # formatting (markdown + JSON)
npx -y markdownlint-cli2@0.17                     # markdown lint
node tools/validate-manifests.mjs                 # plugin manifest / MCP config validation
node tools/validate-cross-refs.mjs                # cross-reference validation
python3 tools/verify-catalog-refs.py              # CATALOG answer-key citation checker
claude plugin validate features/migration-to-gcp  # one advisory warning: version intentionally unset (SHA-versioned)
features/migration-to-gcp/bin/gcp-pricing services --filter "Cloud Run"   # live pricing smoke test
```

See [`AGENTS.md`](AGENTS.md) for the conventions, gotchas, and verification gates that apply to AI agents working in this repo.

---

## Migration with AI Workshop (TAP)

AWS 移行の検討を AI で加速する — TAP 実事例と Migration Skills の作り方

AWS / Azure から Google Cloud への移行検討は、現状構成の把握・To-Be アーキテクチャー設計・移行方式の検討・IaC 作成など論点が多く、従来は数ヶ月かかっていました。
この検討プロセス全体を AI Agent(Migration Skills)で加速する TAP メニュー「Migration with AI Workshop」を開発・提供し、実顧客事例では通常数週間〜1ヶ月かかる初期検討を、3 日間の TAP で「Google Cloud 上で実際に動く環境の構築」まで前進させ、CSAT 5 を獲得しました。
本セッションでは、
(1) ワークショップの構成(Day 0–3)と実顧客事例、
(2) 構成分析 → 不足情報のヒアリング → 移行設計 → Terraform・移行タスクリスト生成までを Agent Skill としてパッケージ化したハーネス設計
をデモを交えて紹介します
