# Infrastructure Estimate Schema

Schema for `estimation-infra.json`, produced by `estimate-infra.md`.

---

## Cost tiers (`projected_costs` / `cost_comparison`)

The fields **`gcp_monthly_premium`**, **`gcp_monthly_balanced`**, **`gcp_monthly_optimized`** (under `projected_costs`) and **`option_a_premium`**, **`option_b_balanced`**, **`option_c_optimized`** (under `cost_comparison`) are **three pricing scenarios** for the **same** AWS-to-GCP mapping in `gcp-design.json`. They are **not** three alternative Terraform roots.

| Tier key        | User-facing label | Subtitle (use in reports / MIGRATION_GUIDE)                                                        |
| --------------- | ----------------- | -------------------------------------------------------------------------------------------------- |
| **`premium`**   | Premium           | _Highest resilience / highest monthly estimate in this model_                                      |
| **`balanced`**  | Balanced          | _Default scenario; compare AWS to this first_                                                      |
| **`optimized`** | Optimized         | _Lower monthly estimate; committed use discounts / preemptible / storage class trade-offs assumed_ |

**How to read:** Scenario order is **highest -> middle -> lowest** monthly GCP estimate for the modeled architecture. **Balanced** is the **primary** comparison row vs the AWS baseline. **Premium** and **Optimized** are **bounds** (HA vs cost-optimization skew).

**Terraform:** When the Generate phase produces `terraform/`, it implements **one** infrastructure baseline aligned with the **Balanced** scenario (`aligned_with_estimate_tier` in the `migration_summary` output). **Premium** and **Optimized** remain **estimate-only** unless the customer edits IaC. See `references/phases/generate/generate-artifacts-infra.md` (`terraform/README.md`, `main.tf` header comment).

---

## estimation-infra.json schema

