# Phase 4: Estimate GCP Costs (Azure -> GCP)

**Execute ALL steps in order. Do not skip or optimize.** This file is the entire Estimate phase. Inputs:
`$MIGRATION_DIR/gcp-design.json`, `preferences.json`, and `azure-cost-profile.json` for comparison.
Output: `$MIGRATION_DIR/estimation.json` per `references/shared/schema-artifacts.md` §6.

> **FORBIDDEN:** citing a price from prior knowledge alone (a rate that "looks about right" for a machine
> type is fabrication) without a recorded live tool call this run. Every dollar in `estimation.json` —
> including every $0 line — must trace to a live source captured during THIS run: the bundled
> `gcp-pricing` CLI against the Cloud Billing Catalog API (primary), `google-developer-knowledge` MCP
> (secondary), or WebFetch of an official pricing page (tertiary). Model-recalled prices are a
> Generate-phase blocker — Generate MUST reject rows lacking `pricing.attempts[].evidence` from a live
> call and refuse to advance.
>
> **NON-OFFICIAL SOURCES ARE FORBIDDEN AS PRICING EVIDENCE.** Community mirrors of Google pricing data,
> blogs, third-party calculators and calculator screenshots are never pricing evidence, however plausible
> they look. GCP rate evidence may cite ONLY: `gcp-pricing` output (cloudbilling.googleapis.com), the
> `google-developer-knowledge` MCP, or WebFetch of `cloud.google.com` / `docs.cloud.google.com`. An
> attempt whose evidence cites any other domain FAILS validation exactly like a recalled price.
>
> **Azure-side numbers are never estimated at all.** The Azure baseline comes only from
> `azure-cost-profile.json` (the customer's own billing data). This skill never prices an Azure resource.

## Step 0: Pricing Source Chain (MANDATORY)

### Step 0a: Primary — `gcp-pricing` CLI (Cloud Billing Catalog API)

The plugin bundles `gcp-pricing` (run via Bash; if the bare name does not resolve on PATH, try
`${CLAUDE_PLUGIN_ROOT}/bin/gcp-pricing`, then `node ${CLAUDE_PLUGIN_ROOT}/scripts/gcp-pricing.mjs` —
plugin root is the directory containing `.claude-plugin/plugin.json`. A PATH miss is NOT a tier failure;
fall to Step 0b only after the plugin-root forms also fail). It queries `cloudbilling.googleapis.com`
live, handles pagination, computes decimal unit prices from the raw `units`+`nanos` Money fields, and
emits `retrieved_at` / `auth_mode` / `source_url` provenance.

**Resolve service IDs live — never hardcode one.** Run once at the start of Estimate, filtering on the
services actually present in `gcp-design.json`:

```bash
gcp-pricing services --filter "Compute Engine|Cloud Storage|Cloud SQL|Kubernetes|Cloud Run|Pub/Sub|Artifact Registry|Secret Manager|Networking"
```

Then fetch SKUs per service:

```bash
gcp-pricing skus --service "${SERVICE_ID}" --region "${REGION}" --filter "<sku description regex>" --currency USD
```

`${REGION}` = `preferences.json.region`. Cache fetched rates in memory for this run so the same SKU is
not refetched per resource. Record `pricing.source = "gcp-pricing (Cloud Billing Catalog API)"`, the
exact command line in `pricing.attempts[].tool_call`, and a 1-3 line excerpt of its JSON output in
`pricing.attempts[].evidence`. If the tool exits non-zero, its stderr says what failed (credential steps,
API-enable URL, ambiguous candidates). Fix and retry once; if it still fails for a service, fall to 0b
for that service.

### Step 0b: Secondary — `google-developer-knowledge` MCP

Use for pricing-page context, lifecycle notes and free-tier rules — NOT as the rate source if 0a
succeeded. If 0a fails for a service (no matching SKU, region not covered, tool error), query
`<service-name> pricing site:cloud.google.com` and record
`pricing.source = "google-developer-knowledge MCP"`.

### Step 0c: Tertiary — WebFetch official pricing pages ONLY

Only if 0a and 0b both fail for a service. Record `pricing.source = "WebFetch cloud.google.com"`. Find
the page through the MCP or a site-scoped search rather than assembling a URL from memory — pricing URLs
move, and `cloud.google.com/*` now redirects to `docs.cloud.google.com/*`.

### Step 0d: STOP — no silent fallback, no fabrication

If all three live sources fail for a service, **STOP** and report which service(s) lack a price. Per
failed service the user chooses: (i) fix network/auth and re-run, (ii) exclude the service from totals
and report the gap, or (iii) provide a manual rate, recorded with `pricing.source = "user_provided"` plus
the user's justification in `evidence`. Headless runs apply (ii) automatically with a loud banner and a
`"skipped"` ledger entry.

**Visible degradation:** every network-dependency failure gets a `warnings[]` entry in `estimation.json`
AND a `skipped`/`corrected` ledger entry before falling to the next source. NEVER silently continue.

**Tried-sources audit (binding):** `pricing.attempts[]` MUST list EVERY source tried, in order, with
outcome and evidence excerpt — the successful entry is never the only entry when earlier tiers were
attempted. Failed tiers are recorded as attempts, not only as warnings.

## Step 1: Prerequisites

1. Read `.phase-status.json`. If missing, invalid, or either `phases.clarify` or `phases.design` is not
   exactly `"completed"`: **STOP** — "Phase 3 (Design) not completed or phase state is missing/invalid."
2. Read `preferences.json`. Missing -> **STOP.** Missing `sizing_mode`, `region`, or any of the three gate
   strategies -> **STOP**; re-run Clarify. Estimate may not guess them.
3. Read `gcp-design.json`. Missing -> **STOP** — "No design artifact found. Run Phase 3 first."
4. Read `azure-cost-profile.json` if present. Absence degrades only `comparison_to_azure` — record a
   `warnings[]` entry, do not STOP.

## Step 2: Validate Design Output (BLOCKING gate)

1. `gcp-design.json` parses as JSON. Else **STOP:** "Design file corrupted (invalid JSON). Re-run Phase 3."
2. `groups[]` is non-empty and every group has `resources[]`. Else **STOP.**
3. Every resource has `gcp_service`, a `sizing_mode` and a `disposition`. **Only rows with
   `disposition: "mapped"` are required to carry `gcp_config`** — `deferred` and `needs-decision` rows are
   exempt, are priced at nothing, and go straight to `totals.excluded_deferred[]` with their reason. A
   `needs-decision` row is a normal row to be skipped, NEVER a reason to stop. Otherwise **STOP** naming
   the resource.
4. Deferred rows — `gcp_service` exactly `"Deferred — specialist engagement"` (treat the ASCII forms
   `"Deferred -- specialist engagement"` and `"Deferred - specialist engagement"` as equivalent) — must
   carry **no `gcp_config` key** and get **no dollars** in this phase. A Deferred row carrying config is a
   design defect: **STOP.**
5. A Windows **client** OS row whose `disposition` is not `needs-decision` is a design defect: **STOP.**
6. A row with `gcp_config.machine_type: null` (unresolved Azure size) is NOT priced — route it straight to
   `totals.excluded_deferred[]` with the reason, and continue.

Append a ledger entry (gate `estimate/design-validation`).

## Step 3: Build the pricing worklist

Group `gcp-design.json` rows by `gcp_service` and price each distinct configuration once, then multiply
by count. Per family:

1. **Compute Engine.** For each distinct machine type: query the Compute Engine service filtered on that
   series' core and RAM SKU descriptions. Read the returned descriptions — predefined types price as
   vCPU-hours plus RAM GiB-hours. If a filter matches nothing, broaden it and read the live descriptions;
   never guess a SKU shape.
2. **Disks.** Price the disk type named in each `gcp_config` by its description, as capacity GiB-month.
   Add provisioned IOPS or throughput SKUs only when the design specifies beyond-baseline values.
3. **Windows Server / SQL Server licence premium.** Only for rows whose `gcp_config.os_license` says
   license-included, which Design copied from `preferences.license_strategy`. Filter the Compute Engine
   service for the licensing-fee SKUs and read the returned unit — do not assume the billing unit; derive
   `assumed_quantity` from what the SKU's `usageUnit` actually says. **Client Windows rows can never be
   priced license-included** — if one arrives priced, **STOP** (design defect).
4. **Managed services** (Cloud SQL, GKE, Cloud Run, Cloud Storage, Pub/Sub, Artifact Registry, Secret
   Manager, Memorystore, load balancing, Cloud CDN): price each from its own catalog service. Consumption-
   priced services need an `assumed_quantity` grounded in a cited source — `sizing_data` from Clarify, a
   figure in `azure-cost-profile.json`, or an explicit user statement. **A consumption estimate with no
   grounded quantity is not an estimate**; route it to `external_costs[]` or `excluded_deferred[]` with
   the gap named, rather than inventing a request count.
5. **Migrate to Virtual Machines.** One `component` row. Verify its current charging model live rather
   than assuming; whatever the page says, record the attempt normally and note that **replication storage
   and any test-clone or cutover instances consume billable resources until they are cleaned up**.
6. **Storage Transfer Service** for the Blob -> Cloud Storage hop: price per the live page; the data
   landing in Cloud Storage is priced as storage regardless.
7. **Egress and cross-cloud connectivity.** Coexistence traffic between Azure and Google Cloud is a real
   cost on both sides. Price the Google side from the catalog where a SKU matches the design's
   `network.connectivity`; put the **Azure-side** egress and circuit fees in `external_costs[]` with no
   dollars — this skill does not price Azure.

**Deferred and excluded items.** Every Deferred row (analytics gate, Cosmos Gremlin/Table, specialist
rows), every `needs-decision` row (M2VM-ineligible, EOL/client OS, orphaned, zero-capacity), and every
unresolved-size row: NO rate lookups, NO dollars, NOT in `resources[]`. List each in
`totals.excluded_deferred[]` as `{"item", "reason"}`.

**No human-labour cost lines.** Labour, professional services, partner fees and licence-negotiation
outcomes are NEVER dollar estimates anywhere in `estimation.json`. Vendor fees only.

## Step 4: Pricing-coverage self-check (MANDATORY before any calculation)

Enumerate every distinct `gcp_service` in the worklist; verify each has at least one in-memory rate
populated by a tool call THIS run; if any lacks live-call evidence, **STOP**, list the missing services,
and re-run Step 0 for them. You may not write `estimation.json` until this passes. Append a ledger entry
(gate `estimate/pricing-coverage`) with per-source counts and any Step 0d exclusions.

## Step 5: Calculate rows

`monthly_cost` = rate x quantity; the arithmetic lives in `pricing.calculation`. **Quantity grounding:**
`assumed_quantity` MUST derive from `gcp_config` fields (machine-type vCPU/RAM, disk GiB, instance count,
node count) times 730 h/month, or from an explicit `preferences.json` / `sizing_data` value, cited
inline. Vague strings ("estimated typical usage", "approximately") FAIL Step 7.

**`sizing_mode`:** echo the row's Design-recorded `sizing_mode` onto every `resources[]` row. Estimate
prices the design exactly as designed and **never re-sizes**.

**Validation rules (BLOCKING — Generate refuses to advance if violated):**

1. At least one `attempts[]` entry with `result == "ok"`; if every attempt failed, the resource has no
   price and the file is invalid.
2. `evidence` is REQUIRED on every `result == "ok"` attempt: a non-empty 1-3 line VERBATIM excerpt of the
   actual tool response showing the rate. "Looked it up" / "from docs" / "approximately" are NOT evidence.
3. `tool_call` is REQUIRED on every attempt: the literal command or MCP invocation made. `"recalled"`,
   `"from training"` or similar mean the entry is fabricated — Generate rejects it.
4. `source` and `result` must come from the enums in `references/shared/schema-artifacts.md` §6. Use the
   most specific `result` value.
5. `attempts[]` lists EVERY tier tried, in order.

## Step 6: Totals and the Azure comparison

**Totals.** `gcp_monthly_total` is the sum of `resources[].monthly_cost`. `by_service` breaks it down.
`note` states that `external_costs[]` and Deferred items are NOT included.

**Load `references/shared/billing-exports.md` §3 before building the comparison** — it defines the
`discount_normalization` fields Discover recorded and the comparability rule applied below.

**`comparison_to_azure` — this is where most cross-cloud estimates lie, so it is gated.** Build it from
`azure-cost-profile.json`, labelled `"source-billing-derived actuals"`, and populate
`discount_normalization` from `azure-cost-profile.json.discount_normalization`:

- `azure_baseline_is_discounted` is `true` when `pricing_models_seen[]` contains anything other than
  `OnDemand`, or when any `[AHB_SIGNAL]` exists in the inventory.
- `gcp_side_basis` states what the GCP number actually is — normally
  `"list-price, license-included, no committed-use discount"`.
- **`comparable` is `false`** whenever `azure_baseline_is_discounted` is true and no on-demand equivalent
  was recovered (which is almost always: an export shows what was paid under the commitment, not what the
  same usage would have cost on demand).
- `caveats[]` MUST include, in plain language: which discount models the Azure side carries; that Azure
  Hybrid Benefit is an Azure-only offer that does not follow the workload; that the Azure actuals include
  services staying on Azure and items Deferred on the GCP side; that `external_costs[]` are excluded from
  the GCP total; and that GCP committed-use discounts and sustained-use behaviour are **not** modelled.

When `comparable` is `false`, the delta is still computed but is presented as **"not like-for-like"** in
both the artifact and the summary. Never present a headline saving derived from a discounted Azure
baseline against a GCP list-price total.

Missing `azure-cost-profile.json` -> `{"available": false, "note": "azure-cost-profile.json not found —
re-run Discover with an Azure cost export to enable comparison"}` plus a `warnings[]` entry.

## Step 7: Pre-write self-check (MANDATORY before writing `estimation.json`)

Walk every `resources[]` entry and verify ALL of: (1) `attempts[]` has >=1 `result == "ok"` with non-empty
verbatim `evidence`; (2) `source` enum valid, no cached value; (3) `pricing.calculation` parses as
rate x quantity = `monthly_cost` within +/-$0.50; (4) `assumed_quantity` grounded in cited
`gcp_config`/`preferences.json`/`sizing_data` values; (5) `sizing_mode` present on every row; (6) evidence
cites only official domains; (7) no Deferred, `needs-decision` or unresolved-size item appears in
`resources[]`, and no `external_costs[].note` contains a dollar figure; (8) `comparison_to_azure`
carries a populated `discount_normalization` whenever a cost profile exists.

If any check fails, **STOP**, list the failing rows plus the specific check, and redo Step 0/Step 5 for
those rows. Append a ledger entry (gate `estimate/pre-write-self-check`).

## Step 8: Write outputs, ledger, phase status

1. Write `$MIGRATION_DIR/estimation.json` per the schema.
2. Append this phase's ledger entries (`estimate/design-validation`, `estimate/pricing-coverage`,
   `estimate/pre-write-self-check`, plus one per degradation). **Ledger resume rule:** on session resume,
   Read `validation-ledger.json` ONCE before this session's first append — earlier phases' entries are not
   re-derivable and a blind Write clobbers them. The no-prior-Read protocol applies to `.phase-status.json`
   only.
