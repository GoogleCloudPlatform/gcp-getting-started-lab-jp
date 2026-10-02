---
name: azure-to-gcp
description: "Migrate Microsoft Azure workloads and estates to Google Cloud. Triggers on: migrate from Azure, Azure to GCP, Azure to Google Cloud, move off Azure, Azure VMs to Compute Engine, VM Scale Sets to managed instance groups, AKS to GKE, App Service to Cloud Run, Azure Functions to Cloud Run functions, Azure SQL to Cloud SQL, Blob Storage to Cloud Storage, Cosmos DB migration, Azure OpenAI to Vertex AI, Bicep migration, ARM template migration, azurerm Terraform migration, Azure Migrate assessment. Runs a 5-phase process — discover (azurerm Terraform, Bicep, ARM, app code, cost exports, Azure Migrate/mcdc), clarify, design, estimate, generate. Clarify must finish before Design, Estimate, or Generate. Do not use for: AWS sources (use aws-to-gcp), Oracle Cloud VMware Solution or on-premises vSphere, GCP-to-Azure reverse migrations, Azure Virtual Desktop, Entra B2C, Power Platform/Dynamics, Azure DevOps pipeline conversion, Azure Government/China/Stack."
---

# Azure-to-GCP Migration Skill

## Philosophy

- **Always research before deciding (MANDATORY for non-deterministic calls)**: For every non-deterministic Design decision, every cost estimate, and every recommended `gcp_config` field, you MUST do a live research pass first — Google-side, in order: (a) `google-developer-knowledge` MCP, (b) WebSearch, (c) WebFetch on `docs.cloud.google.com/<service>/docs` and `cloud.google.com/<service>/pricing`; Azure-side (service capabilities, retirement dates, SDK support, export schemas, IaC syntax), in order: (a) `microsoft-learn` MCP, (b) WebFetch on `learn.microsoft.com` / `azure.microsoft.com`. Cite what it found (URL + `fetched_at`) in the resource's `rationale` or `pricing.fetched_url`. **Training-data recall is NEVER a valid basis for a recommendation.** This binds both **updates** (service capabilities, pricing, retirements — Azure retired unmanaged disks in 2026 and renamed FOCUS columns in 1.2-preview; stale recall WILL mislead) and **patterns** (best-practice config, known cost pitfalls). When research surfaces a newer Google Cloud product that fits the Azure source better than this skill's default, the newer product wins — the skill is not entitled to recommend a stale option.

- **Surface trade-offs instead of silently picking**: For every mapping where 2+ viable GCP targets exist after research, present a **trade-off card** populated from live research (NOT from these files, NOT from recall) and ASK. Record the pick in `preferences.json.design_choices[]`. **A decision not recorded in `preferences.json` MUST NOT shape `gcp-design.json`.** `references/shared/service-map.md` marks which mappings are cards; the card's content is always researched at run time.

  ```text
  Trade-off for <decision_id> (<source resource | component>):
  Option A: <gcp_target_label>
    - Source: <cited_url> (fetched <YYYY-MM-DD>)
    - Cost shape / Rewrite + downtime cost / Ops: <description each>
    - Dealbreakers: <description>
  Option B: ...
  Pick (A/B/...):
  ```

