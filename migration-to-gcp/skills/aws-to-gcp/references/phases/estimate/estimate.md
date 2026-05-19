# Phase 4: Estimate GCP Costs (Orchestrator)

**Execute ALL steps in order. Do not skip or optimize.**

## Step 0: Pricing Mode Selection

Before running any sub-estimate file, determine the pricing source.

### Step 0a: Load Pricing Cache

Read `shared/pricing-cache.md`. Check the `Last updated` date in the header:

- If <= 90 days old: **Cached prices are the primary source.** Proceed to Step 0b for web search verification of key services if desired, otherwise proceed to Step 1.
- If > 90 days old: Cache is stale. Attempt web search (Step 0b) for fresh prices; use stale cache as fallback.

### Step 0b: Verify Current GCP Pricing

**Primary current-docs method:** Prefer `google-developer-knowledge` when available to find current Google Cloud pricing/model documentation and service lifecycle notes. Verify prices against official Google Cloud pricing pages. If the MCP server is unavailable, use web search restricted to official provider pricing pages.

Attempt current-doc lookup with **up to 2 retries** (3 total attempts):

1. **Attempt 1**: Use `google-developer-knowledge` with a query such as `[service name] pricing Google Cloud`
2. **If timeout/error**: Wait 1 second, retry (Attempt 2)
3. **If still fails**: Wait 2 seconds, retry (Attempt 3)
4. **If all 3 attempts fail**: Search official provider pricing pages directly, for example `site:cloud.google.com [service name] pricing`
5. **If all live lookups fail**: Use cached prices from `shared/pricing-cache.md` with staleness warning

### Pricing Hierarchy

Each sub-estimate file uses this lookup order per service:

1. **Google Developer Knowledge MCP (preferred when available)** -- Search official Google developer documentation, then verify against official pricing pages. Set `pricing_source: "google_developer_knowledge"`.
2. **Official web search** -- Search `cloud.google.com/pricing/*` or official provider pricing pages directly (+-5-10% accuracy). Set `pricing_source: "web_search"`.
3. **`shared/pricing-cache.md` (quick reference)** -- Cached prices (+-5-10% accuracy if <= 90 days old, +-15-25% if stale). Set `pricing_source: "cached"`. Used when live lookup is unavailable or for rapid estimation of common services already in the cache.
4. **Cache after live lookup failure** -- If live lookup was attempted but failed, and the service IS in the cache, use the cached price. Set `pricing_source: "cached_fallback"`. This distinguishes intentional cache use from live lookup failure recovery.
5. **Unavailable** -- If a service is NOT in the cache AND live lookup is unavailable, set `pricing_source: "unavailable"` for that service. Add the service to `services_with_missing_fallback` and display a warning to the user: "Pricing unavailable for [service] -- not in cache and official live lookup unreachable. Exclude from totals or provide a manual estimate."

**`pricing_source` values summary:**

| Value               | Meaning                                                      |
| ------------------- | ------------------------------------------------------------ |
| `"google_developer_knowledge"` | Retrieved with Google Developer Knowledge MCP and verified against official docs |
| `"web_search"`      | Retrieved via web search from cloud.google.com/pricing       |
| `"cached"`          | Found in pricing-cache.md (normal path)                      |
| `"cached_fallback"` | Live lookup was attempted but failed; fell back to cache     |
| `"billing_heuristic"` | Billing-only estimate derived from AWS spend because no IaC sizing exists |
| `"unavailable"`     | Not in cache AND live lookup failed; service excluded from totals |

If cache is > 90 days old and live lookup is unavailable:

- Add warning: "Cached pricing data is >90 days old; accuracy may be significantly degraded"
- **Display to user**: Add visible warning with staleness notice

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

After all applicable sub-estimates finish, use the Phase Status Update Protocol (Write tool) to write `.phase-status.json` with `phases.estimate` set to `"completed"` -- **in the same turn** as the output message below.

Output to user: "Cost estimation complete. Proceeding to Phase 5: Generate Migration Artifacts."

## Reference Files

- `shared/pricing-cache.md` -- Cached GCP + source provider pricing (+-5-25%, quick reference)
- `google-developer-knowledge` -- Preferred official-docs MCP lookup for current Google Cloud pricing/model documentation when configured

## Scope Boundary

**This phase covers financial analysis ONLY.**

FORBIDDEN -- Do NOT include ANY of:

- Changes to architecture mappings from the Design phase
- Execution timelines or migration schedules
- Terraform or IaC code generation
- Detailed migration procedures or runbooks
- Team staffing or resource allocation

**Your ONLY job: Show the financial picture of moving to GCP. Nothing else.**
