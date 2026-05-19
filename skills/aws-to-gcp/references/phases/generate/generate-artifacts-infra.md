# Generate Phase: Infrastructure Artifact Generation

> Loaded by generate.md when generation-infra.json and gcp-design.json exist.

**Execute ALL steps in order. Do not skip or optimize.**

> **Resource-type verification gate (MANDATORY — blocks Generate completion)**:
>
> Every `google_*` resource type emitted in a `.tf` file MUST be verified against the current Terraform provider registry before the file is saved. Hallucinated resource types like `google_dataproc_batch` (does NOT exist — actual: `google_dataproc_cluster`, `google_dataproc_workflow_template`, `google_dataproc_autoscaling_policy`, or runtime-only via gcloud) cause `terraform validate` to fail and make the entire migration non-deployable.
>
> **Protocol — runs before writing ANY `.tf` file:**
> 1. Collect the set of `google_*` resource type names you are about to emit.
> 2. For each one, verify it exists by ONE of these methods, in order:
>    - **Preferred**: WebFetch `https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/<TYPE_WITHOUT_PREFIX>` — a 200 response confirms it exists. A 404 means the resource type does NOT exist; STOP and use a different mapping.
>    - **Alternative**: WebSearch `"<google_TYPE>" site:registry.terraform.io` — a matching documentation page confirms it.
>    - **Alternative (slow)**: Bash `terraform providers schema -json` after a `terraform init` against a tiny scratch `main.tf` — programmatic source of truth, but slow.
> 3. If a resource type cannot be verified, the skill MUST NOT emit it. Instead, EITHER:
>    - Choose a verified alternative (e.g. `google_dataproc_cluster` instead of the non-existent `google_dataproc_batch`), update `gcp-design.json` AND `gcp-architecture.mmd` AND the ADR accordingly, and proceed.
>    - OR, if no Terraform-native alternative exists (e.g. Dataproc Serverless batches are submit-only via gcloud), comment out the resource in the `.tf` file with `# TODO: <type> has no Terraform resource — provision via $MIGRATION_DIR/scripts/<NN>-<service>-runtime.sh post-apply` and add the runtime provisioning step to a shell script.
> 4. Append every verification to `$MIGRATION_DIR/generation-validation.json.resource_types[]`:
>    ```json
>    {"resource_type": "google_dataproc_cluster", "verified_via": "WebFetch registry.terraform.io", "verified_at": "2026-05-18T18:00:00Z", "result": "exists"}
>    ```
> 5. After writing any `.tf` file, run `terraform validate` on it locally if `terraform` is in PATH (it is; the test bed installs it during preflight). Any `Invalid resource type` error is a phase failure: roll back the file and re-attempt with verified types only. Do NOT advance with a known-broken `.tf` file.

## Overview

Transform the design (`gcp-design.json`) and migration plan (`generation-infra.json`) into deployable Terraform configurations. Migration scripts are generated separately by `generate-artifacts-scripts.md`.

## Prerequisites

Read from `$MIGRATION_DIR/`:

- `gcp-design.json` (REQUIRED) -- GCP architecture design with cluster-level resource mappings
- `generation-infra.json` (REQUIRED) -- Migration plan with timeline and service assignments
- `preferences.json` (REQUIRED) -- User preferences including target region, sizing, compliance
- `aws-resource-clusters.json` (REQUIRED) -- Cluster dependency graph for ordering
- `aws-sdk-usage.json` (OPTIONAL) -- App SDK call-site inventory; consumed by Step 4.8 only if present
- `sdk-migration-plan.json` (OPTIONAL) -- Per-call-site rewrite plan; consumed by Step 4.8 only if present

Reference files (read as needed): `references/design-refs/index.md` and domain-specific files (compute.md, database.md, storage.md, networking.md, messaging.md, ai.md, sdk-mapping.md for the source-code rewrite step). Also: `references/shared/companion-skills.md` for the AWS -> GCP -> google/skill mapping that drives Step 0.5 below.

If any REQUIRED file is missing: **STOP**. Output: "Missing required artifact: [filename]. Complete the prior phase that produces it."

## Step 0.5: Probe Companion Skills (google/skills)

Mirror Step 0.5 from `design-infra.md`. Probe whether each potentially-relevant google/skill is installed and build a `companion_skills_available` map:

- For every distinct `gcp_service` appearing in `gcp-design.json`, look up the google/skill in `design-refs/index.md` (or `references/shared/companion-skills.md`).
- For each unique google/skill referenced, attempt to Read its `SKILL.md` from (in order):
  1. `~/.claude/skills/<skill-name>/SKILL.md`
  2. `~/.agents/skills/<skill-name>/SKILL.md`
  3. `.claude/skills/<skill-name>/SKILL.md`
- Record the resolved path (or `null`).
- For skills already used in the Design phase, the `gcp-design.json.warnings[]` will already contain the "not installed" warning; do not duplicate it. Surface a brief reminder in the Phase Completion summary if any are still missing.

This probe is **non-blocking**. If a skill cannot be read, generation continues using the fallback patterns in this file and the `design-refs/*.md` rubrics.

## Output Structure

Generate `$MIGRATION_DIR/terraform/` with only the files needed for domains that have resources in `gcp-design.json`:

| File            | Domain     | Contains                                                 |
| --------------- | ---------- | -------------------------------------------------------- |
| `main.tf`       | core       | Provider config, backend, data sources                   |
| `variables.tf`  | core       | All input variables with types and defaults              |
| `outputs.tf`    | core       | Resource outputs and migration summary                   |
| `vpc.tf`        | networking | VPC, subnets, Cloud NAT, firewall rules, Cloud Router    |
| `security.tf`   | security   | IAM service accounts, roles, KMS keys                    |
| `storage.tf`    | storage    | Cloud Storage buckets, lifecycle policies                |
| `database.tf`   | database   | Cloud SQL instances, parameter flags, Spanner             |
| `compute.tf`    | compute    | Cloud Run, GKE, Compute Engine instances                 |
| `monitoring.tf` | monitoring | Cloud Monitoring dashboards, alert policies, log sinks   |
| `README.md`     | core       | Cost tiers vs this Terraform (one stack; Balanced-aligned) |

## Step 1: Source of truth — `gcp-design.json` (READ THIS BEFORE ANY OTHER STEP)

**Generate's source of truth is `$MIGRATION_DIR/gcp-design.json`, NOT `aws-resource-inventory.json`.**

This section runs BEFORE Step 0 (Preflight), Step 1a (Generate main.tf), Step 1b (Generate terraform/README.md), and every other step below. The numbered "Step 0" / "Step 1a" / "Step 1b" / "Step 2" / etc. headings further down the file are preserved from earlier iterations for stable cross-references — but this rule binds the moment you load the file.

Before writing any `.tf` file:

1. READ `gcp-design.json` in full.
2. For each resource in `gcp-design.json.clusters[].resources[]`, the fields `gcp_service`, `gcp_config`, `confidence`, and `rationale` are **decisions already made by Phase 3 (Design)**. Generate MUST NOT re-derive them. Generate's job is purely to translate the Design's decisions into Terraform HCL.
3. If you find yourself wanting to "pick a target service" or "decide the database version" for a resource — STOP. That work belongs in Design. Go back and re-read the entry in `gcp-design.json`.
4. Specifically: when emitting `google_sql_database_instance`, the `database_version` field MUST equal `source_resource.gcp_config.database_version` from Design (e.g. `MYSQL_8_0`). If Design's value differs from what Generate's rubric would have chosen, **Design wins**.

`aws-resource-inventory.json` may be consulted ONLY for:

- Enumerating which source PRIMARY resources exist (to drive Step 2.5 per-resource blocks).
- Looking up source `image` URIs for ECS task definitions (so Generate can translate ECR → Artifact Registry — see compute section in Step 3).
- Resolving the source `engine`/`engine_version` solely for the Step 2.6 validation gate's "does Design's value match the source?" cross-check (the gate may LOG a discrepancy but MUST still emit Design's chosen `database_version`).

Generate MUST NOT use `aws-resource-inventory.json` to choose `gcp_service` (e.g. "is this Aurora MySQL or PostgreSQL?"), to size the GCP target, or to override any value already present in Design's `gcp_config`. If Design's `gcp_config` is empty for a field that Generate needs (e.g. memory size for `google_redis_instance`), use Design's documented defaults from `references/design-refs/*.md`, NOT a fresh inference from the source.

### Step 1 — Cross-Reference Validation Gate (BLOCKING — runs after each `.tf` file is written in Step 3)

For every `google_*` block in the generated file, find the corresponding entry in `gcp-design.json` by `aws_address`. Verify:

- `google_sql_database_instance.database_version` equals Design's `gcp_config.database_version` for the matching `aws_address`.
- `google_redis_instance.redis_version` equals Design's `gcp_config.redis_version` (if Design set it).
- The Terraform resource type (e.g. `google_cloud_run_v2_service`) matches Design's `gcp_service` (e.g. `"Cloud Run"` → `google_cloud_run_v2_service` or `google_cloud_run_v2_job`; `"Cloud SQL MySQL"` → `google_sql_database_instance`; `"Memorystore Redis"` → `google_redis_instance`).
- The Terraform `region` / `location` argument equals Design's `gcp_config.region` (or `var.gcp_region` if Design omits it).

If ANY mismatch is found: REWRITE the offending block before saving — Design's value wins, every time. NEVER save a file that contradicts Design. If you believe Design is wrong, see the **Generate is a translation step, not a redesign step** rule in `generate.md` — emit a `warnings[]` entry in `generation-infra.json` and still output the Terraform that matches Design.

This gate is BLOCKING. The Step 5 self-check re-runs it as a sanity check; failing this gate the first time means the file MUST be regenerated before Step 5 runs.

## Step 0: Preflight — Path Discipline + Plan Generation Scope

**Path discipline (mandatory before any Write call in this sub-file):**

Every `.tf` file, `terraform/README.md`, and any other artifact produced here MUST be written under `$MIGRATION_DIR/terraform/` — for example `$MIGRATION_DIR/terraform/main.tf`. NEVER write to `./terraform/` (cwd) or anywhere outside `$MIGRATION_DIR`. The source project's own files (especially the project-root `README.md`) MUST NOT be touched. NEVER emit a helper Python/Node/Bash parser script (e.g. `discover_iac.py`, `map_infrastructure.py`) to read the design — use Read/Grep/Glob on `$MIGRATION_DIR/gcp-design.json` and `$MIGRATION_DIR/aws-resource-inventory.json` directly. See **SKILL.md > File Output Discipline (CRITICAL)** for the full rule set.

**Plan Generation Scope:**

Build a generation manifest: read all resources from `gcp-design.json` clusters, assign each to its target .tf file by `gcp_service`:

| GCP Service                                            | Target File     |
| ------------------------------------------------------ | --------------- |
| VPC, Subnet, Cloud NAT, Firewall, Cloud Router         | `vpc.tf`        |
| Service Account, IAM Binding, KMS Key                  | `security.tf`   |
| Cloud Storage                                          | `storage.tf`    |
| Cloud SQL, Spanner, Firestore, Memorystore, AlloyDB    | `database.tf`   |
| Cloud Run, Cloud Run functions, GKE, Compute Engine     | `compute.tf`    |
| Cloud Monitoring, Pub/Sub (for alerting)               | `monitoring.tf` |

**Redshift / specialist-deferred:** If `gcp_service` is **`Deferred -- specialist engagement`**, **do not** generate Terraform for that resource (no BigQuery, Dataflow, or Dataproc modules from the plugin). Optionally add **`$MIGRATION_DIR/terraform/README-REDSHIFT-DEFERRED.md`** with a short checklist: engage **GCP account team** and/or **data analytics migration partner** before implementing analytics infrastructure.

## Step 1a: Generate main.tf

**Requirements:**

- **File header comment block (first lines in `main.tf`, before `terraform {`):** Explain that (1) this directory implements the **single** architecture in `gcp-design.json`; (2) the migration report's **Premium / Balanced / Optimized** figures are **three pricing scenarios** from `estimation-infra.json` for that same map -- **not** three separate generated stacks; (3) **this Terraform is aligned with the Balanced cost scenario** (default sizing/HA posture used for the middle estimate); (4) **Premium** = higher HA / higher $ model; **Optimized** = cost-optimization assumptions -- users must **edit IaC or add modules** to realize those postures. Point readers to `terraform/README.md` and the `migration_summary` output.
- `terraform` block: `required_version >= 1.5.0`, `hashicorp/google ~> 5.0`, `hashicorp/google-beta ~> 5.0`, commented GCS backend
- `provider "google"` block: `project = var.gcp_project`, `region = var.gcp_region`, `default_labels` with project, environment, managed-by, migration-id
- Data sources: `google_project`, `google_compute_zones`

## Step 1b: Generate terraform/README.md

**Always create** `$MIGRATION_DIR/terraform/README.md` when generating Terraform (same pass as Step 1a).

**Required sections:**

1. **What this directory is** -- Implements one deployable baseline from `gcp-design.json` (and `generation-infra.json` / `preferences.json` as applicable).
2. **Cost tiers in the migration report** -- Premium, Balanced, and Optimized are **monthly cost scenarios** in `estimation-infra.json` for the **same** service mapping; order is high -> mid -> low estimate.
3. **Which scenario this Terraform matches** -- **Balanced** (primary comparison to AWS; default migration posture in the advisor model). Premium and Optimized are **not** auto-generated as alternate roots.
4. **If you need Premium or Optimized in production** -- Manually adjust machine types, HA settings, preemptible mix, Committed Use Discounts, storage classes, etc., then re-estimate.
5. **Artifacts** -- Reference `estimation-infra.json`, `migration-report.html` / `MIGRATION_GUIDE.md` for full tier tables.

Keep it under one screen of text.

## Step 2: Generate variables.tf