- **SEVEN GATES.** Each fires in Clarify, before Design, and each has a documented headless disposition:

  1. **Identity adjacency** — any Entra ID / Active Directory signal raises a three-option advisory: federate Entra ID with Cloud Identity (the default — IdP migration is a separate project), Managed Service for Microsoft AD (when AD-joined VMs, Kerberos/LDAP or SMB with AD are in scope), or re-platform identity. The skill never migrates an identity provider. Headless: `identity_strategy: "Federate Entra ID with Cloud Identity — IdP migration deferred"`.
  2. **Microsoft licensing** — any Windows Server, SQL Server or Azure Hybrid Benefit signal raises an **advisory only**. Load-bearing facts, all cited in `references/phases/clarify.md`: Google is a Microsoft **Listed Provider**; the Flexible Virtualization Benefit **excludes** Listed Providers; License Mobility through Software Assurance covers SQL Server but **not** Windows Server, and on a Listed Provider reaches only servers dedicated to the customer — which does **not** by itself mean a GCP sole-tenant node (a BYOL Windows Server image underneath is what forces one); Azure Hybrid Benefit is an **Azure-only** offer and cannot follow the workload to Google Cloud. **HARD RULE: an AHB- or reservation-discounted Azure baseline is NOT comparable to GCP license-included list pricing** — Estimate sets `comparison_to_azure.discount_normalization.comparable = false` and says so. The skill never counts licences or asserts a customer's entitlement. Headless: `license_strategy: "license-included (Google-provided images); BYOL eligibility Deferred to licensing specialist"`.
  3. **Analytics / data-platform gate** — Synapse, Microsoft Fabric, Databricks, HDInsight, Azure Data Explorer, Stream Analytics or Data Factory in scope means `Deferred — specialist engagement`. Those rows are carried **verbatim** through Design (no `gcp_config`), Estimate (no dollars) and Generate (no Terraform), and the user is directed to their Google Cloud account team. Headless: `analytics_strategy: "Deferred — specialist engagement"`.
  4. **M2VM per-VM eligibility** — a VM with an **ephemeral OS disk** or a **non-managed disk** is excluded from the automated wave as `needs-decision`; those are the two attributes Migrate to Virtual Machines documents as unsupported for Azure sources. **Azure Disk Encryption is NOT a blocker** — it is a high-friction card citing the 2028-09-15 ADE retirement and the fact that ADE migration is not in place.
  5. **Cosmos DB re-platform** — every Cosmos DB account gets a MANDATORY trade-off card by API flavor. Gremlin and Table APIs have no documented target and are Deferred.
  6. **Live-Azure sizing consent** — reading the user's live Azure subscription (`az monitor metrics list`) requires explicit per-run consent with the exact commands and subscription printed first. **Never assumed, never headless.**
  7. **Out-of-scope refusal** — the frontmatter's "Do not use for" list is binding. AWS sources go to `aws-to-gcp`; Oracle Cloud VMware Solution / vSphere sources are out of scope for this plugin; Azure VMware Solution, Azure Virtual Desktop, Entra B2C, Power Platform/Dynamics, Azure DevOps pipeline conversion and Azure Government/China/Stack estates are refused with a one-line reason, not partially attempted.

- **Re-host by default, re-platform by decision**: VMs map to Compute Engine; managed services map to their documented managed target. Re-platforming (containerizing a VM, changing a database engine) is a Clarify/Design decision, never an assumption.
- **Sizing is one explicit mode, never a blend**: `preferences.sizing_mode` is required (`as-provisioned` | `rightsize`). Every `estimation.json` row states the mode it used; mixing modes in one estimate is an Estimate gate failure. **There is no M2VM utilization report for Azure sources** — sizing evidence comes from `mcdc`, Azure Monitor, or the user.
- **No human one-time migration costs**: never present labour, professional services, or people-time as dollars; vendor charges grounded in data belong in `external_costs[]`. **Multi-signal approach**: Discover adapts to whichever inputs exist — azurerm Terraform, Bicep, ARM, app code, cost exports, Azure Migrate or `mcdc` exports, `az resource list` output.

---

## Companion skills (google/skills)

`references/shared/companion-skills.md` is the authoritative Azure -> GCP -> google/skill map and the
resolution protocol (`~/.claude/skills` -> `~/.agents/skills` -> `.claude/skills` -> documented fallback
warning). Design and Generate consult it before shaping any GCP-side configuration; it never overrides a
gate or resolves a trade-off card.

---

## Definitions

- **"Load"** = Read the file with the Read tool and follow its instructions; do not summarize or skip sections. **`$MIGRATION_DIR`** = the run-specific directory under `.migration/` at the USER PROJECT root (e.g. `.migration/0806-0910/`), set during Phase 1 (Discover) Step 0.
- **Card** = a mapping with 2+ viable targets, decided by the user and recorded in `design_choices[]`.
- **Deferred row** = a resource whose disposition is `Deferred — specialist engagement`: carried verbatim through Design (no `gcp_config`), Estimate (no dollars) and Generate (no Terraform). **needs-decision row** = a resource excluded from the automated wave pending a user decision (M2VM-ineligible, EOL/client OS, orphaned, zero-capacity). Both are listed by name in every summary, never silently dropped.

---

## File Output Discipline (CRITICAL)

**All skill-generated files MUST be written under `$MIGRATION_DIR`** (= `.migration/<MMDD-HHMM>/`,
established by Discover Step 0). FORBIDDEN paths and behaviours:

- Writing `terraform/`, `scripts/`, `README.md`, a migration guide, any runbook, or ANY file at the project root (cwd) — those would overwrite or pollute the source project. The user's own `README.md` MUST NOT be touched, and outputs never go to cwd even when cwd is the project root: always resolve `$MIGRATION_DIR` first.
- Writing Python/Bash helper scripts (e.g. `parse_bicep.py`, `extract_arm.py`, `build_inventory.py`, `map_resources.py`) anywhere on disk. To parse Terraform, Bicep, ARM, app code, exports or cost files, use the Read, Grep and Glob tools directly — DO NOT generate a parser script and execute it. The only Generate-phase scripts allowed are user-facing migration shell scripts under `$MIGRATION_DIR/scripts/`.
- Writing a secret value, connection string, client secret, SAS token or access key into ANY artifact. Record where a credential must be re-created, never the credential.

Correct paths: `$MIGRATION_DIR/terraform/main.tf`, `$MIGRATION_DIR/scripts/01-validate-prerequisites.sh`,
`$MIGRATION_DIR/M2VM-RUNBOOK.md`, `$MIGRATION_DIR/MIGRATION_GUIDE.md`, and `$MIGRATION_DIR/README.md` (the migration run's own, NOT the source project's).

**Pre-Write self-check (BLOCKING — applies to EVERY Write tool call this skill ever makes):**

1. If the path does not start with `$MIGRATION_DIR` (or `.migration/<MMDD-HHMM>/`) — **STOP and rewrite the path.** The only file this skill may write outside `$MIGRATION_DIR` is `.migration/.gitignore` (Discover Step 0).
2. If the path ends in `.py` — **REFUSE.** This skill generates no application source code, and the ONLY scripts it may write are SHELL scripts (`*.sh`) under `$MIGRATION_DIR/scripts/`, run by the user during cutover. The sole sanctioned exception is `$MIGRATION_DIR/_extract_cost.*` (rule 3).
3. **Banned filename stems (auto-refuse regardless of path):** `build_*.py`, `generate_*.py`, `parse_*.py`, `extract_*.py`, `analyze_*.py`, `discover_*.py`, `map_*.py`, `summarize_*.py`, `inventory_*.py`, `scan_*.py` — including underscore-prefixed variants. If you catch yourself wanting to Write one — STOP and use Read/Grep/Glob in context instead. **The SINGLE sanctioned exception:** `$MIGRATION_DIR/_extract_cost.py` (or `.js`/`.sh`) written by Discover's cost-export extraction, which exists to keep multi-MB cost files out of context and MUST be deleted after its one run. More than ONE `.py` file in a run means you are violating this rule.

Repeat this self-check at the moment you assemble the Write call, not in a planning step that gets forgotten — the check binds at call time.

---

## Prerequisites

The user must provide at least one Azure source input. **Cost data here means source Azure cost/usage
data, not GCP billing.**

- **Terraform (`azurerm`)**: `.tf` / `.tfvars` / `.tfstate` containing `azurerm_*` resources. Legacy resource names are parsed as source; see `references/shared/iac-parsing.md`.
- **Bicep**: `.bicep` files. Local modules are followed; registry (`br:`/`br/public:`) and template-spec (`ts:`) modules are recorded as unresolved, not guessed.
- **ARM templates**: `.json` with `$schema` containing `deploymentTemplate`. Both the `resources` array and the `languageVersion: "2.0"` object-keyed form are supported.
- **Application code**: any source tree containing Azure SDK call sites (see `references/shared/sdk-map.md`).
- **Azure cost export**: FOCUS (1.0 / 1.0r2 / 1.2-preview) or actual/amortized cost details, CSV or CSV.gz. Parquet is not parsed — ask for CSV.
- **Azure Migrate assessment export** (`.xlsx` from **Export assessment**), a Migration Center `mcdc` export, or **`az resource list` JSON** output.

If none are found, stop and ask the user to provide at least one source type.

---

## Headless / Unattended Runs (Interaction Contract)

When no interactive user can answer (headless drivers like `claude -p`, CI pipelines, or any run where a
question would block forever), the skill MUST NOT stall — stalled prompts killed prior harness iterations
of the sibling skills. Every interaction point has a defined headless disposition. Whenever one is
applied, record it as a plain-string entry in `preferences.json.headless_defaults_applied[]` (e.g.
`"Q_SIZING=conservative-defaults"`), stamp `chosen_by: "headless-default"` on the matching
`design_choices[]` entry, and echo ALL applied dispositions in a **"Headless assumptions"** block in the
Clarify summary and in `MIGRATION_GUIDE.md`.

**Headless detection (binding):** treat the run as HEADLESS only when the driving context establishes no
interactive human — `claude -p` pipelines, CI, an explicit "unattended" instruction, or a driver that
keeps continuing the run without a human answer ever arriving. **A card left unanswered in the turn that
presented it is NOT a headless signal**: interactive replies arrive in a later turn, so present cards, STOP, and wait.

