---
name: aws-to-gcp
description: "Migrate workloads from Amazon Web Services to Google Cloud Platform. Triggers on: migrate from AWS, AWS to GCP, move to Google Cloud, migrate EC2 to GCE, migrate RDS to Cloud SQL, migrate EKS to GKE, migrate S3 to GCS, AWS migration, Amazon to Google Cloud. Runs a 6-phase process: discover AWS resources from Terraform or CloudFormation files, app code, or AWS billing exports, clarify migration requirements, design GCP architecture, estimate costs, generate migration artifacts. Clarify must finish before Design, Estimate, or Generate. Do not use for: Azure or on-premises migrations to GCP, GCP-to-AWS reverse migration, general GCP architecture advice without migration intent, AWS-to-AWS refactoring, or multi-cloud deployments that do not involve migrating off AWS."
---

# AWS-to-GCP Migration Skill

## Philosophy

- **Always research before deciding (MANDATORY for non-deterministic calls)**: For every non-deterministic Design decision, every cost estimate, and every recommended `gcp_config` field, Gemini MUST do a live research pass first — in order: (a) `google-developer-knowledge` MCP, (b) WebSearch, (c) WebFetch on `cloud.google.com/<service>/docs` and `/pricing` pages — and cite what it found (URL + `fetched_at`) in the resource's `rationale` or `pricing.fetched_url`. **Training-data recall is NOT acceptable as the sole basis for a recommendation.** This applies to both **updates** (latest service capabilities, pricing changes, deprecations, new products like Cloud Run Worker Pool CREMA autoscaling) and **patterns** (best-practice config, idiomatic SDK usage, known cost pitfalls, scale-to-zero trade-offs). When research surfaces a newer GCP product that better fits the AWS source than the rubric's default, that newer product takes precedence — the skill is not entitled to recommend a stale option.

- **Surface trade-offs to the user instead of silently picking**: For every non-deterministic mapping where 2+ viable GCP targets exist after research, Gemini MUST present a **trade-off card** populated from its live research (NOT from this file or model recall) and ASK the user which to pick. The card MUST include: option label, cited URL(s), cost shape (per-instance / per-request / always-on / scale-to-zero), cold-start behavior, ops complexity, and dealbreaker conditions. Do not autonomously choose between viable options just because the rubric has a preferred default. Record the user's pick in `preferences.json.design_choices[]` keyed by `aws_address`.

  Trade-off card template (Gemini fills in from research, does NOT copy pre-baked options from this file):
  ```
  Trade-off for <aws_address> (<aws_type>):
  Option A: <gcp_service_label>
    - Source: <cited_url> (fetched <YYYY-MM-DD>)
    - Cost shape: <description>
    - Cold-start: <description>
    - Ops: <description>
    - Dealbreakers: <description>
  Option B: <gcp_service_label>
    ...
  Pick (A/B/...):
  ```

- **Re-platform by default**: Select GCP services that match AWS workload types (e.g., Fargate → Cloud Run, RDS → Cloud SQL, EKS → GKE).
- **Dev sizing unless specified**: Default to development-tier capacity (e.g., db-f1-micro, single zone). Upgrade only on user direction.
- **No human one-time migration costs**: Do not present human labor, professional services, or people-time work as dollar estimates or "one-time migration cost" budget categories. Vendor charges grounded in data (for example AWS data transfer egress in the infra estimate when billing exists) are allowed.
- **Multi-signal approach**: Design phase adapts based on available AWS inputs — Terraform or CloudFormation IaC for infrastructure, AWS billing/cost/usage data for service mapping, and app code for AI workload detection.
- **Redshift / `aws_redshift_*`**: The skill **does not** recommend a specific GCP analytics or warehouse service. During **Clarify**, if discovery shows Redshift (IaC `aws_redshift_*` and/or billing rows for Redshift), you **must** surface the specialist advisory **before** Design (see `references/phases/clarify/clarify.md`). Design output uses **`Deferred — specialist engagement`**; keep directing the user to their **Google Cloud account team** and/or a **data analytics migration partner** through Design, Estimate, and docs (see `references/phases/design/design-infra.md` Redshift specialist gate).

---

## Companion skills (google/skills)

This skill is designed to work **alongside** Google's official [`google/skills`](https://github.com/google/skills) package. When installed, those skills are the **canonical source of truth** for GCP service guidance and you should defer to them during the **Design** and **Generate** phases instead of duplicating their guidance here.

