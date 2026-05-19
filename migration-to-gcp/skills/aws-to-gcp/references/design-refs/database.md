# Database Services Design Rubric

**Applies to:** RDS, Aurora, DynamoDB, Redshift, ElastiCache (Redis)

**Quick lookup (no rubric):** Check `fast-path.md` first (RDS PostgreSQL -> Cloud SQL PostgreSQL, RDS MySQL -> Cloud SQL MySQL, ElastiCache Redis -> Memorystore, etc.)

## Companion skill (google/skills)

Before applying this rubric or shaping the GCP-side configuration:

- **Cloud SQL targets** (RDS MySQL / PostgreSQL / SQL Server, Aurora MySQL): read the latest version of **`cloud-sql-basics`** at `~/.claude/skills/cloud-sql-basics/SKILL.md` (fallback `~/.agents/skills/cloud-sql-basics/SKILL.md`). Use its canonical templates for instance tier selection, HA (regional / `REGIONAL`), private IP + authorized networks, backups and point-in-time recovery, IAM database authentication, and Cloud SQL Auth Proxy guidance.
- **AlloyDB targets** (Aurora PostgreSQL): read the latest version of **`alloydb-basics`** at the same paths. Use its sizing, primary + read pool, columnar engine, and IAM recipes.
- **Firestore targets** (DynamoDB when key-value / document): consult **`firebase-basics`** if installed (Firestore is part of the Firebase suite). For Bigtable / Memorystore / Spanner targets there is no dedicated google/skill -- use this file directly.
- **Redshift / `aws_redshift_*`:** the **Redshift specialist gate** (see `design-infra.md`) always applies regardless of whether `bigquery-basics` is installed. Do **not** auto-map Redshift to BigQuery even if `bigquery-basics` is present; the gate output remains `Deferred -- specialist engagement`. Specialists may consult `bigquery-basics` during their own engagement.

This rubric is the AWS -> GCP **decision** layer. The google/skill is the **how** layer for the chosen GCP target. If a companion skill is not installed, fall back to this file and add a `warnings[]` entry per the protocol in `references/shared/companion-skills.md`.

## Eliminators (Hard Blockers)

| AWS Service              | GCP              | Blocker                                                                                                       |
| ------------------------ | ---------------- | ------------------------------------------------------------------------------------------------------------- |
| DynamoDB                 | Firestore        | Item size >1 MiB required -> use Bigtable (Firestore max document size is 1 MiB)                             |
| Redshift                 | _(no auto-target)_ | **Plugin does not prescribe BigQuery/Dataproc/Dataflow** -- use `Deferred -- specialist engagement` in design output; OLTP latency needs -> Cloud SQL or Firestore per workload review with specialists |
| RDS (PostgreSQL)         | Cloud SQL        | PostGIS extension -> supported (Cloud SQL supports PostGIS)                                                   |
| Aurora (PostgreSQL)      | AlloyDB          | Custom Aurora extensions -> verify AlloyDB compatibility; fallback to Cloud SQL if unsupported                 |

## Signals (Decision Criteria)

### RDS (PostgreSQL, MySQL, SQL Server)

- **PostgreSQL, MySQL, SQL Server** -> Direct Cloud SQL mapping (fast-path)
- **High availability required** -> Cloud SQL HA (regional instance with automatic failover)
- **Dev/test sizing** -> Cloud SQL with shared-core machine type (~$7-15/mo for db-f1-micro)
- **Production, always-on** -> Cloud SQL with dedicated machine type (or Enterprise Plus for highest performance)

### Aurora (PostgreSQL/MySQL)

- **Aurora PostgreSQL** -> AlloyDB (PostgreSQL-compatible, columnar engine for analytics)
- **Aurora MySQL** -> Cloud SQL MySQL with HA (closest managed equivalent)
- **Aurora Serverless v2** -> Cloud SQL with auto-storage-increase (GCP does not have per-ACU serverless; use AlloyDB for PostgreSQL workloads needing scale-out)
- **Aurora Global Database** -> AlloyDB Cross-Region Replication or Cloud SQL cross-region read replicas

### DynamoDB

- **Key-value + document model** -> Firestore (Native mode)
- **High-throughput, wide-column, >10K writes/sec** -> Bigtable (purpose-built for massive scale)
- **Strong consistency required** -> Firestore supports strongly consistent reads by default
- **DynamoDB Streams** -> Firestore real-time listeners (or Bigtable change streams)
- **DynamoDB Global Tables** -> Firestore multi-region (or Bigtable replicated clusters)

### Redshift

