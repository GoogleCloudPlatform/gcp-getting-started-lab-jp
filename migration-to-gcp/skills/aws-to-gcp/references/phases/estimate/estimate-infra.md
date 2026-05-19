# Estimate Phase: Infrastructure Cost Analysis

> Loaded by estimate.md when gcp-design.json exists.

**Execute ALL steps in order. Do not skip or optimize.**

> **FORBIDDEN:** Citing a price from prior knowledge alone (e.g. "Cloud Run costs about $0.0000024 per vCPU-second") without a `pricing_source` and `fetched_at`. Every dollar number in `estimation-infra.json` must trace back to a live source (MCP, WebSearch, WebFetch) OR to the cached fallback with the explicit caveat. Model-only price estimates are a Generate phase blocker -- Generate MUST reject `estimation-infra.json` entries missing `pricing.source` and refuse to advance.

## Step 0 -- Pull live GCP pricing per service (MANDATORY before any cost calculation)

For each distinct `gcp_service` in `gcp-design.json` (e.g. Cloud Run, Cloud SQL MySQL, Memorystore Redis, Cloud Storage, Cloud Load Balancing, Cloud KMS, Pub/Sub, Secret Manager, Cloud Logging, Cloud Monitoring, Dataflow, BigQuery, Artifact Registry):

1. **Prefer `google-developer-knowledge` MCP** (`search_documents`, `get_documents`, `answer_query`) for the canonical pricing page. Query template: `<service-name> pricing site:cloud.google.com`. Example: `Cloud Run pricing site:cloud.google.com`. Capture the URL, fetched date, and the per-SKU rate. Set `pricing.source` = `"google-developer-knowledge MCP"`.