| Interaction point                                                                                | Headless disposition                                                                                                                                                                                                                                                                                                       |
| ------------------------------------------------------------------------------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Discover: resume choice [A/B/C] / unresolved source field / Parquet-only cost export             | [A] Resume latest / leave `null`, add `[UNRESOLVED_SOURCE_FIELD]` and a `skipped` ledger entry, never guess / stop intake for that file, record the gap, continue with the other sources                                                                                                                                   |
| Prior `preferences.json` reuse (Clarify Step 0)                                                  | Reuse only if it passes the Validation Checklist, else regenerate                                                                                                                                                                                                                                                          |
| `Q_IDENTITY` (gate 1)                                                                            | `identity_strategy: "Federate Entra ID with Cloud Identity — IdP migration deferred"`                                                                                                                                                                                                                                      |
| `Q_LICENSE` (gate 2)                                                                             | `license_strategy: "license-included (Google-provided images); BYOL eligibility Deferred to licensing specialist"`                                                                                                                                                                                                         |
| `Q_ANALYTICS` (gate 3)                                                                           | `analytics_strategy: "Deferred — specialist engagement"` — never guess an analytics target                                                                                                                                                                                                                                 |
| `Q_M2VM` (gate 4)                                                                                | Every ephemeral-OS-disk / unmanaged-disk VM -> `needs-decision`, EXCLUDED from the automated wave, named in a banner. ADE VMs -> migrate with the friction warning attached                                                                                                                                                |
| `Q_MAP.cosmos` (gate 5)                                                                          | `needs-decision` per account — a Cosmos target is NEVER chosen headlessly. Gremlin/Table -> `Deferred — specialist engagement`                                                                                                                                                                                             |
| `Q_SIZING` (gate 6)                                                                              | `sizing_mode: "as-provisioned"`, `sizing_source: "conservative-defaults"`, with the loud banner in `references/phases/clarify.md`. **Path A (live `az monitor`) may NEVER be selected headlessly**                                                                                                                         |
| Out-of-scope source (gate 7)                                                                     | Same refusal as interactive: name the correct skill or the exclusion, record it, do not partially attempt                                                                                                                                                                                                                  |
| `Q_MAP.appservice` / `Q_MAP.aks`                                                                 | Cloud Run, App Engine recorded as the alternative / GKE Standard (closest to a self-managed AKS node pool), Autopilot recorded as the alternative                                                                                                                                                                          |
| `Q_MAP.vmss` / `Q_MAP.postgres`                                                                  | Managed instance group rebuild, per-VM M2VM recorded as the alternative / Cloud SQL for PostgreSQL (the only documented homogeneous DMS target), AlloyDB recorded as the alternative                                                                                                                                       |
| `Q_MAP.files`                                                                                    | By protocol: NFS -> Filestore; SMB -> NetApp Volumes with its Active Directory prerequisite named. Protocol unknown -> `needs-decision`                                                                                                                                                                                    |
| `Q_MAP.messaging`                                                                                | Pub/Sub, with a per-queue warning naming any session, DLQ, scheduled-delivery or transaction feature whose parity was not verified                                                                                                                                                                                         |
| `Q_MAP.keyvault` / `Q_MAP.observability`                                                         | Secrets -> Secret Manager, keys -> Cloud KMS, content type unknown -> `needs-decision` / OpenTelemetry to Cloud Monitoring, Cloud Logging and Cloud Trace, custom telemetry -> `needs-decision`                                                                                                                            |
| `Q_MAP.edge`                                                                                     | Cloud CDN behind an external Application Load Balancer; every source rule listed as `needs-decision`, none invented                                                                                                                                                                                                        |
| `Q_MAP.apim` / `Q_MAP.logicapps`                                                                 | API Gateway, Apigee recorded as the alternative / `needs-decision` — connector coverage cannot be assumed                                                                                                                                                                                                                  |
| `Q_MAP.ai` / `Q_MAP.search`                                                                      | OpenAI-compatible Chat Completions route, model selection `needs-decision`, auth-shape change recorded as a warning / Agent Search, with reindex scope and any skillset dependency recorded as `needs-decision`                                                                                                            |
| `Q_SDK`                                                                                          | Rewrite guidance recorded as notes only, `manual_review: true` on every row; no code is emitted in any run                                                                                                                                                                                                                 |
| `Q_OS`                                                                                           | Supported guests migrate as-is; every `[EOL_OS]` and `[CLIENT_OS]` guest -> `needs-decision`, EXCLUDED from auto-design, named in a banner                                                                                                                                                                                 |
| `Q_ZOMBIE`                                                                                       | Every `[POWERED_OFF]`, `[STOPPED_NOT_DEALLOCATED]`, `[ORPHANED_DISK]` and `[VMSS_ZERO]` item -> `defer`, individually listed. The skill never retires anything unilaterally                                                                                                                                                |
| `Q_NET`                                                                                          | `re-ip`, listed as an assumption (CIDR preservation is never assumed)                                                                                                                                                                                                                                                      |
| `Q_REGION`                                                                                       | Derived from the source Azure location per `references/phases/clarify.md`, else `us-central1`, `chosen_by: "headless-default"`                                                                                                                                                                                             |
| `Q_INTENT`                                                                                       | `cutover`, listed as an assumption                                                                                                                                                                                                                                                                                         |
| `Q_ADJ`                                                                                          | `defer`, each item listed                                                                                                                                                                                                                                                                                                  |
| Design: live-`gcloud` read consent / ambiguous domain controller / machine-series tie-break card | Never call `gcloud` — use the docs/live-research chain plus a `warnings[]` entry and a `skipped` ledger entry / `needs-decision` warning naming the VM, never image-migrate a suspected DC / apply the documented default series with a loud banner and a `design_choices[]` entry stamped `chosen_by: "headless-default"` |
| Pricing-failure menu (Estimate Step 0d)                                                          | (ii) exclude the component from totals + report the failure. NEVER fabricate a rate                                                                                                                                                                                                                                        |

