# Phase 1: Discover the Azure Estate

Self-contained discovery for a Microsoft Azure source estate. Inventory what exists on the Azure side —
nothing else. **Execute ALL steps in order. Do not skip or deviate.**

Parsing rules for every source type live in `references/shared/iac-parsing.md` and
`references/shared/billing-exports.md`; artifact schemas live in `references/shared/schema-artifacts.md`.
Load each one before you first need it.

## Step 0: Initialize Migration State

1. Check for an existing `.migration/` directory at the project root.
   - **If existing runs found:** list them with their phase status and ask:
     `[A] Resume: continue with <latest run>` / `[B] Fresh: create a new migration run` / `[C] Cancel`.
   - **If resuming:** set `$MIGRATION_DIR` to the selected run's directory, read its `.phase-status.json`
     (session-resume detection — the other sanctioned Read is each phase's entry gate; what is forbidden
     is reading it just before the completion Write) and jump to the right phase per the State Machine.
   - **If fresh or no existing runs:** continue to step 2.
2. Create `.migration/[MMDD-HHMM]/` from the current timestamp. Set `$MIGRATION_DIR` to it.
3. Create `.migration/.gitignore` (if not already present) with exact content:

   ```text
   # Migration runtime state. Add `.migration/` to your project's root .gitignore
   # to keep these artifacts out of source control. We do NOT put a `*` pattern
   # here because Claude Code and other agentic CLIs honor `.gitignore` for their
   # file-read sandbox — a `*` here would block the skill from reading its own
   # outputs (azure-inventory.json, gcp-design.json, etc.) in later phases.
   ```

   This is a comment-only file. The user adds `.migration/` to the **project root** `.gitignore`
   themselves — the skill NEVER modifies it. Caveat that creates: a root-gitignored `.migration/` can be
   hidden from ignore-respecting Glob, so resume detection in step 1 MUST enumerate runs by direct path
   Reads of `.migration/*/.phase-status.json` (Bash `ls .migration/`, then Read each), never by Glob.

4. Write `$MIGRATION_DIR/.phase-status.json` with `discover: "in_progress"` and every other phase
   `"pending"` (schema in `references/shared/schema-artifacts.md` §7).
5. Confirm both files exist before Step 1.
6. If the project is a git repo, run `git status --porcelain` ONCE now and keep the output as the
   phase-start baseline for Step 9's write audit — paths already dirty here are the user's, out of scope.

## Step 1: Detect Input Sources

Glob the project for each input type; process only what is present. **Parsing is Read/Grep/Glob ONLY —
helper parser scripts are BANNED (see the banned-stem list in `SKILL.md`). The SINGLE sanctioned
exception is `$MIGRATION_DIR/_extract_cost.*` in Step 4.**

- **1a. Terraform (`azurerm`)** — Glob `**/*.tf`, `**/*.tfvars`, `**/*.tfstate`; Grep the matches for
  `azurerm_` and `"azurerm"`. A `.tfstate` outranks `.tf` for resolved values (variables are already
  interpolated) — record which you used per resource.
- **1b. Bicep** — Glob `**/*.bicep`.
- **1c. ARM templates** — Glob `**/*.json`, then Grep for `deploymentTemplate` in `$schema` to separate
  templates from unrelated JSON. Also Grep for `"languageVersion"` to pick the right `resources` shape.
- **1d. Application code** — Glob source trees and dependency manifests (`requirements.txt`,
  `pyproject.toml`, `package.json`, `*.csproj`, `pom.xml`, `build.gradle`, `go.mod`), then Grep for the
  detection patterns in `references/shared/sdk-map.md`.
- **1e. Azure cost export** — Glob `**/*cost*.csv`, `**/*cost*.csv.gz`, `**/*usage*.csv{,.gz}`,
  `**/*focus*.csv{,.gz}`, `**/*billing*.csv{,.gz}`, `**/*reservation*.csv{,.gz}`, `**/_manifest.json`, `**/*.parquet`. Confirm by
  reading the header line only (dataset table in `references/shared/billing-exports.md`). A
  `_manifest.json` means a partitioned export — read it to enumerate partitions rather than guessing
  filenames. Parquet -> STOP for that file and ask for CSV.
- **1f. Azure Migrate / `mcdc` export** — Glob `**/*.xlsx` (assessment exports),
  `**/metadata.json` alongside `**/data.*.json`, and `**/*mc-frames*.zip`.