```json
{
  "phase": "estimate",
  "design_source": "infrastructure",
  "timestamp": "2026-04-12T14:00:00Z",
  "pricing_source": {
    "status": "gcp_pricing_catalog_api|google_developer_knowledge|web_fetch|user_provided|unavailable",
    "message": "12 of 14 resources priced via gcp-pricing (Cloud Billing Catalog API); 2 via WebFetch cloud.google.com",
    "services_by_source": {
      "gcp_pricing_catalog_api": ["Cloud Run", "Cloud SQL", "Memorystore"],
      "google_developer_knowledge": [],
      "web_fetch": ["Artifact Registry"],
      "user_provided": [],
      "unavailable": []
    },
    "services_with_missing_fallback": []
  },
  "warnings": [],
  "accuracy_confidence": "+-2-5%",

  "resources": [
    {
      "aws_address": "aws_ecs_service.web",
      "gcp_service": "Cloud Run",
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
        "fetched_at": "2026-05-19T12:00:00Z",
        "sku_rate": "$0.000024 per vCPU-second (Tier 1 region)",
        "assumed_quantity": "vCPU-seconds/month from access_pattern_data: avg_rps=120 * concurrency=80 = 1.5 instances avg * 730h * 3600s * 1 vCPU = 3,942,000 vCPU-sec, rounded to 5,184,000 with 30% headroom",
        "calculation": "rate * quantity = 0.000024 * 5184000 = $124.42/month"
      }
    }
  ],

  "current_costs": {
    "source": "billing_data|inventory_estimate|preferences|user_provided|unavailable",
    "aws_monthly": 300,
    "aws_annual": 3600,
    "baseline_note": "From billing-profile.json actual spend data",
    "breakdown": { "compute": 75, "database": 50, "storage": 40, "networking": 20, "other": 15 }
  },

  "projected_costs": {
    "gcp_monthly_premium": 1003,
    "gcp_monthly_balanced": 265,
    "gcp_monthly_optimized": 194,
    "gcp_annual_optimized": 2328,
    "breakdown": {
      "compute": {
        "service": "Cloud Run",
        "monthly": 71,
        "alternative": { "service": "Compute Engine (e2-medium)", "monthly": 50, "savings": 21 }
      },
      "database": {
        "service": "Cloud SQL PostgreSQL",
        "monthly": 269,
        "alternative": {
          "service": "Cloud SQL PostgreSQL (db-custom-1-3840)",
          "monthly": 75,
          "savings": 194
        }
      },
      "storage": {
        "service": "Cloud Storage Standard + Nearline",
        "monthly": 86,
        "alternative": { "service": "Cloud Storage Coldline", "monthly": 65, "savings": 21 }
      },
      "networking": { "service": "Cloud Load Balancing + Cloud NAT", "monthly": 53 },
      "supporting": { "secret_manager": 1.20, "cloud_logging": 35.30 }
    }
  },

  "cost_comparison": {
    "aws_monthly_baseline": 300,
    "option_a_premium": {
      "gcp_monthly": 1003,
      "monthly_difference": 703,
      "annual_difference": 8436,
      "percent_change": "+234%"
    },
    "option_b_balanced": {
      "gcp_monthly": 265,
      "monthly_difference": -35,
      "annual_difference": -420,
      "percent_change": "-12%"
    },
    "option_c_optimized": {
      "gcp_monthly": 194,
      "monthly_difference": -106,
      "annual_difference": -1272,
      "percent_change": "-35%"
    }
  },

  "migration_cost_considerations": {
    "billing_data_available": true,
    "categories": [
      "Data transfer (AWS egress fees based on migration volume)"
    ],
    "note": "AWS charges for outbound data transfer during migration. Volume depends on database sizes and storage to migrate."
  },

  "roi_analysis": {
    "recurring_savings": {
      "monthly_difference_balanced": -35,
      "monthly_difference_optimized": -106,
      "annual_difference_balanced": -420,
      "annual_difference_optimized": -1272,
      "note": "Negative = GCP cheaper. Based on balanced/optimized tiers vs AWS baseline."
    },
    "operational_efficiency_factors": [
      "Reduced operational overhead from managed services (Cloud Run, Cloud SQL)",
      "Reduced on-call burden from GCP-managed HA, patching, and scaling",
      "Engineering time freed for product work instead of infrastructure maintenance"
    ],
    "non_cost_benefits": [
      "Operational efficiency (fewer engineers needed for managed services)",
      "Strong data analytics and BigQuery ecosystem",
      "Broader AI/ML capabilities with the Gemini Enterprise Agent Platform (formerly Vertex AI)",
      "Better Kubernetes experience with GKE",
      "Vendor diversification (reduce single-vendor risk)",
      "Committed use discounts, sustained use discounts, preemptible VMs flexibility"
    ],
    "note": "AWS data transfer egress fees (if estimated) are vendor one-time charges excluded from recurring ROI calculations. Human/professional-services migration costs are not modeled here."
  },

  "optimization_opportunities": [
    {
      "opportunity": "Committed Use Discounts",
      "target_services": ["Cloud SQL", "Compute Engine"],
      "savings_monthly": 58,
      "savings_percent": "40%",
      "commitment": "1-year",
      "implementation_effort": "low",
      "description": "Commit to 1-year or 3-year usage for predictable workloads"
    },
    {
      "opportunity": "Cloud Storage Nearline",
      "target_services": ["Cloud Storage"],
      "savings_monthly": 52,
      "savings_percent": "38%",
      "commitment": "none",
      "implementation_effort": "low",
      "description": "Move infrequently accessed data to Nearline or Coldline storage class"
    },
    {
      "opportunity": "Preemptible VMs for Batch",
      "target_services": ["Compute Engine"],
      "savings_monthly": 6,
      "savings_percent": "70%",
      "commitment": "none",
      "implementation_effort": "medium",
      "description": "Use preemptible or Spot VMs for fault-tolerant batch processing jobs"
    },
    {
      "opportunity": "Sustained Use Discounts",
      "target_services": ["Compute Engine", "Cloud SQL"],
      "savings_monthly": 20,
      "savings_percent": "25%",
      "commitment": "none (automatic)",
      "implementation_effort": "low",
      "description": "GCP automatic discounts for sustained monthly usage (applied automatically for eligible resources)"
    }
  ],

  "financial_summary": {
    "current_aws_monthly": 300,
    "projected_gcp_balanced_monthly": 265,
    "projected_gcp_optimized_monthly": 194,
    "monthly_savings_balanced": 35,
    "monthly_savings_optimized": 106,
    "annual_savings_optimized": 1272,
    "recommendation": "Migrate with optimizations for best ROI"
  },

  "recommendation": {
    "path": "Full Infrastructure with Optimizations",
    "roi_justification": "2.6 month payback with operational efficiency; $475K 5-year savings",
    "confidence": "high",
    "next_steps": [
      "Review financial case with stakeholders",
      "Confirm service tier selections (Cloud SQL vs AlloyDB, Cloud Run vs GKE)",
      "Get approval to proceed to Execute phase",
      "Schedule migration timeline per cluster evaluation order"
    ]
  }
}
```