**Global variables (always include):** `gcp_project` (from `preferences.json`), `gcp_region` (from `preferences.json` target_region), `project_name`, `environment` (from `preferences.json`), `migration_id`.

**Per-cluster variables:** Extract configurable values from `gcp_config` in `gcp-design.json`. Infer types (`string`, `number`, `bool`, `list(string)`, `map(string)`). Use `gcp_config` values as defaults. Deduplicate shared variables. Add AWS source as comment (e.g., `# AWS source: db.r6g.large`).

## Step 2.5: Per-Resource Enumeration (MANDATORY before writing any compute / database / storage / vpc / security / monitoring .tf file)

The Iter 1 generator collapsed 8 distinct ECS services into ONE generic Cloud Run "app-service". That is the failure mode this step exists to prevent. The .tf file must contain ONE distinct `google_*` resource block for EACH matching source resource — never a single generic block standing in for many.

**Do this BEFORE writing each `.tf` file in Step 3:**

1. Re-read `$MIGRATION_DIR/gcp-design.json` AND `$MIGRATION_DIR/aws-resource-inventory.json`.
2. Enumerate every source resource where `type` (in `aws-resource-inventory.json.resources[]`) matches the category being generated, AND `classification` is `"PRIMARY"` for the primary list (secondaries are still emitted as supporting blocks; see "secondary resources" below). **Use the INCLUDE list below — and obey the EXCLUDE list. Config wrappers, cluster member instances, and AWS-internal spec types are PRIMARY in `classification-rules.md` (so they create their own clusters in Discover) but they MUST NOT each produce a standalone `google_*` resource block in Generate.** Their content is folded into the parent workload's block (e.g. a `aws_db_subnet_group` becomes `google_sql_database_instance.settings.ip_configuration` on the parent cluster's instance, NOT its own `google_sql_database_instance`).

   | Target file       | INCLUDE (emit ONE `google_*` block per matching source) | EXCLUDE (do NOT emit standalone blocks; fold into the parent or skip) |
   | ----------------- | -------------------------------------------------------- | --------------------------------------------------------------------- |
   | `compute.tf`      | every `aws_ecs_service` (a running service), every `aws_ec2_instance` / `aws_instance` (a running VM), every `aws_lambda_function`, every `aws_batch_job_definition` (use `google_cloud_run_v2_job`) | `aws_ecs_task_definition` (it is the spec consumed by `aws_ecs_service` — emit nothing; copy the task's `cpu`, `memory`, `image`, and env into the parent ECS service's `google_cloud_run_v2_service.template.containers` block). `aws_ecs_cluster` (the cluster itself is an empty container; do NOT emit `google_cloud_run_v2_service` for it — emit ONLY if you need a dedicated service account for IAM scoping, in which case emit `google_service_account` in `security.tf`, not a Cloud Run service here). `aws_launch_template`, `aws_launch_configuration` (these are EC2 spec; fold into the `google_compute_instance_template` for the matching autoscaling group, or skip if no `aws_autoscaling_group` exists). |
   | `database.tf`     | every `aws_rds_cluster` (Aurora cluster — emit ONE `google_sql_database_instance`), every `aws_db_instance` (standalone RDS), every `aws_elasticache_replication_group` (Redis cluster — emit ONE `google_redis_instance`), every `aws_elasticache_cluster` (standalone Redis/Memcached node), every `aws_dynamodb_table`, every `aws_redshift_cluster` (becomes a `Deferred` README note, not a Terraform block — see Step 0) | `aws_rds_cluster_instance` (the parent `aws_rds_cluster` already covers it; double-emitting creates conflicting `google_sql_database_instance` blocks with the same `name`). `aws_db_subnet_group`, `aws_rds_cluster_parameter_group`, `aws_db_parameter_group` (these are VPC/config wrappers — they map to `google_sql_database_instance.settings.ip_configuration.private_network` / `.settings.database_flags` on the parent instance, NOT separate `google_sql_database_instance` resources). `aws_elasticache_subnet_group`, `aws_elasticache_parameter_group` (same — they map to `google_redis_instance.authorized_network` / `.redis_configs` on the parent instance, NOT separate `google_redis_instance` resources). |
   | `storage.tf`      | every `aws_s3_bucket`, every `aws_efs_file_system` | `aws_s3_bucket_policy`, `aws_s3_bucket_versioning`, `aws_s3_bucket_server_side_encryption_configuration`, `aws_s3_bucket_public_access_block` (these map to `google_storage_bucket.versioning`, `.encryption`, `.iam_policy` arguments on the parent bucket, NOT separate `google_storage_bucket` resources). |
   | `vpc.tf`          | every `aws_vpc`, every `aws_subnet`, every `aws_security_group`, every `aws_internet_gateway`, every `aws_nat_gateway`, every `aws_route_table`, every `aws_route_table_association` | none (every networking primary deserves its own block) |
   | `security.tf`     | every `aws_iam_role`, every `aws_iam_policy` (attached to a role used by a primary), every `aws_secretsmanager_secret`, every `aws_kms_key` | `aws_iam_role_policy_attachment`, `aws_iam_policy_attachment`, `aws_iam_user_policy_attachment` (these become `google_project_iam_member` or `google_service_account_iam_binding` references attached to the parent service account, NOT separate `google_iam_*` resources of their own type). |
   | `monitoring.tf`   | every `aws_cloudwatch_metric_alarm`, every `aws_sns_topic` referenced by an alarm, every `aws_cloudwatch_log_group` | `aws_cloudwatch_log_stream` (folds into the parent `google_logging_project_sink` filter, no standalone block). |

   **Rule for EXCLUDE rows:** If you find yourself about to emit a `google_*` block for an EXCLUDE source, STOP. Re-read this table. The source's intent belongs as an argument on the parent workload's block (which you have already emitted, or will emit later in the same file). If you cannot tell which parent it belongs to, follow the `aws-resource-inventory.json.resources[*].edges` references from the EXCLUDE source backward to the nearest INCLUDE source — that is the parent.

   **One-line examples of EXCLUDE rejection** (memorize these):

   - `aws_db_subnet_group.AuroraSubnetGroup` → becomes part of `google_sql_database_instance.settings.ip_configuration` on the parent `aws_rds_cluster`'s instance, NOT its own `google_sql_database_instance`.
   - `aws_rds_cluster_instance.ProductionAuroraInstance1` → is already represented by the parent `aws_rds_cluster.ProductionAuroraCluster` block; emitting it again produces a duplicate `google_sql_database_instance.ProductionAuroraInstance1` that conflicts with the cluster's instance.
   - `aws_ecs_task_definition.ProductionPumaTaskDefinition` → its `image`, `cpu`, `memory` go into `google_cloud_run_v2_service.production_puma_service.template.containers` (the matching `aws_ecs_service`'s block), NOT a separate `google_cloud_run_v2_service.production_puma_task_definition`.
   - `aws_elasticache_subnet_group.RedisSubnetGroup` → becomes `google_redis_instance.production_redis.authorized_network`, NOT its own `google_sql_database_instance` or `google_redis_instance`.

   **Conflict note vs `references/clustering/terraform/classification-rules.md`:** `classification-rules.md` correctly lists `aws_ecs_task_definition` and `aws_rds_cluster_instance` as PRIMARY so they create distinct clusters in Discover. The PRIMARY label there governs **clustering**, not **Terraform emission**. Generate's INCLUDE/EXCLUDE table above is the source of truth for which PRIMARY types become standalone `google_*` blocks. There is no contradiction — these are two different decisions about the same resource.

3. For EACH enumerated source resource, emit ONE distinct `google_*` resource block in the target file. The Terraform resource label MUST be derived from the source `address` so the mapping is auditable:

   - Take `address.split('.')[1]` (the part after the type), e.g. `aws_ecs_service.ProductionPumaService` → `ProductionPumaService`
   - Lower-snake-case it: `production_puma_service`
   - Prefix with the appropriate `google_*` type, e.g. `resource "google_cloud_run_v2_service" "production_puma_service" { ... }`
   - For database: `aws_rds_cluster.orders_db` → `resource "google_sql_database_instance" "orders_db" { ... }`
   - For storage: `aws_s3_bucket.user_uploads` → `resource "google_storage_bucket" "user_uploads" { ... }`

4. Configuration for each emitted block comes from the matching `clusters[].resources[]` entry in `gcp-design.json` (look up by `aws_address` equal to the source `address`). Use `gcp_config` to populate the HCL fields.

5. **Secondary resources** (service accounts, firewall rules, subnet attachments, IAM bindings) are emitted alongside the primaries they serve. One service account per Cloud Run service is the norm — not a single shared service account.

**FORBIDDEN patterns (will cause the file to be rejected by Step 5 self-check):**

- Writing ONE generic `google_cloud_run_service.app` with `image = "gcr.io/cloudrun/hello"` to represent multiple source ECS services.
- Writing ONE generic `google_sql_database_instance.main` to represent multiple source RDS instances.
- Writing ONE generic `google_storage_bucket.main` to represent multiple source S3 buckets.
- Using a fixed placeholder resource label like `"app"`, `"main"`, or `"default"` when there is more than one source resource of that type. Each block's label MUST be derived from a distinct source `address`.
- Omitting a source resource because "they all look similar" — they are distinct services with distinct names, IAM roles, and environment.

**Worked example — compute.tf with 3 source ECS services:**

Source `aws-resource-inventory.json.resources[]` (filtered to compute primaries):

```json
[
  { "address": "aws_ecs_service.orders_api", "type": "aws_ecs_service", "classification": "PRIMARY", "config": { "desired_count": 2, "cpu": 512, "memory": 1024 } },
  { "address": "aws_ecs_service.payments_worker", "type": "aws_ecs_service", "classification": "PRIMARY", "config": { "desired_count": 1, "cpu": 256, "memory": 512 } },
  { "address": "aws_ecs_service.notifications", "type": "aws_ecs_service", "classification": "PRIMARY", "config": { "desired_count": 1, "cpu": 256, "memory": 512 } }
]
```

WRONG (Iter 1 failure mode — do not do this):

```hcl
resource "google_cloud_run_service" "app" {
  name     = "app-service"
  location = var.gcp_region
  template { spec { containers { image = "gcr.io/cloudrun/hello" } } }
}
```

RIGHT (3 source services → 3 distinct Cloud Run services, names derived from source addresses):

```hcl
resource "google_cloud_run_v2_service" "orders_api" {
  name     = "orders-api"
  location = var.gcp_region
  template {
    scaling { min_instance_count = 1, max_instance_count = 4 }
    containers {
      image = "${var.gcp_region}-docker.pkg.dev/${var.gcp_project}/migration/orders-api:latest"  # TODO: confirm image tag after container migration
      resources { limits = { cpu = "500m", memory = "1Gi" } }
    }
    service_account = google_service_account.orders_api.email
  }
  labels = { project = var.project_name, environment = var.environment, "managed-by" = "terraform", "migration-id" = var.migration_id }
}

resource "google_cloud_run_v2_service" "payments_worker" {
  name     = "payments-worker"
  location = var.gcp_region
  template {
    scaling { min_instance_count = 1, max_instance_count = 2 }
    containers {
      image = "${var.gcp_region}-docker.pkg.dev/${var.gcp_project}/migration/payments-worker:latest"  # TODO
      resources { limits = { cpu = "250m", memory = "512Mi" } }
    }
    service_account = google_service_account.payments_worker.email
  }
  labels = { project = var.project_name, environment = var.environment, "managed-by" = "terraform", "migration-id" = var.migration_id }
}

resource "google_cloud_run_v2_service" "notifications" {
  name     = "notifications"
  location = var.gcp_region
  template {
    scaling { min_instance_count = 1, max_instance_count = 2 }
    containers {
      image = "${var.gcp_region}-docker.pkg.dev/${var.gcp_project}/migration/notifications:latest"  # TODO
      resources { limits = { cpu = "250m", memory = "512Mi" } }
    }
    service_account = google_service_account.notifications.email
  }
  labels = { project = var.project_name, environment = var.environment, "managed-by" = "terraform", "migration-id" = var.migration_id }
}
```

**Post-write validation (BLOCKING — Generate phase must stop and regenerate if this check fails):**

> After writing any `<category>.tf` file, immediately:
>
> 1. Read it back from `$MIGRATION_DIR/terraform/<category>.tf` using the Read tool — do NOT trust the in-memory buffer; trust only what is on disk.
> 2. Count `^resource "google_*"` blocks in the file (anchored at line start to avoid counting the word "resource" inside string literals or comments).
> 3. Count matching PRIMARY source resources from `gcp-design.json` (joined against `aws-resource-inventory.json` if needed) whose `aws_type` belongs to this category's INCLUDE list in the Step 2.5 table above.
> 4. If counts don't match (other than by a deliberate one-to-many fan-out that is explicitly documented in the resource's `rationale` field in `gcp-design.json` — e.g. one `aws_ecs_service` legitimately fanning out to one `google_cloud_run_v2_service` PLUS one `google_cloud_run_domain_mapping`), DELETE the file and regenerate from scratch using a one-resource-block-per-source loop. If a single generic block (e.g. `google_cloud_run_v2_service.app`, `google_sql_database_instance.main`, `google_storage_bucket.main`) stands in for multiple distinct source resources, that ALSO fails this check — DELETE and regenerate.
> 5. Re-validate (re-read the regenerated file and re-count). Refuse to advance to the next file until counts match.
>
> **Audit trail (MANDATORY):** write the count check result to `$MIGRATION_DIR/generation-validation.json` after every `.tf` file is validated. The file accumulates one entry per file across the whole Generate run. Use exactly this shape:
>
> ```json
> {
>   "files": [
>     {"file": "terraform/compute.tf", "expected_blocks": 8, "actual_blocks": 8, "passed": true},
>     {"file": "terraform/database.tf", "expected_blocks": 2, "actual_blocks": 2, "passed": true},
>     {"file": "terraform/storage.tf", "expected_blocks": 3, "actual_blocks": 3, "passed": true}
>   ]
> }
> ```
>
> If `generation-validation.json` already exists from a prior run, READ it, APPEND the new file entries (or REPLACE prior entries for the same `file` path), and rewrite the whole file — never lose a prior entry from this run. Every entry MUST include `file` (relative to `$MIGRATION_DIR`), `expected_blocks` (integer), `actual_blocks` (integer), and `passed` (boolean: `expected_blocks == actual_blocks`).
>
> The Step 5 self-check below re-reads `generation-validation.json` and rejects the Generate phase if any `passed: false` entry is present.