Headless mode never upgrades to riskier behaviour than an interactive session would take — it only
substitutes documented, conservative, clearly-labelled defaults.

## State Machine

This is the execution controller. After completing each phase, consult this table for the next action.

| Current State   | Condition | Next Action                          |
| --------------- | --------- | ------------------------------------ |
| `start`         | always    | Load `references/phases/discover.md` |
| `discover_done` | always    | Load `references/phases/clarify.md`  |
| `clarify_done`  | always    | Load `references/phases/design.md`   |
| `design_done`   | always    | Load `references/phases/estimate.md` |
| `estimate_done` | always    | Load `references/phases/generate.md` |
| `generate_done` | (any)     | Migration planning complete          |

**How to determine current state:** on session resume, read `$MIGRATION_DIR/.phase-status.json` -> check
the `phases` object -> find the last phase with value `"completed"`.

**Phase gate checks:** if the prior phase is incomplete, do not advance.

**Clarify is mandatory:** do not load `references/phases/design.md`, `references/phases/estimate.md` or
`references/phases/generate.md` unless `$MIGRATION_DIR/.phase-status.json` exists and `phases.clarify` is
exactly `"completed"`. A `preferences.json` file alone is **not** proof that Clarify ran. If the user
asks to skip Clarify or jump straight to Design, cost estimate, or artifact generation, refuse briefly,
then load `references/phases/clarify.md` and run Phase 2. There is no exception for "quick" or "obvious"
migrations.

**Three additional Design-entry gates** (checked when loading `references/phases/design.md`) — for each,
evidence present in the discovery artifacts with no matching strategy recorded in `preferences.json`
means STOP and return to Clarify: **identity** (Entra/AD evidence, no `identity_strategy`), **licensing**
(Windows/SQL/AHB evidence, no `license_strategy`), **analytics** (analytics evidence, no
`analytics_strategy`).

---

## State Validation

When reading `$MIGRATION_DIR/.phase-status.json`, validate before proceeding:

1. **Multiple sessions**: if multiple directories exist under `.migration/`, list them with their phase status and ask: [A] Resume latest, [B] Start fresh, [C] Cancel.
2. **Invalid JSON**: if it fails to parse, STOP. Output: "State file corrupted (invalid JSON). Delete the file and restart the current phase."
3. **Unrecognized phase or status**: a phase not in {discover, clarify, design, estimate, generate}, or a value not in {pending, in_progress, completed, failed} -> STOP, naming the offending value and the valid set.
4. **Failed phase**: `"failed"` is a legal, resumable state — do NOT treat it as corruption. On resume, re-enter that phase and pick up from its missing outputs, reporting which phase failed and why (`generation-validation.json` for Generate failures) first.

---

## State Management

Migration state lives in `$MIGRATION_DIR` (`.migration/[MMDD-HHMM]/`), created by Phase 1 and persisted
across invocations. The `.phase-status.json` schema, and every other artifact schema, is defined once in
`references/shared/schema-artifacts.md` — phases follow that file, not a local copy.