## Output Validation Checklist

- `design_source` is `"infrastructure"`
- `pricing_source.status` is `"gcp_pricing_catalog_api"`, `"google_developer_knowledge"`, `"web_fetch"`, `"user_provided"`, or `"unavailable"`. No legacy `"cached"` / `"cached_fallback"` / `"gcloud_billing_catalog_api"` values.
- **Every `resources[]` entry has a `pricing` object with non-empty `source`, `attempts[]`, `fetched_url`, `fetched_at`, `sku_rate`, `assumed_quantity`, and `calculation`.** A missing or empty field is a **Generate-phase blocker** -- Generate MUST reject `estimation-infra.json` entries missing any of these and refuse to advance. This enforces the FORBIDDEN clause in `references/phases/estimate/estimate-infra.md`.
- **`pricing.attempts[]` contains at least one entry with `result == "ok"` AND non-empty `evidence` AND non-empty `tool_call`.** Evidence must be a 1-3 line verbatim excerpt of the actual tool-call response showing the rate. `tool_call` must be the literal command/MCP invocation made (`gcp-pricing` command line, MCP tool name + query). A `tool_call` of `"recalled"` / `"from training"` / `"general knowledge"` is fabrication — fail.
- `pricing.source` is one of: `"gcp-pricing (Cloud Billing Catalog API)"`, `"google-developer-knowledge MCP"`, `"WebFetch cloud.google.com"`, `"user_provided"`. Model-fabricated rates are NOT a valid `pricing.source` value.
- **`pricing.calculation` arithmetic checks within ±$0.50 of `monthly_estimate_usd`.** Parse the calculation as `<rate> * <quantity> = <result>`; the result must match `monthly_estimate_usd`. Off-by-orders-of-magnitude errors fail this check.
- **`pricing.assumed_quantity` is grounded.** It must reference either (a) a specific value from `preferences.json.design_constraints.access_pattern_data` (the access-pattern signal from Clarify Q_SIZING), or (b) the explicit `conservative_defaults` chosen by the user. Vague strings like "typical usage" or "estimated" without grounding fail this check.
- `accuracy_confidence` matches the pricing mode (+/-2-5% for Cloud Billing Catalog API; +/-5-10% for WebFetch/MCP).
- `current_costs.source` is `"billing_data"` if `billing-profile.json` was used, `"inventory_estimate"`, `"preferences"`, `"user_provided"` (asked during estimate), or `"unavailable"` (user declined) otherwise
- `current_costs.aws_monthly` matches billing-profile.json total (if used) or is a reasonable estimate
- `projected_costs` has all three tiers (premium, balanced, optimized)
- **Tier semantics:** Three totals are **scenario $** only (same design); **Balanced** matches generated Terraform baseline -- see **Cost tiers** section above; user-facing labels must use the subtitles there (also `estimate-infra.md` Present Summary / `generate-artifacts-report.md`)
- `projected_costs.breakdown` covers compute, database, storage, networking, and supporting services
- Every service in `gcp-design.json` is represented in the cost breakdown
- `cost_comparison` shows all three options with monthly and annual differences
- `migration_cost_considerations.billing_data_available` is `true` if `billing-profile.json` exists, `false` otherwise
- If `billing_data_available` is `true`: `migration_cost_considerations.categories` lists **AWS vendor egress / data transfer** only (never human or professional-services costs)
- If `billing_data_available` is `false`: `migration_cost_considerations.categories` is empty; `note` explains that billing data is required for AWS egress fee estimates
- `roi_analysis` presents recurring monthly/annual savings (or increase) per tier
- `roi_analysis` is honest -- if migration increases cost, say so and justify with non-cost benefits
- `optimization_opportunities` only includes strategies relevant to the designed architecture
- `financial_summary` provides a clear executive-level view
- `recommendation.next_steps` includes actionable items
- No references to AI-specific costs (those belong in `estimate-ai.md`)
- No references to billing-only estimates (those belong in `estimate-billing.md`)
- All cost values are numbers, not strings
- Output is valid JSON
