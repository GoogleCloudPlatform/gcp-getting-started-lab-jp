# Design Phase: Billing-Only Service Mapping

> Loaded by `design.md` when `billing-profile.json` exists and `aws-resource-inventory.json` does NOT exist.

**Execute ALL steps in order. Do not skip or optimize.**

This is the fallback design path when only AWS billing data is available (no Terraform or CloudFormation IaC). Mappings are inferred from AWS billing service names and SKU descriptions -- confidence is always `billing_inferred`.

---

## Step 0: Load Inputs

Read `$MIGRATION_DIR/billing-profile.json`. This file contains:

- `services[]` -- Each AWS service with monthly cost, SKU breakdown, and AI signals
- `summary` -- Total monthly spend and service count

Read `$MIGRATION_DIR/preferences.json` -> `design_constraints` (target region, compliance, etc.).

Also read `preferences.json` -> `metadata.inventory_clarifications` (may be empty if user defaulted all Category B questions). These are billing-only configuration answers collected during Clarify.

---

## Step 1: Load Billing Services

For each entry in `billing-profile.json` -> `services[]`:

1. Extract `aws_service` (display name, e.g., "Amazon EC2")
2. Extract `aws_service_type` (Terraform-style type, e.g., "aws_instance")
3. Extract `top_skus[]` for additional context (SKU descriptions hint at specific features)
4. Extract `monthly_cost` for cost context

---

## Step 2: Service Lookup

For each billing service, attempt lookup in order:

**2a. Fast-path lookup:**

1. Look up `aws_service_type` in `design-refs/fast-path.md` -> Direct Mappings table
2. If found: assign GCP service
3. Enrich with SKU hints:
   - If `top_skus` mention "PostgreSQL" -> specify "Cloud SQL PostgreSQL"
   - If `top_skus` mention "MySQL" -> specify "Cloud SQL MySQL"
   - If `top_skus` mention "Linux" or "On-Demand" -> indicates compute (Compute Engine)
   - If `top_skus` mention "Storage" -> check if object storage (GCS) or block storage (Persistent Disk)

**2b. Billing heuristic lookup (if not in fast-path):**

Look up `aws_service_type` in the table below. These are default mappings for common AWS services when no configuration data is available. The IaC path uses the full rubric in category files and may select a different GCP target based on actual configuration.

| `aws_service_type`               | Billing Name                | Default GCP Target | Alternatives (chosen by IaC path)                  |
| -------------------------------- | --------------------------- | ------------------ | -------------------------------------------------- |
| `aws_ecs_service`                | Amazon ECS (Fargate)        | Cloud Run          | GKE, Compute Engine                                |
| `aws_lambda_function`            | AWS Lambda                  | Cloud Run functions     | Cloud Run services/jobs                       |
| `aws_instance`                   | Amazon EC2                  | Compute Engine     | Cloud Run, GKE                                     |
| `aws_eks_cluster`                | Amazon EKS                  | GKE                | Cloud Run, Compute Engine                          |
| `aws_elastic_beanstalk_environment` | AWS Elastic Beanstalk    | Cloud Run          | App Engine, GKE                                    |
| `aws_dynamodb_table`             | Amazon DynamoDB             | Firestore          | Bigtable                                           |
| `aws_redshift_cluster`           | Amazon Redshift             | **`Deferred -- specialist engagement`** | **No** BigQuery/Dataproc/Dataflow in automated output. **`human_expertise_required: true`**. User must engage **GCP account team** and/or **data analytics migration partner**. |
| `aws_lb`                         | Elastic Load Balancing      | Cloud Load Balancing | --                                               |
| `aws_lb_target_group`            | Elastic Load Balancing      | Cloud Load Balancing Backend Service | --                                  |
| `aws_sns_topic`                  | Amazon SNS                  | Pub/Sub            | --                                                 |
| `aws_sqs_queue`                  | Amazon SQS                  | Pub/Sub (pull)     | Cloud Tasks                                        |
| `aws_cloudwatch_event_rule`      | Amazon EventBridge          | Eventarc           | Cloud Scheduler                                    |

If found: assign the Default GCP Target. Set rationale to: "AWS billing heuristic: [AWS service] -> [GCP service]. Provide Terraform files or CloudFormation templates for configuration-aware mapping." **Exception:** For Redshift, use: "AWS billing indicates Redshift spend -- **no automated GCP analytics target**; engage GCP account team / data analytics migration partner (`Deferred -- specialist engagement`)."

**Set `human_expertise_required`**: If `aws_service_type` is `aws_redshift_cluster` (or billing rows clearly represent Redshift analytics), set `human_expertise_required: true` and `gcp_service` to **`Deferred -- specialist engagement`** (same rules as `design-infra.md` Redshift gate). For all other services, set `human_expertise_required: false`. This field is REQUIRED on every service in the output.

**Preferred GCP target check**: **Skip** when `gcp_service` is **`Deferred -- specialist engagement`**. Otherwise verify the assigned `gcp_service` aligns with the Preferred GCP Target Services table in `design-refs/fast-path.md`. If a non-preferred service is selected, substitute the preferred alternative. Add a note to the rationale: "Preferred target: [alternative] selected for stronger ecosystem integration."