### HCL formatting rule (MANDATORY — applies to every `.tf` file written in Step 3)

Terraform rejects single-line nested blocks. Every nested block (a block inside a block) MUST use multi-line syntax.

WRONG (`terraform validate` rejects this):

```hcl
replication { auto {} }
```

RIGHT:

```hcl
replication {
  auto {}
}
```

Or, for the empty-block special case, prefer the modern argument form:

```hcl
replication {
  automatic = true
}
```

Common offenders to watch for: `replication { auto {} }`, `lifecycle { rule { ... } }`, `network_interface { access_config {} }`, `template { spec { containers { ... } } }`. Always format nested blocks on separate lines — the Step 2.6 / Step 5 self-check WILL reject single-line nested blocks because `terraform validate` rejects them.

## Step 2.6: Database-Version Validation Gate (BLOCKING — runs immediately after writing `database.tf`)

Iter 1 wrote `database_version = "POSTGRES_14"` for an Aurora MySQL source. This gate exists to make that impossible.

**For each `google_sql_database_instance` block you just wrote to `database.tf`:**

1. Identify the corresponding source resource: take the Terraform resource label (e.g. `orders_db`) and look up the matching `clusters[].resources[]` entry in `gcp-design.json` whose `aws_address` equals `aws_rds_cluster.orders_db` or `aws_db_instance.orders_db`.
2. From `aws-resource-inventory.json.resources[]` find the source entry with the same `address`. Read `config.engine` (e.g. `aurora-mysql`, `aurora-postgresql`, `mysql`, `postgres`, `mariadb`, `sqlserver-se`) and `config.engine_version`.
3. Verify the generated `database_version` value matches per this table (this mirrors `references/design-refs/database.md > Engine Preservation`):

   | source `engine`                 | required `database_version` value                                            |
   | ------------------------------- | ---------------------------------------------------------------------------- |
   | `aurora-mysql` (or `aurora`)    | `MYSQL_8_0` (use `MYSQL_5_7` if source `engine_version` major < 8)            |
   | `aurora-postgresql`             | `POSTGRES_15` (or `POSTGRES_<N>` matching source major)                        |
   | `mysql`                         | `MYSQL_<X>_<Y>` matching source major.minor (e.g. `MYSQL_8_0`, `MYSQL_5_7`)    |
   | `postgres`                      | `POSTGRES_<N>` matching source major (e.g. `POSTGRES_13`, `POSTGRES_15`)       |
   | `mariadb`                       | `MYSQL_8_0` — Cloud SQL has no MariaDB; record substitution in a `# Substituted: MariaDB → MySQL 8.0 (Cloud SQL has no MariaDB target)` comment |
   | `sqlserver-se` / `sqlserver-ee` | `SQLSERVER_2019_STANDARD` or `SQLSERVER_2019_ENTERPRISE` per source edition    |
   | `oracle-*`                      | This resource should have been routed to `Deferred — specialist engagement` in Design; do NOT emit a `google_sql_database_instance` block |

