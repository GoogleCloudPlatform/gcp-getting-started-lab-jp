# Phase 5: Generate Migration Artifacts

**Execute ALL steps in order. Do not skip or optimize.** This file is self-contained — no sub-files.

> **Mandatory-artifact discipline (headless / time-constrained runs):** every artifact in the table below
> that applies to this run is MANDATORY, and a sentinel or stub never substitutes for a real artifact. If
> any MANDATORY artifact is missing or fails a gate at phase end, write `phases.generate = "failed"` (NOT
> `"completed"`). `"failed"` is a legal, RESUMABLE status: the next run re-enters Generate, consults
> `generation-validation.json`, and regenerates ONLY missing or failing artifacts. Record what was dropped
> and why in `generation-validation.json.budget_skipped[]`. Checkpoint to disk after EACH file (log one
> line, e.g. `wrote terraform/main.tf`); never buffer to the end; never roll back an already-written file;
> NEVER emit nothing — if Terraform is blocked, still write the migration guide explaining the blocker.

| # | Artifact (all under `$MIGRATION_DIR`)  | Emitted for                                                      | Order                   |
| - | -------------------------------------- | ---------------------------------------------------------------- | ----------------------- |
| 1 | `terraform/` (Steps 2-3)               | all runs                                                         | 1st                     |
| 2 | `scripts/01-validate-prerequisites.sh` | all runs                                                         | 2nd                     |
| 3 | `scripts/02-cutover-checklist.sh`      | all runs                                                         | 3rd                     |
| 4 | `M2VM-RUNBOOK.md`                      | any Compute Engine row migrated with Migrate to Virtual Machines | 4th                     |
| 5 | `GKE-RUNBOOK.md`                       | any GKE or Cloud Run target from an AKS / Container Apps source  | 5th                     |
| 6 | `DATA-MIGRATION-RUNBOOK.md`            | any storage or database row                                      | 6th                     |
| 7 | `MIGRATION_GUIDE.md`                   | all runs                                                         | 7th                     |
| 8 | `README.md`                            | all runs                                                         | 8th                     |
| 9 | `generation-validation.json`           | all runs                                                         | updated after each file |

A run with no compute rows emits no M2VM runbook and that is not a failure — applicability is decided by
`gcp-design.json`, and `generation-validation.json` records only the artifacts that apply.

## File output discipline (before writing anything)

Every file MUST live under `$MIGRATION_DIR` (= `.migration/<MMDD-HHMM>/`, set in Discover Step 0). Before
EVERY Write: if the path does not begin with `$MIGRATION_DIR`, STOP and fix it. Forbidden: writing to the
user project root (a root-level `terraform/`, README, or guide); overwriting the source project's own
README; emitting ANY helper or parser script (banned stems in `SKILL.md`); emitting application source
code; and writing any secret value, connection string, client secret, SAS token or access key into any
artifact. The ONLY shell scripts Generate writes are the two user-facing scripts in the table. Nothing
Generate writes is ever executed against Azure or Google Cloud by this skill — artifacts are for user
review and manual execution.

## Generate is a translation step, not a redesign step

`gcp-design.json` is FROZEN. Generate translates Design's decisions into artifacts verbatim; it consults
`azure-inventory.json` only to enumerate resources and copy per-resource facts. If Generate notices a
Design mistake: (1) append a `warnings[]` entry in `generation-validation.json` naming the offending
`source_id`; (2) emit the artifact that MATCHES Design anyway — Design wins, every time; (3) surface the
warning in the completion summary and recommend re-running Design. A decision not recorded in
`preferences.json.design_choices[]` or `gcp-design.json` may not shape any artifact. **Branch on
`disposition`:** rows with `deferred` (`gcp_service` = `Deferred — specialist engagement`, or its ASCII
forms `Deferred -- specialist engagement` / `Deferred - specialist engagement`) or `needs-decision` get NO
Terraform, NO runbook steps, NO invented tasks — they appear ONLY in the callouts of the migration guide
and runbook prefaces, verbatim from Design. Only `mapped` rows become artifacts.