3. **Post-phase write audit** per the `SKILL.md` protocol; any session-written path outside
   `$MIGRATION_DIR` (sole exceptions `.migration/.gitignore`, and `_extract_cost.*` which must already be
   deleted) -> **STOP**, list offenders, instruct removal, record a `fail` entry.
4. **Phase Status Update Protocol** (Write, complete file, no prior Read): `phases.estimate: "completed"`.
5. Present a summary (<=20 lines): rows priced per source tier (for example "14 of 16 rows via gcp-pricing
   (Cloud Billing Catalog API), 2 via WebFetch cloud.google.com — no fabrication") with an accuracy note
   (+/-2-5% Catalog API, +/-5-10% WebFetch); `gcp_monthly_total`; the Azure comparison labelled
   source-billing-derived actuals **with the comparability verdict stated first**; `external_costs[]`
   items (no dollars); the `excluded_deferred[]` list; and every `fail`/`corrected`/`skipped` ledger
   entry.
6. Output: "Cost estimation complete. Proceeding to Phase 5: Generate Migration Artifacts."

## Scope Boundary

**Financial analysis ONLY.** FORBIDDEN: changes to Design-phase mappings; execution timelines or
schedules; Terraform or IaC generation; migration procedures or runbooks; team staffing, human-labour or
professional-services dollar lines; any Azure-side price the customer's own billing data did not supply.

**Your ONLY job: show the financial picture of moving these Azure workloads to Google Cloud. Nothing else.**