4. **If the generated `database_version` does NOT match the required value:** REWRITE the value in `database.tf` BEFORE proceeding to the next file. Do NOT leave a wrong engine in the file. Surface a single log line like `corrected database_version for <resource label>: was <wrong>, now <right>`.

5. **`google_redis_instance` validation:** For each `google_redis_instance` block, look up the source `aws_elasticache_replication_group` or `aws_elasticache_cluster`. Require `redis_version` to match source `engine_version` (e.g. source `7.0` → `REDIS_7_0`; source `6.x` → `REDIS_6_X`). Rewrite if mismatched.

6. **`google_alloydb_cluster` validation:** AlloyDB is PostgreSQL-only. If the source `aws_rds_cluster.engine` is `aurora-mysql`, the design phase should have routed this to Cloud SQL MySQL, not AlloyDB. If you find a `google_alloydb_cluster` block whose source is `aurora-mysql`, that is a Design-phase bug — rewrite the block to `google_sql_database_instance` with `database_version = "MYSQL_8_0"` and add a `warnings[]` log line.

**This gate is BLOCKING.** `database.tf` may not be considered written until every block passes engine validation.

## Step 3: Generate Per-Domain .tf Files

For each domain with resources in the generation manifest, **first run Step 2.5 per-resource enumeration for that domain, then write the file, then run the Step 1 Cross-Reference Validation Gate, then (for `database.tf`) run Step 2.6 validation. Both gates are BLOCKING — if either fails, regenerate the file with corrected values before moving on to the next domain.**

**General rules:**

- Consult `references/design-refs/*.md` for GCP configuration best practices
- **For every `google_*` Terraform resource being generated:** before writing the HCL block, look up the resource's `gcp_service` in `design-refs/index.md` (google/skill column) and consult `companion_skills_available` from Step 0.5. If the companion skill resolved to a path, read its `SKILL.md` (if not already read this turn) and use:
  - **The canonical Terraform block shape** the skill documents (correct argument names, nested-block layout, dependency wiring).
  - **Optional fields commonly used in production** that the skill calls out (e.g. for `cloud-run-basics`: VPC connector, secrets via `volumes` block, custom audiences; for `cloud-sql-basics`: IAM database authentication flag, query insights, deletion protection; for `gke-basics`: Workload Identity, release channel, network policy).
  - **Prerequisites the skill flags** (e.g. enabling required APIs, creating a service account first, KMS key for CMEK). Express these as separate `google_project_service`, `google_service_account`, or `google_kms_*` resources in the appropriate .tf file, or as a Step 5 self-check item.
- A single AWS resource may map to multiple GCP resources (1:Many expansion). Companion skills often drive this expansion (e.g. a Cloud Run service skill may prescribe a paired Cloud Run domain mapping or Eventarc trigger).
- Use `gcp_config` values from `gcp-design.json` to populate resource attributes; let the companion skill override defaults where the rubric is silent.
- For `confidence: "inferred"` resources, add comment: `# Tailored to your setup -- verify configuration (JSON confidence: inferred)`
- For `confidence: "deterministic"` resources, optional comment: `# Standard pairing (fixed mapping list)`
- For resources whose `gcp_design.json.rationale` includes `sourced from google/skills/<skill-name> SKILL.md`, add comment: `# Canonical config sourced from google/skills/<skill-name>`
- For resources where the companion skill was **not** installed (per the warning in `gcp-design.json.warnings[]`), add comment: `# Fallback config -- install google/skills/<skill-name> for richer guidance`
- Include `secondary_resources` from the cluster (service accounts, firewall rules)
- Label every resource: project, environment, managed-by, migration-id

