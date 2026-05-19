# Generate Phase: Documentation Generation

> Loaded by generate.md LAST, after all other artifact generation sub-files complete.

**Execute ALL steps in order. Do not skip or optimize.**

## Overview

Produce comprehensive migration documentation from all generated artifacts. This runs LAST because it references all previously generated plans and artifacts.

**Outputs:**

- `$MIGRATION_DIR/MIGRATION_GUIDE.md` -- Step-by-step migration guide organized by phase
- `$MIGRATION_DIR/README.md` -- Quick start, artifact catalog, and architecture overview (this is the **migration run's** README, NOT the source project's `README.md`)

## Step 0: Path Discipline (READ FIRST)

`MIGRATION_GUIDE.md` and `README.md` MUST be written to `$MIGRATION_DIR/MIGRATION_GUIDE.md` and `$MIGRATION_DIR/README.md` respectively. The source project's existing `README.md` at the project root MUST NOT be overwritten or modified — doing so would destroy the user's project documentation. If a `README.md` already exists at cwd, do not touch it. NEVER emit a helper parser script. See **SKILL.md > File Output Discipline (CRITICAL)** for the full rule set.

## Prerequisites

At least one generation JSON must exist in `$MIGRATION_DIR/`:

- `generation-infra.json` (infrastructure migration plan)
- `generation-ai.json` (AI migration plan)
- `generation-billing.json` (billing-only migration plan)

Scan for all generated artifacts:

- `terraform/` directory (Terraform configurations)
- `scripts/` directory (migration scripts)
- `ai-migration/` directory (AI provider adapter and test harness)

If **no** generation JSON exists: **STOP**. Output: "No migration plans found. Stage 1 of Generate phase did not complete."

## Output Structure

```
$MIGRATION_DIR/
+-- MIGRATION_GUIDE.md     # Detailed step-by-step migration guide
+-- README.md              # Quick reference and artifact catalog
```

## Step 1: Generate MIGRATION_GUIDE.md

Build a phase-based migration guide that adapts sections based on which tracks ran.

### Required Sections (HARD MINIMUM — guide must contain ALL of these; one-sentence stubs are forbidden)

Iter 1 produced a `MIGRATION_GUIDE.md` containing only the single line "Follow the terraform README to deploy." That is unacceptable. The guide MUST contain ALL of the following top-level sections (in this order), each with **at least three sentences** of substantive content drawn from the migration artifacts:

1. **Executive Summary** — 1 paragraph. Source workload one-liner (from `aws-resource-inventory.json` summary: total_resources, primary count, dominant tier). Target one-liner (from `gcp-design.json` cluster summary: number of clusters, dominant GCP services). Headline metric from `estimation-infra.json` (Balanced monthly USD) and total timeline weeks from `generation-infra.json`.
2. **Source Architecture Overview** — Mirrors `aws-resource-inventory.json`. List AWS regions, primary resource counts by tier (compute / database / storage / networking / messaging), and call out any specialist-deferred items (e.g. Redshift). Reference the inventory file path.
3. **Target Architecture Overview** — Mirrors `gcp-design.json` cluster summary. List target region, each cluster's primary GCP services, and which clusters depend on which (creation_order_depth). Include a small table of AWS → GCP service mappings extracted from `clusters[].resources[]`.
4. **User Journeys to Verify Post-Cutover** — One row per journey listed in `$MIGRATION_DIR/user-journeys/index.md`, in the same order. Each row carries: journey name, criticality (high/medium/low from `index.md`), the parity-test script path (`user-journeys/<NNN>-<name>.sh`), and an unchecked Markdown checkbox the operator ticks after running the script against GCP. If `user-journeys/user-journeys.md` exists (graceful-degradation sentinel), substitute a single line: "User journeys not derived (no routes file in inventory)." If neither file exists (Generate ran without app code at all), omit this section. This section MUST precede Section 5 (Migration Sequence).
5. **Migration Sequence** — Per-cluster ordering by `creation_order_depth` (0 → N). For each cluster: cluster_id, services involved, and the week range from `generation-infra.json`.
6. **Data Migration Steps** — Reference the actual scripts in `$MIGRATION_DIR/scripts/` (only the ones that exist; e.g. `02-migrate-data.sh`, `03-migrate-containers.sh`, `04-migrate-secrets.sh`). For each, a 2-3 sentence description of source → target and a dry-run + execute command pair.
7. **Cutover Plan** — DNS strategy (Cloud DNS or third-party), traffic shift approach (e.g. weighted routing, blue/green), and an explicit rollback procedure with the RTO from `generation-infra.json` rollback section.
8. **Post-migration Validation Checklist** — Concrete checks: services responding (link to `scripts/05-validate-migration.sh`), data integrity (row counts / checksums), performance thresholds vs AWS baseline, cost tracking active. Include a sub-checklist that re-references every `user-journeys/<NNN>-<name>.sh` from Section 4 so the operator does not forget to re-run them as part of validation.
9. **Known Limitations and Manual Steps** — Every `TODO` marker discovered via `grep -rn "TODO" $MIGRATION_DIR/terraform $MIGRATION_DIR/scripts`. Every `human_expertise_required: true` cluster from the design. Any companion-skill-missing warnings from `gcp-design.json.warnings[]`.

