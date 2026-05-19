# Phase 3: Design GCP Architecture (Orchestrator)

**Execute ALL steps in order. Do not skip or optimize.**

## Prerequisites

1. Read `$MIGRATION_DIR/.phase-status.json`. If missing, invalid, or `phases.clarify` is not exactly `"completed"`: **STOP**. Output: "Phase 2 (Clarify) not completed or phase state is missing/invalid. Run `references/phases/clarify/clarify.md` until Clarify finishes and `.phase-status.json` shows `phases.clarify`: `completed`."
2. Read `$MIGRATION_DIR/preferences.json`. If missing: **STOP**. Output: "Phase 2 (Clarify) not completed. Run Phase 2 first."

Check which discovery artifacts exist in `$MIGRATION_DIR/`:

- `aws-resource-inventory.json` (IaC discovery ran)
- `aws-resource-clusters.json` (IaC discovery ran)
- `billing-profile.json` (billing discovery ran)
- `ai-workload-profile.json` (AI workloads detected)
- `aws-sdk-usage.json` (non-AI AWS SDK call sites detected — drives source-code rewrite planning in `design-infra.md` Step 4.7)

If **none** of these artifacts exist: **STOP**. Output: "No discovery artifacts found. Run Phase 1 (Discover) first."

## Routing Rules

### Infrastructure Design (IaC-based)

IF `aws-resource-inventory.json` AND `aws-resource-clusters.json` both exist:

-> Load `design-infra.md`

Produces: `gcp-design.json`

### Billing-Only Design (fallback)

IF `billing-profile.json` exists AND `aws-resource-inventory.json` does **NOT** exist:

-> Load `design-billing.md`

Produces: `gcp-design-billing.json`

### AI Workload Design

IF `ai-workload-profile.json` exists:

-> Load `design-ai.md`

Produces: `gcp-design-ai.json`

### Mutual Exclusion

- **design-infra** and **design-billing** never both run (billing-only is the fallback when no IaC exists).
- **design-ai** runs independently of either design-infra or design-billing (no shared state). Run it after the infra/billing design completes.

## Phase Completion

After all applicable sub-designs finish, use the Phase Status Update Protocol (Write tool) to write `.phase-status.json` with `phases.design` set to `"completed"` -- **in the same turn** as the output message below.

Output to user: "GCP Architecture designed. Proceeding to Phase 4: Estimate Costs."

## Reference Files

Sub-design files may reference rubrics in `design-refs/`:

- `design-refs/index.md` -- AWS type -> rubric file lookup
- `design-refs/fast-path.md` -- Direct (table) mappings vs rubric path; **User-facing vocabulary** for presenting `confidence` to users (**Standard pairing** / **Tailored to your setup** / **Estimated from billing only**)
- `design-refs/compute.md` -- Compute service rubric
- `design-refs/database.md` -- Database service rubric
- `design-refs/storage.md` -- Storage service rubric
- `design-refs/networking.md` -- Networking service rubric
- `design-refs/messaging.md` -- Messaging service rubric
- `design-refs/ai.md` -- AI/ML service rubric
- `design-refs/sdk-mapping.md` -- per-language `aws-sdk-*` -> `google-cloud-*` call-site rewrite rubric (consumed by `design-infra.md` Step 4.7 to produce `sdk-migration-plan.json`)

## Scope Boundary

**This phase covers architecture mapping ONLY.**

FORBIDDEN -- Do NOT include ANY of:

- Cost calculations or pricing estimates
- Execution timelines or migration schedules
- Terraform or IaC code generation
- Risk assessments or rollback procedures
- Team staffing or resource allocation

**Your ONLY job: Map AWS resources to GCP services. Nothing else.**
