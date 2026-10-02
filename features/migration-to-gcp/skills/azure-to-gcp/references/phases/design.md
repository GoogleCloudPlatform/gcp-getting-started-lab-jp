# Phase 3: Design the GCP Architecture

**Execute ALL steps in order. Do not skip or optimize.**

Rubric discipline: **eliminators -> signals -> scoring**, research BEFORE deciding, and a decision
recorded in `preferences.json.design_choices[]` behind every non-deterministic mapping. A decision not
recorded there may NOT silently shape `gcp-design.json`.

## Prerequisites

1. Read `$MIGRATION_DIR/.phase-status.json`. If missing, invalid, or `phases.clarify` is not exactly
   `"completed"`: **STOP.** Output: "Phase 2 (Clarify) not completed or phase state is missing/invalid.
   Run `references/phases/clarify.md` until `.phase-status.json` shows `phases.clarify`: `completed`."
2. Read `$MIGRATION_DIR/preferences.json`. If missing: **STOP** — "Phase 2 (Clarify) not completed."
3. Read `$MIGRATION_DIR/azure-inventory.json`. If missing: **STOP** — "No discovery artifacts found. Run
   Phase 1 (Discover) first." Read `adjacent-services.json` and `azure-cost-profile.json` if present.
4. **Three gate re-checks** (mirroring the Design-entry gates in `SKILL.md`). For each: evidence present
   in the discovery artifacts + no matching strategy in `preferences.json` -> **STOP** and return to
   Clarify.
   - Entra/AD evidence and no `identity_strategy`.
   - Windows/SQL/AHB evidence and no `license_strategy`.
   - Analytics evidence and no `analytics_strategy`.
5. **Live `gcloud` reads are consent-gated.** Any `gcloud` read of the user's project in this phase
   (`gcloud compute machine-types list`, `gcloud compute regions describe`) runs ONLY after the user
   interactively confirms the target project this run. Headless runs never call `gcloud`: use the
   docs/live-research chain, add a `warnings[]` entry and a `skipped` ledger entry.
6. A non-empty `preferences.headless_defaults_applied[]` means headless semantics below: documented
   defaults plus loud banners, never interactive cards.

## Step 1: Load the mapping rubric and set the frame

**Load `references/shared/service-map.md` NOW.** It owns the class of every mapping (deterministic /
card / deferred), the M2VM eligibility facts, and the **FACTS THAT GO STALE** table — any stale-listed
fact relied on here needs a same-run live fetch. Also load `references/shared/companion-skills.md` and,
for each GCP target with a listed google/skill, resolve that skill before shaping its config.

**Live-research protocol per resource class** (research before deciding): Google-side
(1) `google-developer-knowledge` MCP -> (2) WebSearch -> (3) WebFetch of the docs page; Azure-side
(1) `microsoft-learn` MCP -> (2) WebFetch of learn.microsoft.com. Cite the URL actually consulted in each
affected resource's `rationale`. If a source errors, record it (a `warnings[]` entry AND a `skipped`
ledger entry) and fall to the next; if all fail, apply the documented default and record a `corrected`
ledger entry — NEVER silently continue.

**Standing warnings to append to top-level `warnings[]` when they apply:**

- **No M2VM utilization report exists for Azure sources.** If `sizing_mode` is `rightsize`, state which
  `sizing_data` source backed each resized resource; if a resource has no sizing data, it is sized
  as-provisioned and carries a per-resource warning. Mixing modes silently is an Estimate gate failure.
- **`[PARTIAL_IAC]` / `[IAC_DRIFT]` carry forward.** When the IaC covered a minority of the billed
  estate, the design covers a minority of the estate. Say it in `warnings[]` with the ratio from
  Discover, not as a footnote.

## Step 2: Compute mapping loop (Azure VMs and scale sets -> Compute Engine)

For EVERY compute row in `azure-inventory.json`, in order:

**2.1 Skip rules — carry as warnings, NEVER silently drop.**