**Install (if missing):** `npx skills add google/skills`

**Resolution protocol (use this for every Design/Generate sub-step that picks or configures a GCP service):**

1. Use the AWS -> GCP -> google/skill mapping table below to find the relevant google/skill name for the GCP target.
2. Attempt to **Read** the skill's `SKILL.md` from these paths, in order. Stop at the first one that exists:
   - `~/.claude/skills/<skill-name>/SKILL.md` (Claude default install path)
   - `~/.agents/skills/<skill-name>/SKILL.md` (agent-neutral install path used by other agent runtimes)
   - `.claude/skills/<skill-name>/SKILL.md` (project-local install)
3. **If a `SKILL.md` is found:** treat its templates, configuration recipes, and best-practice fields as the **primary** source for that GCP service. Use this skill's own `references/design-refs/*.md` only for the AWS -> GCP **decision** rubric (eliminators, signals, 6-criteria scoring). In `gcp-design.json`, set `resources[].rationale` to include the phrase `"sourced from google/skills/<skill-name> SKILL.md"`.
4. **If not found (graceful degradation):** fall back to this skill's `references/design-refs/*.md` as the primary source. Add to `gcp-design.json.warnings`:
   `"google/skills/<skill-name> not installed; used aws-to-gcp fallback rubric. Install with: npx skills add google/skills"`
   Surface the same one-liner in the user-facing Design summary so the user can decide whether to install and re-run.

**Stable language reminder:** Refer to "the latest version of `<skill-name>`". Do not pin a version. google/skills evolves independently.

**AWS -> GCP -> google/skill mapping (canonical):**

| AWS source                                                          | GCP target                                              | google/skill (canonical guidance)                                                |
| ------------------------------------------------------------------- | ------------------------------------------------------- | -------------------------------------------------------------------------------- |
| ECS / Fargate                                                       | Cloud Run                                               | `cloud-run-basics`                                                               |
| Lambda                                                              | Cloud Run functions / Cloud Run service / Cloud Run jobs | `cloud-run-basics`                                                              |
| EKS                                                                 | GKE                                                     | `gke-basics`                                                                     |
| RDS MySQL / PostgreSQL / SQL Server                                 | Cloud SQL                                               | `cloud-sql-basics`                                                               |
| Aurora PostgreSQL                                                   | AlloyDB                                                 | `alloydb-basics`                                                                 |
| Redshift                                                            | **Deferred -- specialist engagement** (do not auto-map) | _Specialist gate applies; `bigquery-basics` is reading material for specialists only._ |
| Cognito / IAM Identity Center / third-party auth (when replaced)    | Firebase Auth or Identity Platform                      | `firebase-basics`, `google-cloud-recipe-auth`                                    |
| ALB / NLB / VPC routing                                             | Cloud Load Balancing / VPC                              | `google-cloud-networking-observability`                                          |
| AWS WAF + Shield                                                    | Cloud Armor                                             | `google-cloud-waf-security`                                                      |
| Bedrock / OpenAI / foundation models                                | Vertex AI Gemini                                        | `gemini-api`, `gemini-interactions-api`                                          |
| First-time-to-GCP onboarding                                        | (cross-cutting)                                         | `google-cloud-recipe-onboarding`                                                 |
| Design-time cost/reliability/security review                        | (cross-cutting)                                         | `google-cloud-waf-cost-optimization`, `google-cloud-waf-reliability`, `google-cloud-waf-security` |

**Cross-cutting skills** (consult once per migration, not per resource) and a full per-skill scope summary live in `references/shared/companion-skills.md`. That file is the single, authoritative version of the table; `design-refs/*.md`, `design-infra.md`, and `generate-artifacts-infra.md` all link to it.

**Resources with no companion skill:** EC2/Compute Engine, DynamoDB, S3/GCS, EFS/Filestore, EBS/PD, messaging (Pub/Sub, Cloud Tasks, Eventarc, Workflows), and traditional ML (Vertex AI Endpoints, Cloud Vision, Document AI) currently have **no** dedicated google/skill. For those, continue to use this skill's own `references/design-refs/*.md` rubrics.

---

## Definitions