- **1g. `az resource list` JSON** — Glob `**/*.json` and Grep for `"type": "Microsoft.` alongside
  `"id": "/subscriptions/`.

**If NONE matched:** STOP and output: "No Azure sources detected. Provide at least one: azurerm
Terraform, Bicep, ARM templates, application code with Azure SDK calls, an Azure cost export (CSV), an
Azure Migrate or mcdc export, or `az resource list` JSON. Then re-run Discover."

**If the sources are clearly NOT Azure** (for example `aws_*` Terraform, `oci_ocvp_*`, RVTools CSVs):
STOP and name the right skill — `aws-to-gcp` for AWS; Oracle Cloud VMware Solution / vSphere sources are out of scope for this plugin.
Do not partially inventory an out-of-scope estate.

## Step 2: Build `azure-inventory.json`

Always written, even when no per-resource source exists: an empty `resources: []` plus
`[PARTIAL_INVENTORY] no per-resource source data — inventory is cost-export-only` keeps the phase chain
alive. Clarify hard-requires this artifact.

Precedence when the same resource appears in several sources, highest first:
**`.tfstate` -> `az resource list` -> `.tf`/`.bicep`/ARM -> Azure Migrate export -> cost export ->
app code.** Record the winning source in `source` and every contributing source in `source_ref`.

Per dialect, follow `references/shared/iac-parsing.md` exactly. The rules that most often get skipped:

- **Bicep symbolic name is not the resource name** — the symbolic name goes in `source_ref`, the `name`
  property goes in `name`.
- **`existing` Bicep declarations are excluded** from the created-resource inventory and recorded as
  dependency evidence instead.
- **ARM `languageVersion: "2.0"`** makes `resources` an object keyed by symbolic name, not an array.
- **Copy loops / `for` loops** with a statically resolvable count produce one row per iteration; an
  unresolvable count produces ONE row carrying the expression plus `[PARTIAL_IAC]`.
- **Never evaluate `reference()`** — its value does not exist in the template text.
- **Unresolved registry/template-spec modules and absolute-URI linked templates** are recorded as
  `[PARTIAL_IAC]`, never guessed.
- **Legacy `azurerm` names are parsed** (`azurerm_virtual_machine`, `azurerm_app_service`,
  `azurerm_sql_server`, `azurerm_postgresql_server`, `azurerm_mysql_server`, `azurerm_function_app`,
  `azurerm_virtual_machine_scale_set`) — they are real source estate. Generation never emits them.
- **Scale-set orchestration mode comes from the resource NAME** (`azurerm_orchestrated_*` = Flexible;
  `azurerm_linux/windows_virtual_machine_scale_set` = Uniform). Record it — it is not recoverable later.

Write the file per `references/shared/schema-artifacts.md` §1. **Never drop a row**: stopped VMs,
zero-capacity scale sets, orphaned disks and conditionally-deployed resources all stay in `resources[]`.
Dispositions belong to Clarify.

## Step 3: Cross-source reconciliation (drift and coverage)

Run this whenever two or more source types matched. Both outputs are decision-shaping, so compute them
even when they are unflattering.

1. **`[IAC_DRIFT]`** — a resource present in IaC but absent from the cost export or `az resource list`
   (or vice versa), or the same resource with a different SKU/size between sources. One warning per
   disagreement, naming both sources and both values. Do NOT silently prefer one.
2. **`[PARTIAL_IAC]` coverage ratio** — when a cost export exists, compute
   `distinct resources in IaC / distinct billed resource ids in the export`. Below roughly half, emit
   `[PARTIAL_IAC] IaC covers <n> of <m> billed resources (<p>%) — the estate is larger than the code`.
   State the number; do not editorialize beyond it.
3. **Stopped-but-allocated detection** — **any** VM a cost source bills for compute while any discovery
   source reports it stopped or suspended is `[STOPPED_NOT_DEALLOCATED]`. The signal is cost plus power
   state, never IaC presence: a ClickOps VM that never entered the templates bills identically, and there
   this co-fires with `[IAC_DRIFT]`. Power state comes from an assessment export or
   `az vm list --show-details`, which shows "public ip address, FQDN, and power states" and "will run
   slow" (https://learn.microsoft.com/en-us/cli/azure/vm) — never from a plain `az resource list`. One of
   the most common real-world cost surprises; give it an explicit line in the summary.