**Domain-specific rules (companion-skill-aware):**

| Domain     | Companion google/skill (if installed) | Key Rules                                                                                                                      |
| ---------- | ------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------ |
| Networking | `google-cloud-networking-observability` | At least 2 zones; private + public subnets; Cloud NAT for private subnet internet; Cloud Router. Defer to skill for LB scheme + URL map shape. |
| Security   | `google-cloud-recipe-auth`, `google-cloud-waf-security` | Least-privilege IAM (specific roles, never `roles/owner`); per-service service accounts for Cloud Run/GKE. Defer to skill for Cloud Armor + Workload Identity Federation patterns. |
| Storage    | _none_                                | Versioning enabled; uniform bucket-level access; encryption (Google-managed or CMEK); lifecycle policies                       |
| Database   | `cloud-sql-basics`, `alloydb-basics`  | Private IP; authorized networks; automated backups; encryption; point-in-time recovery enabled. Defer to skill for tier selection, IAM database auth, query insights. |
| Compute    | `cloud-run-basics`, `gke-basics`      | Cloud Run in VPC connector; service configs from `gcp_config` CPU/memory; auto-scaling. Defer to skill for concurrency, secrets, custom audiences, GKE Workload Identity. **Container image must be derived from the source ECS task definition's `image` — see "Container image translation" rule directly below.** |

### Container image translation (Cloud Run / Cloud Run jobs / GKE Deployments)

When emitting `google_cloud_run_v2_service`, `google_cloud_run_v2_job`, or a GKE container spec for an ECS / Lambda / EC2-container source, the container `image` field MUST be derived from the source resource's container image.

**Translation procedure:**