**Do not use this rubric to pick a GCP product.** For any `aws_redshift_*` resource, follow **`design-infra.md` -> Redshift specialist gate** only: set `gcp_service` to **`Deferred -- specialist engagement`**, `human_expertise_required: true`, and direct the customer to **their GCP account team and/or a data analytics migration partner**. Do **not** output BigQuery, Dataproc, Dataflow, or similar as the automated mapping in `gcp-design.json`.

The sections below are **background for humans** after engagement -- not for the agent to select automatically:

- Warehousing, SQL analytics, BI, and ML-on-data choices require assessment (e.g. query patterns, data volume, SLAs, cost model).
- **Redshift ML** uses the **same specialist gate** -- no automated Vertex AI/BigQuery ML target from this plugin.

### ElastiCache (Redis)

- **In-memory cache** -> Memorystore Redis (fast-path, 1:1 mapping)
- **Cluster mode enabled** -> Memorystore Redis with cluster mode
- **High availability required** -> Memorystore Redis Standard Tier (automatic failover, cross-zone replication)

## 6-Criteria Rubric

Apply in order:

1. **Eliminators**: Does AWS config require GCP-unsupported features? If yes: switch
2. **Operational Model**: Managed (Cloud SQL, Firestore, AlloyDB) vs Self-hosted (Compute Engine-based)?
   - Prefer managed unless: Production + cost-optimized + predictable load -> consider dedicated machine types
3. **User Preference**: From `preferences.json`: `design_constraints.database_tier`, `design_constraints.db_io_workload`?
   - If `database_tier = "standard"` -> Standard Cloud SQL HA
   - If `database_tier = "enterprise"` -> AlloyDB or Cloud SQL Enterprise Plus
   - If `db_io_workload = "high"` -> AlloyDB (columnar engine for mixed OLTP/OLAP)
4. **Feature Parity**: Does AWS config need features unavailable in GCP?
   - Example: Aurora parallel query -> AlloyDB columnar engine (comparable analytics acceleration)
   - Example: DynamoDB DAX (caching layer) -> Firestore + Memorystore (app-level caching)
5. **Cluster Context**: Are other resources in cluster using Cloud SQL? Prefer same family
6. **Simplicity**: Fewer moving parts = higher score
   - Managed > Self-hosted > Custom

## Examples

### Example 1: RDS PostgreSQL (dev environment)

- AWS: `aws_db_instance` (engine=postgres, engine_version=13.12, instance_class=db.t3.micro)
- Signals: PostgreSQL, dev tier (implied from sizing)
- Criterion 1 (Eliminators): PASS
- Criterion 2 (Operational Model): Cloud SQL with shared-core (dev best practice)
- -> **GCP: Cloud SQL PostgreSQL (db-f1-micro, dev tier)**
- Confidence: `deterministic`

### Example 2: Aurora PostgreSQL (production)

- AWS: `aws_rds_cluster` (engine=aurora-postgresql, engine_version=15.4, instance_class=db.r6g.xlarge)
- Signals: Aurora PostgreSQL, production tier, HA
- Criterion 1 (Eliminators): PASS
- Criterion 2 (Operational Model): AlloyDB (managed, PostgreSQL-compatible, columnar engine)
- Criterion 3 (User Preference): database_tier=enterprise
- -> **GCP: AlloyDB (2 vCPUs, 16 GB RAM, HA with read pool)**
- Confidence: `inferred`

### Example 3: DynamoDB (mobile app)

- AWS: `aws_dynamodb_table` (billing_mode=PAY_PER_REQUEST, hash_key="userId")
- Signals: NoSQL, key-value, on-demand billing
- Criterion 1 (Eliminators): PASS (Firestore supports flexible schema)
- Criterion 2 (Operational Model): Firestore (managed NoSQL)
- Criterion 3 (User Preference): NoSQL type detected from AWS resource -> Firestore confirmed
- -> **GCP: Firestore (Native mode, pay-as-you-go)**
- Confidence: `inferred`

### Example 4: DynamoDB (high-throughput IoT)

- AWS: `aws_dynamodb_table` (billing_mode=PROVISIONED, read_capacity=50000, write_capacity=50000)
- Signals: Extremely high throughput, wide-column access pattern
- Criterion 1 (Eliminators): Scale signal -> evaluate Bigtable vs Firestore
- Criterion 2 (Operational Model): Bigtable (purpose-built for massive throughput)
- -> **GCP: Bigtable (3-node cluster, SSD storage)**
- Confidence: `inferred`

### Example 5: Redshift (analytics)