## Step 4: Build `azure-cost-profile.json` (from 1e; skip with a warning if no cost file)

Follow `references/shared/billing-exports.md` end to end: identify the dataset and version from the
header, pick `cost_basis` (`EffectiveCost` for FOCUS), bucket on the **inclusive** `ChargePeriodStart`,
resolve column names through the version alias map (1.2-preview renames `x_InvoiceId` -> `InvoiceId`,
`x_PricingCurrency` -> `PricingCurrency`, `x_SkuMeterName` -> `SkuMeter`), and populate
`discount_normalization` including `unused_reservation_cost` (or `null` with the reason — 1.2-preview
FOCUS cannot express it).

Size check first via Bash `wc -l` + `ls -l`, then either an in-context Read (<= 200 rows AND <= 1 MB) or
the single sanctioned `_extract_cost.*` helper, deleted immediately after its one run.

## Step 5: Resolve compute specs (live, or leave null)

Azure VM size strings (`Standard_D4s_v5`) do not carry their vCPU and memory counts, and **this skill
never expands a size string from recall.** In precedence order:

1. An Azure Migrate assessment export or `mcdc` export that already states cores/memory -> use it.
2. `microsoft-learn` MCP (`microsoft-learn:microsoft_docs_search`) or WebFetch of the matching
   `learn.microsoft.com` VM-sizes page -> use it, and record the URL in the row's `source_ref`.
3. Neither available -> leave `vcpu` and `memory_gib` as `null`, add
   `[UNRESOLVED_SOURCE_FIELD] <vm>: size <name> not resolved to cores/memory`, and record a `skipped`
   ledger entry.

A `null` here is honest and recoverable; a guessed core count silently corrupts every downstream
estimate. The same rule applies to App Service plan SKUs, database SKUs and scale-set instance sizes.

## Step 6: Build `adjacent-services.json`

Scan ALL detected sources for services adjacent to the migrating workloads. Record VERBATIM evidence
strings. Leave `candidate_strategies` as `[]` — Clarify populates it. **Discover names no GCP services
and no strategies.** Set `gate` per item so Clarify knows which advisory it arms:

- **`identity`** — Entra ID / Azure AD signals: `azurerm_*_active_directory_*`, `Microsoft.AAD/*`,
  managed identity blocks, `DefaultAzureCredential` in code, AD-joined VM extensions, an Azure Files
  share with AD authentication, `azuread_` provider usage.
- **`licensing`** — Windows Server or SQL Server images, `license_type = "Windows_Server"` /
  `"Windows_Client"` / `"AHUB"`, `azurerm_mssql_*`, SQL Server VM extensions, or cost-export meters
  matching `/windows|sql server/i`. Any AHB signal also raises `[AHB_SIGNAL]` on the resource.
- **`analytics`** — Synapse, Microsoft Fabric, Databricks, HDInsight, Data Explorer/Kusto, Stream
  Analytics, Data Factory: `Microsoft.Synapse/*`, `Microsoft.Databricks/*`, `Microsoft.Kusto/*`,
  `Microsoft.StreamAnalytics/*`, `Microsoft.DataFactory/*`, `azurerm_synapse_*`,
  `azurerm_databricks_workspace`, `azurerm_kusto_*`, `azurerm_data_factory*`, or cost meters matching
  `/synapse|databricks|data explorer|stream analytics|data factory|fabric/i`.
- **`datastore`** — `Microsoft.DocumentDB/*` / `azurerm_cosmosdb_*` (record the API flavor from `kind`
  and `capabilities` when present — it drives the mandatory Cosmos card).
- **`none`** — anything else worth carrying (Private Endpoints, ExpressRoute circuits, Front Door
  profiles, API Management instances, Key Vaults).

**Cost-line matching rule:** meter and service names vary in case and separator. Always match
case-insensitively with hyphen and underscore treated as space.

### Step 6b: Project-docs scan