- **M2VM-ineligible** (`[EPHEMERAL_OS_DISK]`, `[UNMANAGED_DISK]`): the recorded `Q_M2VM` disposition
  decides. `remediate-first` / `rebuild-from-image` -> a row with `migration_method` set accordingly and
  `human_expertise_required: false` only if Clarify recorded a concrete method; `exclude` /
  `needs-decision` -> no `gcp_config`, disposition copied VERBATIM into `warnings[]` with the VM name.
  **Never emit a normal M2VM row for these VMs** — migration fails with an error.
- **EOL / client OS**: the recorded `Q_OS` disposition decides. `migrate-as-is-where-supported` -> map
  through 2.2-2.5 and copy the "migration support only" support-risk warning into the row's `warnings[]`.
  `upgrade-first` / `exclude` / `needs-decision` -> skip with the disposition verbatim. **A guest Clarify
  excluded STAYS excluded — Design never re-includes it.**
- **Windows client SKUs** are the carve-out: even on a `migrate-as-is-where-supported` pick they get a
  `needs-decision` row recording that pick, never a normal mapped row, because the licensing constraints
  from `Q_LICENSE` precede any design. Estimate STOPs on a priced client-OS row.
- **Stopped / orphaned / zero-capacity** (`[POWERED_OFF]`, `[STOPPED_NOT_DEALLOCATED]`,
  `[ORPHANED_DISK]`, `[VMSS_ZERO]`): the recorded `Q_ZOMBIE` disposition decides; `defer`/`retire` skip
  with the disposition verbatim.
