# Estimate Phase: Infrastructure Cost Analysis

## Contents

- Step 0 -- Pull live GCP pricing per service (MANDATORY before any cost calculation)
- Pricing Mode
- Step 0.9: Validate Design Output (runs after the Step 0 pricing pull, before Part 1)
- Web Search Pricing References
- Part 1: Calculate Current AWS Costs
- Part 2: Calculate Projected GCP Costs
- Part 3: Cost Comparison
- Part 4: AWS Data Transfer Egress (Vendor Fees Only)
- Part 5: ROI Analysis
- Part 6: Cost Optimization Opportunities
- Part 7: Recommendation
- Final Step -- Pre-write self-check (MANDATORY before writing estimation-infra.json)
- Present Summary
- Generate Phase Integration

> Loaded by estimate.md when gcp-design.json exists.

**Execute ALL steps in order. Do not skip or optimize.**

> **FORBIDDEN:** Citing a price from prior knowledge alone (e.g. "Cloud Run costs about $0.0000XX per vCPU-second" — deliberately a placeholder; never copy a rate out of an instruction file) without a recorded live tool call this run. Every dollar number in `estimation-infra.json` must trace back to a live source captured during THIS run — the bundled `gcp-pricing` CLI against the Cloud Billing Catalog API (primary), `google-developer-knowledge` MCP (secondary), or WebFetch of an official cloud.google.com pricing page (tertiary). Model-recalled prices are a Generate-phase blocker -- Generate MUST reject `estimation-infra.json` entries lacking `pricing.attempts[].evidence` from a live call and refuse to advance.

## Step 0 -- Pull live GCP pricing per service (MANDATORY before any cost calculation)

The orchestrator (`estimate.md` Step 0) has already established the source hierarchy and built the service-id map via `gcp-pricing services`. This file repeats the per-resource recording requirements.

For each distinct `gcp_service` in `gcp-design.json` (Cloud Run, Cloud SQL MySQL, Memorystore Redis, Cloud Storage, Cloud Load Balancing, Cloud KMS, Pub/Sub, Secret Manager, Cloud Logging, Cloud Monitoring, Dataflow, BigQuery, Artifact Registry, etc.):