Network and addressing constraints are often documented only in project prose. Grep/Read the user
project's README and docs (`**/README*`, `**/*.md`, `**/docs/**`; skip `.migration/`) for
migration-relevant statements: fixed IP ranges, on-premises CIDRs, ExpressRoute dependencies, hard-coded
addresses, firewall allowlists keyed to Azure IPs, and Private Endpoint/Private Link dependencies.
Record each hit twice — verbatim in `azure-inventory.json.warnings[]` as
`[NETWORK_CONTINUITY] <quote> (<file>)`, and as an `adjacent-services.json` item with the same quote and
file as evidence. Clarify's `Q_NET` consumes these. No hits -> no entry needed.

## Step 7: Ambiguity ledger

Surface EVERY ambiguity as a `warnings[]` entry formatted `[TAG] <resource>: <detail>`. **Never silently
include or exclude an ambiguous row — every flagged resource stays in `resources[]`; disposition is a
Clarify decision.** The full taxonomy is in `references/shared/schema-artifacts.md` §1; the detection
rules that need spelling out:

- `[EPHEMERAL_OS_DISK]` — Grep `diffDiskSettings` (ARM/Bicep) and `diff_disk_settings` (Terraform) on
  every run. **M2VM-ineligible.**
- `[UNMANAGED_DISK]` — `vhd { uri }` / `osDisk.vhd` / `storage_os_disk` with `vhd_uri`, or any
  `azurerm_virtual_machine` using them. **M2VM-ineligible, and retired on the Azure side since
  2026-03-31.**
- `[ADE_ENCRYPTED]` — Azure Disk Encryption extensions (`AzureDiskEncryption`,
  `AzureDiskEncryptionForLinux`) or `encryption_settings` on a disk. **Not an M2VM blocker** — a
  friction card.
- `[EOL_OS]` / `[CLIENT_OS]` — guest image publisher/offer/SKU indicating an end-of-life server OS or a
  Windows client SKU; also App Service `linuxFxVersion` / stack settings pinned to an end-of-support
  runtime. Flag for `Q_OS`; do not decide here.
- `[POWERED_OFF]` vs `[STOPPED_NOT_DEALLOCATED]` — distinguish them. Deallocated means no compute
  billing; stopped-but-allocated **still bills** and surfaces only by crossing a cost source with power
  state (Step 3.3), IaC or no IaC.