- **ADE-encrypted VMs** map normally, with the friction warning attached to the row.
- **Domain controllers** (Windows Server image + AD/DC evidence; ambiguous -> ask interactively, or a
  `needs-decision` warning headless) map as **rebuild-and-replicate**, never image migration:
  `migration_method: "new VM promoted via AD replication — never image-migrate a DC (USN rollback risk)"`
  (https://learn.microsoft.com/en-us/windows-server/identity/ad-ds/get-started/virtual-dc/virtualized-domain-controllers-hyper-v).
  Counts as mapped, and couples to the `Q_IDENTITY` decision.

**2.2 Machine type (eliminators -> signals -> scoring).** Verify every fact below live before applying it.

- **Eliminators:** Arm-based series cannot run migrated x86 images; some series have no custom machine
  types; some series cannot attach the disk type you intend. Confirm the current constraint set from
  https://docs.cloud.google.com/compute/docs/machine-resource rather than assuming last year's rules.
- **Signals:** general-purpose lift-and-shift -> the current general-purpose series; consistently
  high-performance tiers -> the compute-optimized series; strictly cost-dominated small VMs -> the
  cost-optimized series.
- **Scoring / tie-break:** (1) offered in `preferences.region` — via the live-research chain, or
  `gcloud compute machine-types list --zones=<zone>` after consent; (2) custom-shape support when the
  Azure size has no predefined equivalent; (3) fewest disk-type exceptions. If 2+ series remain genuinely
  viable for a tier, raise a trade-off card and record it in `design_choices[]` before applying it.
  **Headless:** apply the general-purpose default with a loud banner and a `design_choices[]` entry
  stamped `chosen_by: "headless-default"` plus a matching `headless_defaults_applied[]` string — never
  stall on a Design-time card.
- **Shape:** match the source `vcpu`/`memory_gib`. **If either is `null`** (Discover could not resolve the
  Azure size string), do NOT guess: emit the row with
  `gcp_config.machine_type: null`, `human_expertise_required: true` and a warning naming the unresolved
  size. Estimate will exclude it from totals rather than price a guess.
- Do NOT downsize vCPU/RAM in `rightsize` mode without `sizing_data` for that resource — CPU/RAM
  rightsizing needs measurement, and there is no Azure-source utilization report to fall back on.

**2.3 Disks (honor `sizing_mode`, stamp it on every row).**

- `as-provisioned`: target size = the source disk size.
- `rightsize`: size from measured use with stated headroom; **boot disks stay as-provisioned** (shrinking
  a boot volume is in-guest surgery, outside lift-and-shift). Any data disk sized below provisioned gets
  a warning: "requires a data-copy/shrink step at cutover — replication alone does not shrink volumes."
- Disk type follows the chosen machine series. **Always set the type explicitly** in `gcp_config` rather
  than relying on an API default, and cite the current disk-type page you consulted.
- An `[ORPHANED_DISK]` disposed `migrate` becomes a standalone disk row, not an instance row.

**2.4 OS licensing.** Copy `preferences.license_strategy` VERBATIM onto every Windows/SQL row and set
`gcp_config.os_license` from it. **Design never re-decides licensing** and never asserts entitlement.
Linux guests map normally.

**2.5 Scale sets.** Apply the recorded `Q_MAP.vmss` choice. A MIG rebuild produces one instance-template
row plus one MIG row (not N instance rows) and records the source capacity and autoscale settings in
`gcp_config`. A `[VMSS_ZERO]` scale set disposed `migrate` is designed at its configured, not current,
capacity — and says so.

**2.6 Network interfaces per `network_mode`.** `re-ip` -> map each source subnet to the mirrored subnet
from Step 4 with ephemeral addressing; reserve static internal IPs only where an application requires it
(noted per resource). `preserve-cidr` -> the mirrored subnet keeps the source CIDR; record the collision
check that proved it safe.

## Step 3: Managed-service mapping loop

For every non-compute row, resolve its class from `references/shared/service-map.md`:

- **deterministic** -> map directly, `design_choice_ref: "deterministic"`, `rationale` citing the URL you
  consulted this run, `migration_method` naming the documented tool for the hop.
- **card** -> read the recorded `design_choices[]` entry and apply it VERBATIM. **No recorded entry ->
  STOP** and return to Clarify; do not pick a default here.
- **deferred** -> a Deferred row: `gcp_service: "Deferred — specialist engagement"`, **no `gcp_config`
  key at all**, `human_expertise_required: true`, plus an entry in the top-level `deferred[]` naming the
  gate. Do NOT recommend a GCP target for it anywhere, including the chat summary.

Migration-method facts that must appear on the relevant rows, re-verified this run:

- **Blob Storage -> Cloud Storage** via Storage Transfer Service, which supports Azure Storage sources
  with SAS token, Azure Shared Key (Secret Manager only), or **Azure workload identity federation**
  (`federatedIdentityConfig`, Issuer `https://accounts.google.com`, Audience `api://AzureADTokenExchange`,
  Subject = the Google service agent's `subjectId`; the Azure custom role needs blob `read`, plus
  `delete` only if deleting at source; the service agent also needs
  `roles/iam.serviceAccountTokenCreator`). Google recommends SAS tokens created from stored access
  policies **because basic SAS tokens cannot be revoked** — prefer the keyless federation path and say
  why (https://docs.cloud.google.com/storage-transfer/docs/source-microsoft-azure).
- **Azure SQL Database / Managed Instance -> Cloud SQL for SQL Server.** **DMS is not the path.** DMS
  lists Azure SQL MI and Azure SQL Database (tier S3 and above) only under the _heterogeneous_ SQL Server
  to Cloud SQL for PostgreSQL / AlloyDB scenarios; no Azure source appears in the homogeneous SQL Server
  to Cloud SQL for SQL Server table. Use **BACPAC export via SqlPackage** for one-time or
  scheduled-maintenance migrations (recommended especially for files in the hundreds of GB or larger), or
  **Managed Instance link plus DMS** for continuous replication with minimal downtime from MI
  (https://docs.cloud.google.com/database-migration/docs/supported-databases, plus the two Azure SQL
  guides in `references/shared/service-map.md`).
- **Azure Database for MySQL / PostgreSQL Flexible Server -> Cloud SQL.** Built-in engine backups for
  one-time migrations; DMS for continuous replication, with **pglogical** for PostgreSQL. Note the DMS
  source lists: MySQL 5.7/8.0/8.4 and PostgreSQL Flexible Server 11+, the latter only into Cloud SQL for
  PostgreSQL — **not** under the AlloyDB section. If `Q_MAP.postgres` chose AlloyDB, the migration method
  is engine backups or a specialist path, not DMS-into-AlloyDB; say so on the row.
- **AKS -> GKE** is a redeploy, not a lift: there is no cluster-migration tool. The row records the
  Autopilot/Standard choice, the workload-identity binding, and the fact that manifests, admission
  controllers and CSI drivers are re-applied.
- **Containerization of a VM** is a post-landing step: Migrate to Containers accepts VMware and Compute
  Engine sources only, so an Azure VM lands on Compute Engine first
  (https://docs.cloud.google.com/migrate/containers/docs/getting-started). Never design a direct
  Azure-VM-to-container hop.

## Step 4: Network design

- **VPC and subnets:** one VPC unless the design_choices say otherwise; mirror each distinct source
  virtual network / subnet as a subnet in `preferences.region`. Record a source-segment -> subnet/CIDR
  table in `network{}`. Under `re-ip`, choose new non-overlapping CIDRs; under `preserve-cidr`, carry the
  source CIDR and record the collision check.
- **Private Endpoints -> Private Service Connect.** Every `[PRIVATE_ENDPOINT]` finding becomes an explicit
  connectivity row, not an implicit one. State that this is a rebuild: the endpoint, its DNS override,
  and the consuming resource's private-access setting all move.
- **Hybrid / coexistence connectivity:** when the migration is phased, Azure and Google Cloud must talk.
  Pick between Cloud Interconnect (the documented ExpressRoute counterpart) and Cloud VPN using the
  live-research chain; record `product`, `capacity` and `count` in `network.connectivity` from discovery
  evidence, or `null` plus a warning where evidence is missing. **Cross-cloud egress and attachment fees
  are real** — they are `external_costs[]` NOTES for Estimate, never dollars here.
- **DNS:** Cloud DNS private zones with forwarding between Google Cloud and Azure/on-premises resolvers
  during coexistence; AD-integrated zones stay with the domain controllers.
- **Hard-coded addresses:** every `[NETWORK_CONTINUITY]` quote from Discover appears in
  `network.rationale` with its source file. Under `re-ip` these are cutover work items, not surprises.

## Step 5: Identity design

Copy `preferences.identity_strategy` VERBATIM into `identity.strategy`, then design only its mechanics:

- **Federation** -> the Entra-to-Cloud-Identity provisioning and SSO wiring, or Workforce Identity
  Federation, per the strategy. Record which, and cite the guide consulted this run.
- **Managed Service for Microsoft AD** -> record it when AD-joined VMs, Kerberos/LDAP apps, or an SMB
  share via NetApp Volumes need it. **NetApp Volumes SMB requires Active Directory and does not support
  workgroup mode**, so an SMB row without an AD design is an incomplete design — flag it.
- **Workload identity** -> per workload: a service account plus IAM, and on GKE, Workload Identity
  Federation for GKE. Where a workload must keep calling Entra-protected Azure resources during
  coexistence, record that the Entra federated credential is re-pointed at the GKE service account and
  that **two federations then coexist** — do not imply one replaces the other.
- **Never** design a credential file, a long-lived key, or a secret value into any row.

## Step 6: Application-code plan (only when `Q_SDK` put call sites in scope)

Load `references/shared/sdk-map.md`. Per call site produce a plan entry: source pattern, file and line,
target GCP service, rewrite class, and `manual_review` (always `true` for Go, .NET and Java, and for
every Cosmos DB call site). **Never name an import or method without a same-run citation of that
service's client-libraries page** — an unconfirmed name becomes a `# TODO(verify):` note in Generate.
**This skill emits no application source code in any phase.**

## Step 7: Write `$MIGRATION_DIR/gcp-design.json`

Follow `references/shared/schema-artifacts.md` §5 exactly. Write the file the moment it is complete;
never buffer to phase end. Every resource row MUST carry a non-empty `rationale` with at least one cited
URL, a `sizing_mode`, a `disposition` (`mapped` | `deferred` | `needs-decision`), and a
`design_choice_ref`. Deferred rows carry `gcp_service: "Deferred — specialist engagement"` — readers also
accept the ASCII `Deferred -- specialist engagement` and `Deferred - specialist engagement`, but WRITE the
em-dash form — plus no `gcp_config` key and `human_expertise_required: true`.

## Step 8: Fidelity self-check gates (BLOCK completion)

**8a — Inventory fidelity.** Reconcile against `azure-inventory.json` BEFORE completing the phase. EVERY
inventory resource must be accounted for exactly once as **mapped**, **deferred**, or **warned-skip**, per
its RECORDED Clarify disposition:

`total_resources == mapped_rows + deferred_rows + warned_skips`

Each of the three counts rows that are PRESENT in `gcp-design.json` carrying the matching `disposition`
value — `warned_skips` counts `disposition: "needs-decision"` rows, which are written out like any other
row (minus `gcp_config`), never omitted. Omitting them unbalances this equation and strands Estimate.
A stopped or EOL resource disposed `migrate` counts in `mapped_rows`, never in `warned_skips`. If the
equation does not balance, find the dropped or double-counted resource and fix the design — **STOP; do
not complete the phase with an unbalanced count.** Ledger entry: gate `design/inventory-fidelity`, with
the equation and real numbers as `evidence`.

**8b — Preferences fidelity.** Walk every non-deterministic mapping and every Deferred row against
`preferences.json`: each must reference a `design_choices[]` entry by `design_choice_ref`, or carry the
gate strategy verbatim. Any unrecorded decision shaping the design: **STOP.** Ledger entry:
`design/preferences-fidelity`, `evidence` = mappings walked and unrecorded decisions found.

**8c — Gate carriage.** Verify that: every Deferred row has no `gcp_config` key and no dollars anywhere;
every M2VM-ineligible VM is absent from the automated wave; every Windows client row is `needs-decision`;
`identity_strategy`, `license_strategy` and `analytics_strategy` appear verbatim where they apply. Ledger
entry: `design/gate-carriage`.

**8d — Sizing-mode uniformity.** Every row carries a `sizing_mode` equal to `preferences.sizing_mode`,
except rows explicitly downgraded to as-provisioned for lack of `sizing_data` — each of those carries the
warning from Step 1. Ledger entry: `design/sizing-mode`.

## Step 9: Ledger, write audit, phase status

1. Append the Step 8 entries plus one entry per research degradation (`skipped`/`corrected`) to
   `validation-ledger.json` (Write the complete file; Read once first on session resume).
2. **Post-phase write audit** per the `SKILL.md` protocol — primary source is your own write list; any
   session-written path outside `$MIGRATION_DIR` is a `fail` and a STOP (headless: warn and continue).
3. **Phase Status Update Protocol** (Write, complete file, no prior Read): `phases.design: "completed"`,
   in the SAME turn as the final message.
4. Output to the user: "GCP architecture designed (`<N>` mapped, `<N>` deferred, `<N>` warned — reconciled
   with inventory). Proceeding to Phase 4: Estimate Costs." Surface every `fail`/`corrected` ledger entry
   and every headless banner. If any row is `Deferred — specialist engagement`, state prominently that
   NO GCP target was chosen for it. If any machine type is `null` for an unresolved Azure size, name
   those VMs — they will be excluded from cost totals.

## Scope Boundary

**Architecture mapping ONLY.** FORBIDDEN here: cost calculations or dollar figures (external-cost items
are NOTES for Estimate), execution timelines, Terraform or IaC generation, runbook steps, risk registers,
staffing, and application source code.

**Your ONLY job: map Azure resources to GCP targets with cited rationale. Nothing else.**