**Command honesty (binding):** every command in every artifact must come from the verified facts inlined
in this file's steps or from official docs you fetch NOW (`registry.terraform.io`,
`docs.cloud.google.com`, `learn.microsoft.com` — the `microsoft-learn` MCP first for Azure-side
commands). Cite the URL in a comment. Where no stable CLI surface is confirmed, write the console or API
step honestly. **NEVER invent a `gcloud`, `az`, or Terraform name, flag or argument.** If a fetch fails or
returns empty (registry pages are JS-rendered and often return empty bodies), emit a `# TODO(verify):`
comment, add a `warnings[]` entry, and append a `"skipped"` ledger entry — visible degradation, never
silent.

## Step 0: Prerequisites (STOP conditions)

1. Read `$MIGRATION_DIR/.phase-status.json`. If missing/invalid, or ANY of `phases.clarify`,
   `phases.design`, `phases.estimate` is not exactly `"completed"`: **STOP** — "Generate requires
   completed Clarify, Design and Estimate phases." (Clarify is MANDATORY — no exceptions.)
2. Read `preferences.json`, `gcp-design.json`, `estimation.json`. Any missing: **STOP**, naming the file
   and its phase.
3. **Pricing-evidence gate:** every `estimation.json.resources[]` row carrying a dollar figure MUST have
   `pricing.attempts[]` with a `tool_call` and non-empty `evidence`, a `source` from the binding chain,
   plus its `sizing_mode`, `pricing.fetched_at`, `pricing.sku_rate`, `pricing.assumed_quantity` and
   `pricing.calculation`. Any priced row failing any of these: **STOP** — "Estimation rows lack pricing
   evidence — re-run Estimate." Record each rejected row in `generation-validation.json.warnings[]`
   (creating the file with the Step 1 schema if needed) and append a `"fail"` ledger entry.
   `external_costs[]` and Deferred rows are exempt — they carry no dollars.
4. **Gate-carriage check:** if any Deferred row carries a `gcp_config`, or any M2VM-ineligible VM appears
   in a migration wave, **STOP** — that is a Design defect, not something to work around here.
5. Set `phases.generate = "in_progress"` via the Phase Status Update Protocol (Write complete file, no
   prior Read). On re-entry after `"failed"`: consult `generation-validation.json` and skip artifacts
   already passing all gates.

## Step 1: Initialize `generation-validation.json`

Write it per `references/shared/schema-artifacts.md` §9. After EACH artifact, evaluate its gates and
rewrite the COMPLETE file with the appended entry (replacing any prior entry for the same path, never
losing the others). Gate meanings — `present`: the file exists at the exact contract path; `non_empty`:
real content, not a placeholder; `references_design`: the content is traceable to `gcp-design.json` by
the concrete checks in Steps 2-7.

## Step 2: `terraform/` — shared files

**Load `references/shared/companion-skills.md` before writing any HCL in Steps 2-4.** For each target
service, resolve the matching google/skill by its protocol and follow its guidance on resource shape and
defaults. It never overrides Design's decisions, a recorded `design_choices[]` pick, or a gate — where it
disagrees with `gcp-design.json`, Design wins and the disagreement becomes a `warnings[]` entry.

- `terraform/main.tf` — a `terraform` block with `required_providers` (google provider), a
  `provider "google"` using `var.project_id` / `var.region` (region from `preferences.json.region`), and
  `default_labels` including `migration_id` and `source = "azure"`. Backend left as a commented stub.
- `terraform/variables.tf` + `terraform/outputs.tf` — every value consumed from `gcp-design.json` enters
  through a variable with a default copied from Design; outputs cover network self-links and the key
  resource ids. The skeleton must be valid HCL immediately.
- `terraform/network.tf` — `google_compute_network` (custom subnet mode), one `google_compute_subnetwork`
  per subnet in `gcp-design.json.network`, and a `google_compute_firewall` baseline containing ONLY rules
  and ranges present in Design. Missing source ranges or ports -> a `# TODO(verify):` comment; never
  invent a CIDR and never open `0.0.0.0/0`.
- `terraform/connectivity.tf` — **PLACEHOLDER ONLY** when the design has Azure coexistence connectivity: a
  comment block plus `# TODO(manual):` describing the chosen product (Cloud Interconnect or Cloud VPN),
  because ordering a cross-cloud circuit is a manual partner/console workflow with lead time. Name the
  design's choice, the manual ordering step, and where the attachment values will later go. Do NOT emit
  attachment resources with fabricated arguments.
