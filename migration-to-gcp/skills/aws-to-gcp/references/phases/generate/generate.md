# Phase 5: Generate Migration Artifacts (Orchestrator)

**Execute ALL steps in order. Do not skip or optimize.**

> **Budget-aware artifact priority (headless / time-constrained runs)**:
>
> Generate MUST produce artifacts in this priority order. When time pressure forces dropping outputs, drop ONLY from the OPTIONAL list. Never drop a MANDATORY artifact to fit OPTIONAL ones; never substitute a sentinel-only file for a MANDATORY category.
>
> **MANDATORY (always produce):**
> 1. `terraform/{main,variables,outputs,vpc,security,storage,database,compute,monitoring}.tf`
> 2. `terraform/analytics.tf` — REQUIRED if `gcp-design.json` has any resource with `aws_type` matching `aws_glue_*`, `aws_athena_*`, `aws_kinesis_*`, `aws_msk_*`, `aws_opensearch_*`, or `aws_emr_*`. Cannot be substituted.
> 3. `adrs/*.md` — ONE per resource where Design `confidence != "deterministic"`.
> 4. `code-patches/*.patch` — REQUIRED if `aws-sdk-usage.json.summary.total_call_sites > 0`. ONE per source file with aws-sdk calls.
> 5. `MIGRATION_GUIDE.md` with all required sections.
> 6. `scripts/*.sh` migration shell scripts.
>
> **OPTIONAL (sentinel allowed if skipped):**
> - `user-journeys/*.{md,mmd,sh}`
> - `migration-report.html`
> - `terraform/README.md`
>
> Dropping a MANDATORY artifact → emit `phases.generate = "failed"` (NOT `"completed"`). Skipped OPTIONAL → log to `generation-validation.json.budget_skipped[]` with a reason.

## File Output Discipline (READ BEFORE WRITING ANYTHING)

Every file produced by this phase and its sub-files MUST live under `$MIGRATION_DIR` (= `.migration/<MMDD-HHMM>/`, set in Discover Step 0). See **SKILL.md > File Output Discipline (CRITICAL)** for the full rules. Recap:

- Correct: `$MIGRATION_DIR/terraform/main.tf`, `$MIGRATION_DIR/scripts/02-migrate-data.sh`, `$MIGRATION_DIR/MIGRATION_GUIDE.md`, `$MIGRATION_DIR/README.md`, `$MIGRATION_DIR/migration-report.html`.
- Forbidden: writing to project root (cwd), e.g. `./terraform/`, `./README.md`, `./MIGRATION_GUIDE.md`, `./scripts/`, `./discover_iac.py`, `./gen_summary.py`. The source project's own `README.md` MUST NOT be overwritten.
- Forbidden: emitting any Python / Node / Bash helper script to "parse" or "summarize" inventory. Use Read, Grep, and Glob directly. The only shell scripts written by Generate are the user-facing migration scripts under `$MIGRATION_DIR/scripts/`.

If the Write path you are about to use does not begin with `$MIGRATION_DIR`, STOP and fix it before calling the tool.

## Generate is a translation step, not a redesign step

The output of Design (`gcp-design.json`) is **FROZEN** once Design completes. Generate's job is to translate Design's decisions into Terraform HCL and supporting artifacts, not to revisit them.

