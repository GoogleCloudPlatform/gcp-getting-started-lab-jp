# Phase 4: Estimate GCP Costs (Orchestrator)

**Execute ALL steps in order. Do not skip or optimize.**

## Step 0: Pricing Source — `gcp-pricing` CLI (MANDATORY)

**Every dollar number in this phase's output MUST trace to a live tool call made during this run.** Model-recalled prices ("I know Cloud Run is about $0.0000XX per vCPU-second" — placeholder on purpose; rates printed in instruction files are copy-through bait) are FABRICATION and are forbidden — the schema and self-check in `estimate-infra.md` reject any resource lacking live-call evidence.

### Step 0a: Primary source — `gcp-pricing` CLI (Cloud Billing Catalog API)

The plugin bundles the `gcp-pricing` command (available on PATH; run it with the Bash tool). It queries the authoritative Cloud Billing Catalog API (`cloudbilling.googleapis.com`) live, handles pagination, computes decimal unit prices from the raw `units`+`nanos` Money fields, and emits provenance (`retrieved_at`, `auth_mode`, `source_url`) in its JSON output. Auth is resolved automatically: gcloud ADC first, then gcloud user credentials, then an API key (`GCP_PRICING_API_KEY` env or plugin config).

Run this once at the start of Estimate to build the service-id map (one call per distinct service name):

```bash
gcp-pricing services --filter "Cloud Run|Cloud SQL|Memorystore|Cloud Storage"
```

Then for every distinct `gcp_service` in `gcp-design.json` (Cloud Run, Cloud SQL, Memorystore Redis, Cloud Storage, Cloud Load Balancing, Cloud KMS, Pub/Sub, Secret Manager, Cloud Logging, Cloud Monitoring, Dataflow, BigQuery, Artifact Registry, etc.), fetch the relevant SKUs:

```bash
gcp-pricing skus --service 152E-C115-5142 --region us-central1 --filter "CPU|Memory" --currency USD
```

Each returned SKU carries `tieredRates[].unitPrice` as a ready-to-use decimal string (e.g. `"0.000024"` per vCPU-second) plus `usageUnit`, `serviceRegions`, and `pricingEffectiveTime`. Use `--filter` to narrow by SKU description and `--limit 0` only when you need the full list. Cache the fetched rate in-memory for the run so the same SKU isn't refetched per resource.

Record `pricing.source = "gcp-pricing (Cloud Billing Catalog API)"` and put the exact `gcp-pricing` command line in `pricing.attempts[].tool_call` plus a 1–3 line excerpt of its JSON output in `pricing.attempts[].evidence` (see `estimate-infra.md` schema).

If the tool exits non-zero, its stderr says exactly what failed (credential setup steps, the API-enable activation URL, or ambiguous service candidates). Fix and retry once; if it still fails for a service, fall through to Step 0b for that service.

### Step 0b: Secondary — google-developer-knowledge MCP (verification/context only)

Use `google-developer-knowledge` MCP for pricing-page context, lifecycle notes, free-tier rules — NOT as the rate source if Step 0a succeeded. If Step 0a fails for a specific service (no matching SKU found, region not covered, tool error), use this as the next attempt and record `pricing.source = "google-developer-knowledge MCP"`.

### Step 0c: Tertiary — WebFetch official pricing pages

Only if both 0a and 0b fail for a service. Use the URL table in `estimate-infra.md` "Web Search Pricing References". Record `pricing.source = "WebFetch cloud.google.com"`.

### Step 0d: STOP — no silent fallback to stale data

If all three live sources fail for a service, **STOP** and report which service(s) lack a price. Do NOT emit estimates with fabricated or stale numbers. The user can choose to: (i) fix network/auth so the API succeeds, (ii) exclude the service from totals, or (iii) provide a manual rate that the skill records with `pricing.source = "user_provided"` plus the user's justification in `evidence`.

### Pre-Part-2 self-check (MANDATORY before any cost calculation)

Before proceeding to "Part 2: Calculate Projected GCP Costs" in `estimate-infra.md`:

