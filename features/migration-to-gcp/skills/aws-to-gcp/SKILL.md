---
name: aws-to-gcp
description: "Migrate workloads from Amazon Web Services to Google Cloud Platform. Triggers on: migrate from AWS, AWS to GCP, move off AWS to Google Cloud, migrate EC2 to GCE, migrate RDS to Cloud SQL, migrate EKS to GKE, migrate S3 to GCS, AWS migration, Amazon to Google Cloud. Runs a 5-phase process: discover AWS resources from Terraform or CloudFormation files, app code, or AWS billing exports, clarify migration requirements, design GCP architecture, estimate costs, generate migration artifacts. Clarify must finish before Design, Estimate, or Generate. Do not use for: Azure sources (use azure-to-gcp), on-premises migrations to GCP, GCP-to-AWS reverse migration, general GCP architecture advice without migration intent, AWS-to-AWS refactoring, or multi-cloud deployments that do not involve migrating off AWS."
---

# AWS-to-GCP Migration Skill

## Philosophy

- **Always research before deciding (MANDATORY for non-deterministic calls)**: For every non-deterministic Design decision, every cost estimate, and every recommended `gcp_config` field, you MUST do a live research pass first — in order: (a) `google-developer-knowledge` MCP, (b) WebSearch, (c) WebFetch on `cloud.google.com/<service>/docs` and `/pricing` pages — and cite what it found (URL + `fetched_at`) in the resource's `rationale` or `pricing.fetched_url`. **Training-data recall is NOT acceptable as the sole basis for a recommendation.** This applies to both **updates** (latest service capabilities, pricing changes, deprecations, new products like Cloud Run Worker Pool CREMA autoscaling) and **patterns** (best-practice config, idiomatic SDK usage, known cost pitfalls, scale-to-zero trade-offs). When research surfaces a newer GCP product that better fits the AWS source than the rubric's default, that newer product takes precedence — the skill is not entitled to recommend a stale option.

- **Surface trade-offs to the user instead of silently picking**: For every non-deterministic mapping where 2+ viable GCP targets exist after research, you MUST present a **trade-off card** populated from your live research (NOT from this file or model recall) and ASK the user which to pick. The card MUST include: option label, cited URL(s), cost shape (per-instance / per-request / always-on / scale-to-zero), cold-start behavior, ops complexity, and dealbreaker conditions. Do not autonomously choose between viable options just because the rubric has a preferred default. Record the user's pick in `preferences.json.design_choices[]` keyed by `aws_address`.

  Trade-off card template (fill it in from research, do NOT copy pre-baked options from this file):
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

1. Use the canonical AWS -> GCP -> google/skill mapping table in `references/shared/companion-skills.md` to find the relevant google/skill name for the GCP target.
2. Attempt to **Read** the skill's `SKILL.md` from these paths, in order. Stop at the first one that exists:
   - `~/.claude/skills/<skill-name>/SKILL.md` (Claude default install path)
   - `~/.agents/skills/<skill-name>/SKILL.md` (agent-neutral install path used by other agent runtimes)
   - `.claude/skills/<skill-name>/SKILL.md` (project-local install)
3. **If a `SKILL.md` is found:** treat its templates, configuration recipes, and best-practice fields as the **primary** source for that GCP service. Use this skill's own `references/design-refs/*.md` only for the AWS -> GCP **decision** rubric (eliminators, signals, 6-criteria scoring). In `gcp-design.json`, set `resources[].rationale` to include the phrase `"sourced from google/skills/<skill-name> SKILL.md"`.
4. **If not found (graceful degradation):** fall back to this skill's `references/design-refs/*.md` as the primary source. Add to `gcp-design.json.warnings`:
   `"google/skills/<skill-name> not installed; used aws-to-gcp fallback rubric. Install with: npx skills add google/skills"`
   Surface the same one-liner in the user-facing Design summary so the user can decide whether to install and re-run.

**Stable language reminder:** Refer to "the latest version of `<skill-name>`". Do not pin a version. google/skills evolves independently.

**AWS -> GCP -> google/skill mapping:** the single canonical table lives in `references/shared/companion-skills.md` (Design/Generate load it via the resolution protocol above; `design-refs/index.md` carries a per-resource-type google/skill column). Do not duplicate the table here or anywhere else — earlier duplicated copies drifted (e.g. the Cognito row). That file also defines cross-cutting skills (consult once per migration: `google-cloud-recipe-onboarding`, the `google-cloud-waf-*` reviews) and lists targets with **no** dedicated google/skill (Compute Engine, GCS, Filestore, disks, messaging, traditional ML) — for those, use this skill's own `references/design-refs/*.md` rubrics. A second family — Google's agent skills (`google-agents-cli-*`, installed via `uv tool install google-agents-cli`, not via `npx skills add`) — is registered in the same file for agent workloads.

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

