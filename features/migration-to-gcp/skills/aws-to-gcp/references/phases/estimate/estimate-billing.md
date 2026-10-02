# Estimate Phase: Billing-Only Cost Analysis

> Loaded by `estimate.md` when `gcp-design-billing.json` exists and `gcp-design.json` does NOT exist.

**Execute ALL steps in order. Do not skip or optimize.**

## Overview

This is the fallback estimate path when only AWS billing data is available. It provides a conservative budget range from service-level spend and billing SKU hints, but it does not have the configuration detail needed for deployable sizing.

Use this path for stakeholder budgeting only. Recommend Terraform or CloudFormation discovery before execution.

## Step 0: Load Inputs

Read these artifacts from `$MIGRATION_DIR/`:

- `billing-profile.json` (REQUIRED) -- AWS billing breakdown from Discover
- `gcp-design-billing.json` (REQUIRED) -- billing-only service mapping from Design
- `preferences.json` (REQUIRED) -- target region and migration preferences

If any required file is missing: **STOP**. Output: "Missing required artifact: [filename]. Complete the prior phase that produces it."

## Step 1: Establish Current AWS Costs

Use `billing-profile.json.summary.total_monthly_spend` as the current AWS monthly baseline.

For each service in `billing-profile.json.services[]`, preserve:

- `aws_service`
- `aws_service_type`
- `monthly_cost`
- `top_skus[]`

## Step 2: Estimate GCP Costs from Billing-Only Design

For each entry in `gcp-design-billing.json.services[]`:

1. Match the service to the AWS billing row by `aws_service` or `aws_service_type`.
2. Use `monthly_cost` as the AWS service baseline.
3. Estimate three GCP scenarios:
   - **Premium:** `aws_monthly * 1.40`
   - **Balanced:** `aws_monthly * 1.00`
   - **Optimized:** `aws_monthly * 0.65`
4. If `gcp_service` is **`Deferred -- specialist engagement`**, exclude it from all GCP numeric totals and add it to `deferred_services[]`.
5. If the service is in `unknowns[]`, exclude it from GCP numeric totals and add it to `unmapped_services[]`.

These multipliers are placeholders for budget-range modeling only. Do not present them as SKU-accurate pricing.

## Step 3: Pricing Source

Set:

```json
"pricing_source": {
  "status": "billing_heuristic",
  "message": "Billing-only estimate based on AWS service spend and mapped GCP service category; no IaC sizing available",
  "accuracy_confidence": "+-30-50%"
}
```

If `google-developer-knowledge` or official pricing pages were used to sanity-check service categories, add the checked services under `pricing_source.services_checked[]`. Do not narrow the accuracy range unless actual sizing is known.

## Step 4: Migration Cost Considerations

Set `migration_cost_considerations.billing_data_available` to `true`.

Include only AWS vendor/network data transfer considerations. Do **not** include human labor, contractor, professional-services, or engineering effort as dollar costs.

## Step 5: Write estimation-billing.json

Write `$MIGRATION_DIR/estimation-billing.json` with:

```json
{
  "phase": "estimate",
  "design_source": "billing_only",
  "confidence": "low",
  "timestamp": "2026-04-12T14:00:00Z",
  "pricing_source": {
    "status": "billing_heuristic",
    "message": "Billing-only estimate based on AWS service spend and mapped GCP service category; no IaC sizing available",
    "accuracy_confidence": "+-30-50%",
    "services_checked": []
  },
  "current_costs": {
    "source": "billing_data",
    "aws_monthly": 2450.00,
    "aws_annual": 29400.00,
    "breakdown": [
      {
        "aws_service": "Amazon ECS",
        "aws_service_type": "aws_ecs_service",
        "monthly_cost": 450.00
      }
    ]
  },
  "projected_costs": {
    "gcp_monthly_premium": 3430.00,
    "gcp_monthly_balanced": 2450.00,
    "gcp_monthly_optimized": 1592.50,
    "services": [
      {
        "aws_service": "Amazon ECS",
        "aws_service_type": "aws_ecs_service",
        "gcp_service": "Cloud Run",
        "aws_monthly": 450.00,
        "gcp_monthly_premium": 630.00,
        "gcp_monthly_balanced": 450.00,
        "gcp_monthly_optimized": 292.50,
        "confidence": "billing_inferred",
        "notes": ["No IaC sizing available; refine with Terraform or CloudFormation"]
      }
    ],
    "deferred_services": [],
    "unmapped_services": []
  },
  "cost_comparison": {
    "aws_monthly_baseline": 2450.00,
    "premium_difference": 980.00,
    "balanced_difference": 0.00,
    "optimized_difference": -857.50
  },
  "migration_cost_considerations": {
    "billing_data_available": true,
    "categories": ["AWS vendor egress / data transfer may apply during migration"],
    "note": "Only AWS vendor/network charges are considered. Human and professional-services migration costs are intentionally excluded."
  },
  "recommendation": {
    "confidence": "low",
    "next_steps": [
      "Provide Terraform files or CloudFormation templates for configuration-aware sizing",
      "Manually verify instance sizes, database engines, storage volume, and networking topology",
      "Use this estimate for initial budgeting only"
    ]
  }
}
```

## Output Validation Checklist

- `design_source` is `"billing_only"`
- `confidence` is `"low"`
- `pricing_source.status` is `"billing_heuristic"`
- `current_costs.aws_monthly` matches `billing-profile.json.summary.total_monthly_spend`
- Every mapped service from `gcp-design-billing.json.services[]` appears in `projected_costs.services[]` or `projected_costs.deferred_services[]`
- Every `gcp-design-billing.json.unknowns[]` entry appears in `projected_costs.unmapped_services[]`
- Redshift / `Deferred -- specialist engagement` services are excluded from numeric GCP totals
- No BigQuery, Dataproc, or Dataflow estimate is created for Redshift
- No human labor, contractor, professional-services, or engineering effort appears as a dollar cost
- Output is valid JSON

## Present Summary

After writing `estimation-billing.json`, present under 20 lines:

1. Current AWS monthly spend from billing data
2. GCP Premium / Balanced / Optimized budget range
3. Accuracy warning: billing-only estimate, `+-30-50%`
4. Mapped service count, unmapped service count, deferred specialist services
5. Recommendation to provide Terraform or CloudFormation before execution