- `[ORPHANED_DISK]` — a managed disk with no owning VM in the inventory.
- `[VMSS_ZERO]` — a scale set with capacity 0 or `instances = 0`: invisible in cost, real in IaC.
- `[TLS_LEGACY]` — storage account with `minimumTlsVersion` / `min_tls_version` absent or below
  `TLS1_2`. Absence matters: PowerShell, CLI and ARM leave the property unset, and an unset account
  "will permit requests sent with TLS version 1.0 or greater"
  (https://learn.microsoft.com/en-us/azure/storage/common/transport-layer-security-configure-minimum-version).
- `[LEGACY_SDK]` — `WindowsAzure.ServiceBus`, `Microsoft.Azure.ServiceBus` or
  `com.microsoft.azure.servicebus` in app code. Carries a source-side 2026-09-30 retirement deadline.
- `[PRIVATE_ENDPOINT]` — `Microsoft.Network/privateEndpoints`, `azurerm_private_endpoint`, or a resource
  with public network access disabled. Every one is a connectivity item for Design.
- `[BASIC_SKU]` — Basic public IP or Basic Load Balancer, both retired 2025-09-30. Existing ones keep
  running but are **unsupported and outside any SLA**, so each is a must-replace item, never keep-as-is.
  No official page documents an earlier creation cutoff — which is **not** evidence that creating one
  still succeeds today. Never propose creating a Basic SKU resource on either side of the migration. The
  one documented carve-out is Cloud Services Extended Support, where Basic IPs and Basic LBs can still be
  created via non-portal methods; if the estate has CSES deployments, say so rather than reporting the
  Basic resources as simply impossible.
- `[AHB_SIGNAL]`, `[IAC_DRIFT]`, `[PARTIAL_IAC]`, `[PARTIAL_INVENTORY]`, `[UNRESOLVED_SOURCE_FIELD]`,
  `[NETWORK_CONTINUITY]` — per Steps 3, 5, 6b and the schema file.

## Step 8: Checkpoint discipline

Write each artifact to `$MIGRATION_DIR/` the moment its step completes — never buffer to phase end. On
re-entry with `phases.discover = "in_progress"`, skip steps whose artifacts already exist and continue
from the first missing one (overwrite-clean re-runs only when inputs changed).

## Step 9: Validate, Ledger, Status Update, Summary

1. Confirm at least one artifact exists in `$MIGRATION_DIR`. If none: STOP with "Discovery ran but
   produced no artifacts. Check that your inputs contain Azure data and try again."
2. Append to `$MIGRATION_DIR/validation-ledger.json` (Write the complete file; on session resume Read it
   once first):
   - `discover/input-detection` — which of 1a-1g matched, with file counts.
   - `discover/enumeration` — resource count by `azure_type`, subscription count, cost total + currency +
     `cost_basis`, adjacent-item count by `gate`.
   - `discover/reconciliation` — drift count and the IaC coverage ratio from Step 3.
   - `discover/ambiguity-ledger` — warning count per tag.
   - One `skipped`/`corrected` entry per degradation (unresolved size, helper fallback, unresolvable
     module, Parquet refusal, any network-dependency failure). Never silently continue.
3. **Post-phase write audit** per the protocol in `SKILL.md`: the primary source is your own Write/Edit
   call list; `git status --porcelain` is only a cross-check against the Step 0.6 baseline. Any
   session-written path outside `$MIGRATION_DIR` (sole exceptions `.migration/.gitignore`, and
   `_extract_cost.*` which must ALREADY be deleted) -> STOP, list the offenders, instruct removal, record
   a `fail` entry. Headless: record the `fail` plus a prominent warning and continue.
4. In the same turn, use the Phase Status Update Protocol (Write, complete file, NO prior Read) to set
   `phases.discover = "completed"`.
5. Output to the user — build from whichever artifacts exist:
   - "Inventoried N Azure resources across S subscriptions from `[sources]`."
   - Counts for the decision-shaping classes: VMs, M2VM-ineligible VMs, managed databases, storage
     accounts, container platforms, messaging, analytics services.
   - "Azure spend: `[currency]` `[total]`/month (basis: `[cost_basis]`) across `[n]` services." Plus,
     when a discount model is present: "Baseline includes `[PricingModel values]` pricing — not directly
     comparable to a GCP list-price estimate."
   - "Adjacent services: `[list]`." Then, for each armed gate, one line: "Entra ID / Active Directory
     detected — Clarify must run the identity advisory", "Windows/SQL licensing signals detected —
     Clarify must run the licensing advisory", "Analytics platform detected (`[names]`) — Clarify must
     run the analytics gate", "Cosmos DB detected (`[n]` accounts) — Clarify must run the datastore card".
   - **Every `warnings[]` entry from every artifact, verbatim**, plus any `fail`/`corrected` ledger
     entries.
   - Then: "Discover phase complete. Next required step: Phase 2 — Clarify. Load
     `references/phases/clarify.md` now. Do not load Design, Estimate or Generate until Clarify completes
     and `.phase-status.json` marks `phases.clarify` as `completed`."

## Output Files

Written to `$MIGRATION_DIR/` ONLY: `azure-inventory.json`, `azure-cost-profile.json`,
`adjacent-services.json`, plus run state (`.phase-status.json`, `validation-ledger.json`) and the
transient `_extract_cost.*` (deleted before phase end).

**No other files:** no README, no discovery summary, no report/log/analysis files. All user
communication happens through output messages.

## Error Handling

- Missing `.migration/` or `.migration/.gitignore` -> create them (Step 0).
- Out-of-scope source estate -> STOP and name the correct skill (Step 1).
- No input sources at all -> STOP (Step 1).
- Parquet-only cost export -> STOP for that file, ask for CSV, continue with other sources (Step 1e).
- Unresolvable VM size -> `null` + warning, never a guess (Step 5).
- Helper runtime missing -> delete the helper, fall back to a chunked in-context Read, `corrected` ledger
  entry (Step 4).
- Write-audit violation -> STOP (interactive) or prominent warning + continue (headless); `fail` entry
  either way (Step 9).
- No artifacts produced -> STOP (Step 9).

## Scope Boundary

**This phase covers Discovery ONLY.** FORBIDDEN: GCP service names, equivalents or recommendations;
migration strategies (`candidate_strategies` stays `[]`); Terraform generation; cost estimates or GCP
comparisons; effort estimates; dispositions for flagged resources.

**Your ONLY job: inventory what exists in the Azure estate and around it. Nothing else.**
