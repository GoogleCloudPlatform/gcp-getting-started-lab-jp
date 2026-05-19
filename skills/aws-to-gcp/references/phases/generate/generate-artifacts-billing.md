# Generate Phase: Billing Skeleton Artifact Generation

> Loaded by generate.md when generation-billing.json and gcp-design-billing.json exist.

**Execute ALL steps in order. Do not skip or optimize.**

## Overview

Generate **skeleton Terraform** with TODO markers for billing-only migrations. These configurations are NOT deployable as-is -- they require manual configuration refinement based on actual infrastructure discovery.

Every resource block includes TODO markers indicating what is missing and where to get it.

## Prerequisites

Read from `$MIGRATION_DIR/`:

- `gcp-design-billing.json` (REQUIRED) -- Billing-based service mapping from Phase 3
- `generation-billing.json` (REQUIRED) -- Conservative migration plan from Stage 1

If any required file is missing: **STOP**. Output: "Missing required artifact: [filename]. Complete the prior phase that produces it."

## Output Structure

| File           | When                                 | Contains                               |
| -------------- | ------------------------------------ | -------------------------------------- |
| `main.tf`      | Only if infra track didn't create it | Provider config, backend, data sources |
| `variables.tf` | Only if infra track didn't create it | Inferred variables with TODO markers   |
| `skeleton.tf`  | Always                               | Resource stubs with TODO markers       |

Do NOT overwrite existing `main.tf` or `variables.tf` if the infrastructure track already generated them.

## Step 0: Read Design Inputs

From `gcp-design-billing.json`: `services[]` (mapped), `unknowns[]` (unmapped), `metadata.total_services`, `metadata.confidence_note`.

From `generation-billing.json`: migration timeline (for header comments), risk level (for confidence tags).

## Step 1: Generate main.tf (if not present)

**Requirements:**

- Header comment block: "SKELETON TERRAFORM -- BILLING-ONLY MIGRATION", WARNING about TODO markers, confidence LOW, action required note
- `terraform` block: `required_version >= 1.5.0`, `hashicorp/google ~> 5.0`, commented GCS backend
- `provider "google"` block: `project = var.gcp_project`, `region = var.gcp_region`, `default_labels` with project, environment, managed-by, `confidence = "billing-only-skeleton"`
- Data sources: `google_project`, `google_compute_zones`

## Step 2: Generate variables.tf (if not present)

**Global variables:** `gcp_project`, `gcp_region` (from preferences.json), `project_name`, `environment`.

**Per-service variables:** For each mapped service in `gcp-design-billing.json.services[]`, create variables with:

- **Known defaults** get a `# Verify` comment
- **Unknown values** get a `# TODO` comment with placeholder
- Use billing SKU hints to inform reasonable defaults where possible

Header comment: "Many values are placeholders. Search for TODO to find values needing manual configuration."

## Step 3: Generate skeleton.tf

For each mapped service in `gcp-design-billing.json.services[]`, generate a resource stub.

**Every resource block must include:**

- Header comment: GCP service name, AWS source, confidence level, monthly AWS cost, SKU hints
- `# TODO: Verify all configuration values against actual AWS resource settings`
- At least one `# TODO` per configurable attribute
- Labels: name, aws-source, `confidence = "billing-inferred"`

**Resource generation by AWS service type:**

| AWS Service            | GCP Resource Type                      | Key TODO Attributes                                    |
| ---------------------- | -------------------------------------- | ------------------------------------------------------ |
| Fargate, ECS, EKS, EC2 | Cloud Run service / GKE cluster       | CPU, memory, container image, port, auto-scaling       |
| RDS, Aurora            | Cloud SQL instance                     | Engine, version, tier, storage, networking              |
| DynamoDB               | Firestore / Cloud Spanner              | Capacity, schema, access patterns                      |
| S3                     | Cloud Storage bucket + versioning + encryption | Bucket count, storage classes, lifecycle policies |
| ALB, NLB               | VPC + Cloud Load Balancing             | Subnets, firewall rules, health checks, backends       |
| Route 53               | Cloud DNS                              | Zone names, record types                               |
| NAT Gateway            | Cloud NAT                              | Subnet associations, Cloud Router                      |

For compute stubs: include Cloud Run service with container configuration, or GKE cluster with node pool.

For database stubs: include `settings.backup_configuration.enabled = true`, `deletion_protection = false # TODO: Set to true for production`.

For storage stubs: include bucket with project ID suffix, versioning enabled, uniform bucket-level access.

**Unmapped services:** At the bottom of `skeleton.tf`, add a comment block for each service in `unknowns[]` with: service name, monthly cost, reason unmapped, possible GCP target suggestion, TODO marker.

## Step 4: Self-Check

- [ ] Every mapped service has a resource stub in `skeleton.tf`
- [ ] Every resource has at least one `# TODO` comment
- [ ] No resource is presented as production-ready -- all have confidence markers
- [ ] Skeleton warning header present at top of `main.tf` and `skeleton.tf`
- [ ] No hardcoded credentials
- [ ] Labels include `confidence = "billing-inferred"` on every resource
- [ ] Unmapped services from `unknowns[]` listed at bottom
- [ ] Did not overwrite existing `main.tf` or `variables.tf` from infrastructure track

## Phase Completion

Report generated files to the parent orchestrator. **Do NOT update `.phase-status.json`** -- the parent `generate.md` handles phase completion.

```
Generated billing skeleton artifacts:
- terraform/skeleton.tf (with TODO markers)
- terraform/main.tf (if not already present)
- terraform/variables.tf (if not already present)

WARNING: These are SKELETON configurations generated from billing data only.
They are NOT deployable without manual configuration.
TODO markers: [N] items requiring manual configuration
Unmapped services: [N] services need manual GCP target assignment

Recommendation: Provide Terraform files or CloudFormation templates and re-run discovery for deployable configurations.
```