- AWS: `aws_redshift_cluster` (node_type=dc2.large, number_of_nodes=4)
- **Agent output:** `gcp_service`: **`Deferred -- specialist engagement`**, `human_expertise_required`: **`true`**, `confidence`: **`inferred`**, `rubric_applied`: `["Redshift specialist gate -- no automated GCP service target"]`
- **User-facing:** Engage **GCP account team** and/or **data analytics migration partner** before choosing GCP analytics architecture. **Do not** state BigQuery vs Dataproc vs Dataflow as the plugin's recommendation.

## Engine Preservation (MANDATORY for `gcp_config.database_version`)

When mapping any AWS RDS/Aurora resource to Cloud SQL or AlloyDB, you **MUST** populate `gcp_config.database_version` from the source engine. **Never** emit `database_version: null` — that breaks the Generate phase Terraform output.

Apply this mapping deterministically before writing the resource to `gcp-design.json`:

| AWS source attribute                                                  | `gcp_config.database_version` (Cloud SQL)         | If AlloyDB target                                    |
| --------------------------------------------------------------------- | ------------------------------------------------- | ---------------------------------------------------- |
| `aws_rds_cluster.engine == "aurora-mysql"` (or `aurora`)              | `MYSQL_8_0` (fallback `MYSQL_5_7` if engine_version starts with `5.7`) | n/a — AlloyDB is PostgreSQL-only; use Cloud SQL MySQL |
| `aws_rds_cluster.engine == "aurora-postgresql"`                       | `POSTGRES_15` (fallback to nearest major from `engine_version`) | `POSTGRES_15` |
| `aws_db_instance.engine == "mysql"`                                   | `MYSQL_8_0` (or `MYSQL_5_7` if `engine_version` starts with `5.7`) | n/a |
| `aws_db_instance.engine == "postgres"`                                | `POSTGRES_15` (or nearest major matching `engine_version`, e.g. `13.x` -> `POSTGRES_13`) | `POSTGRES_15` |
| `aws_db_instance.engine == "mariadb"`                                 | `MYSQL_8_0` (Cloud SQL has no MariaDB; document substitution in `rationale`) | n/a |
| `aws_db_instance.engine == "sqlserver-*"`                             | `SQLSERVER_2019_STANDARD` (or `_ENTERPRISE` per source edition) | n/a |
| `aws_db_instance.engine == "oracle-*"`                                | Set `gcp_service` to `Deferred -- specialist engagement`; Cloud SQL has no Oracle target | n/a |
| Engine field missing / cluster member (`aws_db_instance` inside Aurora cluster) | Inherit from parent `aws_rds_cluster.engine` via cluster context | Inherit from parent |

**Rules:**

1. If `gcp_config.database_version` cannot be confidently derived, set it to `"MYSQL_8_0"` for MySQL-family or `"POSTGRES_15"` for PostgreSQL-family and add a `warnings[]` entry: `"database_version inferred for <aws_address>; verify engine version before apply"`.
2. **Never** leave `database_version` as `null` or absent. The output validation checklist in `design-infra.md` should reject this.
3. When the source is `aws_rds_cluster` with `engine_version` like `8.0.mysql_aurora.3.04.0`, parse the major.minor (`8.0`) and map to the closest Cloud SQL version (`MYSQL_8_0`).
4. Engine inheritance: members of an Aurora cluster (`aws_db_instance` rows referencing a parent `aws_rds_cluster`) inherit the cluster's `engine`. Resolve this during Pass 2 cluster context evaluation.

## Output Schema

```json
{
  "aws_type": "aws_db_instance",
  "aws_address": "prod-postgres-db",
  "aws_config": {
    "engine": "postgres",
    "engine_version": "13.12",
    "instance_class": "db.r6g.xlarge",
    "multi_az": true
  },
  "gcp_service": "Cloud SQL PostgreSQL",
  "gcp_config": {
    "database_version": "POSTGRES_13",
    "tier": "db-custom-4-15360",
    "availability_type": "REGIONAL",
    "region": "us-central1"
  },
  "confidence": "deterministic",
  "human_expertise_required": false,
  "rationale": "1:1 mapping; RDS PostgreSQL -> Cloud SQL PostgreSQL",
  "rubric_applied": [
    "Eliminators: PASS",
    "Operational Model: Managed Cloud SQL",
    "User Preference: database_tier=standard, db_io_workload=medium",
    "Feature Parity: Full (extensions, replication)",
    "Cluster Context: Consistent with app tier",
    "Simplicity: Cloud SQL (managed, HA)"
  ]
}
```