The conditional sections (AI track, billing-only track, Redshift specialist callout) listed further below are ADDITIONS to these nine required sections — they do not replace any of them.

### Document Structure

The MIGRATION_GUIDE.md follows this structure:

- Title: `# AWS to GCP Migration Guide`
- Subtitle: `> Generated by AWS to GCP Migration Advisor`
- Table of Contents (auto-generated from sections)
- The eight Required Sections listed above (mapped into the conditional/common structure below as appropriate; "Section 1: Prerequisites" expands the Executive Summary's "before you begin" details)
- Section 1: Prerequisites (always included)

#### Prerequisites Section Content

Include these checklists:

- GCP Project Setup: project created, billing enabled, gcloud CLI configured, Terraform >= 1.5.0
- AWS Access: account access, aws CLI, IAM user with export permissions
- Tools Required: terraform, gcloud, aws, docker, jq, gsutil
- If AI track ran: add python >= 3.9, google-cloud-aiplatform

### Conditional Sections

#### IF infrastructure track ran (generation-infra.json exists)

Generate the following sections:

**Section 2: Infrastructure Setup** -- Deploy GCP Infrastructure subsection with numbered steps:

1. Review Terraform configurations in `terraform/` (main.tf, variables.tf, domain .tf files)
1. Initialize and plan: `cd terraform/ && terraform init && terraform plan -out=migration.tfplan`
1. Review the plan output carefully before applying
1. Apply: `terraform apply migration.tfplan`

Post-Infrastructure Tasks checklist: verify resources, check firewall rules, validate IAM service accounts.

**Section 3: Data Migration** -- **Include ONLY if `scripts/02-migrate-data.sh`,
`scripts/03-migrate-containers.sh`, or `scripts/04-migrate-secrets.sh` exist.**
If NONE of these scripts were generated, skip Section 3 entirely.

Include only subsections for scripts that were generated:

Database Migration subsection (only if `scripts/02-migrate-data.sh` exists) with numbered steps:

1. Run prerequisites check: `./scripts/01-validate-prerequisites.sh`
1. Execute data migration (dry run first): `./scripts/02-migrate-data.sh` then `./scripts/02-migrate-data.sh --execute`
1. Validate data integrity: `./scripts/05-validate-migration.sh`

Container Image Migration (only if `scripts/03-migrate-containers.sh` exists): `./scripts/03-migrate-containers.sh` (dry run, then `--execute`)

Secrets Migration (only if `scripts/04-migrate-secrets.sh` exists): `./scripts/04-migrate-secrets.sh` (dry run, then `--execute`)

**Section 4: Service Migration** -- Per-cluster migration steps from generation-infra.json, organized by creation_order depth.

**Human Expertise Advisory (Redshift / deferred analytics)** -- If any service has `human_expertise_required: true` for Redshift or `gcp_service` is **`Deferred -- specialist engagement`**, include a prominent callout in Section 4 next to that service:

> **Specialist engagement required (Redshift):** This plugin **does not** choose a GCP analytics or warehouse target (no BigQuery/Dataflow/Dataproc recommendation). Engage your **GCP account team** and/or a **data analytics migration partner** before data warehouse, lake, or SQL analytics design. Redshift work involves query patterns, data movement, ETL/ELT, and BI integration that must be assessed by specialists.

#### IF AI track ran (generation-ai.json exists)

Generate the following section:

**Section 5: AI Migration** with subsections:

- Setup Vertex AI Access: run `./setup_vertex.sh`, enable API in GCP Console
- Deploy Provider Adapter: review adapter file, update TODO markers, deploy with application
- Run A/B Comparison: `python ai-migration/test_comparison.py --quick`, review results, verify quality >= 90%
- Gradual Rollout: shadow mode, 10% traffic, scale to 100%, disable Bedrock after 48 hours stable

#### IF billing-only track ran (generation-billing.json exists)

Generate the following section:

**Section 2: Billing-Only Limitations** -- Include blockquote warning that the plan was generated from billing data only. Before Proceeding subsection recommending IaC discovery or manual audit. Using the Skeleton Terraform subsection with steps to find and resolve TODO markers.

### Common Sections (always included)

**Cutover section** with subsections:

- Pre-Cutover Checklist (from generation plan)
- Execute Cutover (DNS switch, traffic migration, monitoring)
- Post-Cutover Monitoring (24-48 hour watch, then 30-day monitoring)

**Validation and Cleanup section** with subsections:

- Validation Steps checklist: services responding, performance thresholds, data integrity, cost tracking
- AWS Teardown checklist (after stability period): archive data, delete resources, disable billing

**Troubleshooting section** with a Common Issues table:

| Issue                          | Cause                      | Resolution                                  |
| ------------------------------ | -------------------------- | ------------------------------------------- |
| Terraform apply fails          | Missing permissions        | Check service account has required IAM roles |
| Database connection refused    | Firewall rules             | Verify firewall allows app subnet CIDR       |
| Container image pull fails     | Artifact Registry auth     | Run `gcloud auth configure-docker`           |
| Vertex AI GenerateContent fails | API not enabled           | Enable in GCP Console                        |
| High latency after migration   | Suboptimal machine type    | Review Cloud Monitoring metrics and right-size |

Rollback Procedure subsection (from generation plan -- rollback triggers, steps, and RTO).

### Footer

End the document with:

```
---
Generated by AWS to GCP Migration Advisor
```

## Step 2: Generate README.md

Build a quick-reference README for the migration artifacts.

### README Structure

The README.md follows this structure:

- Title: `# AWS to GCP Migration Artifacts`
- Subtitle: `> Generated by AWS to GCP Migration Advisor`

#### Quick Start

Numbered steps:

1. Review the Migration Guide (link to MIGRATION_GUIDE.md)
1. Deploy infrastructure: `cd terraform/ && terraform init && terraform plan`
1. Run migration scripts: `./scripts/01-validate-prerequisites.sh`
1. If AI track ran: Set up AI: `cd ai-migration/ && ./setup_vertex.sh`

#### Artifact Catalog

Table with columns: Artifact, Description, Status. List all generated files/directories.

Subsections:

- Migration Plans (Stage 1): list generation-*.json files
- Infrastructure (Stage 2): list .tf files, **`terraform/README.md`** (when infra Terraform was generated), and migration scripts if they exist
- AI Migration (Stage 2): list adapter, test harness, setup script if they exist
- Documentation: MIGRATION_GUIDE.md and README.md

#### Architecture Overview

- Source (AWS): list AWS services from design artifacts
- Target (GCP): list GCP services from design artifacts with region
- Migration Approach: summary from generation plans (phased/fast-track/conservative)

#### Cost Summary

Table from estimation artifacts with: Current AWS Monthly, Projected GCP Monthly (use **Balanced** tier for the primary GCP column when `estimation-infra.json` exists), Timeline. **Only include a "AWS data transfer egress (est.)" column when `estimation-infra.json` exists and `migration_cost_considerations.billing_data_available` is `true`.** Do **not** add columns or rows for human labor, professional services, or other people-time migration costs. If billing data is unavailable, add a note below the table: "AWS data transfer egress estimates require billing data. Provide a Cost and Usage Report and re-run discovery to see vendor egress projections."

**How to read cost tiers** (required when infra estimates include Premium / Balanced / Optimized):

- The three GCP monthly totals are **scenarios** for the **same** architecture, ordered **high -> mid -> low** estimate.
- **Premium** -- *Highest resilience / highest monthly estimate in this model*
- **Balanced** -- *Default scenario; compare AWS to this first*
- **Optimized** -- *Lower monthly estimate; committed use / preemptible / storage trade-offs assumed*
- **Terraform:** The `terraform/` directory (when present) implements **one** stack, aligned with the **Balanced** scenario. **Premium** and **Optimized** are not separate generated folders -- see `terraform/README.md` and the `migration_summary` output in `outputs.tf`.

Include a compact three-tier row or table if the executive report does, matching figures from `estimation-infra.json`.

#### Key Decisions

Bullet list from design and generation artifacts: Compute, Database, Storage, and AI/ML (if applicable) with AWS service, GCP service, and rationale. For each AWS->GCP mapping, add how it was chosen using `design-refs/fast-path.md` -> **User-facing vocabulary**: **Standard pairing**, **Tailored to your setup**, or **Estimated from billing only** (from the design artifact's `confidence` field). For any service with `human_expertise_required: true`, append: "(Specialist guidance recommended -- contact your GCP account team)".

#### TODO Items

Include a command to find all TODO markers:

```bash
grep -rn "TODO" terraform/ scripts/ ai-migration/ 2>/dev/null
```

#### Footer

End with: `Generated by AWS to GCP Migration Advisor`

### Populate from artifacts

- **Artifact catalog**: List all files actually generated (check for directory/file existence)
- **Architecture overview**: Extract from `gcp-design.json`, `gcp-design-ai.json`, or `gcp-design-billing.json`
- **Cost summary**: Extract from `estimation-infra.json`, `estimation-ai.json`, or `estimation-billing.json`; include **How to read cost tiers** when three infra tiers exist; state **Balanced** as primary vs AWS and Terraform alignment per `terraform/README.md` when present
- **Key decisions**: Extract from design artifact `rationale` fields and map `confidence` to user-facing labels per `design-refs/fast-path.md` -> **User-facing vocabulary**
- **Timeline**: Extract from `generation-*.json` `migration_plan.total_weeks`

## Step 3: Self-Check

After generating documentation, verify:

1. **Path discipline**: `MIGRATION_GUIDE.md` and `README.md` were written to `$MIGRATION_DIR/`, NOT to the project root. The source project's existing `README.md` was not modified.
1. **Required sections present in MIGRATION_GUIDE.md** (BLOCKING): all nine Required Sections (Executive Summary, Source Architecture Overview, Target Architecture Overview, User Journeys to Verify Post-Cutover, Migration Sequence, Data Migration Steps, Cutover Plan, Post-migration Validation Checklist, Known Limitations and Manual Steps) are present and each contains at least three sentences of substantive content. The User Journeys section is satisfied when `user-journeys/index.md` exists and is referenced row-by-row, OR when the graceful-degradation sentinel text from `user-journeys/user-journeys.md` is inlined verbatim, OR when no `user-journeys/` directory exists at all (Generate ran with no app code). A one-line guide like "Follow the terraform README to deploy." MUST be rejected and the file regenerated.
1. **All file references are valid**: Every file path mentioned in MIGRATION_GUIDE.md exists in the artifact directory
1. **Commands are syntactically correct**: All bash commands use correct syntax
1. **No unresolved placeholders**: All `[placeholder]` values are replaced with actual data from artifacts
1. **Conditional sections match**: Only sections for tracks that actually ran are included
1. **TODO count is accurate**: Count matches actual TODO markers in generated artifacts
1. **Cost figures match**: Values in README.md match estimation artifacts
1. **Timeline matches**: Week counts match generation plan artifacts
1. **Rollback instructions match**: Rollback steps match generation plan

## Phase Completion

Report the list of generated files to the parent orchestrator. **Do NOT update `.phase-status.json`** -- the parent `generate.md` handles phase completion.

Output:

```
Generated documentation:
- MIGRATION_GUIDE.md ([N] sections, covering [tracks that ran])
- README.md (artifact catalog, architecture overview, cost summary)

Sections included:
- [List which conditional sections were generated based on tracks that ran]
```