1. If path ends in `.py` and you are not generating user-facing Cloud Run / Cloud Functions source code that the user will deploy — **REFUSE** (sole exception: `$MIGRATION_DIR/_extract_billing.*`, rule 4). Use Read/Grep/Glob to parse files instead of writing parser scripts. (Generate-phase exception: a Lambda Zip → Cloud Run translation may need to emit the _user's_ Python handler under `$MIGRATION_DIR/cloud-run-source/<service>/main.py` for the user to deploy. That is allowed because it is a deployable artifact, not a helper.)
2. If path is a relative `*.py` or `*.txt` file at the project root (no `$MIGRATION_DIR/` prefix) — **REFUSE**.
3. The ONLY scripts this skill may write are SHELL scripts (`*.sh`) under `$MIGRATION_DIR/scripts/`. Bash is allowed because the user runs these scripts as part of the migration cutover (`01-validate-prerequisites.sh`, `02-migrate-data.sh`, etc.). Python parser scripts are NEVER allowed — with the single sanctioned `_extract_billing.*` exception defined in rule 4.
4. **Banned filename patterns (auto-refuse regardless of path):** `build_*.py`, `generate_*.py`, `parse_*.py`, `extract_*.py`, `analyze_*.py`, `discover_*.py`, `map_*.py`, `summarize_*.py`, `inventory_*.py`, `scan_*.py` — including underscore-prefixed variants of the same stems. If you catch yourself wanting to Write any of these — STOP and use the model's built-in Read / Grep / Glob tools to do the same work in-context. **The SINGLE sanctioned exception:** `$MIGRATION_DIR/_extract_billing.py` (or `.js`/`.sh`) written by Discover's lightweight billing extraction (discover.md), which exists to keep multi-MB raw billing files out of context and MUST be deleted after its one run. Every other helper script remains banned: parsing tasks read the file directly, and transformation logic lives in the `.md` reference files.
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

## Headless / Unattended Runs (Interaction Contract)

When no interactive user can answer (headless drivers like `claude -p`, CI pipelines, or any run where a question would block forever), the skill MUST NOT stall waiting for input — stalled interactive prompts killed harness iterations 3, 8, and 12. Every interaction point has a defined headless disposition. Whenever one is applied, record it in `preferences.json` with `chosen_by: "headless-default"` and echo ALL applied dispositions in a **"Headless assumptions"** block in the Clarify summary and `MIGRATION_GUIDE.md`.

| Interaction point                                               | Headless disposition                                                                                                                                       |
| --------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Q_SIZING1 (sizing data source)                                  | (D) `conservative_defaults`, with the loud banner defined in `clarify-sizing.md`                                                                           |
| Q_INTENT (Step 1.4)                                             | `cutover`, recorded as an assumption                                                                                                                       |
| Step 1.45 cross-cloud connection confirmations                  | N (no connection) per connection, listed as assumptions                                                                                                    |
| Section 0 discovery ambiguities                                 | `Deferred — specialist engagement` (existing rule — never guess)                                                                                           |
| Category A–H questions                                          | The documented per-question defaults (same as "use all defaults")                                                                                          |
| Resume choice [A/B/C]                                           | [A] Resume latest                                                                                                                                          |
| CloudWatch Path-A pre-flight consent                            | Consent CANNOT be assumed headlessly — never read the user's AWS account without explicit confirmation; fall back to (D) conservative defaults with banner |
| Pricing-failure menu (fix / exclude / manual rate)              | (ii) exclude the service from totals + report the failure. NEVER fabricate a rate                                                                          |
| Agent-placement trade-off card (`design-refs/agent-runtime.md`) | Agent Runtime (the documented default), recorded with `chosen_by: "headless-default"`                                                                      |

Headless mode never upgrades to riskier behavior than an interactive session would take — it only substitutes documented, conservative, clearly-labeled defaults for questions.

## State Machine

This is the execution controller. After completing each phase, consult this table to determine the next action.

| Current State   | Condition | Next Action                                   |
| --------------- | --------- | --------------------------------------------- |
| `start`         | always    | Load `references/phases/discover/discover.md` |
| `discover_done` | always    | Load `references/phases/clarify/clarify.md`   |
| `clarify_done`  | always    | Load `references/phases/design/design.md`     |
| `design_done`   | always    | Load `references/phases/estimate/estimate.md` |
| `estimate_done` | always    | Load `references/phases/generate/generate.md` |
| `generate_done` | (any)     | Migration planning complete                   |

**How to determine current state:** On session resume, read `$MIGRATION_DIR/.phase-status.json` -> check `phases` object -> find the last phase with value `"completed"`.

**Phase gate checks**: If prior phase incomplete, do not advance (e.g., cannot enter estimate without completed design).

**Clarify is mandatory:** Do not load `references/phases/design/design.md`, `references/phases/estimate/estimate.md`, or `references/phases/generate/generate.md` unless `$MIGRATION_DIR/.phase-status.json` exists and `phases.clarify` is exactly `"completed"`. A `preferences.json` file alone is **not** sufficient proof that Clarify ran. If the user asks to skip Clarify or jump straight to Design, cost estimate, or artifact generation, refuse briefly, then load `references/phases/clarify/clarify.md` and run Phase 2. There is no exception for "quick" or "obvious" migrations.

---

## State Validation

When reading `$MIGRATION_DIR/.phase-status.json`, validate before proceeding:

1. **Multiple sessions**: If multiple directories exist under `.migration/`, list them with their phase status and ask: [A] Resume latest, [B] Start fresh, [C] Cancel.
2. **Invalid JSON**: If `.phase-status.json` fails to parse, STOP. Output: "State file corrupted (invalid JSON). Delete the file and restart the current phase."
3. **Unrecognized phase**: If `phases` object contains a phase not in {discover, clarify, design, estimate, generate}, STOP. Output: "Unrecognized phase: [value]. Valid phases: discover, clarify, design, estimate, generate."
4. **Unrecognized status**: If any `phases.*` value is not in {pending, in_progress, completed, failed}, STOP. Output: "Unrecognized status: [value]. Valid values: pending, in_progress, completed, failed."
5. **Failed phase**: If a phase's value is `"failed"` (e.g. Generate dropped a MANDATORY artifact), that is a legal, resumable state — do NOT treat it as corruption. On resume, re-enter that phase from its reference file; its sub-files checkpoint per artifact and pick up from missing outputs. Report to the user which phase failed and why (see `generation-validation.json` for Generate failures) before re-entering.

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

**Status values:** `"pending"` → `"in_progress"` → `"completed"`. A phase may instead end at `"failed"` (incomplete MANDATORY output — see generate.md's budget rules); `"failed"` → `"in_progress"` on re-entry is the only allowed backward transition.

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

### Run Validation Ledger, Write Audit, and Degradation Reporting

Three run-wide protocols every phase follows (harness history: gates that leave a written trace stick; prose-only rules were reliably bypassed):

1. **Validation ledger** — `$MIGRATION_DIR/validation-ledger.json`, an array of `{"phase", "gate", "result": "pass"|"fail"|"corrected"|"skipped", "evidence", "at"}`. Each phase appends one entry per BLOCKING gate it ran (Discover: enumeration/ambiguity counts; Clarify: defaults + headless dispositions applied; Design: engine-fidelity self-check; Estimate: pricing-attempt summary; Generate: gate results — `generation-validation.json` remains Generate's detailed per-file audit, the ledger is the run-level roll-up). Same Write-complete-file protocol as `.phase-status.json`. Every phase-completion summary MUST surface any `fail`/`corrected` entries to the user.
2. **Post-phase write audit (mechanical backstop for File Output Discipline)** — at each phase completion, enumerate the files written during the phase (e.g. `git status --porcelain` when the project is a repo, else the tracked write list). If ANY path lies outside `$MIGRATION_DIR` (sole exceptions: `.migration/.gitignore`, and `$MIGRATION_DIR/_extract_billing.*` which must already be deleted), STOP: list the offending paths, instruct their removal, and record a `fail` ledger entry. Pre-Write self-discipline alone was bypassed in past harness iterations — this audit is the after-the-fact catch.
3. **Visible degradation** — when a network dependency fails (`google-developer-knowledge` MCP errors, 429/5xx bursts, WebFetch failures), record the failure (a `warnings[]` entry in the phase artifact AND a `skipped`/`corrected` ledger entry) and fall to the documented next source in order; NEVER silently continue with degraded data. This generalizes the pricing chain's proven pattern: ordered fallbacks + recorded attempts + explicit STOP terminal.

---

## Phase Summary Table

| Phase        | Inputs                                                                                                                                                                                                                                                                       | Outputs                                                                                                                                                                                                                                                                                                                                                                                                                                                            | Reference                                |
| ------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ---------------------------------------- |
| **Discover** | Terraform or CloudFormation files, app source code, and/or AWS billing exports (at least one required)                                                                                                                                                                       | `aws-resource-inventory.json`, `aws-resource-clusters.json`, `ai-workload-profile.json`, `aws-sdk-usage.json` (non-AI SDK call sites), `app-routes.json` (HTTP routing topology — consumed by Generate's user-journey synthesis), `billing-profile.json`, `.phase-status.json` updated (outputs vary by input)                                                                                                                                                     | `references/phases/discover/discover.md` |
| **Clarify**  | Discovery artifacts (`aws-resource-inventory.json`, `aws-resource-clusters.json`, `ai-workload-profile.json`, `aws-sdk-usage.json`, `billing-profile.json` — whichever exist)                                                                                                | `preferences.json`, `.phase-status.json` updated                                                                                                                                                                                                                                                                                                                                                                                                                   | `references/phases/clarify/clarify.md`   |
| **Design**   | `preferences.json` + discovery artifacts                                                                                                                                                                                                                                     | `gcp-design.json` (infra), `gcp-design-ai.json` (AI), `gcp-design-billing.json` (billing-only), `sdk-migration-plan.json` (if `aws-sdk-usage.json` exists)                                                                                                                                                                                                                                                                                                         | `references/phases/design/design.md`     |
| **Estimate** | `gcp-design.json` or `gcp-design-billing.json` or `gcp-design-ai.json`, `preferences.json`                                                                                                                                                                                   | `estimation-infra.json` or `estimation-ai.json` or `estimation-billing.json`, `.phase-status.json` updated                                                                                                                                                                                                                                                                                                                                                         | `references/phases/estimate/estimate.md` |
| **Generate** | `estimation-infra.json` or `estimation-ai.json` or `estimation-billing.json`, `gcp-design.json` or `gcp-design-billing.json` or `gcp-design-ai.json`, `preferences.json`, `sdk-migration-plan.json` (optional), `app-routes.json` (optional — drives user-journey synthesis) | `generation-infra.json` or `generation-ai.json` or `generation-billing.json` + `terraform/`, `scripts/`, `ai-migration/`, `code-patches/` (if `sdk-migration-plan.json` present), `code-migration-summary.md` (same), `user-journeys/` (per-journey narrative `.md` + Mermaid `.mmd` + parity-test `.sh` + `index.md`, or single-line `user-journeys.md` sentinel when no routes were discovered), `MIGRATION_GUIDE.md`, `README.md`, `.phase-status.json` updated | `references/phases/generate/generate.md` |

---

## Bundled MCP Servers and Tools

The plugin ships three official MCP servers (`.mcp.json` at the plugin root) — `google-developer-knowledge`, `awsknowledge`, and `microsoft-learn` — and one CLI tool (`bin/gcp-pricing`, on PATH while the plugin is enabled). This skill does not use the `microsoft-learn` server — it exists for the azure-to-gcp skill.

**google-developer-knowledge** (`https://developerknowledge.googleapis.com/mcp`, official Google):

- Provides the `google-developer-knowledge:search_documents`, `google-developer-knowledge:get_documents`, and `google-developer-knowledge:answer_query` tools for Google's official developer documentation (always reference MCP tools server-qualified — bare names can fail to resolve when multiple servers are connected)
- Use for Google Cloud architecture validation, service capability checks, product lifecycle checks, and current Google Cloud docs before falling back to general web search
- Auth (via the plugin's bundled proxy): gcloud ADC first (`gcloud auth application-default login` + Developer Knowledge API enabled on the quota project), then gcloud user credentials, then the API key from plugin config (`google_dev_knowledge_api_key`)
- Source/setup: https://developers.google.com/knowledge/mcp

**awsknowledge** (`https://knowledge-mcp.global.api.aws`, official AWS):

- Provides AWS documentation and service reference lookups
- Used during Discover phase for AWS service understanding
- No auth required
- Source: https://github.com/awslabs/mcp

**gcp-pricing** (bundled CLI, runs via Bash):

- `gcp-pricing services --filter <regex>` — resolve Cloud Billing service IDs
- `gcp-pricing skus --service <id|name> [--region <r>] [--filter <regex>] [--currency <ISO>]` — live SKU rates from the Cloud Billing Catalog API with decimal unit prices computed from `units`+`nanos`, plus `retrieved_at` / `auth_mode` / `source_url` provenance fields
- Auth: same ADC-first chain as above (API key failover: `GCP_PRICING_API_KEY` or plugin config); requires `cloudbilling.googleapis.com` enabled on the quota project

**Pricing**: Live lookup is **MANDATORY** and there is no cache fallback — recall from prior knowledge is fabrication. Source-of-truth order, mirroring `references/phases/estimate/estimate-infra.md` Step 0: (1) **`gcp-pricing` CLI** (Cloud Billing Catalog API) for structured per-SKU rates; (2) `google-developer-knowledge` MCP only if (1) fails for a specific service (no matching SKU, region not covered, tool error); (3) WebFetch `cloud.google.com/<service>/pricing` only if both (1) and (2) failed; (4) **STOP** if all three failed — report the failure rather than recall a price. Every dollar number in `estimation-infra.json` must carry `pricing.source`, `pricing.attempts[]` (with `tool_call` and non-empty `evidence` on the successful entry), `pricing.fetched_url`, `pricing.fetched_at`, `pricing.sku_rate`, `pricing.assumed_quantity`, and `pricing.calculation` -- model-recalled rates are forbidden and are a Generate-phase blocker. There is no pricing cache; any reference to "cached pricing" or `pricing.source: "cached_fallback"` in output indicates the skill is running stale instructions.

---

## Files in This Skill

```
aws-to-gcp/
├── SKILL.md                       ← You are here (orchestrator + state machine)
├── evals/evals.json               # Regression scenarios (IaC-full, billing-only, AI-only)
└── references/
    ├── phases/<phase>/            # One orchestrator per phase + its sub-files, loaded by the state machine:
    │                              #   discover/  discover.md + discover-{iac,app-code,app-sdk,billing}.md
    │                              #   clarify/   clarify.md + clarify-{global,compute,database,sizing,ai,ai-only}.md
    │                              #   design/    design.md + design-{infra,ai,billing}.md
    │                              #   estimate/  estimate.md + estimate-{infra,ai,billing}.md
    │                              #   generate/  generate.md + generate-{infra,ai,billing}.md
    │                              #              + generate-artifacts-{infra,scripts,ai,billing,journeys,report,docs}.md
    ├── design-refs/               # AWS→GCP decision rubrics, loaded via index.md:
    │                              #   index.md, fast-path.md, compute/database/storage/networking/messaging/
    │                              #   logging-analytics/ai/agent-runtime .md, ai-{bedrock,openai}-to-vertex.md, sdk-mapping.md
    ├── clustering/terraform/      # classification-rules, clustering-algorithm, depth-calculation, typed-edges-strategy
    └── shared/                    # companion-skills.md (canonical google/skills table) +
                                   # schema-{phase-status,discover-iac,discover-ai,discover-billing,estimate-infra}.md
```

| Condition                                                                            | Action                                                                                                                                                                                                                                                                |
| ------------------------------------------------------------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| No AWS sources found (no Terraform/CloudFormation, no app code, no AWS billing data) | Stop. Output: "No AWS sources detected. Provide at least one source type (Terraform files, CloudFormation templates, application code, or AWS billing exports) and try again."                                                                                        |
| `.phase-status.json` missing phase gate                                              | Stop. Output: "Cannot enter Phase X: Phase Y-1 not completed. Start from Phase Y or resume Phase Y-1."                                                                                                                                                                |
| All live pricing sources fail for a service                                          | STOP for that service. Do NOT emit an estimate. Report which service lacks a price and offer the user (i) fix network/auth and re-run, (ii) exclude it from totals, or (iii) provide a manual rate (`pricing.source: "user_provided"` + justification in `evidence`). |
| User skips questions or says "use all defaults"                                      | Apply documented defaults from each category file. Phase 2 completes either way.                                                                                                                                                                                      |
| `gcp-design.json` missing required clusters                                          | Stop Phase 4. Output: "Re-run Phase 3 to generate missing cluster designs."                                                                                                                                                                                           |

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
- GCP cost estimation (live Cloud Billing Catalog API via the bundled `gcp-pricing` CLI; no cached fallback)
- Migration artifact generation (Terraform, scripts, AI adapters, **source-code unified-diff patches under `code-patches/`**, documentation)