Phase 1 creates a comment-only `.migration/.gitignore` explaining the exclusion; to actually keep
`.migration/` out of version control the user adds `.migration/` to the project root `.gitignore`
themselves — this skill NEVER edits the project root `.gitignore`.

### Phase Status Update Protocol

**The UPDATE is write-only — never Read `.phase-status.json` immediately before writing it.** You already
know the current state: you are executing phases sequentially. Write the **complete file** in the same
turn as your final phase work, filling `migration_id` with the run id, generating `last_updated` as an ISO
8601 UTC timestamp yourself, and setting every phase to its correct status. **Reading it IS required in
two places** — session-resume detection (Discover Step 0), and each phase's ENTRY gate, where Design,
Estimate and Generate each open by reading it to confirm the prior phase is `"completed"`. Only the
redundant read-then-write at phase completion is forbidden.

### Run Validation Ledger, Write Audit, and Degradation Reporting

Three run-wide protocols every phase follows (harness history: gates that leave a written trace stick;
prose-only rules were reliably bypassed):

1. **Validation ledger** — `$MIGRATION_DIR/validation-ledger.json`, an array of `{"phase","gate","result","evidence","at"}`. Each phase appends one entry per BLOCKING gate it ran (Discover: source enumeration + warning counts; Clarify: each of the seven gates' outcomes + headless dispositions applied; Design: fidelity self-checks; Estimate: pricing-attempt summary + sizing-mode uniformity; Generate: artifact gates). **Ledger resume rule:** on session resume, Read this file ONCE before the session's first append — earlier phases' entries are not re-derivable and a blind Write clobbers them. Within a session, keep writing the complete file with no further Reads. Every phase-completion summary MUST surface any `fail`/`corrected` entries.
2. **Post-phase write audit** — at each phase completion, audit the files THIS SESSION wrote during the phase. The **primary source is the session's own write list** (track your Write/Edit calls as you make them); `git status --porcelain` is only a cross-check against a baseline captured at phase start — it cannot see the skill's own writes once the user root-gitignores `.migration/`, its paths are repo-root-relative (normalize to absolute before comparing), and it lists the user's pre-existing dirty paths, which are out of scope. If ANY session-written path lies outside `$MIGRATION_DIR` (sole exceptions: `.migration/.gitignore`, and `$MIGRATION_DIR/_extract_cost.*` which must already be deleted), STOP: list the offending paths, instruct their removal, and record a `fail` ledger entry. Headless: record the `fail` entry plus a prominent warning in the phase summary and continue — never stall. Files the session did not itself write are NEVER violations.
3. **Visible degradation** — when a network dependency fails (`google-developer-knowledge` or `microsoft-learn` MCP errors, 429/5xx bursts, WebFetch failures), record it (a `warnings[]` entry in the phase artifact AND a `skipped`/`corrected` ledger entry) and fall to the documented next source in order; NEVER silently continue with degraded data.

---

## Phase Summary Table

| Phase        | Inputs                                                                                                                     | Outputs                                                                                                                                                                  | Reference                       |
| ------------ | -------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ------------------------------- |
| **Discover** | azurerm Terraform, Bicep, ARM, app code, Azure cost export, Azure Migrate/`mcdc` export, `az resource list` (>=1 required) | `azure-inventory.json`, `azure-cost-profile.json`, `adjacent-services.json`, `validation-ledger.json`, `.phase-status.json` updated (outputs vary by input)              | `references/phases/discover.md` |
| **Clarify**  | Discovery artifacts (whichever exist)                                                                                      | `preferences.json` (the seven gates, sizing, network, region, `design_choices[]`, `headless_defaults_applied[]`), `validation-ledger.json`, `.phase-status.json` updated | `references/phases/clarify.md`  |
| **Design**   | `preferences.json` + discovery artifacts                                                                                   | `gcp-design.json`, `validation-ledger.json`, `.phase-status.json` updated                                                                                                | `references/phases/design.md`   |
| **Estimate** | `gcp-design.json`, `preferences.json`, `azure-cost-profile.json`                                                           | `estimation.json` (per-row `pricing.attempts[]`, `external_costs[]`, totals, `comparison_to_azure`), `validation-ledger.json`, `.phase-status.json` updated              | `references/phases/estimate.md` |
| **Generate** | `estimation.json`, `gcp-design.json`, `preferences.json`                                                                   | `terraform/`, `scripts/`, applicable runbooks, `MIGRATION_GUIDE.md`, `README.md`, `generation-validation.json`, `validation-ledger.json`, `.phase-status.json` updated   | `references/phases/generate.md` |

---

## Bundled MCP Servers and Tools

The plugin ships official MCP servers (`.mcp.json` at the plugin root) and one CLI tool
(`bin/gcp-pricing`, on PATH while the plugin is enabled). **This skill uses `google-developer-knowledge`
and `microsoft-learn`, and does NOT use the `awsknowledge` MCP server** — there is no AWS side to an
Azure migration. Always reference MCP tools server-qualified; bare names can fail to resolve when
multiple servers are connected. Community mirrors and non-official domains are forbidden sources at
every tier.

**google-developer-knowledge** (`https://developerknowledge.googleapis.com/mcp`, official Google):

- Tools: `google-developer-knowledge:search_documents`, `google-developer-knowledge:get_documents`, `google-developer-knowledge:answer_query`.
- Use for GCP service capability checks, product lifecycle checks, and current Google Cloud docs before falling back to general web search.
- Auth (via the plugin's bundled proxy): gcloud ADC first (`gcloud auth application-default login` + Developer Knowledge API enabled on the quota project), then gcloud user credentials, then the API key from plugin config.
- Source/setup: https://developers.google.com/knowledge/mcp

**microsoft-learn** (`https://learn.microsoft.com/api/mcp`, official Microsoft, **keyless**):

- Tools: `microsoft-learn:microsoft_docs_search`, `microsoft-learn:microsoft_code_sample_search`, `microsoft-learn:microsoft_docs_fetch`.
- **This is the FIRST source for every Azure-side fact** — retirement dates, plan/tier behaviour, export schemas, SDK support windows, ARM/Bicep syntax. WebFetch of `learn.microsoft.com` is the second tier, used when the MCP errors or returns nothing.
- Registration adds it to the plugin `.mcp.json`; it requires no key or account.

**gcp-pricing** (bundled CLI, runs via Bash):

- `gcp-pricing services --filter <regex>` — resolve Cloud Billing service IDs.
- `gcp-pricing skus --service <id|name> [--region <r>] [--filter <regex>] [--currency <ISO>]` — live SKU rates from the Cloud Billing Catalog API with decimal unit prices computed from `units`+`nanos`, plus `retrieved_at` / `auth_mode` / `source_url` provenance.
- Auth: the same ADC-first chain (API key failover: `GCP_PRICING_API_KEY` or plugin config); requires `cloudbilling.googleapis.com` enabled on the quota project.

**Pricing**: live lookup is **MANDATORY** and there is no cache fallback — recall from prior knowledge is
fabrication. Source-of-truth order, mirroring `references/phases/estimate.md` Step 0: (1) **`gcp-pricing`
CLI**; (2) `google-developer-knowledge` MCP only if (1) fails for a component; (3) WebFetch the official
`cloud.google.com` / `docs.cloud.google.com` pricing page only if both failed; (4) **STOP** if all three
failed — report the failure rather than recall a price. Every dollar in `estimation.json` must carry
`pricing.source`, `pricing.attempts[]` (with `tool_call` and non-empty `evidence` on the successful
entry), `pricing.fetched_url`, `pricing.fetched_at`, `pricing.sku_rate`, `pricing.assumed_quantity` and
`pricing.calculation`. **Generate REJECTS any estimation entry lacking this live-evidence provenance.**

---

## Files in This Skill

```text
azure-to-gcp/
├── SKILL.md          ← You are here (orchestrator + state machine)
├── evals/evals.json  # Regression scenarios
└── references/
    ├── phases/       # One SELF-CONTAINED file per phase, driven by the state machine:
    │                 #   discover.md, clarify.md, design.md, estimate.md, generate.md
    └── shared/       # schema-artifacts.md (artifact JSON contracts), service-map.md (targets, cards,
                      #   licensing, stale facts), sdk-map.md, iac-parsing.md (ARM/Bicep/azurerm),
                      #   billing-exports.md (FOCUS + actual-cost), companion-skills.md
```

| Condition                                                                                                                        | Action                                                                                                                                                                                                                                                          |
| -------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| No Azure sources found                                                                                                           | Stop. Output: "No Azure sources detected. Provide at least one: azurerm Terraform, Bicep, ARM templates, application code with Azure SDK calls, an Azure cost export (CSV), an Azure Migrate or mcdc export, or `az resource list` JSON. Then re-run Discover." |
| Source is AWS, Oracle Cloud VMware Solution / vSphere, or another out-of-scope estate                                            | Stop. Name the correct skill (`aws-to-gcp`) or the exclusion, and do not partially attempt the migration.                                                                                                                                                       |
| Cost export supplied as Parquet only                                                                                             | Stop intake for that file; ask for a CSV or CSV.gz export. Other provided sources may still proceed.                                                                                                                                                            |
| `.phase-status.json` missing a phase gate                                                                                        | Stop. Output: "Cannot enter Phase X: Phase X-1 not completed. Start from Phase X-1 or resume it."                                                                                                                                                               |
| Entra/AD, Windows/SQL/AHB, or analytics evidence present with no matching strategy in `preferences.json`                         | Stop before Design (gates 1-3). Re-run Clarify so the advisory fires.                                                                                                                                                                                           |
| `gcp-design.json` contradicts `preferences.json` (a configured Deferred row, or a card mapping with no `design_choices[]` entry) | Stop Estimate. Re-run Design — unrecorded decisions may not ship.                                                                                                                                                                                               |
| All live pricing sources fail for a component                                                                                    | STOP for that component. Offer: (i) fix network/auth and re-run, (ii) exclude from totals, (iii) user-provided manual rate (`pricing.source: "user_provided"` + justification in `evidence`).                                                                   |
| `estimation.json` row missing `pricing.attempts[]` evidence or its sizing mode                                                   | Stop Generate (blocker in `generation-validation.json`). Fix by re-running Estimate.                                                                                                                                                                            |
| User skips questions or says "use all defaults"                                                                                  | Apply the documented dispositions from `references/phases/clarify.md` with `chosen_by: "user-requested-default"`. Phase 2 completes either way — but this can never acknowledge a licensing entitlement or pick a Cosmos DB target.                             |

## Defaults

- **IaC output**: Terraform configurations, migration shell scripts, per-workload runbooks, and documentation. **Cost currency**: USD.
- **Region**: derived from the source Azure location per `references/phases/clarify.md`; otherwise `us-central1`. An explicit user choice always wins.
- **Sizing**: `as-provisioned` (rightsizing only on explicit user direction; the mode is stamped on every estimate row). **Network mode**: `re-ip` (CIDR preservation only by user choice, and only where it does not collide).
- **Identity**: federate Entra ID with Cloud Identity; never migrate the IdP. **Windows/SQL licensing**: license-included Google-provided images; BYOL only on an explicit user decision recorded with its rationale.

## Workflow Execution

When invoked, the agent **MUST follow this exact sequence**:

1. **Load phase status on resume only**: if `.migration/*/.phase-status.json` exists, read it to resume or advance. If not, initialize Phase 1 (Discover).
2. **Determine the phase**: status `in_progress` -> resume it; `completed` -> advance per the State Machine. Then load that phase's full reference file.
3. **Execute ALL steps in order**: follow every numbered step. **Do not skip, optimize, or deviate.**
4. **Validate outputs** against `references/shared/schema-artifacts.md`, then **update phase status** via the Phase Status Update Protocol (Write, no Read) in the same turn as the phase's final message.
5. **Display summary**: what was accomplished, the next phase, or confirmation of completion.

**Critical constraint**: adhere strictly to the reference file's workflow. If unable to complete a step,
stop and report the exact step that failed. The user can invoke the skill again to resume.

## Scope Notes

**v0.1 includes:** discovery from azurerm Terraform, Bicep, ARM templates, application code, Azure cost
exports (FOCUS and actual/amortized), Azure Migrate and `mcdc` exports, and `az resource list` JSON;
Clarify with the seven gates, per-mapping trade-off cards, four sizing paths (including the consent-gated
live `az monitor` path) and per-resource dispositions; Design with Deferred-row carriage,
preferences-fidelity enforcement and cited rationale on every row; GCP cost estimation (live Cloud
Billing Catalog API via the bundled `gcp-pricing` CLI, no cached fallback) with explicit Azure-discount
normalization in `comparison_to_azure`; and artifact generation (Terraform, cutover shell scripts,
applicable runbooks, documentation, `generation-validation.json`).

**v0.1 does not include:** AWS, Oracle Cloud VMware Solution or on-premises vSphere sources; Azure VMware Solution
(no Azure-series journey exists for it); Azure Virtual Desktop; Entra B2C; Power Platform and Dynamics;
Azure DevOps pipeline conversion; Azure Government, China or Stack estates; Parquet cost-export parsing;
emitting application source code (SDK rewrites are review notes only); automated Azure-side teardown;
analytics/data-platform design (deferred to a specialist by gate 3).