1. Enumerate every distinct `gcp_service` you intend to price.
2. For each, verify you have at least one entry in your in-memory rate cache populated from a tool call this run (`gcp-pricing`/MCP/WebFetch).
3. If any service is missing live-call evidence, **STOP**, list the missing services, and re-run Step 0 for those services. You may not write `estimation-infra.json` until this passes.

**`pricing.source` values (allowed enum):**

| Value                                       | Meaning                                                             |
| ------------------------------------------- | ------------------------------------------------------------------- |
| `"gcp-pricing (Cloud Billing Catalog API)"` | Primary — bundled CLI against cloudbilling.googleapis.com (Step 0a) |
| `"google-developer-knowledge MCP"`          | Secondary — MCP lookup of official pricing docs (Step 0b)           |
| `"WebFetch cloud.google.com"`               | Tertiary — direct fetch of official pricing page (Step 0c)          |
| `"user_provided"`                           | User supplied the rate after all live sources failed (Step 0d)      |
| `"billing_heuristic"`                       | Billing-only path derived from AWS spend (no IaC sizing exists)     |

There is no `"cached"` or `"cached_fallback"` value. There is no pricing cache file; cached recall of prices is fabrication.

## Step 1: Prerequisites

1. Read `$MIGRATION_DIR/.phase-status.json`. If missing, invalid, `phases.clarify` is not exactly `"completed"`, or `phases.design` is not exactly `"completed"`: **STOP**. Output: "Phase 3 (Design) not completed or phase state is missing/invalid. Complete Design before Estimate."
2. Read `$MIGRATION_DIR/preferences.json`. If missing: **STOP**. Output: "Phase 2 (Clarify) not completed. Run Phase 2 first."

Check which design artifacts exist in `$MIGRATION_DIR/`:

- `gcp-design.json` (infrastructure design from IaC)
- `gcp-design-ai.json` (AI workload design)
- `gcp-design-billing.json` (billing-only design)

If **none** of these artifacts exist: **STOP**. Output: "No design artifacts found. Run Phase 3 (Design) first."

## Step 2: Routing Rules

### Infrastructure Estimate

IF `gcp-design.json` exists:

> Load `estimate-infra.md`

Produces: `estimation-infra.json`

### Billing-Only Estimate

IF `gcp-design-billing.json` exists AND `gcp-design.json` does **NOT** exist:

> Load `estimate-billing.md`

Produces: `estimation-billing.json`

### AI Estimate

IF `gcp-design-ai.json` exists:

> Load `estimate-ai.md`

Produces: `estimation-ai.json`

### Mutual Exclusion

- **estimate-infra** and **estimate-billing** never both run (billing-only is the fallback when no IaC exists).
- **estimate-ai** runs independently of either estimate-infra or estimate-billing (no shared state). Run it after the infra/billing estimate completes.

## Phase Completion

After all applicable sub-estimates finish, use the Phase Status Update Protocol (Write tool) to write `.phase-status.json` with `phases.estimate` set to `"completed"` -- **in the same turn** as the output message below. Also append a pricing-attempts summary (services priced per source tier; any exclusions) to `validation-ledger.json` and run the post-phase write audit (SKILL.md > Run Validation Ledger).

Output to user: "Cost estimation complete. Proceeding to Phase 5: Generate Migration Artifacts."

## Reference Files

- **`gcp-pricing` CLI** -- bundled with the plugin; live Cloud Billing Catalog API lookups (primary; ADC-first auth, API-key failover)
- `google-developer-knowledge` MCP -- Secondary, for pricing-page context and verification
- Official cloud.google.com pricing pages -- Tertiary fallback for WebFetch

## Scope Boundary

**This phase covers financial analysis ONLY.**

FORBIDDEN -- Do NOT include ANY of:

- Changes to architecture mappings from the Design phase
- Execution timelines or migration schedules
- Terraform or IaC code generation
- Detailed migration procedures or runbooks
- Team staffing or resource allocation

**Your ONLY job: Show the financial picture of moving to GCP. Nothing else.**