- `terraform/psc.tf` — one commented block per `[PRIVATE_ENDPOINT]` finding carried into Design, naming
  the consuming resource and the DNS override that must be rebuilt. Confirm resource names against the
  registry before emitting HCL; otherwise `# TODO(verify):`.

## Step 3: `terraform/` — workload files

- `terraform/modules/migrated-instance/` (`main.tf`, `variables.tf`) — ONE reusable module wrapping
  `google_compute_instance`: variables for name, machine_type, zone, boot and data disks (sizes from
  Design's `sizing_mode`-resolved values), subnetwork, service account, and labels (must include
  `source_id`). Verify any argument you are not certain of against the registry, or `# TODO(verify):` it.
- `terraform/instances.tf` — one `module "<source_id>"` block per Compute Engine row in
  `gcp-design.json` whose `disposition` is `mapped` (never `deferred`, never `needs-decision`), values
  copied verbatim from `gcp_config`. **MANDATORY header comment:** Migrate to Virtual Machines CREATES the target instances at
  cut-over — these blocks codify the approved target state for review and for post-migration
  `terraform import` adoption; do NOT `terraform apply` compute resources before cut-over (network and
  firewall may be applied ahead).
- `terraform/managed-services.tf` — one block per managed-service row (Cloud SQL, GKE, Cloud Run, Cloud
  Storage, Pub/Sub, Artifact Registry, Secret Manager, Memorystore, load balancing/CDN), values copied
  verbatim from `gcp_config`. **Secret Manager blocks create the secret resource, never a secret
  version with a value** — the value is added by the user out of band, stated in a comment.
- `terraform/iam.tf` — service accounts and IAM bindings from `gcp-design.json.identity`, including the
  Workload Identity Federation for GKE bindings where the design uses them. No keys, ever.
- **`references_design` gate for this step:** the instance-module count equals the eligible Compute Engine
  row count, every block label maps to a distinct `source_id`, and every managed-service row in Design has
  a block or an explicit `# TODO(verify):` naming it. One generic block standing in for many resources is
  a gate failure.

## Step 4: `scripts/`