2. **If the MCP returns no usable pricing data, fall back to web search** (the model's WebSearch / WebFetch tools, OR Bash `curl https://cloud.google.com/<service>/pricing` + parse). Capture the same URL, fetched date, and rate. Set `pricing.source` = `"WebSearch"` or `"WebFetch cloud.google.com"`.

3. **Only fall back to `references/shared/pricing-cache.md` if BOTH the MCP and web search are unavailable.** When using the cache, set the per-resource `pricing.source` field to `"cached_fallback"` and add a top-level warning: `"Cost estimate used cached pricing from <cache-date>. Re-run with internet access for accurate numbers."`

4. Cache the live-fetched rates in-memory for the duration of this Estimate run so the same SKU isn't refetched per resource.

### Tried-sources audit (MANDATORY — applies to every per-resource `pricing` object)

Each per-resource pricing object in `estimation-infra.json.resources[].pricing` MUST include a `pricing.attempts[]` array listing EVERY source tried, in order, with the outcome of each attempt. This is the audit trail that proves the lookup actually walked the MCP -> WebSearch -> WebFetch -> cached_fallback hierarchy instead of going straight to the cache.

```json
"pricing": {
  "attempts": [
    {"source": "google-developer-knowledge MCP", "result": "MCP_AUTH_FAILED", "fallback_to": "WebSearch"},
    {"source": "WebSearch", "result": "no_pricing_page_found", "fallback_to": "WebFetch"},
    {"source": "WebFetch https://cloud.google.com/run/pricing", "result": "ok", "fetched_at": "2026-05-18T18:00:00Z"}
  ],
  "source": "WebFetch https://cloud.google.com/run/pricing",
  "fetched_url": "https://cloud.google.com/run/pricing",
  "fetched_at": "2026-05-18T18:00:00Z",
  "sku_rate": "$0.00002400 per vCPU-second"
}
```

**Validation rule (BLOCKING):** If `attempts[]` contains ONLY one entry of `source: "cached_fallback"` without any prior live-attempt entries (i.e. no MCP attempt and no WebSearch/WebFetch attempt was recorded), that resource's pricing FAILS validation. The Generate phase refuses to advance with such a file — the Estimate phase MUST re-run the live lookup or document a real `MCP_*` / `WebSearch_*` failure result in `attempts[]` before falling back.

**Naming consistency (MANDATORY):** the cache-fallback value of `pricing.source` MUST be the literal string `"cached_fallback"` (NOT `"cached"`, NOT `"local-cache"`, NOT `"reference"`, NOT `"pricing-cache.md"`). Generate's validation matches on this exact string. Each `attempts[]` entry's `source` field uses the same vocabulary: `"google-developer-knowledge MCP"`, `"WebSearch"`, `"WebFetch <url>"`, `"cached_fallback"`.

Allowed `result` values: `"ok"`, `"MCP_AUTH_FAILED"`, `"MCP_NO_RESULT"`, `"MCP_UNAVAILABLE"`, `"WebSearch_no_pricing_page_found"`, `"WebSearch_unavailable"`, `"WebFetch_404"`, `"WebFetch_parse_failed"`, `"WebFetch_unavailable"`, `"cached_used"`. Use the most specific value that describes the actual outcome.

## Pricing Mode

The parent `estimate.md` determines pricing source before loading this file.

**Price lookup order for each GCP service in `gcp-design.json`:**

1. **Google Developer Knowledge MCP (preferred when available)** -- Search official Google developer docs for current pricing/model docs, then verify against official pricing pages. Set `pricing.source: "google-developer-knowledge MCP"` (and per-service `pricing_source: "google_developer_knowledge"`).
2. **Official web search** -- Search `cloud.google.com/pricing/[service]` or the service's official pricing page for current rates. Use WebSearch or WebFetch. Set `pricing.source: "WebSearch"` or `"WebFetch cloud.google.com"` (and per-service `pricing_source: "web_search"`).
3. **`shared/pricing-cache.md` (last resort, must be flagged in output)** -- Read once only when BOTH MCP and live web search were attempted and failed. Look up each service by table. Set `pricing.source: "cached_fallback"` AND `pricing_source: "cached_fallback"`, AND add the top-level warning string from Step 0 item 3.
4. **Unavailable** -- If a service is NOT in the cache AND live lookup failed, set `pricing_source: "unavailable"`. Add to `services_with_missing_fallback` and warn the user.

Live lookup is **mandatory** before the cache may be used. The cache is no longer a "quick reference" shortcut -- it is a last-resort fallback that must be flagged in the output.

## Step 0: Validate Design Output

Before pricing queries, validate `gcp-design.json`:

1. **File exists**: If missing, **STOP**. Output: "Phase 3 (Design) not completed. Run Phase 3 first."
2. **Valid JSON**: If parse fails, **STOP**. Output: "Design file corrupted (invalid JSON). Re-run Phase 3."
3. **Required fields**:
   - `clusters` array is not empty: If empty, **STOP**. Output: "No clusters in design. Re-run Phase 3."
   - Each cluster has `resources` array: If missing, **STOP**. Output: "Cluster [id] missing resources. Re-run Phase 3."
   - Each resource has `gcp_service` field: If missing, **STOP**. Output: "Resource [address] missing gcp_service. Re-run Phase 3."
   - Each resource has `gcp_config` field: If missing, **STOP**. Output: "Resource [address] missing gcp_config. Re-run Phase 3."

If all validations pass, proceed to Part 1.

## Web Search Pricing References

When web search is available, use these URLs for each GCP service:

| GCP Service       | Pricing Page URL                                    |
| ------------------ | --------------------------------------------------- |
| Compute Engine     | cloud.google.com/compute/vm-instance-pricing        |
| Cloud Run          | cloud.google.com/run/pricing                        |
| Cloud SQL          | cloud.google.com/sql/pricing                        |
| GKE                | cloud.google.com/kubernetes-engine/pricing           |
| Cloud Storage      | cloud.google.com/storage/pricing                    |
| Cloud Run functions| cloud.google.com/run/pricing                        |
| Cloud Load Balancing | cloud.google.com/vpc/network-pricing               |
| Cloud NAT          | cloud.google.com/nat/pricing                        |
| Memorystore        | cloud.google.com/memorystore/docs/redis/pricing     |
| Cloud Logging      | cloud.google.com/stackdriver/pricing                |
| Secret Manager     | cloud.google.com/secret-manager/pricing             |
| Pub/Sub            | cloud.google.com/pubsub/pricing                     |

---

## Part 1: Calculate Current AWS Costs

Determine the current AWS monthly infrastructure costs. Use the best available source:

1. **`billing-profile.json` (preferred)** -- Use actual billing data as the AWS baseline. Highest confidence (+-5%).
2. **`aws-resource-inventory.json` (fallback)** -- Estimate costs from discovered resource configurations. Wider range (+-20-30%).
3. **`preferences.json` -> `aws_monthly_spend`** -- User-provided monthly spend from clarification.
4. **Ask the user** -- If none of the above are available, ask: "I need your current AWS monthly spend to produce a meaningful cost comparison. What is your approximate AWS monthly infrastructure cost?" Use the user's answer. If the user declines or is unsure, present GCP costs without an AWS comparison and note: "AWS baseline unavailable -- GCP costs shown without comparison."

Present the AWS baseline as a total and per-service breakdown, noting which source was used.

---

## Part 2: Calculate Projected GCP Costs

For each service in `gcp-design.json`, calculate monthly cost using rates from `google-developer-knowledge`, official pricing pages, or `pricing-cache.md`. Track `pricing_source` per service.

**Redshift / deferred analytics (mandatory):** For any resource where `gcp_service` is exactly **`Deferred -- specialist engagement`** OR `aws_type` starts with `aws_redshift_`:

- **Do not** apply BigQuery, Dataflow, or Dataproc rates as the plugin's "projected" analytics stack.
- **Exclude** these resources from Premium / Balanced / Optimized **numeric totals** (or list them under a `deferred_services[]` / `excluded_from_totals` section in `estimation-infra.json` with reason: *pending specialist engagement*).
- In the user-facing summary, state that **GCP analytics costs are unknown** until the **GCP account team** and/or **data analytics migration partner** defines the target architecture.

Calculate 3 cost tiers to show the optimization range:

| Tier          | Description                             | Examples                                                                       |
| ------------- | --------------------------------------- | ------------------------------------------------------------------------------ |
| **Premium**   | Latest generation, highest availability | n2-standard instances, HA Cloud SQL, regional GKE, multi-region storage        |
| **Balanced**  | Standard generation, typical setup      | e2-standard instances, Cloud SQL single zone, zonal GKE, standard storage      |
| **Optimized** | Cost-minimized with trade-offs          | e2-medium with CUD, preemptible nodes, Coldline for cold data, Autopilot GKE  |

**Per-service calculation approach:**

| Domain                 | Formula                                                                              | Key inputs from gcp-design.json                         |
| ---------------------- | ------------------------------------------------------------------------------------ | ------------------------------------------------------- |
| Compute (Cloud Run)    | (vCPU x vCPU-second rate + memory GiB x GiB-second rate) x seconds/month            | `gcp_config.cpu`, `gcp_config.memory`                   |
| Compute (GCE)          | instance rate x 730 hours x instance count                                           | `gcp_config.machine_type`, `gcp_config.count`           |
| Compute (Cloud Run functions) | Cloud Run request + vCPU-second + GiB-second rates | Estimated from usage patterns                          |
| Database (Cloud SQL)   | instance rate x 730 hours x instance count + storage GB x storage rate               | `gcp_config.tier`, `gcp_config.disk_size`               |
| Database (Spanner)     | node rate x 730 hours x node count + storage GB x storage rate                       | `gcp_config.num_nodes`, `gcp_config.disk_size`          |
| Storage (GCS)          | GB x per-GB rate + request estimates                                                 | `gcp_config.storage_gb` or source `aws_config`          |
| Networking (LB)        | forwarding rule hours + data processed x data rate                                   | From compute service count                              |
| Networking (NAT)       | fixed monthly x count + GB processed x data rate                                     | From VPC design                                         |
| GKE                    | cluster fee + node costs (or Autopilot per-pod pricing)                              | `gcp_config.node_count`, `gcp_config.machine_type`      |
| Supporting             | Per-unit rates x quantities (secrets, log GB, metrics)                               | Inferred from service count                             |

Show calculation breakdown per service: rate x quantity = cost. Present all 3 tiers side-by-side.

### Per-resource `pricing` audit trail (MANDATORY)

Each `resources[]` entry in `estimation-infra.json` MUST include a `pricing` object that traces every dollar number back to its live source. The `calculation` field is the audit trail -- a reviewer must be able to follow `rate x quantity` to the dollar:

```json
{
  "aws_address": "...",
  "gcp_service": "...",
  "monthly_estimate_usd": 123.45,
  "pricing": {
    "attempts": [
      {"source": "google-developer-knowledge MCP", "result": "MCP_UNAVAILABLE", "fallback_to": "WebSearch"},
      {"source": "WebSearch", "result": "ok"}
    ],
    "source": "WebSearch" ,
    "fetched_url": "https://cloud.google.com/run/pricing",
    "fetched_at": "2026-05-18T17:30:00Z",
    "sku_rate": "$0.00002400 per vCPU-second (Tier 1 region)",
    "assumed_quantity": "vCPU-seconds/month based on min_instances=2, avg_concurrency=80, etc.",
    "calculation": "rate * quantity = 0.00002400 * 5184000 = $124.42/month"
  }
}
```

Allowed `pricing.source` values: `"google-developer-knowledge MCP"`, `"WebSearch"`, `"WebFetch cloud.google.com"`, `"cached_fallback"` (exactly that literal — see Step 0 "Naming consistency").

A missing or empty `pricing.source`, `pricing.fetched_at`, `pricing.sku_rate`, `pricing.calculation`, or `pricing.attempts[]` is a Generate-phase blocker (see the FORBIDDEN clause at the top of this file).

### Tricky pricing models -- capture assumed usage

Some services have unusual pricing models (queried bytes, slot reservations, GPU-hours, request volume). For each, the skill MUST record the assumed-usage inputs so the dollar number is reproducible:

| Service                 | Required `pricing.assumed_quantity` inputs                                                                                                  |
| ----------------------- | ------------------------------------------------------------------------------------------------------------------------------------------- |
| **BigQuery (on-demand)**| `assumed_query_bytes_per_month` (TiB scanned), `assumed_active_storage_gib`, `assumed_long_term_storage_gib`, `assumed_streaming_inserts_gb` |
| **BigQuery (editions)** | `assumed_slot_hours_per_month`, `edition` (Standard/Enterprise/Enterprise Plus), `commitment` (none/1yr/3yr)                                |
| **Dataflow**            | `assumed_vCPU_hours`, `assumed_memory_GB_hours`, `assumed_pd_GB_hours`, `assumed_ssd_GB_hours`, `worker_type` (batch/streaming)             |
| **Dataproc**            | `assumed_cluster_vCPU_hours`, `assumed_memory_GB_hours`, `assumed_pd_GB_hours`                                                              |
| **Pub/Sub**             | `assumed_message_TiB_per_month`, `subscription_type` (basic/BigQuery/GCS/import)                                                            |
| **Cloud Run**           | `min_instances`, `avg_concurrency`, `assumed_requests_per_month`, `vCPU_seconds_per_month`, `GiB_seconds_per_month`                         |
| **Cloud Run functions** | `assumed_invocations_per_month`, `GB_seconds`, `GHz_seconds`, `egress_GB`                                                                   |
| **Cloud Storage**       | `assumed_storage_GB_by_class` (Standard/Nearline/Coldline/Archive), `assumed_class_a_ops`, `assumed_class_b_ops`, `assumed_retrieval_GB`    |
| **Cloud Logging**       | `assumed_ingestion_GB_per_month` (over 50 GB free), `assumed_storage_GB_month`                                                              |
| **Cloud Monitoring**    | `assumed_custom_metric_time_series` (first 100K free), `assumed_api_calls`                                                                  |
| **Vertex AI Gemini**    | `model_name`, `assumed_input_tokens_per_month`, `assumed_output_tokens_per_month`, `region_tier`                                            |

If the assumed-usage inputs cannot be derived from `gcp-design.json`, `billing-profile.json`, or `preferences.json`, ask the user once for the missing input before calculating -- do NOT fabricate a number.

---

## Part 3: Cost Comparison

Present a side-by-side comparison:

- AWS current monthly total
- GCP Premium / Balanced / Optimized monthly totals
- Difference (savings or increase) per tier vs AWS
- Per-service breakdown for the Balanced tier

---

## Part 4: AWS Data Transfer Egress (Vendor Fees Only)

This section covers **AWS vendor/network charges** for outbound data during migration -- not human labor or professional-services costs (those are never presented as dollar estimates by this advisor).

**Billing data check:** Before generating this section, check if `$MIGRATION_DIR/billing-profile.json` exists.

### IF billing data IS available (`billing-profile.json` exists):

**Data transfer** -- egress fees from AWS during migration. AWS charges for outbound data transfer; volume depends on database sizes and storage to migrate. Use the billing data to estimate the volume of data that needs to move.

Set `billing_data_available: true` in the output `migration_cost_considerations` object.

### IF billing data is NOT available (`billing-profile.json` does not exist):

**Omit AWS data transfer fee estimates.** Without billing data, there is no grounding for egress projections. Instead, include only this note in the output:

Set `migration_cost_considerations` to:

```json
{
  "categories": [],
  "billing_data_available": false,
  "note": "Data transfer cost estimates require AWS billing data. Re-run discovery with an AWS Cost and Usage Report to see AWS egress fee projections."
}
```

In the user-facing summary, when billing data is missing, state: "AWS data transfer egress estimates require billing data. Provide a Cost and Usage Report and re-run discovery to see vendor egress projections."

---

## Part 5: ROI Analysis

Present the monthly and annual cost difference between AWS baseline and each GCP tier (Premium, Balanced, Optimized). This is the recurring savings (or increase) the customer can expect.

- If GCP is cheaper: present the monthly and annual savings for each tier
- If GCP is more expensive: state clearly and note that cost savings alone do not justify migration -- operational benefits must be the driver

**Operational efficiency factors to highlight** (qualitative -- do not assign dollar values):

- Reduction in operational overhead from managed services (Cloud Run vs self-managed, Cloud SQL vs self-hosted DB)
- Reduced on-call burden from GCP-managed HA, patching, and scaling
- Engineering time freed for product work instead of infrastructure maintenance

**Non-cost benefits to present:** operational efficiency, data analytics ecosystem (BigQuery), AI/ML capabilities (Vertex AI), Kubernetes leadership (GKE), vendor diversification, scaling flexibility (sustained use discounts, committed use discounts, preemptible VMs).

**Note:** AWS data transfer egress fees (if estimated in Part 4) are **vendor** one-time charges excluded from recurring ROI calculations -- not human migration costs.

---

## Part 6: Cost Optimization Opportunities

Present applicable optimizations with estimated savings:

| Optimization                 | Savings Range | Applies To                       | When                                    |
| ---------------------------- | ------------- | -------------------------------- | --------------------------------------- |
| Committed Use Discounts      | 40-57%        | Compute Engine, Cloud SQL        | Post-migration (after validating usage) |
| Sustained Use Discounts      | Up to 30%     | Compute Engine (N1/N2)           | Automatic                               |
| Cloud Storage Nearline/Coldline | 50-80%     | Cloud Storage                    | During migration                        |
| Preemptible / Spot VMs       | 60-91%        | Batch/non-critical workloads     | If batch jobs exist                     |
| GKE Autopilot                | 20-40%        | GKE clusters                     | If overprovisioned clusters exist       |

For each applicable optimization, calculate the before and after monthly cost.

---

## Part 7: Recommendation

Present 3 paths:

1. **Migrate with Optimizations (Best ROI)** -- optimized service choices, monthly cost, projected annual savings
2. **Phased Migration (Lower Risk)** -- cluster-by-cluster per design evaluation order, validate each before proceeding
3. **Stay on AWS (Lowest Cost)** -- only if GCP is more expensive and costs are the sole metric

Include migrate/stay decision factors:

- **Migrate if:** operational efficiency matters, GCP-specific services needed (BigQuery, Vertex AI, GKE), batch workloads (preemptible savings), long-term GCP strategy, growing infrastructure
- **Stay if:** cost is the only metric and GCP is more expensive, team deeply experienced with AWS, no need for GCP-specific services

---

## Output

Read `shared/schema-estimate-infra.md` for the `estimation-infra.json` schema and validation checklist, then write `estimation-infra.json` to `$MIGRATION_DIR/`.

## Present Summary

After writing `estimation-infra.json`, present a concise summary to the user:

1. **Pricing source and accuracy**: State whether prices came from Google Developer Knowledge MCP, official web search, cache, or fallback, and the accuracy range (+-5-10% for infrastructure from official live lookup/cache, +-15-25% if cache is stale). Example: "Estimates based on cached GCP pricing (2026-04-12), accuracy +-5-10%."
2. AWS baseline vs GCP projected (balanced tier) -- one-line comparison
3. Three-tier table: **Premium**, **Balanced**, **Optimized** with monthly totals. Under or beside each label, use the **short subtitles**: Premium -- *Highest resilience / highest monthly estimate in this model*; Balanced -- *Default scenario; compare AWS to this first*; Optimized -- *Lower monthly estimate; committed use / preemptible / storage trade-offs assumed*. Add a one-line **How to read**: three figures are **pricing scenarios** for the same architecture (high -> mid -> low); **not** three Terraform stacks. When Terraform is generated later, it aligns with **Balanced**.
4. Per-service cost breakdown (balanced tier, 1 line per service)
5. **If billing data available**: Estimated AWS data transfer egress fees. **If billing data NOT available**: "Data transfer cost estimates require AWS billing data."
6. Monthly and annual savings (or increase) vs AWS per tier
7. Top 2-3 optimization opportunities with savings amounts

Keep it under 25 lines. The user can ask for details or re-read `estimation-infra.json` at any time.

## Generate Phase Integration

The Generate phase (`generate.md`) uses `estimation-infra.json` as follows:

1. **`projected_costs.breakdown`** -- Budget allocation per cluster migration phase
2. **`migration_cost_considerations`** -- Data transfer egress cost estimates (if billing data available)
3. **`optimization_opportunities`** -- Which optimizations to implement and when (some during initial migration, some post-migration)
4. **`cost_comparison`** -- Set cost monitoring targets and alerts for each migrated cluster
5. **`recommendation.next_steps`** -- Prerequisites for starting generation
6. **Cost tier vs Terraform** -- Generated **`terraform/`** implements **one** baseline aligned with the **Balanced** scenario; **Premium** and **Optimized** are **estimate-only** bands unless the user changes IaC. See `generate-artifacts-infra.md` (`terraform/README.md`, `migration_summary` output).

The generated artifacts reference the cost estimates to set per-cluster cost monitoring thresholds and validate that actual GCP spend aligns with projections after each cluster migration.
