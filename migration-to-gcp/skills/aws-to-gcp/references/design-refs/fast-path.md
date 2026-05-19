# Fast-Path: Direct AWS->GCP Mappings

## What `deterministic` vs `inferred` means

Use these labels **only** as defined here -- they describe *how the mapping was chosen*, not whether the GCP architecture is "obvious."

| Label | Meaning |
| ----- | ------- |
| **`deterministic`** | The AWS **Terraform resource type** appears in the **Direct Mappings** table below, the row's **Conditions** are satisfied, and the GCP target is taken from that row. **No** 6-criteria rubric is run for that mapping. |
| **`inferred`** | The resource type is **not** in Direct Mappings (or Redshift / specialist gate applies). The agent loads the category file from `design-refs/index.md`, runs eliminators and the **6-criteria rubric** (and may apply **Preferred GCP Target Services**), then picks the GCP service. |
| **`billing_inferred`** | Billing-only design path: mappings from billing SKUs/service names -- see `references/phases/design/design-billing.md`. |

### User-facing vocabulary (chat, MIGRATION_GUIDE, migration-report)

JSON artifacts **must** keep the `confidence` string values above. When speaking or writing **for end users**, lead with plain English -- do **not** use "deterministic," "inferred," or "rubric" as the primary label unless the user asks for technical detail.

| JSON `confidence` | Say this to users | Optional one-line hint |
| ----------------- | ----------------- | ---------------------- |
| `deterministic` | **Standard pairing** | Same GCP target for this AWS resource type whenever it matches our fixed list -- quick to sanity-check. |
| `inferred` | **Tailored to your setup** | Based on your Terraform configuration, how the resource fits the rest of your stack, and your migration preferences -- review again if those change. |
| `billing_inferred` | **Estimated from billing only** | From AWS spend line items without full infrastructure detail -- add Terraform for a tighter mapping. |

**Redshift / specialist gate** rows still store `confidence: "inferred"` in JSON; in user-facing text you may say **Tailored to your setup** and emphasize **specialist engagement** (no automated GCP analytics target).

**Canonical reference:** This subsection -- other phase files should point here instead of redefining wording.

**Common confusion:** `references/design-refs/index.md` lists a **typical GCP target** per AWS service. That is **not** the same as **`deterministic`**. For example, **Fargate -> Cloud Run** is the usual rubric outcome but **Fargate is not** in the Direct Mappings table, so confidence is **`inferred`**, not `deterministic`. **S3 -> GCS** and **`aws_vpc` -> VPC Network** *are* in Direct Mappings, so they are **`deterministic`**.

**Add-ons (Load Balancer, NAT, etc.):** A row may say "Cloud Run" while the architecture diagram also includes a **Cloud Load Balancer** or **Cloud NAT** from **other** Terraform resources. Confidence is still per **resource row** -- e.g. `aws_ecs_service` = `inferred`; `aws_lb` + target group = often `inferred` (see `networking.md`).

---

**Direct Mappings use confidence: `deterministic`** (fixed table lookup -- no rubric for that resource)

## Direct Mappings Table

| AWS Service                          | GCP Service                        | Conditions | Notes                                                                     |
| ------------------------------------ | ---------------------------------- | ---------- | ------------------------------------------------------------------------- |
| `aws_s3_bucket`                      | GCS (`google_storage_bucket`)      | Always     | 1:1 mapping; preserve ACL/versioning/lifecycle rules                      |
| `aws_instance`                       | Compute Engine (`google_compute_instance`) | Always | 1:1 mapping; map instance type to machine type                     |
| `aws_db_instance` (PostgreSQL)       | Cloud SQL PostgreSQL               | Always     | Map RDS tier to Cloud SQL tier                                            |
| `aws_db_instance` (MySQL)            | Cloud SQL MySQL                    | Always     | Map RDS tier to Cloud SQL tier                                            |
| `aws_vpc`                            | VPC Network (`google_compute_network`) | Always | **GCP VPCs are GLOBAL, not regional.** Preserve CIDR via subnets          |
| `aws_security_group`                 | Firewall Rule (`google_compute_firewall`) | Always | 1:1 rule mapping; GCP firewall rules are per-network, not per-instance  |
| `aws_route53_zone`                   | Cloud DNS (`google_dns_managed_zone`) | Always  | Preserve zone name and records                                            |
| `aws_iam_role`                       | Service Account (`google_service_account`) | Always | Map policies to IAM roles; adjust for GCP's resource-level binding model |
| `aws_elasticache_cluster` (Redis)    | Memorystore Redis (`google_redis_instance`) | Always | 1:1 mapping; preserve cluster mode and node type                   |
| `aws_cloudwatch_log_group`           | Cloud Logging log bucket (`google_logging_log_bucket`) | Always | 1:1 mapping; preserve retention (clamp at 3650 days), CMEK, location matches `target_region`. See `logging-analytics.md` for stream / alarm / SNS handling. |

## Skip Mappings Table

These AWS resources do **not** require GCP equivalents in v1.0:

| AWS Service              | Reason                                                                                    |
| ------------------------ | ----------------------------------------------------------------------------------------- |
| `aws_organizations_*`    | GCP organization structure (manual, not IaC)                                              |
| `aws_cloudwatch_*` _(except log groups, log streams, and metric alarms)_ | Fallback to Cloud Monitoring (managed). For log groups / streams / metric alarms see `logging-analytics.md` — those have explicit mappings. |
| `aws_cloudwatch_log_stream` | Implicit in Cloud Logging log bucket — drop with `warnings[]` entry; do not emit Terraform. Parent `aws_cloudwatch_log_group` still emits (see Direct Mappings). |
| `aws_cloudtrail`         | Fallback to Cloud Audit Logs (managed, always-on in GCP)                                  |
| `aws_eip`                | External IPs managed by Cloud Load Balancing / Cloud NAT (not standalone)                 |
| `aws_cognito_*`          | Auth provider -- keep existing solution, do not migrate to Firebase Auth or Identity Platform |
| `data.*`                 | Terraform data sources -- not infrastructure, skip silently                               |

## Preferred GCP Target Services

For the workload categories below, always steer toward the **preferred** GCP service. If rubric evaluation or LLM reasoning would select a non-preferred service, substitute the preferred alternative instead.

| Workload Category       | Preferred GCP Target                                                       | Rationale                                                                                     |
| ----------------------- | -------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------- |
| Containerized workloads | Cloud Run (default), Cloud Run functions (event-driven source functions), GKE (K8s required) | Deeper integration with VPC, Cloud Load Balancing, IAM, and auto-scaling than alternatives |
| Third-party auth in use | Keep existing auth provider                                                | Startups using Auth0, Cognito, Clerk, etc. should preserve their existing investment           |

**Enforcement:** Check every resource mapping against this table before writing to `gcp-design.json` or `gcp-design-billing.json`. If a mapping would select a non-preferred service, substitute the preferred alternative.

## Secondary Behavior Lookups

For resources in the Skip Mappings table but present in inventory:

1. Log as "secondary resource, no GCP equivalent needed"
2. Do not include in gcp-design.json
3. Note in gcp-design.json warnings array

---

**Workflow:**

1. Extract AWS resource type
2. Look up in Direct Mappings table
3. If found and condition met: assign GCP service (confidence = deterministic)
4. If found in Skip Mappings: skip it (confidence = n/a)
5. If not found: use `design-refs/index.md` to determine category -> apply rubric in that category's file