- `scripts/01-validate-prerequisites.sh` — `set -euo pipefail`; read-only and enablement checks ONLY:
  (1) `gcloud auth list` and `gcloud config get-value project` with clear failure messages; (2)
  `gcloud services enable` for the APIs this design actually needs (include `vmmigration.googleapis.com`
  only when there are M2VM rows — that host-project service list is documented at
  https://docs.cloud.google.com/migrate/virtual-machines/docs/5.0/get-started/enable-services, which also
  requires `servicemanagement`, `servicecontrol`, `iam`, `cloudresourcemanager` and `compute`); (3) a
  quota section of echo-driven operator checks — Compute CPU, disk
  and IP quota in `preferences.region`, with console paths; do not script quota commands you have not
  verified; (4) an org-policy section of echo notes, including an OS Login note
  (`constraints/compute.requireOsLogin` affects first login to migrated VMs — when enforced it adds
  `enable-oslogin=true` to new projects and rejects requests setting it false, so plan break-glass access
  before cut-over; https://docs.cloud.google.com/compute/docs/oslogin/manage-oslogin-in-an-org) and a
  note to confirm any domain-restricted-sharing constraint before cross-org federation.
- `scripts/02-cutover-checklist.sh` — echo-driven checklist ONLY, **ZERO destructive commands** (nothing
  that deletes, stops or mutates anything): change freeze confirmed; final replication or sync current;
  test-clone validated; DNS and addressing plan staged per `preferences.network_mode`; rollback criteria
  and decision owner named; post-cutover finalize step done; leftover test clones deleted (they keep
  billing); Azure source resources retained until the validation window closes.
- **`references_design` gate:** the scripts echo this run's actual region, project variable, artifact
  paths and API list — not generic boilerplate.

## Step 5: `M2VM-RUNBOOK.md` (when any row migrates with Migrate to Virtual Machines)

Numbered sections, strictly from the facts inlined here or docs you fetch now:

1. **Azure-side source setup — four steps.** Register an app on the Azure portal App Registration page;
   add a client secret and **copy the value at creation, because it cannot be retrieved later** from the
   Azure portal or the Google Cloud console; create a custom role; assign that role to the registered
   app. Cite
   https://docs.cloud.google.com/migrate/virtual-machines/docs/5.0/migrate/create-an-azure-source.
2. **Immutable-at-creation banner.** Google Cloud region, Azure location, Name, Subscription ID and
   Tenant ID cannot be edited after the source is created; a typo in the region means the source never
   becomes Active and must be recreated. Print the exact values from `preferences.json` and
   `azure-inventory.json` for the operator to check **before** creating the source.
3. **Host-project prerequisites.** Enable the VM Migration API on the host project; a maximum of 15 cloud
   sources (AWS and Azure combined) per host project; a new source can take up to 15 minutes to become
   Active. Source: the Azure VM migration guide linked in `references/shared/service-map.md`.
4. **Eligibility exclusions, by name.** List every `[EPHEMERAL_OS_DISK]` and `[UNMANAGED_DISK]` VM with
   its Clarify disposition verbatim. State plainly that these fail migration with an error and are NOT in
   any wave. List every `[ADE_ENCRYPTED]` VM with its friction note and the 2028-09-15 ADE retirement.
5. **Lifecycle steps.** Verify the CURRENT `gcloud` / console / API surface for sources, onboarding,
   replication, test-clone and cut-over before writing any command — do not assume a CLI verb exists.
   Where no stable CLI surface is confirmed, write the Google Cloud console step or the VM Migration API
   call, and say which. Never invent a command.
6. **Replication and test-clone.** Monitor per-VM replication to steady state; test-clone each VM per
   wave, validate the application and OS, then DELETE the clone — leftovers keep billing. Note that
   temporary-disk data is not guaranteed to survive clone or cut-over.
7. **Cut-over and finalize.** Per-wave cut-over; the target instance values must match
   `terraform/instances.tf`; finalize to stop replication billing.
8. **Rollback.** The Azure source VM is the rollback asset — do not decommission it until the validation
   window closes. Rollback is process, not product commands: stop using or delete the target instance,
   restart the Azure VM if it was stopped for cut-over, revert DNS per the checklist.
9. **Domain controllers.** NEVER image-migrate a live DC — stand up a new DC and use AD replication
   (promote, transfer roles, demote source); cloning a DC image risks USN rollback. Applies to every
   resource Design flagged as a DC.
10. **Per-guest notes**, carried verbatim from Design: EOL and Windows client guests are "migration
    support only"; Windows client guests additionally carry the `Q_LICENSE` constraints; the licensing
    strategy recorded in `preferences.license_strategy` is stated once, unedited.
11. **Sizing note.** State that **no M2VM utilization report exists for Azure sources** and name the
    actual sizing evidence used (`preferences.sizing_source`), so nobody looks for a report that is not
    there.

## Step 6: `GKE-RUNBOOK.md` and `DATA-MIGRATION-RUNBOOK.md`

**`GKE-RUNBOOK.md`** (AKS -> GKE, or Container Apps/App Service -> Cloud Run): there is no cluster-lift
tool, so this is a redeploy runbook. Sections: cluster creation per the recorded Autopilot/Standard
choice; image re-hosting into Artifact Registry; manifest review (admission controllers, CSI drivers,
node selectors and DaemonSets that assume AKS); Workload Identity Federation for GKE bindings replacing
the AKS pod-identity pattern, including the coexistence case where an Entra federated credential is
re-pointed at the GKE service account; ingress and certificate rebuild; a per-workload cutover table with
one row per Design row; and rollback by DNS/traffic weight while the AKS cluster still runs.

**`DATA-MIGRATION-RUNBOOK.md`**, one section per data row, each naming the method Design recorded:

- **Blob Storage -> Cloud Storage via Storage Transfer Service.** Give the three supported auth methods —
  SAS token (inline or in Secret Manager), Azure Shared Key (Secret Manager only), and Azure workload
  identity federation — and **recommend the federation path**, with the SAS caveat stated in Google's own
  terms: basic SAS tokens cannot be revoked, so tokens should be created from stored access policies. For
  the federation path give the exact field values: Issuer `https://accounts.google.com`, Audience
  `api://AzureADTokenExchange`, Subject identifier = the `subjectId` of your Google service agent, an
  Azure custom role with blob `read` (plus `delete` only if deleting at source), and
  `roles/iam.serviceAccountTokenCreator` on the service agent
  (https://docs.cloud.google.com/storage-transfer/docs/source-microsoft-azure). Cover run-once versus
  scheduled jobs and a final delta sync at cutover.
- **Azure SQL Database / Managed Instance -> Cloud SQL for SQL Server.** State up front that **DMS is not
  the homogeneous path for Azure SQL sources** — no Azure source appears in the DMS homogeneous
  SQL Server to Cloud SQL for SQL Server table. Use BACPAC export via SqlPackage for one-time or
  scheduled-maintenance migrations (recommended especially at hundreds of GB and larger), or Managed
  Instance link plus DMS for minimal-downtime continuous replication from MI.
- **Azure Database for MySQL / PostgreSQL Flexible Server -> Cloud SQL.** Built-in engine backups for
  one-time migrations; DMS for continuous replication, with pglogical for PostgreSQL. If the design chose
  AlloyDB for a PostgreSQL source, say plainly that the DMS homogeneous listing covers Cloud SQL for
  PostgreSQL and not AlloyDB, and give the method Design actually recorded.
- **Azure Files.** Per protocol: NFS to Filestore, SMB to NetApp Volumes with its Active Directory
  prerequisite spelled out (NetApp Volumes joins the domain and does not support workgroup mode).
- **Cosmos DB.** Only the target recorded by `Q_MAP.cosmos`, described as an export-and-rewrite with no
  lift tool. Gremlin and Table accounts appear only in the Deferred callout.

Runbook `references_design` gate: the wave and step tables list every eligible Design `source_id` exactly
once; Deferred and `needs-decision` resources appear ONLY in the preface callout.

## Step 7: `MIGRATION_GUIDE.md` and `README.md`

`MIGRATION_GUIDE.md` MUST contain: (1) a phase recap — per phase, artifacts produced plus headline
numbers (resource count, monthly total, region); (2) **Headless assumptions** — `headless_defaults_applied[]`
and the matching `design_choices[]` entries copied VERBATIM, including every banner; (3) **Warnings and
traps** — EVERY warning carried from `azure-inventory.json`, `gcp-design.json` (top-level and
per-resource) and estimation notes, none dropped; (4) **External costs** — every `external_costs[]` item
listed as a procurement or coexistence item with NO invented dollar figures; (5) **Deferred and
needs-decision callout** — the analytics gate rows, Cosmos Gremlin/Table, M2VM-ineligible VMs, EOL and
Windows client guests, all verbatim, with no config and no dollars; (6) **Licensing advisory** — the
`license_strategy` verbatim plus the comparability verdict from
`estimation.json.comparison_to_azure.discount_normalization`, stated in plain language; (7) **Source-side
deadlines** the customer owns regardless of this migration (legacy Service Bus SDK retirement, ADE
retirement, any EOL runtime); (8) next steps. `references_design` gate: sections 2-7 are present whenever
their source data exists.

`README.md` (the run's own, at `$MIGRATION_DIR/README.md` — NEVER the project root): the artifact map,
which runbook to start with, resume instructions (`"failed"` re-enters Generate), and a safety note that
nothing here executes automatically and no credential is stored in any of it.

## Step 8: Phase Completion

1. Evaluate `generation-validation.json`: every applicable MANDATORY artifact must be `present`,
   `non_empty` and `references_design`. Any failure -> list it in `budget_skipped[]` with a reason, write
   `phases.generate = "failed"` (resumable), and tell the user exactly what to re-run. All pass ->
   `"completed"`.
2. Append this phase's ledger entries (pricing-evidence gate, gate-carriage gate, artifact-gates roll-up).
   **Ledger resume rule:** on session resume, Read `validation-ledger.json` ONCE before this session's
   first append; the no-prior-Read protocol applies to `.phase-status.json` only.
3. **Post-phase write audit** per the `SKILL.md` protocol; any session-written path outside
   `$MIGRATION_DIR` -> STOP, list offenders, instruct removal, record a `"fail"` entry.
4. Update `.phase-status.json` via the Phase Status Update Protocol in the SAME turn as the summary.
5. Summary: artifacts written; `TODO(verify)` / `TODO(manual)` markers needing attention; Deferred and
   `needs-decision` items awaiting decisions; every `fail`/`corrected`/`skipped` ledger entry; external
   costs to procure. Close with: "Migration artifact generation complete. Review
   $MIGRATION_DIR/MIGRATION_GUIDE.md, then start with scripts/01-validate-prerequisites.sh."