- If Generate notices a Design mistake (e.g. wrong target service for a source, wrong `database_version`, an `aws_db_subnet_group` mis-classified as a `gcp_service: "Cloud SQL / Memorystore Configuration"`), it MUST:
  1. Write a `warnings[]` entry in `generation-infra.json` describing the discrepancy and pointing at the offending `aws_address` in `gcp-design.json`.
  2. Emit the Terraform that **matches Design** (not the Terraform that would have been "right" per Generate's own rubric). Design wins, every time.
  3. Surface the warning in the Phase Completion summary so the user knows to re-run Design.
- Re-running Design is the only legitimate way to change a Design decision. Generate has no authority to override Design even when Design is obviously wrong.
- This rule exists because Generate operating on `aws-resource-inventory.json` instead of `gcp-design.json` is the single largest failure mode observed in past iterations (Generate emitted `database_version = "POSTGRES_15"` for an Aurora MySQL source because it re-inferred from the source engine rather than consuming Design's `gcp_config.database_version`). The cure is: Generate consumes Design's decisions verbatim; the source inventory is consulted only for enumeration and image-URI extraction (see `generate-artifacts-infra.md` Step 1 — "Source of truth: gcp-design.json").

## Overview

The Generate phase has **2 mandatory stages** that run sequentially:

1. **Stage 1: Migration Planning** -- Produces execution plans (JSON) from estimation + design artifacts
2. **Stage 2: Artifact Generation** -- Produces deployable code (Terraform, scripts, adapters, docs) from plans + designs

Both stages must complete for the phase to succeed.

## Budget Guidance (Headless / Time-Constrained Runs)

When running headless under Gemini CLI or any LLM driver with a wall-clock budget (e.g. 15 minutes total), **prioritize file emission order** so partial completion still leaves the user with something usable. **Checkpoint to disk after EACH file is written** — do **not** buffer multiple files in memory and write at the end.

**Mandatory artifact emission order (highest priority first):**

1. `terraform/main.tf` (provider, default labels, backend stub) — minimal Terraform skeleton; user can run `terraform init` immediately.
2. `terraform/variables.tf` + `terraform/outputs.tf` (so the skeleton is valid HCL).
3. `terraform/vpc.tf` + `terraform/security.tf` (network + IAM foundation — every downstream resource depends on these).
4. `terraform/storage.tf` + `terraform/database.tf` (data layer — long-lead items in real migrations; emit early so users can review).
5. `terraform/compute.tf` (Cloud Run / GKE services).
6. `terraform/monitoring.tf` (dashboards, alerts).
7. `scripts/migrate-*.sh` (data migration scripts from `generate-artifacts-scripts.md`).
8. `user-journeys/index.md` plus per-journey `.md` files (parity narrative; cheap to emit and used by `MIGRATION_GUIDE.md` + the parity verification step in the feedback phase).
9. `user-journeys/<NNN>-<name>.mmd` + `.sh` (sequence diagrams and parity scripts — non-blocking; if the budget runs out after the narrative `.md` is written the user still has actionable content).
10. `MIGRATION_GUIDE.md`.
11. `README.md` and `terraform/README.md`.
12. `migration-report.html` (lowest priority — non-blocking; failure here does not fail the phase).

**Checkpointing rules:**

- After each file is written, the agent SHOULD log a single line like `wrote terraform/<file>` so a parent harness can observe progress in the transcript.
- If the agent runs out of budget, **do not** roll back already-written files. The user can re-run Generate; it should pick up from the missing files (Stage 2 sub-files already check for prior outputs).
- The Phase Completion check requires only Stage 1 + at least one Stage 2 artifact directory. Partial Stage 2 (e.g., only `terraform/main.tf` + `terraform/vpc.tf` exist) is still a partial success — surface it in the summary with a "resume" recommendation rather than failing.
- **Never** emit nothing. If you cannot generate `terraform/main.tf` for any reason (e.g., design output rejected), write a `MIGRATION_GUIDE.md` stub explaining the blocker so the user has actionable output.

## Prerequisites

1. Read `$MIGRATION_DIR/.phase-status.json`. If missing, invalid, `phases.clarify` is not exactly `"completed"`, `phases.design` is not exactly `"completed"`, or `phases.estimate` is not exactly `"completed"`: **STOP**. Output: "Phase 4 (Estimate) not completed or phase state is missing/invalid. Complete Estimate before Generate."
2. Read `$MIGRATION_DIR/preferences.json`. If missing: **STOP**. Output: "Phase 2 (Clarify) not completed. Run Phase 2 first."

Check which estimation artifacts exist in `$MIGRATION_DIR/`:

- `estimation-infra.json` (infrastructure estimation)
- `estimation-ai.json` (AI workload estimation)
- `estimation-billing.json` (billing-only estimation)

If **none** of these estimation artifacts exist: **STOP**. Output: "No estimation artifacts found. Run Phase 4 (Estimate) first."

## Stage 1: Migration Planning

Route based on which estimation artifacts exist. Multiple paths can run independently.

### Infrastructure Migration Plan

IF `estimation-infra.json` exists:

> Load `generate-infra.md`

Produces: `generation-infra.json`

### AI Migration Plan

IF `estimation-ai.json` exists:

> Load `generate-ai.md`

Produces: `generation-ai.json`

### Billing-Only Migration Plan

IF `estimation-billing.json` exists:

> Load `generate-billing.md`

Produces: `generation-billing.json`

## Stage 2: Artifact Generation

**MUST proceed only after Stage 1 completes.** Route based on generation plans + design artifacts.

### Infrastructure Artifacts

IF `generation-infra.json` AND `gcp-design.json` exist:

> Load `generate-artifacts-infra.md`

Produces: `terraform/` directory

After generate-artifacts-infra.md completes (terraform files generated),
load `generate-artifacts-scripts.md` to generate migration scripts.

Produces: `scripts/` directory

### AI Artifacts

IF `generation-ai.json` AND `gcp-design-ai.json` exist:

> Load `generate-artifacts-ai.md`

Produces: `ai-migration/` directory

### Billing Skeleton Artifacts

IF `generation-billing.json` AND `gcp-design-billing.json` exist:

> Load `generate-artifacts-billing.md`

Produces: `terraform/skeleton.tf` (with TODO markers)

### User Journeys (runs after scripts, before documentation)

AFTER `generate-artifacts-infra.md` + `generate-artifacts-scripts.md` complete (so `terraform/` and `scripts/` paths are stable for cross-reference) and BEFORE `generate-artifacts-docs.md` runs:

> Load `generate-artifacts-journeys.md`

Produces: `user-journeys/` directory (per-journey `.md` + `.mmd` + `.sh` plus `index.md`). On the missing-routes graceful-degradation path, produces only `user-journeys/user-journeys.md`. This sub-file MUST NOT fail Generate — it always either emits journeys or the single-line skip sentinel.

### Documentation (ALWAYS runs after artifact generation)

AFTER all above artifact generation sub-files complete (including user-journey synthesis):

> Load `generate-artifacts-docs.md`

Produces: `MIGRATION_GUIDE.md`, `README.md`

### HTML Report (ALWAYS runs last, after documentation)

AFTER generate-artifacts-docs.md completes:

> Load `generate-artifacts-report.md`

Produces: `migration-report.html`

**Non-blocking:** If report generation fails, log a warning and continue to Phase Completion. Do not fail the phase.

## Phase Completion

Verify both stages are complete:

1. **Stage 1**: At least one `generation-*.json` file exists
2. **Stage 2**: At least one artifact directory or file was produced, plus documentation (HTML report is optional -- its absence does not block completion)

Use the Phase Status Update Protocol (Write tool) to write `.phase-status.json` with `phases.generate` set to `"completed"` -- **in the same turn** as the summary below.

## Summary

Present final summary to user:

1. **Plans generated** -- List all `generation-*.json` files produced
2. **Artifacts generated** -- List all directories and files created (terraform/, scripts/, ai-migration/, MIGRATION_GUIDE.md, README.md, migration-report.html)
3. **Key timelines** -- Highlight migration timeline from the generation plans
4. **Key risks** -- Highlight top risks from the generation plans
5. **TODO markers** -- Note any TODO markers in generated artifacts that require manual attention
6. **Next steps** -- Recommend reviewing generated artifacts, customizing TODO sections, and beginning migration execution

Output to user: "Migration artifact generation complete. All phases of the AWS-to-GCP migration analysis are complete. Your migration report is ready at $MIGRATION_DIR/migration-report.html"