1. **PRIMARY — `gcp-pricing` CLI (Cloud Billing Catalog API).** Look up the service's `serviceId` from the `gcp-pricing services` output (built in `estimate.md` Step 0a), then:
   ```bash
   gcp-pricing skus --service "${SERVICE_ID}" --region "${REGION}" --filter "<sku description regex>" --currency USD
   ```
   The tool returns `tieredRates[].unitPrice` as a ready-to-use decimal string (computed from the API's `Money` `units`+`nanos`), already filtered to SKUs whose `serviceRegions` contain the target region. Set `pricing.source = "gcp-pricing (Cloud Billing Catalog API)"`.

2. **SECONDARY — `google-developer-knowledge` MCP.** Only if step 1 fails for this service (no matching SKU, region not covered, tool error). Query template: `<service-name> pricing site:cloud.google.com`. Set `pricing.source = "google-developer-knowledge MCP"`.

3. **TERTIARY — WebFetch official pricing page.** Only if both 1 and 2 failed. Use the URL table below. Set `pricing.source = "WebFetch cloud.google.com"`.

4. **STOP if all three fail.** Do NOT recall prices from prior knowledge. Do NOT emit estimates with fabricated rates. Output: "Pricing unavailable for [service] — live lookup failed via all three sources. Fix network/auth, exclude from totals, or provide a manual rate."

5. Cache the live-fetched rate in-memory for the duration of this Estimate run so the same SKU isn't refetched per resource of the same type.

### Tried-sources audit (MANDATORY — applies to every per-resource `pricing` object)

Each per-resource pricing object in `estimation-infra.json.resources[].pricing` MUST include a `pricing.attempts[]` array listing EVERY source tried, in order, with the outcome and an evidence excerpt. This is the audit trail that proves the lookup actually called a live source instead of recalling from memory.

```json
"pricing": {
  "attempts": [
    {
      "source": "gcp-pricing (Cloud Billing Catalog API)",
      "tool_call": "gcp-pricing skus --service 152E-C115-5142 --region us-central1 --filter \"Services CPU\" --currency USD",
      "result": "ok",
      "evidence": "skuId: 4856-B847-F1EB | description: 'Services CPU (Request-based billing)' | tieredRates[0].unitPrice = \"0.000024\" USD per vCPU-second | auth_mode: adc | retrieved_at: 2026-07-08T12:00:00Z",
      "fetched_at": "2026-07-08T12:00:00Z"
    }
  ],
  "source": "gcp-pricing (Cloud Billing Catalog API)",
  "fetched_url": "https://cloudbilling.googleapis.com/v1/services/152E-C115-5142/skus?pageSize=5000&currencyCode=USD",
  "fetched_at": "2026-07-08T12:00:00Z",
  "sku_rate": "$0.000024 per vCPU-second (Tier 1 region, on-demand)"
}
```

**Validation rules (BLOCKING — Generate refuses to advance if violated):**

1. **At least one `attempts[]` entry with `result == "ok"`.** If every attempt failed, the resource has no price and the file is not valid.
2. **`evidence` field is REQUIRED on every successful (`result == "ok"`) attempt.** It must be a non-empty 1–3 line verbatim excerpt of the actual tool-call response showing the rate. "Looked it up" / "from docs" / "approximately" are NOT evidence — they prove fabrication.
3. **`tool_call` field is REQUIRED on every attempt.** It must be the literal command or MCP invocation made (e.g. the full `gcp-pricing` command line, or the MCP tool name + query). A tool_call field of `"recalled"`, `"from training"`, `"general knowledge"`, or anything similar means the entry is fabricated — Generate phase rejects.
4. **`source` enum**: `"gcp-pricing (Cloud Billing Catalog API)"`, `"google-developer-knowledge MCP"`, `"WebFetch cloud.google.com"`, `"user_provided"`. (No `"cached"` / `"cached_fallback"` — there is no pricing cache.)

Allowed `result` values: `"ok"`, `"MCP_AUTH_FAILED"`, `"MCP_NO_RESULT"`, `"MCP_UNAVAILABLE"`, `"BillingAPI_NO_SKU_MATCH"`, `"BillingAPI_AUTH_FAILED"`, `"BillingAPI_REGION_NOT_COVERED"`, `"WebFetch_404"`, `"WebFetch_parse_failed"`, `"WebFetch_unavailable"`. Use the most specific value.

## Pricing Mode

The parent `estimate.md` determines pricing source before loading this file. The hierarchy above (`gcp-pricing` CLI → google-developer-knowledge MCP → WebFetch → STOP) is binding. There is no fallback to a cache file. If all live sources fail, report the failure and STOP rather than emit a stale or recalled number.

## Step 0.9: Validate Design Output (runs after the Step 0 pricing pull, before Part 1)

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

| GCP Service          | Pricing Page URL                                |
| -------------------- | ----------------------------------------------- |
| Compute Engine       | cloud.google.com/compute/vm-instance-pricing    |
| Cloud Run            | cloud.google.com/run/pricing                    |
| Cloud SQL            | cloud.google.com/sql/pricing                    |
| GKE                  | cloud.google.com/kubernetes-engine/pricing      |
| Cloud Storage        | cloud.google.com/storage/pricing                |
| Cloud Run functions  | cloud.google.com/run/pricing                    |
| Cloud Load Balancing | cloud.google.com/vpc/network-pricing            |
| Cloud NAT            | cloud.google.com/nat/pricing                    |
| Memorystore          | cloud.google.com/memorystore/docs/redis/pricing |
| Cloud Logging        | cloud.google.com/stackdriver/pricing            |
| Secret Manager       | cloud.google.com/secret-manager/pricing         |
| Pub/Sub              | cloud.google.com/pubsub/pricing                 |

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

For each service in `gcp-design.json`, calculate monthly cost using rates fetched live this run via the `gcp-pricing` CLI (primary), `google-developer-knowledge` MCP (secondary), or WebFetch of official pricing pages (tertiary). Track `pricing.source` per resource. There is no cache — recall from prior knowledge is fabrication.

**Quantity grounding (MANDATORY).** The `pricing.assumed_quantity` for every resource MUST be derived from `preferences.json.design_constraints.access_pattern_data` (the access-pattern signal captured during Clarify Q_SIZING1/Q_SIZING2). Each `gcp-design.json` resource carries a `sizing_source` field set by Design Step 1.5 — use it to find the relevant `access_pattern_data` entry:

- `sizing_source: "access_pattern_data: <aws_address>"` → look up `access_pattern_data[<aws_address>].metrics` and cite the specific metric value(s) inline, e.g. `"vCPU-seconds/month from CloudWatch RequestCountPerTarget.avg=432 req/min × concurrency=80 = 5.4 instances avg × 730h × 3600s × 1 vCPU = 14,191,200 vCPU-sec"`.
- `sizing_source: "access_pattern_data: cluster:<cluster_name>"` → look up cluster-level verbal data and cite the user's stated peak_rps + avg_request_duration_ms in the same way.
- `sizing_source: "conservative_defaults"` → write the assumption verbatim, e.g. `"conservative_defaults: 2× source IaC = min_instances=4, max_instances=8, 1 vCPU each, 50% utilization → 14,016,000 vCPU-sec"`. Also flag in `warnings[]`: "Resource <aws_address> sized from conservative defaults — actual cost may differ by ±100%".

The Final Step self-check at the bottom of this file validates that every `assumed_quantity` is grounded. Vague strings ("estimated typical usage", "approximately", "based on similar workloads") FAIL the self-check.

**Redshift / deferred analytics (mandatory):** For any resource where `gcp_service` is exactly **`Deferred -- specialist engagement`** OR `aws_type` starts with `aws_redshift_`:

- **Do not** apply BigQuery, Dataflow, or Dataproc rates as the plugin's "projected" analytics stack.
- **Exclude** these resources from Premium / Balanced / Optimized **numeric totals** (or list them under a `deferred_services[]` / `excluded_from_totals` section in `estimation-infra.json` with reason: _pending specialist engagement_).
- In the user-facing summary, state that **GCP analytics costs are unknown** until the **GCP account team** and/or **data analytics migration partner** defines the target architecture.

Calculate 3 cost tiers to show the optimization range:

| Tier          | Description                             | Examples                                                                     |
| ------------- | --------------------------------------- | ---------------------------------------------------------------------------- |
| **Premium**   | Latest generation, highest availability | n2-standard instances, HA Cloud SQL, regional GKE, multi-region storage      |
| **Balanced**  | Standard generation, typical setup      | e2-standard instances, Cloud SQL single zone, zonal GKE, standard storage    |
| **Optimized** | Cost-minimized with trade-offs          | e2-medium with CUD, preemptible nodes, Coldline for cold data, Autopilot GKE |

**Per-service calculation approach:**

| Domain                        | Formula                                                                  | Key inputs from gcp-design.json                    |
| ----------------------------- | ------------------------------------------------------------------------ | -------------------------------------------------- |
| Compute (Cloud Run)           | (vCPU x vCPU-second rate + memory GiB x GiB-second rate) x seconds/month | `gcp_config.cpu`, `gcp_config.memory`              |
| Compute (GCE)                 | instance rate x 730 hours x instance count                               | `gcp_config.machine_type`, `gcp_config.count`      |
| Compute (Cloud Run functions) | Cloud Run request + vCPU-second + GiB-second rates                       | Estimated from usage patterns                      |
| Database (Cloud SQL)          | instance rate x 730 hours x instance count + storage GB x storage rate   | `gcp_config.tier`, `gcp_config.disk_size`          |
| Database (Spanner)            | node rate x 730 hours x node count + storage GB x storage rate           | `gcp_config.num_nodes`, `gcp_config.disk_size`     |
| Storage (GCS)                 | GB x per-GB rate + request estimates                                     | `gcp_config.storage_gb` or source `aws_config`     |
| Networking (LB)               | forwarding rule hours + data processed x data rate                       | From compute service count                         |
| Networking (NAT)              | fixed monthly x count + GB processed x data rate                         | From VPC design                                    |
| GKE                           | cluster fee + node costs (or Autopilot per-pod pricing)                  | `gcp_config.node_count`, `gcp_config.machine_type` |
| Supporting                    | Per-unit rates x quantities (secrets, log GB, metrics)                   | Inferred from service count                        |

Show calculation breakdown per service: rate x quantity = cost. Present all 3 tiers side-by-side.

### Per-resource `pricing` audit trail (MANDATORY)

Each `resources[]` entry in `estimation-infra.json` MUST include a `pricing` object that traces every dollar number back to its live source. The `calculation` field is the audit trail -- a reviewer must be able to follow `rate x quantity` to the dollar:

```json
{
  "aws_address": "...",
  "gcp_service": "...",
  "monthly_estimate_usd": 124.42,
  "pricing": {
    "attempts": [
      {
        "source": "gcp-pricing (Cloud Billing Catalog API)",
        "tool_call": "gcp-pricing skus --service 152E-C115-5142 --region us-central1 --filter \"Services CPU\" --currency USD",
        "result": "ok",
        "evidence": "skuId: 4856-B847-F1EB | description: 'Services CPU (Request-based billing)' | tieredRates[0].unitPrice = \"0.000024\" USD per vCPU-second | auth_mode: adc",
        "fetched_at": "2026-07-08T12:00:00Z"
      }
    ],
    "source": "gcp-pricing (Cloud Billing Catalog API)",
    "fetched_url": "https://cloudbilling.googleapis.com/v1/services/152E-C115-5142/skus?pageSize=5000&currencyCode=USD",
    "fetched_at": "2026-07-08T12:00:00Z",
    "sku_rate": "$0.000024 per vCPU-second (Tier 1 region)",
    "assumed_quantity": "vCPU-seconds/month based on min_instances=2, avg_concurrency=80, etc.",
    "calculation": "rate * quantity = 0.000024 * 5184000 = $124.42/month"
  }
}
```

Allowed `pricing.source` values: `"gcp-pricing (Cloud Billing Catalog API)"`, `"google-developer-knowledge MCP"`, `"WebFetch cloud.google.com"`, `"user_provided"`. (There is no pricing cache — no `"cached_fallback"` value.)

A missing or empty `pricing.source`, `pricing.fetched_at`, `pricing.sku_rate`, `pricing.calculation`, `pricing.attempts[]`, or `pricing.attempts[].evidence` (on the successful entry) is a Generate-phase blocker (see the FORBIDDEN clause at the top of this file).

### Tricky pricing models -- capture assumed usage

Some services have unusual pricing models (queried bytes, slot reservations, GPU-hours, request volume). For each, the skill MUST record the assumed-usage inputs so the dollar number is reproducible:

| Service                  | Required `pricing.assumed_quantity` inputs                                                                                                                                                                                                                                                           |
| ------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **BigQuery (on-demand)** | `assumed_query_bytes_per_month` (TiB scanned), `assumed_active_storage_gib`, `assumed_long_term_storage_gib`, `assumed_streaming_inserts_gb`                                                                                                                                                         |
| **BigQuery (editions)**  | `assumed_slot_hours_per_month`, `edition` (Standard/Enterprise/Enterprise Plus), `commitment` (none/1yr/3yr)                                                                                                                                                                                         |
| **Dataflow**             | `assumed_vCPU_hours`, `assumed_memory_GB_hours`, `assumed_pd_GB_hours`, `assumed_ssd_GB_hours`, `worker_type` (batch/streaming)                                                                                                                                                                      |
| **Dataproc**             | `assumed_cluster_vCPU_hours`, `assumed_memory_GB_hours`, `assumed_pd_GB_hours`                                                                                                                                                                                                                       |
| **Pub/Sub**              | `assumed_message_TiB_per_month`, `subscription_type` (basic/BigQuery/GCS/import)                                                                                                                                                                                                                     |
| **Cloud Run**            | `min_instances`, `avg_concurrency`, `assumed_requests_per_month`, `vCPU_seconds_per_month`, `GiB_seconds_per_month`                                                                                                                                                                                  |
| **Cloud Run functions**  | `assumed_invocations_per_month`, `GB_seconds`, `GHz_seconds`, `egress_GB`                                                                                                                                                                                                                            |
| **Cloud Storage**        | `assumed_storage_GB_by_class` (Standard/Nearline/Coldline/Archive), `assumed_class_a_ops`, `assumed_class_b_ops`, `assumed_retrieval_GB`                                                                                                                                                             |
| **Cloud Logging**        | `assumed_ingestion_GB_per_month` (over 50 GB free), `assumed_storage_GB_month`                                                                                                                                                                                                                       |
| **Cloud Monitoring**     | `assumed_metric_MiB_ingested_per_month` (billed per MiB ingested, tiered; first 150 MiB per billing account free — there is NO per-time-series pricing or "first 100K series free" allotment; confirm current tiers on the live Observability pricing page), `assumed_read_api_time_series_returned` |
| **Vertex AI Gemini**     | `model_name`, `assumed_input_tokens_per_month`, `assumed_output_tokens_per_month`, `region_tier`                                                                                                                                                                                                     |
| **Agent Runtime**        | `cpu`, `memory_GiB`, `min_instances`, `assumed_active_instance_hours_per_month` (default 730 x `min_instances`)                                                                                                                                                                                      |

**Agent Runtime** rows: the SKUs live under the same billing service as the model platform — use the lookup recipe in `estimate-ai.md` > Agent Runtime Compute Pricing; price vCPU-hour + GiB-hour, never per-request.

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

**Non-cost benefits to present:** operational efficiency, data analytics ecosystem (BigQuery), AI/ML capabilities (Gemini Enterprise Agent Platform, formerly Vertex AI), Kubernetes leadership (GKE), vendor diversification, scaling flexibility (sustained use discounts, committed use discounts, preemptible VMs).

**Note:** AWS data transfer egress fees (if estimated in Part 4) are **vendor** one-time charges excluded from recurring ROI calculations -- not human migration costs.

---

## Part 6: Cost Optimization Opportunities

Present applicable optimizations with estimated savings:

| Optimization                    | Savings Range                                                                                                                                                                    | Applies To                                   | When                                    |
| ------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------- | --------------------------------------- |
| Committed Use Discounts         | Verify live (Google currently advertises up to ~55% — ~70% memory-optimized — for 3-year RESOURCE-BASED Compute CUDs; flexible CUDs are lower (~28%/46%); Cloud SQL CUDs differ) | Compute Engine, Cloud SQL                    | Post-migration (after validating usage) |
| Sustained Use Discounts         | Up to 30% on the N1 family ONLY; N2/N2D/C2 up to 20%; **E2 and newer series (C3, N4, C4, …) get NO SUD**                                                                         | Compute Engine (eligible legacy series only) | Automatic                               |
| Cloud Storage Nearline/Coldline | 50-80%                                                                                                                                                                           | Cloud Storage                                | During migration                        |
| Preemptible / Spot VMs          | Up to 91%                                                                                                                                                                        | Batch/non-critical workloads                 | If batch jobs exist                     |
| GKE Autopilot                   | Workload-dependent — no official published %; present as "eliminates node overprovisioning", not a number                                                                        | GKE clusters                                 | If overprovisioned clusters exist       |

For each applicable optimization, calculate the before and after monthly cost. Discount percentages drift — verify each against the live discount docs before quoting to the user (same live-lookup rule as SKU rates).

---

## Part 7: Recommendation

Present 3 paths:

1. **Migrate with Optimizations (Best ROI)** -- optimized service choices, monthly cost, projected annual savings
2. **Phased Migration (Lower Risk)** -- cluster-by-cluster per design evaluation order, validate each before proceeding
3. **Stay on AWS (Lowest Cost)** -- only if GCP is more expensive and costs are the sole metric

Include migrate/stay decision factors:

- **Migrate if:** operational efficiency matters, GCP-specific services needed (BigQuery, Agent Platform, GKE), batch workloads (preemptible savings), long-term GCP strategy, growing infrastructure
- **Stay if:** cost is the only metric and GCP is more expensive, team deeply experienced with AWS, no need for GCP-specific services

---

## Final Step -- Pre-write self-check (MANDATORY before writing estimation-infra.json)

Before writing the file to disk, walk every `resources[]` entry and verify all of the following. If any check fails, **STOP**, list the failing `aws_address`(es) plus the specific check that failed, and re-do Step 0 / the per-resource pricing math for those resources. You may not write the file until every resource passes.

1. **Live tool call recorded.** `pricing.attempts[]` contains at least one entry where `result == "ok"` AND `evidence` is a non-empty 1-3 line excerpt of an actual tool-call response. An entry with `tool_call: "recalled"` / `"from training"` / empty `evidence` is fabrication — fail.
2. **Source enum matches.** `pricing.source` is one of `"gcp-pricing (Cloud Billing Catalog API)"`, `"google-developer-knowledge MCP"`, `"WebFetch cloud.google.com"`, `"user_provided"`. No legacy `"cached"` / `"cached_fallback"` / `"gcloud billing catalog API"` values.
3. **Calculation reproducibility.** `pricing.calculation` parses as `<rate> * <quantity> = <monthly_estimate_usd>` and the arithmetic checks within +/- $0.50 of the stated `monthly_estimate_usd`. Example failure: rate `$0.000024`, quantity`5184000`, monthly_estimate_usd`$500`—`0.000024 * 5184000 = $124.42`, off by `$375.58` — fail.
4. **Assumed quantity is grounded.** `pricing.assumed_quantity` references either (a) a value from `preferences.json.design_constraints.access_pattern_data` (the access-pattern signal captured during Clarify Q_SIZING), or (b) the explicit `conservative_defaults` chosen by the user. A vague string like "estimated typical usage" without one of these grounds is fail — re-derive from the user's chosen sizing path.

After all resources pass, then read `shared/schema-estimate-infra.md` for the `estimation-infra.json` schema and validation checklist, then write `estimation-infra.json` to `$MIGRATION_DIR/`.

## Present Summary

After writing `estimation-infra.json`, present a concise summary to the user:

1. **Pricing source and accuracy**: State the proportion of resources priced from each live source (e.g. "12 of 14 resources priced via gcp-pricing (Cloud Billing Catalog API); 2 via WebFetch cloud.google.com — no fabrication"), and the accuracy range (+/-2-5% from the Catalog API; +/-5-10% from WebFetch). If any service had to be excluded for lack of a live price, list it here.
2. AWS baseline vs GCP projected (balanced tier) -- one-line comparison
3. Three-tier table: **Premium**, **Balanced**, **Optimized** with monthly totals. Under or beside each label, use the **short subtitles**: Premium -- _Highest resilience / highest monthly estimate in this model_; Balanced -- _Default scenario; compare AWS to this first_; Optimized -- _Lower monthly estimate; committed use / preemptible / storage trade-offs assumed_. Add a one-line **How to read**: three figures are **pricing scenarios** for the same architecture (high -> mid -> low); **not** three Terraform stacks. When Terraform is generated later, it aligns with **Balanced**.
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
