# Storage Services Design Rubric

**Applies to:** S3, EFS, EBS

**Quick lookup (no rubric):** Check `fast-path.md` first (S3 -> GCS, deterministic)

## Companion skill (google/skills)

There is currently **no** dedicated google/skill for GCS, Filestore, or Persistent Disk. Use this file directly for storage-specific configuration. If networking guidance is needed (e.g. VPC placement for Filestore, private access for GCS), consult **`google-cloud-networking-observability`** as a secondary reference per `references/shared/companion-skills.md`.

When this skill is later expanded to cover S3 -> GCS plus auth (signed URLs, Workload Identity for cross-tenant reads), consult **`google-cloud-recipe-auth`** if installed.

## Deterministic Mapping

**S3 (`aws_s3_bucket`) -> GCS (`google_storage_bucket`)**

Confidence: `deterministic` (always 1:1, no decision tree)

**Behavior preservation:**

- Bucket versioning -> GCS versioning
- Lifecycle rules -> GCS Lifecycle policies
- Access control (ACLs + Bucket Policies) -> GCS IAM + uniform bucket-level access (recommended)
- Regional location -> GCS region selection
- Encryption (SSE-S3 / SSE-KMS) -> GCS encryption (Google-managed or CMEK via Cloud KMS)

## S3 -> GCS Attribute Mapping

| S3 Attribute                 | GCS Equivalent                        | Notes                                          |
| ---------------------------- | ------------------------------------- | ---------------------------------------------- |
| `region`                     | `location` (region)                   | Direct mapping; respect user's region choice   |
| `versioning_enabled`         | `versioning_enabled`                  | 1:1 copy                                       |
| `lifecycle_rule`             | `lifecycle_rule`                      | Adapt rule conditions (syntax differs slightly) |
| `block_public_acl` + policies| `uniform_bucket_level_access`         | Convert S3 ACL block to GCS uniform access     |
| `sse_algorithm = "aws:kms"`  | `encryption` (CMEK via Cloud KMS)     | Use Cloud KMS (customer-managed key)           |
| `cors_rule`                  | `cors`                                | 1:1 copy                                       |
| `object_lock_configuration`  | `retention_policy` + bucket lock      | GCS retention is simpler than S3 Object Lock   |

## S3 Storage Class Mapping

| S3 Storage Class              | GCS Storage Class   | Notes                                          |
| ----------------------------- | ------------------- | ---------------------------------------------- |
| Standard                      | Standard            | Default; hot data                              |
| Intelligent-Tiering           | Autoclass           | GCS Autoclass auto-transitions between classes |
| Standard-IA                   | Nearline            | 30-day minimum; infrequent access              |
| One Zone-IA                   | Nearline            | GCS Nearline is multi-zone by default          |
| Glacier Instant Retrieval     | Nearline            | Instant retrieval, similar pricing tier         |
| Glacier Flexible Retrieval    | Coldline            | 90-day minimum; rare access                    |
| Glacier Deep Archive          | Archive             | 365-day minimum; archival                      |

## Output Schema

```json
{
  "aws_type": "aws_s3_bucket",
  "aws_address": "my-app-assets",
  "aws_config": {
    "region": "us-east-1",
    "versioning_enabled": true,
    "lifecycle_rule": [
      {
        "id": "delete-old-versions",
        "status": "Enabled",
        "noncurrent_version_expiration": { "days": 90 }
      }
    ]
  },
  "gcp_service": "GCS",
  "gcp_config": {
    "name": "my-app-assets-us-central1",
    "location": "us-central1",
    "versioning_enabled": true,
    "lifecycle_rule": [
      {
        "action": { "type": "Delete" },
        "condition": { "age": 90, "with_state": "ARCHIVED" }
      }
    ]
  },
  "confidence": "deterministic",
  "rationale": "S3 -> GCS is 1:1 deterministic; preserve versioning, lifecycle, encryption"
}
```

## EFS -> Filestore

**EFS (`aws_efs_file_system`) -> Filestore (`google_filestore_instance`)**

Confidence: `inferred` (both are managed NFS, but capacity model differs)

**Key difference:** EFS scales automatically with no pre-provisioned capacity. Filestore requires a minimum provisioned capacity (1 TiB for Basic HDD, 2.5 TiB for Basic SSD). Right-size based on current EFS usage.

**Attribute mapping:**

| EFS Attribute                           | Filestore Equivalent              | Notes                                              |
| --------------------------------------- | --------------------------------- | -------------------------------------------------- |
| `throughput_mode = "bursting"`          | `tier` = BASIC_HDD               | General purpose, burstable throughput               |
| `throughput_mode = "provisioned"`       | `tier` = BASIC_SSD               | High-performance, provisioned throughput            |
| `throughput_mode = "elastic"`           | `tier` = ENTERPRISE              | Enterprise tier with auto-scaling performance       |
| No pre-provisioned size                 | `capacity_gb` (minimum required)  | Filestore requires explicit capacity provisioning   |
| `mount_target` subnet                  | `networks` (VPC + subnet)        | Place Filestore in same VPC                         |
| `encrypted = true`                     | Encryption at rest (default)      | Filestore encrypts by default                       |

**Output Schema:**

```json
{
  "aws_type": "aws_efs_file_system",
  "aws_address": "shared-data",
  "aws_config": {
    "throughput_mode": "bursting",
    "performance_mode": "generalPurpose",
    "encrypted": true
  },
  "gcp_service": "Filestore",
  "gcp_config": {
    "tier": "BASIC_HDD",
    "capacity_gb": 1024,
    "network": "default",
    "region": "us-central1"
  },
  "confidence": "inferred",
  "rationale": "EFS -> Filestore; both managed NFS. Capacity must be pre-provisioned on Filestore."
}
```

## EBS -> Persistent Disk

**EBS (`aws_ebs_volume`) -> Persistent Disk (`google_compute_disk`)**

Confidence: `inferred` (both are block storage attached to VMs, but type mapping requires rubric)

**Attribute mapping:**

| EBS Volume Type | Persistent Disk Type       | Notes                                              |
| --------------- | -------------------------- | -------------------------------------------------- |
| gp2 / gp3       | pd-balanced                | General purpose SSD; pd-balanced is closest match  |
| io1 / io2        | pd-ssd                    | Provisioned IOPS SSD; pd-ssd for high performance  |
| st1              | pd-standard               | Throughput-optimized HDD                           |
| sc1              | pd-standard               | Cold HDD -> standard persistent disk               |

**Output Schema:**

```json
{
  "aws_type": "aws_ebs_volume",
  "aws_address": "data-volume",
  "aws_config": {
    "type": "gp3",
    "size": 500,
    "iops": 3000,
    "availability_zone": "us-east-1a"
  },
  "gcp_service": "Persistent Disk",
  "gcp_config": {
    "type": "pd-balanced",
    "size": 500,
    "zone": "us-central1-a"
  },
  "confidence": "inferred",
  "rationale": "EBS gp3 -> Persistent Disk pd-balanced; general purpose SSD block storage"
}
```

## Notes

S3 has no GCP equivalent variations. All mappings are direct.

For non-storage use cases (static site hosting, data lakes, etc.), the hosting compute service (Cloud Run, Cloud CDN) determines architecture, not the bucket itself.
