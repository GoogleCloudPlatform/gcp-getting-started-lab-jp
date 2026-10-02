# Generate Phase: Migration Script Generation

## Contents

- Overview
- Step 0: Path Discipline (READ FIRST)
- Prerequisites
- Step 1: Detect Resource Categories
- Output Structure
- Step 2: Generate Migration Scripts
- Step 3: Self-Check
- Phase Completion

> Loaded by generate.md after generate-artifacts-infra.md completes (terraform files generated).

**Execute ALL steps in order. Do not skip or optimize.**

## Overview

Transform the migration plan (`generation-infra.json`) into numbered migration scripts for data, container, secrets, and validation tasks.

**Outputs:**

- `$MIGRATION_DIR/scripts/` directory -- Numbered migration scripts for data and service migration

## Step 0: Path Discipline (READ FIRST)

All scripts produced by this sub-file MUST be written under `$MIGRATION_DIR/scripts/` — for example `$MIGRATION_DIR/scripts/01-validate-prerequisites.sh`. NEVER write to `./scripts/` (cwd) or the project root. The source project's own files MUST NOT be touched. NEVER emit a helper Python/Node/Bash parser script to read the migration plan — use Read/Grep/Glob on `$MIGRATION_DIR/gcp-design.json` and `$MIGRATION_DIR/generation-infra.json` directly. The only shell scripts this sub-file writes are the user-facing migration scripts named `01-` through `05-` listed below; nothing else. See **SKILL.md > File Output Discipline (CRITICAL)** for the full rule set.

## Prerequisites

Read the following artifacts from `$MIGRATION_DIR/`:

- `gcp-design.json` (REQUIRED) -- GCP architecture design with cluster-level resource mappings
- `generation-infra.json` (REQUIRED) -- Migration plan with timeline and service assignments
- `preferences.json` (REQUIRED) -- User preferences including target region, sizing, compliance

If any REQUIRED file is missing: **STOP**. Output: "Missing required artifact: [filename]. Complete the prior phase that produces it."

## Step 1: Detect Resource Categories

Scan `gcp-design.json` clusters[].resources[] to determine which resource categories exist.
Set boolean flags for downstream script generation:

- **has_databases**: true if ANY resource has `gcp_service` containing "Cloud SQL", "Spanner", "Firestore",
  "Memorystore", "AlloyDB" OR `aws_type` starting with `aws_db_`, `aws_rds_`,
  `aws_dynamodb_`, `aws_elasticache_`, `aws_redshift_`
- **has_storage**: true if ANY resource has `gcp_service` = "Cloud Storage" OR `aws_type` = `aws_s3_bucket`
- **has_containers**: true if ANY resource has `gcp_service` containing "Cloud Run", "GKE", "Compute Engine"
  OR `aws_type` starting with `aws_ecs_`, `aws_eks_`, `aws_instance`
- **has_secrets**: true if ANY resource has `gcp_service` containing "Secret Manager"
  OR `aws_type` starting with `aws_secretsmanager_`
- **has_data_migration**: has_databases OR has_storage (used for script 02)

Report detected categories to user: "Resource categories detected: [list active flags]"

## Output Structure

Scripts 02-04 are generated **only** when the corresponding resource categories are detected:

```
$MIGRATION_DIR/
+-- scripts/
    +-- 01-validate-prerequisites.sh          # Always
    +-- 02-migrate-data.sh                    # Only if has_data_migration
    +-- 03-migrate-containers.sh              # Only if has_containers
    +-- 04-migrate-secrets.sh                 # Only if has_secrets
    +-- 05-validate-migration.sh              # Always (adapts checks)
```

## Step 2: Generate Migration Scripts

### Script Rules

- Every script defaults to **dry-run mode** -- requires `--execute` flag to make changes
- Every script includes a verification step after execution
- Scripts are numbered for execution order
- Scripts use `set -euo pipefail` for safety
- Scripts log all actions to `$MIGRATION_DIR/logs/`

### 01-validate-prerequisites.sh

Verify all prerequisites before migration:

- GCP CLI (`gcloud`) configured and authenticated
- Required IAM permissions present
- Target VPC and subnets exist (Terraform applied)
- AWS connectivity established (for data transfer)
- Required tools installed (gcloud, aws, terraform, jq, docker)
- Workload Identity Federation configured for cross-cloud access where scripts need it (see 02's STS notes) — prefer WIF over long-lived AWS keys or JSON key files

### 02-migrate-data.sh -- IF has_data_migration

**Skip this script entirely if `has_data_migration` is false.**

Based on database and storage resources in `gcp-design.json`:

**RDS/Aurora to Cloud SQL** -- include only if `has_databases`:

**Primary path — Database Migration Service (DMS), continuous replication.** For MySQL / Aurora MySQL / PostgreSQL / Aurora PostgreSQL sources, DMS is Google's recommended path and is what `generate-infra.md`'s migration plan and G4 gate ("replication lag < 1s") assume: serverless, CDC-based, minimal-downtime, no additional charge for homogeneous migrations. Verify current source-version support at `https://docs.cloud.google.com/database-migration/docs` (Aurora MySQL up to 8.4 supported as of mid-2026). Use dump/import (fallback below) only for small/dev databases (roughly <50 GB) or DMS-unsupported engines (e.g. MariaDB).

**DMS prerequisites the guide MUST surface** (verify each against the current DMS known-limitations page before cutover; MySQL-family specifics):

- Target Cloud SQL flag `local_infile = ON` during the initial load (DMS bulk-loads via `LOAD DATA LOCAL INFILE`).
- TLS: Aurora MySQL 8.4 defaults `require_secure_transport=ON` — configure the DMS connection with the source CA cert and `verify-ca`/`verify-full`, or connections fail.
- FREEZE schema changes on the source during the initial snapshot — DDL mid-snapshot breaks the binlog stream mapping and fails the job.
- The dedicated migration user needs replication privileges but must NOT hold `BACKUP_ADMIN`; system schemas (`mysql`, `information_schema`, `performance_schema`, `sys`) are excluded from migration.

```bash
#!/usr/bin/env bash
set -euo pipefail

# RDS/Aurora -> Cloud SQL via Database Migration Service (continuous replication)
# Usage: ./02-migrate-data.sh [--execute]

DRY_RUN=true
[[ "${1:-}" == "--execute" ]] && DRY_RUN=false

echo "=== Database Migration: RDS/Aurora -> Cloud SQL (DMS continuous replication) ==="
echo "Mode: $([ "$DRY_RUN" = true ] && echo 'DRY RUN' || echo 'EXECUTE')"

REGION="<target-region>"                # From preferences.json target_region — Generate substitutes the real value
SOURCE_HOST="<rds-endpoint>"            # TODO: Set RDS/Aurora endpoint
TARGET_INSTANCE="<cloud-sql-instance>"  # From terraform output database_connection_name
PROFILE_ID="mig-source-profile"
JOB_ID="mig-continuous-job"

if [ "$DRY_RUN" = true ]; then
  echo "[DRY RUN] Would create DMS connection profile -> $SOURCE_HOST"
  echo "[DRY RUN] Would create + start continuous migration job -> $TARGET_INSTANCE"
else
  echo "Creating source connection profile..."
  gcloud database-migration connection-profiles create mysql "$PROFILE_ID" \
    --region="$REGION" --host="$SOURCE_HOST" --port=3306 \
    --username="<migration-user>" --prompt-for-password   # TODO: engine-specific: use `postgresql` subcommand for PG sources

  echo "Creating DESTINATION connection profile (required — --destination takes a profile ID, not an instance name)..."
  gcloud database-migration connection-profiles create cloudsql "mig-dest-profile" \
    --region="$REGION" --cloudsql-instance="$TARGET_INSTANCE"   # TODO: verify flag set for your engine via `gcloud database-migration connection-profiles create cloudsql --help`

  echo "Creating continuous migration job..."
  gcloud database-migration migration-jobs create "$JOB_ID" \
    --region="$REGION" --type=CONTINUOUS \
    --source="$PROFILE_ID" --destination="mig-dest-profile"

  echo "Starting migration job..."
  gcloud database-migration migration-jobs start "$JOB_ID" --region="$REGION"

  echo "Monitor replication lag until < 1s, then promote at the cutover window:"
  echo "  gcloud database-migration migration-jobs describe $JOB_ID --region=$REGION"
  echo "  gcloud database-migration migration-jobs promote $JOB_ID --region=$REGION   # cutover step — see MIGRATION_GUIDE"
fi

# Verification
echo "=== Verification ==="
echo "TODO: Compare row counts between source and target"
echo "TODO: Run checksum validation on critical tables"
```

**Fallback — one-shot dump/import** (small/dev databases, or DMS-unsupported engines like MariaDB):

```bash
# Export from RDS, upload, import (one-shot; downtime = export+import duration)
# MySQL: include the compatibility flags — binary-safe dump + GTID stripping:
# mysqldump -h "$SOURCE_HOST" -u admin -p "$DATABASE_NAME" --hex-blob --set-gtid-purged=OFF > export.sql
# PostgreSQL: pg_dump -h "$SOURCE_HOST" -U admin -d "$DATABASE_NAME" > export.sql
# gcloud storage cp export.sql gs://migration-bucket/export.sql
# gcloud sql import sql "$TARGET_INSTANCE" gs://migration-bucket/export.sql --database="$DATABASE_NAME"
```

**DynamoDB to Firestore** -- include only if `has_databases`:

```bash
# DynamoDB -> Firestore migration
# TODO: Use custom export/import script or Dataflow pipeline
```

**S3 to Cloud Storage** -- include only if `has_storage`:

```bash
# S3 -> Cloud Storage: Storage Transfer Service is the PRIMARY path for any cross-cloud
# transfer (Google's recommendation regardless of size). Use federated identity — an AWS
# IAM role trusting the STS service account (Workload Identity Federation pattern) — via
# --source-creds-file with a role ARN, instead of shipping static AWS keys in a file:
#   creds.json: {"roleArn": "arn:aws:iam::<account>:role/gcp-storage-transfer"}
# gcloud transfer jobs create s3://source-bucket gs://target-bucket \
#   --source-creds-file=creds.json
#
# Ongoing sync during the pre-cutover window (implements generate-infra.md's "enable
# ongoing sync"): create an EVENT-DRIVEN transfer job fed by S3 Event Notifications -> SQS
# (see https://docs.cloud.google.com/storage-transfer/docs/event-driven-transfers).
# Caveat: object DELETIONS are not propagated — plan a final reconciliation pass.
#
# Small ad-hoc copies only (not the migration path):
# gcloud storage cp --recursive s3://source-bucket gs://target-bucket/
```

### 03-migrate-containers.sh -- IF has_containers

**Skip this script entirely if `has_containers` is false.**

Migrate container images from ECR to Artifact Registry:

```bash
#!/usr/bin/env bash
set -euo pipefail

# Container image migration: ECR -> Artifact Registry
# Usage: ./03-migrate-containers.sh [--execute]

DRY_RUN=true
[[ "${1:-}" == "--execute" ]] && DRY_RUN=false

GCP_PROJECT="$(gcloud config get-value project)"
GCP_REGION="<target-region>"  # Generate MUST substitute the actual preferences.json target_region value here — never leave a hard-coded region literal
AR_REGISTRY="${GCP_REGION}-docker.pkg.dev/${GCP_PROJECT}/migration"

# TODO: List container images from gcp-design.json compute resources
IMAGES=(
  "123456789012.dkr.ecr.us-east-1.amazonaws.com/image1:latest"
  # Add more images from your AWS ECR
)

for IMAGE in "${IMAGES[@]}"; do
  IMAGE_NAME=$(echo "$IMAGE" | rev | cut -d'/' -f1 | rev | cut -d':' -f1)
  IMAGE_TAG=$(echo "$IMAGE" | rev | cut -d':' -f1 | rev)

  if [ "$DRY_RUN" = true ]; then
    echo "[DRY RUN] Would migrate: $IMAGE -> $AR_REGISTRY/$IMAGE_NAME:$IMAGE_TAG"
  else
    echo "Creating Artifact Registry repository: $IMAGE_NAME"
    gcloud artifacts repositories create "$IMAGE_NAME" \
      --repository-format=docker \
      --location="$GCP_REGION" 2>/dev/null || true

    echo "Pulling from ECR: $IMAGE"
    aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin "$(echo $IMAGE | cut -d'/' -f1)"
    docker pull "$IMAGE"

    echo "Tagging for Artifact Registry: $AR_REGISTRY/$IMAGE_NAME:$IMAGE_TAG"
    docker tag "$IMAGE" "$AR_REGISTRY/$IMAGE_NAME:$IMAGE_TAG"

    echo "Pushing to Artifact Registry..."
    gcloud auth configure-docker "${GCP_REGION}-docker.pkg.dev" --quiet
    docker push "$AR_REGISTRY/$IMAGE_NAME:$IMAGE_TAG"
  fi
done

# Verification
echo "=== Verification ==="
echo "Listing Artifact Registry repositories..."
gcloud artifacts repositories list --location="$GCP_REGION" --format="table(name)"
```

### 04-migrate-secrets.sh -- IF has_secrets

**Skip this script entirely if `has_secrets` is false.**

Migrate secrets from AWS Secrets Manager to GCP Secret Manager:

```bash
#!/usr/bin/env bash
set -euo pipefail

# Secrets migration: AWS Secrets Manager -> GCP Secret Manager
# Usage: ./04-migrate-secrets.sh [--execute]

DRY_RUN=true
[[ "${1:-}" == "--execute" ]] && DRY_RUN=false

# TODO: List secrets to migrate
SECRETS=(
  "database-password"
  "api-key"
  # Add more secrets from your AWS account
)

for SECRET_NAME in "${SECRETS[@]}"; do
  if [ "$DRY_RUN" = true ]; then
    echo "[DRY RUN] Would migrate secret: $SECRET_NAME"
  else
    echo "Reading secret from AWS: $SECRET_NAME"
    SECRET_VALUE=$(aws secretsmanager get-secret-value --secret-id "$SECRET_NAME" --query SecretString --output text)

    echo "Creating secret in GCP: $SECRET_NAME"
    echo -n "$SECRET_VALUE" | gcloud secrets create "$SECRET_NAME" \
      --data-file=- \
      --labels=migration-source=aws-secrets-manager 2>/dev/null || \
    echo -n "$SECRET_VALUE" | gcloud secrets versions add "$SECRET_NAME" \
      --data-file=-
  fi
done

# Verification
echo "=== Verification ==="
gcloud secrets list --format="table(name)"
```

### 05-validate-migration.sh

Post-migration validation script. **Always generated**, but adapt checks based on which resource
categories were detected in Step 1. Only include validation sections for resources that exist.

```bash
#!/usr/bin/env bash
set -euo pipefail

# Post-migration validation
# Usage: ./05-validate-migration.sh

echo "=== Migration Validation ==="

# Check Terraform state (always included)
echo "--- Terraform Resources ---"
cd terraform/
terraform state list | wc -l
echo "resources in Terraform state"

# --- Include ONLY if has_containers ---
# Check Cloud Run services
echo "--- Cloud Run Services ---"
gcloud run services list 2>/dev/null || echo "No Cloud Run services found"  # default columns (NAME/REGION/URL/...) — 'status' is a nested object, not a printable column

# --- Include ONLY if has_databases ---
# Check Cloud SQL instances
echo "--- Cloud SQL Instances ---"
gcloud sql instances list 2>/dev/null || echo "No Cloud SQL instances found"  # default columns include NAME/DATABASE_VERSION/PRIMARY_ADDRESS/STATUS — 'primaryAddress' is not a raw field (it's a computed projection over ipAddresses)

# --- Include ONLY if has_storage ---
# Check Cloud Storage buckets
echo "--- Cloud Storage Buckets ---"
gcloud storage ls | grep "${PROJECT_NAME:-aws-migration}" || echo "No matching Cloud Storage buckets found"

# --- Include ONLY if has_secrets ---
# Check secrets
echo "--- Secret Manager ---"
gcloud secrets list --format="table(name)" 2>/dev/null || echo "No secrets found"

echo "=== Validation Complete ==="
echo "Review the output above. All resources should show healthy status."
echo "TODO: Run application-level health checks"
echo "TODO: Compare performance metrics against AWS baseline"
```

## Step 3: Self-Check

After generating all scripts, verify the following quality rules:

### Script Quality Rules

1. All scripts use `set -euo pipefail`
2. All scripts default to dry-run mode
3. All scripts include verification steps
4. All scripts are numbered for execution order
5. All TODO markers are clearly marked with context

## Phase Completion

Report the list of generated script files to the parent orchestrator. **Do NOT update `.phase-status.json`** -- the parent `generate.md` handles phase completion.

Only list scripts that were actually generated (based on Step 1 resource detection flags):

```
Resource categories detected: [list active flags from Step 1]

Generated migration scripts:
- scripts/01-validate-prerequisites.sh
- scripts/02-migrate-data.sh                    # only if has_data_migration
- scripts/03-migrate-containers.sh              # only if has_containers
- scripts/04-migrate-secrets.sh                 # only if has_secrets
- scripts/05-validate-migration.sh

Total: [N] migration scripts
TODO markers: [N] items requiring manual configuration
Skipped scripts: [list any scripts not generated, with reason]
```