**2c. If not found in either table:** proceed to Step 3.

**2d. Enrich with Category B answers (if available):**

After lookup, check `metadata.inventory_clarifications` for user-provided configuration data and merge into `gcp_config`:

- If `inventory_clarifications.rds_ha` exists -> add `"high_availability": true/false` to the RDS / Cloud SQL design entry
- If `inventory_clarifications.fargate_count` exists -> set `"service_count"` in the Fargate / Cloud Run design entry
- If `inventory_clarifications.elasticache_memory` exists -> set `"memory_gb"` in the ElastiCache / Memorystore design entry
- If `inventory_clarifications.lambda_runtime` exists -> note `"runtime"` in the Lambda / Cloud Run functions design entry

When a clarification is applied, add `"inventory_clarifications_applied": true` to the service's `gcp_config`.

**No rubric evaluation** -- without IaC config, there is insufficient data for the 6-criteria rubric.

---

## Step 3: Flag Unknowns

For each service not found in fast-path or billing heuristic table:

1. Record in `unknowns[]` with:
   - `aws_service` -- Display name
   - `aws_service_type` -- Resource type
   - `monthly_cost` -- How much is spent on this service
   - `reason` -- "No IaC configuration available; service does not match any fast-path or billing heuristic entry"
   - `suggestion` -- "Provide Terraform files or CloudFormation templates for accurate mapping, or manually specify the GCP equivalent"

---

## Step 4: Generate Output

**File 1: `gcp-design-billing.json`**

Write to `$MIGRATION_DIR/gcp-design-billing.json`:

```json
{
  "metadata": {
    "phase": "design",
    "design_source": "billing_only",
    "confidence_note": "All mappings inferred from billing data only -- no IaC configuration available. Confidence is billing_inferred for all services.",
    "total_services": 8,
    "mapped_services": 6,
    "unmapped_services": 2,
    "timestamp": "2026-04-12T14:30:00Z"
  },
  "services": [
    {
      "aws_service": "Amazon ECS (Fargate)",
      "aws_service_type": "aws_ecs_service",
      "gcp_service": "Cloud Run",
      "gcp_config": {
        "region": "us-central1"
      },
      "monthly_cost": 450.00,
      "confidence": "billing_inferred",
      "human_expertise_required": false,
      "rationale": "Fast-path: Fargate -> Cloud Run. SKU hints: CPU + Memory allocation.",
      "sku_hints": ["Fargate-vCPU-Hours", "Fargate-GB-Hours"]
    },
    {
      "aws_service": "Amazon RDS",
      "aws_service_type": "aws_db_instance",
      "gcp_service": "Cloud SQL PostgreSQL",
      "gcp_config": {
        "region": "us-central1",
        "high_availability": false,
        "inventory_clarifications_applied": true
      },
      "monthly_cost": 800.00,
      "confidence": "billing_inferred",
      "rationale": "Fast-path: RDS PostgreSQL -> Cloud SQL. SKU hints: PostgreSQL engine. User confirmed single-zone (Category B).",
      "sku_hints": ["RDS:ChargedFor:DBInstanceHours", "RDS:GP3-Storage"]
    }
  ],
  "unknowns": [
    {
      "aws_service": "AWS Shield",
      "aws_service_type": "aws_shield_protection",
      "monthly_cost": 50.00,
      "reason": "No IaC configuration available; billing name does not match any fast-path entry",
      "suggestion": "Provide Terraform files or CloudFormation templates for accurate mapping, or manually specify the GCP equivalent"
    }
  ]
}
```

## Output Validation Checklist

- `metadata.design_source` is `"billing_only"`
- `metadata.total_services` equals `mapped_services` + `unmapped_services`
- Every service from `billing-profile.json` appears in either `services[]` or `unknowns[]`
- All `confidence` values are `"billing_inferred"`
- Every `services[]` entry has `human_expertise_required` (boolean) -- `true` for Redshift; `false` for all others
- Redshift entries must have `gcp_service` exactly **`Deferred -- specialist engagement`** (not BigQuery/Dataproc/Dataflow)
- Every `services[]` entry has `aws_service`, `gcp_service`, `monthly_cost`, `rationale`
- Every `unknowns[]` entry has `aws_service`, `monthly_cost`, `reason`, `suggestion`
- Output is valid JSON

## Present Summary

After writing `gcp-design-billing.json`, present a concise summary to the user:

1. Mapped X of Y AWS billing services to GCP equivalents
2. Accuracy notice: every mapping here is **Estimated from AWS billing only** (JSON: `billing_inferred`) -- suggest providing Terraform or CloudFormation for a tighter mapping
3. Per-service table: AWS service -> GCP service (with monthly AWS cost); label recommendation type as **Estimated from billing only** unless you also have IaC-backed design
4. Unmapped services list with suggestions
5. Total monthly AWS spend
6. If any service has **`Deferred -- specialist engagement`**: state **prominently** that **no GCP analytics target was chosen**; direct the user to **GCP account team** and/or **data analytics migration partner**. Do **not** recommend BigQuery, Dataproc, or Dataflow in the summary.

Keep it under 20 lines. The user can ask for details or re-read `gcp-design-billing.json` at any time.