- **"Load"** = Read the file using the Read tool and follow its instructions. Do not summarize or skip sections.
- **`$MIGRATION_DIR`** = The run-specific directory under `.migration/` (e.g., `.migration/0226-1430/`). Set during Phase 1 (Discover).

---

## File Output Discipline (CRITICAL)

**All skill-generated files MUST be written under `$MIGRATION_DIR`** (= `.migration/<MMDD-HHMM>/`, established by Discover phase Step 0). FORBIDDEN paths and behaviors:

- Writing `terraform/`, `scripts/`, `README.md`, `MIGRATION_GUIDE.md`, or ANY file at the project root (cwd) — those would overwrite or pollute the source project's files. The user's own `README.md` at the project root MUST NOT be touched.
- Writing Python/Bash helper scripts (e.g. `discover_iac.py`, `map_infrastructure.py`, `gen_summary.py`, `parse_*.py`) anywhere on disk. If you need to parse Terraform/CloudFormation/billing files, use the model's built-in Read, Grep, and Glob tools directly — DO NOT generate a parser script and execute it. The only Generate-phase scripts that are allowed are the user-facing migration shell scripts under `$MIGRATION_DIR/scripts/` (e.g. `01-validate-prerequisites.sh`, `02-migrate-data.sh`).
- Writing outputs to cwd even if cwd happens to be the project root — always resolve `$MIGRATION_DIR` first by reading the migration directory created in Discover Step 0.

Correct paths:

- `$MIGRATION_DIR/terraform/main.tf`, `$MIGRATION_DIR/terraform/compute.tf`, etc.
- `$MIGRATION_DIR/scripts/02-migrate-data.sh`, etc.
- `$MIGRATION_DIR/MIGRATION_GUIDE.md`, `$MIGRATION_DIR/README.md` (the migration run's own README, NOT the source project's README).
- `$MIGRATION_DIR/migration-report.html`.

**Path self-check before EVERY Write call:** If the path you are about to pass to the Write tool does not start with `$MIGRATION_DIR` (or `.migration/<MMDD-HHMM>/`), STOP and rewrite the path. The only files this skill may write outside `$MIGRATION_DIR` are `.migration/.gitignore` (Discover Step 0) and nothing else.

**Pre-Write self-check (BLOCKING — applies to EVERY Write tool call this skill ever makes):**

Before EVERY call to the Write tool, check the path:

1. If path ends in `.py` and you are not generating user-facing Cloud Run / Cloud Functions source code that the user will deploy — **REFUSE**. Use Read/Grep/Glob to parse files instead of writing parser scripts. (Generate-phase exception: a Lambda Zip → Cloud Run translation may need to emit the *user's* Python handler under `$MIGRATION_DIR/cloud-run-source/<service>/main.py` for the user to deploy. That is allowed because it is a deployable artifact, not a helper.)
2. If path is a relative `*.py` or `*.txt` file at the project root (no `$MIGRATION_DIR/` prefix) — **REFUSE**.
3. The ONLY scripts this skill may write are SHELL scripts (`*.sh`) under `$MIGRATION_DIR/scripts/`. Bash is allowed because the user runs these scripts as part of the migration cutover (`01-validate-prerequisites.sh`, `02-migrate-data.sh`, etc.). Python parser scripts are NEVER allowed.
4. **Banned filename patterns (auto-refuse regardless of path):** `build_*.py`, `generate_*.py`, `parse_*.py`, `extract_*.py`, `analyze_*.py`, `discover_*.py`, `map_*.py`, `summarize_*.py`, `inventory_*.py`, `scan_*.py`. If you catch yourself wanting to Write any of these — STOP and use the model's built-in Read / Grep / Glob tools to do the same work in-context. There is NO legitimate reason for this skill to emit a helper Python script: every parsing task can be done by reading the file directly, and every transformation task lives in a `.md` reference file the skill loads.
5. If you have written more than ONE `.py` file in a single Generate run and neither is user-deployable application code, that is a strong signal you are violating this rule. STOP and reconsider — the correct fix is to use Read/Grep/Glob on the source files directly.

Repeat this self-check at the moment you assemble the Write tool call, not in a planning step that gets forgotten — the check binds at call time.

---

## Prerequisites

User must provide at least one AWS source input. **Billing here means source AWS billing/cost/usage data, not GCP billing.**

- **Infrastructure as code**: Terraform (`.tf`, optional `.tfvars`/`.tfstate`) or CloudFormation/SAM/CDK-synthesized templates (`.json`, `.yaml`, `.yml`, `.template` containing `AWSTemplateFormatVersion` or `AWS::` resource declarations)
- **Application code**: Source files with AWS SDK or AI framework imports
- **AWS billing data**: AWS Cost and Usage Report (CUR), Cost Explorer export, or AWS billing/cost/usage CSV/JSON files

If none of the above are found, stop and ask user to provide at least one source type.

---

## State Machine

This is the execution controller. After completing each phase, consult this table to determine the next action.

| Current State   | Condition                        | Next Action                                                                            |
| --------------- | -------------------------------- | -------------------------------------------------------------------------------------- |
| `start`         | always                           | Load `references/phases/discover/discover.md`                                          |
| `discover_done` | always                           | Load `references/phases/clarify/clarify.md`                                            |
| `clarify_done`  | always                           | Load `references/phases/design/design.md`                                              |
| `design_done`   | always                           | Load `references/phases/estimate/estimate.md`                                          |
| `estimate_done` | always                           | Load `references/phases/generate/generate.md`                                          |
| `generate_done` | (any)                            | Migration planning complete                                                            |

**How to determine current state:** On session resume, read `$MIGRATION_DIR/.phase-status.json` -> check `phases` object -> find the last phase with value `"completed"`.

**Phase gate checks**: If prior phase incomplete, do not advance (e.g., cannot enter estimate without completed design).

**Clarify is mandatory:** Do not load `references/phases/design/design.md`, `references/phases/estimate/estimate.md`, or `references/phases/generate/generate.md` unless `$MIGRATION_DIR/.phase-status.json` exists and `phases.clarify` is exactly `"completed"`. A `preferences.json` file alone is **not** sufficient proof that Clarify ran. If the user asks to skip Clarify or jump straight to Design, cost estimate, or artifact generation, refuse briefly, then load `references/phases/clarify/clarify.md` and run Phase 2. There is no exception for "quick" or "obvious" migrations.


---

## State Validation

When reading `$MIGRATION_DIR/.phase-status.json`, validate before proceeding:

1. **Multiple sessions**: If multiple directories exist under `.migration/`, list them with their phase status and ask: [A] Resume latest, [B] Start fresh, [C] Cancel.
2. **Invalid JSON**: If `.phase-status.json` fails to parse, STOP. Output: "State file corrupted (invalid JSON). Delete the file and restart the current phase."
3. **Unrecognized phase**: If `phases` object contains a phase not in {discover, clarify, design, estimate, generate}, STOP. Output: "Unrecognized phase: [value]. Valid phases: discover, clarify, design, estimate, generate."
4. **Unrecognized status**: If any `phases.*` value is not in {pending, in_progress, completed}, STOP. Output: "Unrecognized status: [value]. Valid values: pending, in_progress, completed."

---

## State Management

Migration state lives in `$MIGRATION_DIR` (`.migration/[MMDD-HHMM]/`), created by Phase 1 and persisted across invocations.

**.phase-status.json schema:**

```json
{
  "migration_id": "0226-1430",
  "last_updated": "2026-02-26T15:35:22Z",
  "phases": {
    "discover": "completed",
    "clarify": "completed",
    "design": "in_progress",
    "estimate": "pending",
    "generate": "pending"
  }
}
```

**Status values:** `"pending"` → `"in_progress"` → `"completed"`. Never goes backward.

The `.migration/` directory is automatically protected by a `.gitignore` file created in Phase 1.

### Phase Status Update Protocol

**Do not Read `.phase-status.json` before updating it.** You already know the current state because you are executing phases sequentially. Use the Write tool to write the **complete file** in the same turn as your final phase work (e.g., the output message announcing phase completion).

Example — after completing the Clarify phase, write `$MIGRATION_DIR/.phase-status.json` with:

```json
{
  "migration_id": "MMDD-HHMM",
  "last_updated": "2026-02-26T15:35:22Z",
  "phases": {
    "discover": "completed",
    "clarify": "completed",
    "design": "pending",
    "estimate": "pending",
    "generate": "pending"
  }
}
```

Replace `MMDD-HHMM` with the actual migration ID, generate the `last_updated` ISO 8601 UTC timestamp yourself, and set each phase to its correct status at that point.

**Read `.phase-status.json` ONLY during session resume** (Step 0 of discover.md when checking for existing runs).

---

## Phase Summary Table

| Phase        | Inputs                                                                                                                                                                   | Outputs                                                                                                                                                                                   | Reference                                |
| ------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------- |
| **Discover** | Terraform or CloudFormation files, app source code, and/or AWS billing exports (at least one required)                                                                   | `aws-resource-inventory.json`, `aws-resource-clusters.json`, `ai-workload-profile.json`, `aws-sdk-usage.json` (non-AI SDK call sites), `app-routes.json` (HTTP routing topology — consumed by Generate's user-journey synthesis), `billing-profile.json`, `.phase-status.json` updated (outputs vary by input) | `references/phases/discover/discover.md` |
| **Clarify**  | Discovery artifacts (`aws-resource-inventory.json`, `aws-resource-clusters.json`, `ai-workload-profile.json`, `aws-sdk-usage.json`, `billing-profile.json` — whichever exist) | `preferences.json`, `.phase-status.json` updated                                                                                                                                          | `references/phases/clarify/clarify.md`   |
| **Design**   | `preferences.json` + discovery artifacts                                                                                                                                 | `gcp-design.json` (infra), `gcp-design-ai.json` (AI), `gcp-design-billing.json` (billing-only), `sdk-migration-plan.json` (if `aws-sdk-usage.json` exists)                                | `references/phases/design/design.md`     |
| **Estimate** | `gcp-design.json` or `gcp-design-billing.json` or `gcp-design-ai.json`, `preferences.json`                                                                               | `estimation-infra.json` or `estimation-ai.json` or `estimation-billing.json`, `.phase-status.json` updated                                                                                | `references/phases/estimate/estimate.md` |
| **Generate** | `estimation-infra.json` or `estimation-ai.json` or `estimation-billing.json`, `gcp-design.json` or `gcp-design-billing.json` or `gcp-design-ai.json`, `preferences.json`, `sdk-migration-plan.json` (optional), `app-routes.json` (optional — drives user-journey synthesis) | `generation-infra.json` or `generation-ai.json` or `generation-billing.json` + `terraform/`, `scripts/`, `ai-migration/`, `code-patches/` (if `sdk-migration-plan.json` present), `code-migration-summary.md` (same), `user-journeys/` (per-journey narrative `.md` + Mermaid `.mmd` + parity-test `.sh` + `index.md`, or single-line `user-journeys.md` sentinel when no routes were discovered), `MIGRATION_GUIDE.md`, `README.md`, `.phase-status.json` updated | `references/phases/generate/generate.md` |

---

## MCP Servers

**gcloud** (`@google-cloud/gcloud-mcp`, official Google, npm):

- Provides `run_gcloud_command` tool — runs any gcloud CLI command
- Used for GCP target validation, project/billing-account lookups when available, and infrastructure checks
- Source: https://github.com/googleapis/gcloud-mcp

**google-developer-knowledge** (`https://developerknowledge.googleapis.com/mcp`, official Google):

- Provides `search_documents`, `get_documents`, and `answer_query` tools for Google's official developer documentation
- Use for Google Cloud architecture validation, service capability checks, product lifecycle checks, and current Google Cloud docs before falling back to general web search
- Source/setup: https://developers.google.com/knowledge/mcp

**awsknowledge** (`https://knowledge-mcp.global.api.aws`, official AWS):

- Provides AWS documentation and service reference lookups
- Used during Discover phase for AWS service understanding
- Source: https://github.com/awslabs/mcp

**Pricing**: Live lookup is **MANDATORY** before the cache may be used. Source-of-truth order, mirroring `references/phases/estimate/estimate-infra.md` Step 0: (1) `google-developer-knowledge` MCP (`search_documents`, `get_documents`, `answer_query`) against `cloud.google.com/<service>/pricing`; (2) if the MCP returns no usable data, the model's WebSearch / WebFetch tools (or `curl https://cloud.google.com/<service>/pricing`); (3) **only if BOTH MCP and web search are unavailable**, `references/shared/pricing-cache.md` as a **last resort, must be flagged in output** (`pricing.source = "cached_fallback"` plus a top-level `warnings[]` entry: `"Cost estimate used cached pricing from <cache-date>. Re-run with internet access for accurate numbers."`). Every dollar number in `estimation-infra.json` must carry `pricing.source`, `pricing.fetched_url`, `pricing.fetched_at`, `pricing.sku_rate`, `pricing.assumed_quantity`, and `pricing.calculation` -- model-fabricated rates are forbidden and are a Generate-phase blocker.

---

## Files in This Skill

```
aws-to-gcp/
├── SKILL.md                                    ← You are here (orchestrator + state machine)
│
├── references/
│   ├── phases/
│   │   ├── discover/
│   │   │   ├── discover.md                     # Phase 1: Discover orchestrator
│   │   │   ├── discover-iac.md                 # Terraform/CloudFormation IaC discovery
│   │   │   ├── discover-app-code.md            # App code discovery (AI workload detection)
│   │   │   ├── discover-app-sdk.md             # App code discovery (AWS SDK call-site inventory for source-code rewrite)
│   │   │   └── discover-billing.md             # Billing data discovery
│   │   ├── clarify/
│   │   │   ├── clarify.md                     # Phase 2: Clarify orchestrator
│   │   │   ├── clarify-global.md              # Category A: Global/Strategic (Q1-Q7)
│   │   │   ├── clarify-compute.md             # Categories B+C: Config Gaps + Compute (Q8-Q11)
│   │   │   ├── clarify-database.md            # Category D: Database (Q12-Q13)
│   │   │   ├── clarify-ai.md                  # Category F: AI/Vertex AI (Q14-Q22)
│   │   │   └── clarify-ai-only.md             # Standalone AI-only migration flow
│   │   ├── design/
│   │   │   ├── design.md                       # Phase 3: Design orchestrator
│   │   │   ├── design-infra.md                 # Infrastructure design (IaC-based)
│   │   │   ├── design-ai.md                    # AI workload design (Vertex AI)
│   │   │   └── design-billing.md               # Billing-only design (fallback)
│   │   ├── estimate/
│   │   │   ├── estimate.md                     # Phase 4: Estimate orchestrator
│   │   │   ├── estimate-infra.md               # Infrastructure cost analysis
│   │   │   ├── estimate-ai.md                  # AI workload cost analysis
│   │   │   └── estimate-billing.md             # Billing-only cost analysis
│   │   ├── generate/
│   │   │   ├── generate.md                     # Phase 5: Generate orchestrator
│   │   │   ├── generate-infra.md               # Infrastructure migration plan
│   │   │   ├── generate-ai.md                  # AI migration plan
│   │   │   ├── generate-billing.md             # Billing-only migration plan
│   │   │   ├── generate-artifacts-infra.md     # Terraform configurations
│   │   │   ├── generate-artifacts-scripts.md  # Migration scripts
│   │   │   ├── generate-artifacts-ai.md        # Provider adapter + test harness
│   │   │   ├── generate-artifacts-billing.md   # Skeleton Terraform
│   │   │   ├── generate-artifacts-journeys.md  # User-journey narrative + Mermaid + parity tests (derived from app-routes.json + aws-sdk-usage.json + gcp-design.json)
│   │   │   └── generate-artifacts-docs.md      # MIGRATION_GUIDE.md + README.md
│   │
│   └── design-refs/
│   │   ├── index.md                            # Lookup table: AWS type → design-ref file
│   │   ├── fast-path.md                        # Deterministic 1:1 mappings (Pass 1)
│   │   ├── compute.md                          # Compute mappings (Fargate, EC2, EKS, etc.)
│   │   ├── database.md                         # Database mappings (RDS, DynamoDB, etc.)
│   │   ├── storage.md                          # Storage mappings (S3, EFS, etc.)
│   │   ├── networking.md                       # Networking mappings (VPC, ALB, Route 53, etc.)
│   │   ├── messaging.md                        # Messaging mappings (SNS, SQS, etc.)
│   │   ├── ai.md                               # AI mappings (Bedrock → Vertex AI)
│   │   └── sdk-mapping.md                      # aws-sdk-* → google-cloud-* per-language SDK call-site rewrites (Ruby/Python/JS/TS/Java/Go)
│   │
│   ├── clustering/terraform/
│   │   ├── classification-rules.md             # Primary/secondary classification
│   │   ├── clustering-algorithm.md             # Cluster formation rules
│   │   ├── depth-calculation.md                # Topological depth calculation
│   │   └── typed-edges-strategy.md             # Edge type assignment
│   │
│   └── shared/
│       ├── schema-phase-status.md              # .phase-status.json schema (canonical reference)
│       ├── schema-discover-iac.md              # aws-resource-inventory + clusters schemas (loaded by discover-iac.md)
│       ├── schema-discover-ai.md               # ai-workload-profile schema (loaded by discover-app-code.md)
│       ├── schema-discover-billing.md          # billing-profile schema (loaded by discover-billing.md)
│       ├── schema-estimate-infra.md            # estimation-infra.json schema (loaded by estimate-infra.md at write time)
│       └── pricing-cache.md                    # Cached GCP + source provider pricing (+-5-25%, primary source)
```

| Condition                                                     | Action                                                                                                                                                  |
| ------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------- |
| No AWS sources found (no Terraform/CloudFormation, no app code, no AWS billing data) | Stop. Output: "No AWS sources detected. Provide at least one source type (Terraform files, CloudFormation templates, application code, or AWS billing exports) and try again." |
| `.phase-status.json` missing phase gate                       | Stop. Output: "Cannot enter Phase X: Phase Y-1 not completed. Start from Phase Y or resume Phase Y-1."                                                  |
| Web search unavailable for pricing                            | Display user warning about +-5-25% accuracy. Use `pricing-cache.md`. Add `pricing_source: "cached_fallback"` to the applicable `estimation-*.json` file. |
| User skips questions or says "use all defaults"               | Apply documented defaults from each category file. Phase 2 completes either way.                                                                        |
| `gcp-design.json` missing required clusters                   | Stop Phase 4. Output: "Re-run Phase 3 to generate missing cluster designs."                                                                             |

## Defaults

- **IaC output**: Terraform configurations, migration scripts, AI migration code, and documentation
- **Region**: `us-central1` (unless user specifies, or AWS region → GCP region mapping suggests otherwise)
- **Sizing**: Development tier (e.g., `db-f1-micro` for databases, 0.5 vCPU for Cloud Run)
- **Migration mode**: Adapts based on available inputs (infrastructure, AI, or billing-only)
- **Cost currency**: USD
- **Timeline assumption**: 8-12 weeks total

## Workflow Execution

When invoked, the agent **MUST follow this exact sequence**:

1. **Load phase status on resume only**: If `.migration/*/.phase-status.json` exists, read it to resume or advance the run. If it does not exist, initialize Phase 1 (Discover).

2. **Determine phase to execute**:
   - If status is `in_progress`: Resume that phase (read corresponding reference file)
   - If status is `completed`: Advance to next phase (read next reference file)
   - Phase mapping for advancement:
     - discover (completed) → Execute clarify (read `references/phases/clarify/clarify.md`)
     - clarify (completed) → Execute design (read `references/phases/design/design.md`)
     - design (completed) → Execute estimate (read `references/phases/estimate/estimate.md`)
     - estimate (completed) → Execute generate (read `references/phases/generate/generate.md`)
     - generate (completed) → Migration complete

3. **Read phase reference**: Load the full reference file for the target phase.

4. **Execute ALL steps in order**: Follow every numbered step in the reference file. **Do not skip, optimize, or deviate.**

5. **Validate outputs**: Confirm all required output files exist with correct schema before proceeding.

6. **Update phase status**: Use the Phase Status Update Protocol (Write tool, no Read) in the same turn as the phase's final output message.

7. **Display summary**: Show user what was accomplished, highlight next phase, or confirm migration completion.

**Critical constraint**: Agent must strictly adhere to the reference file's workflow. If unable to complete a step, stop and report the exact step that failed.

User can invoke the skill again to resume from last completed phase.

## Scope Notes

**v1.0 includes:**

- Terraform infrastructure discovery
- App code scanning (AI workload detection)
- App code scanning (non-AI AWS SDK call-site inventory for source-code rewrite — Ruby focus, Python/JS/TS/Java/Go stubbed)
- Billing data import from AWS
- User requirement clarification (adaptive questions by category)
- Multi-path Design (infrastructure, AI workloads, billing-only fallback)
- Per-call-site SDK rewrite planning (`sdk-migration-plan.json` driven by `references/design-refs/sdk-mapping.md`)
- GCP cost estimation (from official pricing pages or cached fallback)
- Migration artifact generation (Terraform, scripts, AI adapters, **source-code unified-diff patches under `code-patches/`**, documentation)