1. From `aws-resource-inventory.json.resources[]`, locate the source `aws_ecs_task_definition` linked to the `aws_ecs_service` you are emitting (follow the `task_definition` reference in the service's `config` or the `task-definition` edge in `aws-resource-clusters.json`). For Lambda, read `aws_lambda_function.image_uri` (if package_type is `Image`) or `aws_lambda_function.handler` + `runtime` (if package_type is `Zip`). For EC2-launched containers, read the `aws_ecr_image` referenced by the user_data / launch_template.
2. Extract the source container image URI (e.g. `123456789.dkr.ecr.ap-northeast-1.amazonaws.com/tunag/puma:abc123`).
3. Translate the ECR URI to the equivalent Artifact Registry path:
   - Source pattern: `<aws-account-id>.dkr.ecr.<aws-region>.amazonaws.com/<repo>/<image>:<tag>`
   - Target pattern: `${var.gcp_region}-docker.pkg.dev/${var.gcp_project}/<repo>/<image>:<tag>`
   - Repository names — keep the same `<repo>/<image>` path so the user knows which source image to mirror.
   - Tags — keep the source tag verbatim. If the source uses `:latest`, keep `:latest` (do NOT silently pin to a different tag).
4. Emit a comment on the resource block: `# IMAGE: mirror ${source_image} → ${target_image} via 'gcloud builds submit' or 'docker push' BEFORE terraform apply`. Also emit a `# REQUIRED: <user-action>` line noting the user must push the image to Artifact Registry before `terraform apply` will succeed.

**Lambda → Cloud Run translation specifics:**

- `package_type = Image` → translate the ECR `image_uri` exactly as above.
- `package_type = Zip` → emit `image = "${var.gcp_region}-docker.pkg.dev/${var.gcp_project}/migration/${function_name}:latest"` and a `# TODO -- build container from Lambda zip source code at <source_path>; see MIGRATION_GUIDE.md "Lambda packaging" section` comment. Do NOT use a placeholder hello image even in the zip case.

**FORBIDDEN image patterns:** The following image references will cause the file to be rejected by the Step 5 self-check.

- `us-docker.pkg.dev/cloudrun/container/hello` (Google's hello-world container)
- `gcr.io/cloudrun/hello` (older alias for the same hello container)
- `gcr.io/google-samples/hello-app:1.0` (Kubernetes hello sample)
- `nginx`, `nginx:latest`, `httpd`, `busybox`, `alpine` (generic upstream images standing in for a real workload)
- ANY image whose path includes the substring `hello`, `sample`, `demo`, or `placeholder` unless the SOURCE container image had the same substring.

If you cannot locate a source image URI in `aws-resource-inventory.json` (e.g. discovery missed the ECR reference), leave the `image` field as `image = "${var.gcp_region}-docker.pkg.dev/${var.gcp_project}/migration/<service-name>:latest"` AND emit a TODO comment `# TODO -- source image not found in discovery; populate ECR/Artifact Registry path manually` AND a `# REQUIRED: <user-action>` line. DO NOT substitute a hello image silently.
| Monitoring | `google-cloud-networking-observability` | Log sinks per service; dashboard with key metrics; alert policies from `generation-infra.json` success_metrics; 30-day retention |

## Step 4: Generate outputs.tf

Output identifiers for key resources (VPC ID, database connection name, Cloud Run URL, etc.) plus a **`migration_summary` output** (object) including at minimum:

| Key | Type / example | Purpose |
| --- | -------------- | ------- |
| `gcp_region` | string | From `var.gcp_region` |
| `environment` | string | From `var.environment` |
| `migration_id` | string | From `var.migration_id` |
| `service_count` | number | Count of primary logical services / resources represented |
| `aligned_with_estimate_tier` | string | Always **`"balanced"`** for this advisor -- generated IaC matches the **Balanced** scenario in `estimation-infra.json` |
| `cost_scenarios_modeled_in_terraform` | string | e.g. **`"design_baseline_only"`** -- only one stack generated; Premium/Optimized exist as **pricing** scenarios in estimates, not as additional Terraform trees |

Add VPC ID or other IDs when known from resources. Descriptions on every output.

**Example shape:**

```hcl
output "migration_summary" {
  description = "Migration run metadata and cost-tier alignment (Balanced baseline)"
  value = {
    gcp_region                            = var.gcp_region
    environment                           = var.environment
    migration_id                          = var.migration_id
    service_count                         = <number>
    aligned_with_estimate_tier            = "balanced"
    cost_scenarios_modeled_in_terraform   = "design_baseline_only"
  }
}
```

## Step 4.5: Checkpoint Discipline (Budget-Aware)

When running under a wall-clock budget (Gemini CLI headless, time-limited harness), follow these per-file rules so partial completion is still useful (see `generate.md` -> **Budget Guidance** for full priority order):

- **Write each `.tf` file to disk the moment it is generated** — do **not** accumulate multiple files in memory and write them in a single final batch. A crash or timeout mid-loop must leave already-written files intact.
- Emit files in this priority order: `main.tf` -> `variables.tf` -> `outputs.tf` -> `vpc.tf` -> `security.tf` -> `storage.tf` -> `database.tf` -> `compute.tf` -> `monitoring.tf` -> `terraform/README.md`. Domains without resources in `gcp-design.json` are skipped entirely.
- After each file is written, surface a single log line (e.g. `wrote terraform/<file>`) so a parent harness can observe progress.
- If the budget runs out mid-stream, **do not** delete partial files. Re-running Generate will resume from the missing files; the Phase Completion check in `generate.md` accepts a partial Stage 2 with a "resume" recommendation in the summary.
- **Never emit nothing.** If a single resource block fails generation, emit the file with the failing block replaced by a `# TODO -- generation failed: <reason>` marker so the user has actionable HCL.

## Step 4.8: Emit Source-Code Migration Patches (`code-patches/` + `code-migration-summary.md`)

**Gate:** Only run this step if `$MIGRATION_DIR/sdk-migration-plan.json` exists (produced by Design Step 4.7). If it does not exist, skip this step entirely — there are no app-level SDK call sites to rewrite. Terraform generation above is unaffected by this step.

This step produces a **separate** artifact tree under `$MIGRATION_DIR/code-patches/` — Terraform files in `$MIGRATION_DIR/terraform/` remain untouched. The patches are unified diffs the user can apply with `git apply` or `patch -p1` after they have reviewed them.

**Path discipline:** every patch MUST be written under `$MIGRATION_DIR/code-patches/`. Never write a patch into the user's source tree directly — the user must apply the patch themselves so they can review and edit before committing. Patches are **proposals**, not unilateral edits.

### Step 4.8.1: Group translations by source file

Read `sdk-migration-plan.json`. Group `translations[]` by `source.file`. Each group becomes ONE patch file. The patch filename is the source file's basename with a `.patch` extension, with directory separators replaced by `__` to avoid collisions:

- `app/config/initializers/01_secrets.rb` -> `code-patches/app__config__initializers__01_secrets.rb.patch`
- `app/app/controllers/attachments_controller.rb` -> `code-patches/app__app__controllers__attachments_controller.rb.patch`

If `aws-sdk-usage.json.summary.wrapper_detected.present` is `true`, the wrapper file gets its own patch (the wrapper rewrite from Step 4.7's wrapper handling). The downstream call-site patches assume the wrapper is rewritten — keyword-argument changes that depend on the new wrapper (e.g. `bucket:` vs `bucket = storage.bucket(...)`) live in the call-site patches, NOT the wrapper patch.

### Step 4.8.2: Emit one unified-diff patch per source file

For each group, write a unified diff (`---` / `+++` / `@@` hunks) showing:

1. **Imports / requires** — remove the `require "aws-sdk-*"` / `import boto3` / `import { ... } from "@aws-sdk/*"` line. Add the corresponding `require "google/cloud/*"` / `from google.cloud import *` / `import { ... } from "@google-cloud/*"` line.
2. **Call expressions** — rewrite each call site per its `target.snippet` from `sdk-migration-plan.json`. Keep enough surrounding context (3 lines above + 3 lines below) so `git apply` can locate the hunk even if line numbers drift.
3. **Inline comments** — for every translation with `manual_review: true` OR `notes`, insert a `# REVIEW: <notes>` (Ruby/Python) or `// REVIEW: <notes>` (JS/TS/Go) or `/* REVIEW: <notes> */` (Java) comment immediately above the rewritten call so the developer can see the diff during review.
4. **Auth comment** — at the top of the patch (after the file header), insert one comment line: `# AUTH: <auth_change>` so the developer remembers to wire Workload Identity at deployment time. Only emit once per file even if multiple call sites share the same auth note.

**Example patch shape** (Ruby — for `app/config/initializers/01_secrets.rb`):

```diff
--- a/app/config/initializers/01_secrets.rb
+++ b/app/config/initializers/01_secrets.rb
@@ -1,5 +1,9 @@
 # frozen_string_literal: true
+# AUTH: AWS IAM role -> GCP service account via Workload Identity Federation
+# (no SDK-level code change; service account binding is configured at deployment time in Terraform)
+#
 # Pulls a runtime secret bundle from GCP Secret Manager at boot.
@@ -17,7 +21,9 @@ $tunag_runtime_secrets = {}
 if %w[production staging].include?(ENV["RAILS_ENV"])
   secret_id = ENV.fetch("SECRETS_MANAGER_SECRET_ID", "tunag-edu-test-production-rails-master-keys")
-  resp = AwsClients.secrets.get_secret_value(secret_id: secret_id)
-  parsed = JSON.parse(resp.secret_string)
+  # REVIEW: response shape changed — resp.secret_string -> resp.payload.data (bytes).
+  resp = GcpClients.secrets.access_secret_version(name: "projects/#{ENV.fetch('GCP_PROJECT')}/secrets/#{secret_id}/versions/latest")
+  parsed = JSON.parse(resp.payload.data.force_encoding("UTF-8"))
   # Symbolize keys so callers can use `[:foo]` consistently across env-injected
   # and Secrets-Manager-injected secrets.
```

**Wrapper-file patch** (for `app/config/initializers/00_aws.rb` when `wrapper_detected.present` is true): emit a single patch that replaces the entire `AwsClients` module body with a `GcpClients` module body. Each `Aws::<Svc>::Client.new(region:)` line becomes the corresponding `Google::Cloud::<Svc>.new` line. Rename the module from `AwsClients` to `GcpClients` so call-site patches' references compile after both patches apply.

**Patches are best-effort.** If the rewrite snippet contains placeholders (`${var.gcp_project}`) or `# MANUAL:` markers, leave them in the patch as-is — the user resolves them when applying.

### Step 4.8.3: Emit `code-migration-summary.md`

Write `$MIGRATION_DIR/code-migration-summary.md` with a per-patch roll-up:

```markdown
# Source-Code Migration Summary

This file lists every patch produced under `$MIGRATION_DIR/code-patches/`.
Apply each patch with `git apply` or `patch -p1` from your app project root, AFTER reviewing the diff.

| Patch | Source file | Call sites | Risk | Manual review |
| ----- | ----------- | ---------: | ---- | ------------- |
| `app__config__initializers__00_aws.rb.patch` | `app/config/initializers/00_aws.rb` | 5 | medium | wrapper rewrite — verify all `Google::Cloud::*` clients construct |
| `app__config__initializers__01_secrets.rb.patch` | `app/config/initializers/01_secrets.rb` | 1 | low | response shape diff (`resp.secret_string` -> `resp.payload.data`) |
| `app__app__controllers__attachments_controller.rb.patch` | `app/app/controllers/attachments_controller.rb` | 3 | low | none |
| ... | ... | ... | ... | ... |

## Risk legend

- **low** — every call site in the patch has `confidence: "deterministic"` and no `manual_review` flag
- **medium** — patch contains at least one `inferred` translation OR rewrites a wrapper that other files depend on
- **high** — patch contains a `# MANUAL:` placeholder (SES, DynamoDB data-model rewrite, or TODO-stubbed language) that requires a human-authored rewrite before the file will run

## Workflow

1. Run `terraform apply` from `$MIGRATION_DIR/terraform/` to provision GCP infrastructure (creates the service accounts and secret containers referenced by the patches).
2. For each patch in this table, in order:
   a. `git apply --check $MIGRATION_DIR/code-patches/<patch>` to dry-run
   b. Read the diff. Resolve any `${var.gcp_project}` placeholders and `# MANUAL:` markers.
   c. `git apply $MIGRATION_DIR/code-patches/<patch>` to apply
   d. Run the project's test suite for the touched files
3. Once all patches apply cleanly and tests pass, remove the `aws-sdk-*` gems / packages from your dependency manifest.

## Auth note

Every patch's top-of-file `# AUTH:` comment reminds you to bind the Cloud Run / GKE service account to the right IAM roles. The Terraform output `migration_summary.service_accounts` lists the service accounts created. Bind each one with `gcloud projects add-iam-policy-binding` per the role recommendations in `MIGRATION_GUIDE.md`.
```

Risk levels are computed per patch by joining the patch's translations (from `sdk-migration-plan.json`) and applying the legend rules.

### Step 4.8.4: Per-file validation

For each patch written:

- File path is under `$MIGRATION_DIR/code-patches/`
- File extension is `.patch`
- First two lines are `--- a/<path>` and `+++ b/<path>`
- At least one `@@` hunk header is present
- Every `+` line that adds a `google.cloud` / `google-cloud` / `@google-cloud` reference appears in a hunk that also `-` removes the corresponding `aws-sdk` / `boto3` / `@aws-sdk` reference, OR the file is the wrapper file (which adds the GCP imports without removing them — the AwsClients module's old imports were deleted in a prior hunk in the same patch)

If any patch fails these checks, regenerate that patch before reporting completion. The Step 5 self-check below adds a checklist item for this.

## Step 5: Self-Check

Verify these quality rules before reporting completion:

- [ ] **Path discipline:** every generated file lives under `$MIGRATION_DIR/terraform/`. Nothing was written to project root (cwd). No helper Python/Node/Bash parser script was written.
- [ ] **Per-resource enumeration (Step 2.5):** for each domain `.tf` file, the count of `google_*` resource blocks is greater than or equal to the count of matching PRIMARY source resources in `aws-resource-inventory.json`. NO file uses a single generic block (e.g. `google_cloud_run_service.app`, `google_sql_database_instance.main`, `google_storage_bucket.main`) to stand in for multiple distinct source resources. Every block label is derived from a distinct source `address`. **Read `$MIGRATION_DIR/generation-validation.json` — it MUST exist, MUST contain one entry per `.tf` file written this run, and EVERY entry MUST have `passed: true`. Any `passed: false` entry fails this self-check; regenerate the offending file before reporting completion.**
- [ ] **Database engine preservation (Step 2.6):** every `google_sql_database_instance.database_version` matches the source `engine`/`engine_version` per the validation table. Every `google_redis_instance.redis_version` matches its source ElastiCache `engine_version`. No `database_version = "POSTGRES_*"` exists for a `mysql` / `aurora-mysql` / `mariadb` source. No `database_version = "MYSQL_*"` exists for a `postgres` / `aurora-postgresql` source.
- [ ] **Design alignment (Step 1 Cross-Reference Gate):** for every `google_*` block, the `database_version` / `redis_version` / `region` / resource type matches the corresponding `gcp-design.json` entry by `aws_address`. NO block contradicts Design. If a contradiction is found, the file MUST be regenerated.
- [ ] **No FORBIDDEN container images** (Step 3 compute rule): no `google_cloud_run_v2_service`, `google_cloud_run_v2_job`, or GKE container spec uses `us-docker.pkg.dev/cloudrun/container/hello`, `gcr.io/cloudrun/hello`, `gcr.io/google-samples/hello-app`, `nginx`, `httpd`, `busybox`, or `alpine` as the image, AND no image path contains `hello`, `sample`, `demo`, or `placeholder` unless the source image had the same substring. Every Cloud Run/Cloud Run job/GKE container image is derived from the source ECS task definition / Lambda image URI, translated to an Artifact Registry path under `${var.gcp_region}-docker.pkg.dev/${var.gcp_project}/`.
- [ ] No overly broad IAM roles (`roles/owner`, `roles/editor` on project)
- [ ] No default VPC references -- all resources use the created VPC
- [ ] No hardcoded credentials in any .tf file
- [ ] Labels on every resource (project, environment, managed-by, migration-id)
- [ ] Encryption at rest on all storage (Cloud Storage, Cloud SQL, persistent disks)
- [ ] Databases and internal services use private IP
- [ ] No `0.0.0.0/0` ingress except load balancer port 443
- [ ] Every variable has `type` and `description`
- [ ] Every output has `description`
- [ ] Region from `var.gcp_region`, never hardcoded
- [ ] `terraform/README.md` exists with cost-tier vs Terraform explanation
- [ ] `main.tf` begins with the required cost-tier / Balanced alignment comment block
- [ ] `migration_summary` output includes `aligned_with_estimate_tier` and `cost_scenarios_modeled_in_terraform`
- [ ] For every `google_*` resource whose `gcp_service` has a companion google/skill that resolved during Step 0.5: prerequisites the skill calls out (required APIs via `google_project_service`, service accounts, KMS keys, etc.) are either present in the generated .tf files or listed as `TODO` markers
- [ ] For every `google_*` resource whose companion google/skill was **not** installed: the resource block carries the `# Fallback config -- install google/skills/<skill-name> for richer guidance` comment so the user knows where to look for richer config later
- [ ] **Source-code patches (Step 4.8):** if `sdk-migration-plan.json` exists, every entry in `translations[]` has a corresponding patch under `$MIGRATION_DIR/code-patches/`, and `$MIGRATION_DIR/code-migration-summary.md` lists every patch with a risk level. If `sdk-migration-plan.json` does NOT exist, this checkbox is automatically satisfied (no patches needed).

**If any of the first FIVE checkboxes fail (path discipline, per-resource enumeration, database engine preservation, Design alignment, no FORBIDDEN images), REGENERATE the affected file(s) before reporting completion. These five are blocking; the others are quality flags.**

## Phase Completion

Report generated files to the parent orchestrator. **Do NOT update `.phase-status.json`** -- the parent `generate.md` handles phase completion.

```
Generated terraform artifacts:
- terraform/README.md
- terraform/main.tf
- terraform/variables.tf
- terraform/outputs.tf
- terraform/[domain].tf (for each domain with resources)

Total: [N] Terraform files
TODO markers: [N] items requiring manual configuration
```

If Step 4.8 ran (i.e. `sdk-migration-plan.json` existed), also include in the report:

```
Generated source-code patches:
- code-patches/<basename>.patch (for each source file with AWS SDK call sites)
- code-migration-summary.md

Total: [M] patches
High-risk patches (manual rewrite required): [K] items
```
