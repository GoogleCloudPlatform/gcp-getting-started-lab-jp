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

| AWS Service         | GCP                | Blocker                                                                                                                                                                                                 |
| ------------------- | ------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| DynamoDB            | Firestore          | Item size >1 MiB required -> use Bigtable (Firestore max document size is 1 MiB)                                                                                                                        |
| Redshift            | _(no auto-target)_ | **Plugin does not prescribe BigQuery/Dataproc/Dataflow** -- use `Deferred -- specialist engagement` in design output; OLTP latency needs -> Cloud SQL or Firestore per workload review with specialists |
| RDS (PostgreSQL)    | Cloud SQL          | PostGIS extension -> supported (Cloud SQL supports PostGIS)                                                                                                                                             |
| Aurora (PostgreSQL) | AlloyDB            | Custom Aurora extensions -> verify AlloyDB compatibility; fallback to Cloud SQL if unsupported                                                                                                          |

## Signals (Decision Criteria)

### RDS (PostgreSQL, MySQL, SQL Server)

- **PostgreSQL, MySQL, SQL Server** -> Direct Cloud SQL mapping (fast-path)
- **High availability required** -> Cloud SQL HA (regional instance with automatic failover)
- **Dev/test sizing** -> Cloud SQL with shared-core machine type (db-f1-micro; price via live lookup at estimate time — never quote a remembered monthly figure)
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
- **Redshift ML** uses the **same specialist gate** -- no automated Agent Platform (formerly Vertex AI) / BigQuery ML target from this plugin.

### ElastiCache (Redis)

- **In-memory cache** -> Memorystore Redis (fast-path, 1:1 mapping)
- **Cluster mode enabled** -> Memorystore Redis with cluster mode
- **High availability required** -> Memorystore Redis Standard Tier (automatic failover, cross-zone replication)

## Sizing from access-pattern data (MANDATORY for Cloud SQL + Memorystore)

After the rubric selects the GCP target service, size it from `preferences.json.design_constraints.access_pattern_data` rather than dev-tier defaults or 1:1 source IaC mapping. Design Step 1.5 already loaded this into in-memory state.

**Lookup order** (same as compute.md):

1. `access_pattern_data[<aws_address>]` — per-resource data (path A/B from Q_SIZING2)
2. `access_pattern_data["cluster:<cluster_name>"]` — cluster-level data (path C)
3. Conservative defaults — dev-tier + emit `# TODO: tune based on actual traffic` comment (path D or fallback)

### Cloud SQL sizing formulas (path A/B/C data present)

| GCP field                   | Formula                                                                                                                                                                  | Source metric (RDS)                                                                        |
| --------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------ |
| `tier` (machine type)       | Choose smallest tier meeting BOTH peak_cpu and peak_memory targets. Map `peak_cpu_pct >= 70` AND `peak_memory_pct >= 70` to "needs upgrade". See breakpoint table below. | `CPUUtilization.max`, `FreeableMemory.min` (compare to instance memory)                    |
| `disk_size_gb`              | `ceil(current_storage_used * 1.5)` (50% headroom)                                                                                                                        | RDS allocated storage from inventory; current usage from CloudWatch `FreeStorageSpace.min` |
| `max_connections` (DB flag) | `ceil(peak_connections * 1.5)`                                                                                                                                           | `DatabaseConnections.max`                                                                  |
| `availability_type`         | `"REGIONAL"` (HA) if `peak_connections > 50` OR `peak_qps > 100` OR existing AWS instance is multi-AZ; else `"ZONAL"`                                                    | `DatabaseConnections.max`, computed peak_qps from `ReadIOPS.max + WriteIOPS.max`           |

**Cloud SQL tier breakpoints by peak load:**

| Peak load profile                        | Recommended tier (MySQL/PostgreSQL)                                             |
| ---------------------------------------- | ------------------------------------------------------------------------------- |
| `peak_cpu_pct < 30 AND peak_qps < 50`    | `db-f1-micro` (1 shared vCPU, 0.6 GB) — dev/test only                           |
| `peak_cpu_pct < 50 AND peak_qps < 500`   | `db-custom-2-7680` (2 vCPU, 7.5 GB)                                             |
| `peak_cpu_pct < 70 AND peak_qps < 2000`  | `db-custom-4-15360` (4 vCPU, 15 GB)                                             |
| `peak_cpu_pct < 80 AND peak_qps < 5000`  | `db-custom-8-30720` (8 vCPU, 30 GB)                                             |
| `peak_qps >= 5000 OR peak_cpu_pct >= 80` | `db-custom-16-61440` (16 vCPU, 60 GB) or larger; consider AlloyDB if PostgreSQL |

### Memorystore Redis sizing formulas (path A/B/C data present)

| GCP field                      | Formula                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 | Source metric (ElastiCache)                                                                                  |
| ------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------ |
| `memory_size_gb`               | `max(1, ceil(BytesUsedForCache.max * 1.5 / 1e9))` (1 GB minimum, 50% headroom)                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          | `BytesUsedForCache.max` (bytes) from `AWS/ElastiCache`                                                       |
| `tier`                         | `"STANDARD_HA"` if peak items > 100K OR cluster-mode-enabled in source OR `peak_cpu_pct > 50`; else `"BASIC"`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           | `CurrItems.max`, `CPUUtilization.max`, source `aws_elasticache_replication_group.automatic_failover_enabled` |
| `redis_version`                | Match source ElastiCache version (`engine_version`). **This row is the ONLY place the Redis version enum is derived — `design-infra.md` examples and Generate's Step 2.6 gate must consume the value recorded in `gcp_config.redis_version`, never re-derive it.** Valid `redisVersion` enum values per the live Memorystore API include `REDIS_6_X`, `REDIS_7_0`, `REDIS_7_2` (plus legacy `REDIS_3_2`/`REDIS_4_0`/`REDIS_5_0`); verify the current list at cloud.google.com/memorystore/docs/redis/supported-versions if the source is outside these. **There is no `REDIS_7_X` — NOT a valid value, even though `REDIS_6_X` exists as a wildcard.** Derivation: source 6.x → `REDIS_6_X`; source 7.0–7.1 → `REDIS_7_0`; source 7.2+ → `REDIS_7_2`. For NEW Redis-compatible workloads (or ElastiCache **Memcached** sources — Memorystore for Memcached is deprecated), prefer **Memorystore for Valkey** (versions 7.2/8.0/9.0) and record the client-protocol note in `rationale`. | source `engine_version`                                                                                      |
| `replica_count` (cluster mode) | `max(1, ceil(peak_qps / 100000))` if `tier == "STANDARD_HA"`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            | computed `peak_qps` from `CmdGet.sum + CmdSet.sum` per second                                                |

### When path D (conservative defaults) is chosen OR a metric is missing

- **Cloud SQL**: `tier = "db-custom-2-7680"` (NOT db-f1-micro — that's actually too small for any production workload; "conservative" here means "small but sane"), `disk_size_gb = ceil(source_allocated_storage * 2)`, `availability_type = "REGIONAL"` (HA by default — safer for production), `max_connections` left at Cloud SQL default.
- **Memorystore**: `memory_size_gb = 1`, `tier = "STANDARD_HA"` (HA by default), `redis_version` matched to source.
- Emit comment inline in generated Terraform: `# TODO: tune <field> based on actual traffic — sizing chosen from conservative defaults (Clarify Q_SIZING1 = D) OR no <metric_name> in CloudWatch data`.

**Record `sizing_source` per resource** in `gcp-design.json` per the Step 1.5 audit-trail rule.

## 6-Criteria Rubric

Apply in order:

1. **Eliminators**: Does AWS config require GCP-unsupported features? If yes: switch
2. **Operational Model**: Managed (Cloud SQL, Firestore, AlloyDB) vs Self-hosted (Compute Engine-based)?
   - Prefer managed unless: Production + cost-optimized + predictable load -> consider dedicated machine types
3. **User Preference**: From `preferences.json`: `design_constraints.database_preference` (the key Clarify Q12 actually writes — values `cloud-sql`, `alloydb`, `spanner`) and `design_constraints.nosql_preference` (Q13 — `firestore`, `bigtable`):
   - If `database_preference = "cloud-sql"` (default) -> Cloud SQL with regional HA
   - If `database_preference = "alloydb"` -> AlloyDB (PostgreSQL-compatible sources only; MySQL-family sources still go to Cloud SQL MySQL with a `warnings[]` note)
   - If `database_preference = "spanner"` -> Cloud Spanner with schema-adaptation flag + architecture review
   - High mixed OLTP/OLAP read load evidenced in `access_pattern_data` -> mention AlloyDB's columnar engine in the trade-off card
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
- Criterion 3 (User Preference): database_preference=alloydb
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

**This table is the ONLY derivation site for `database_version` in the entire skill.** Design records the result in `gcp-design.json.gcp_config.database_version` plus an audit block `gcp_config.engine_fidelity = {"source_engine": "<engine>", "source_engine_version": "<version>", "derived_from": "database.md Engine Preservation"}`. `design-infra.md`'s examples and Generate's Step 2.6 gate CONSUME that recorded value — they must never re-derive it (re-derivation in multiple files is how the Aurora-MySQL→POSTGRES and REDIS_7_X bugs kept recurring).

**Version-currency rule:** Cloud SQL's supported majors move (as of mid-2026: MySQL 8.0/**8.4** with 8.4 the default; PostgreSQL 13–**18**; SQL Server 2019/**2022**/**2025**). Before pinning, verify the current enum list live at `https://docs.cloud.google.com/sql/docs/db-versions` (or `gcloud sql flags list`/API docs). Match the SOURCE major exactly when Cloud SQL supports it — never silently downgrade (an Aurora MySQL 8.4 source maps to `MYSQL_8_4`, not `MYSQL_8_0`).

Apply this mapping deterministically before writing the resource to `gcp-design.json`:

| AWS source attribute                                                            | `gcp_config.database_version` (Cloud SQL)                                                                                                                                                                                                                                                                                          | If AlloyDB target                                     |
| ------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------- |
| `aws_rds_cluster.engine == "aurora-mysql"` (or `aurora`)                        | `MYSQL_<major>_<minor>` matching the parsed source major.minor (e.g. 8.4 → `MYSQL_8_4`, 8.0 → `MYSQL_8_0`, 5.7 → `MYSQL_5_7`)                                                                                                                                                                                                      | n/a — AlloyDB is PostgreSQL-only; use Cloud SQL MySQL |
| `aws_rds_cluster.engine == "aurora-postgresql"`                                 | `POSTGRES_<major>` matching the source major (13–18 supported; verify live)                                                                                                                                                                                                                                                        | `POSTGRES_<major>`                                    |
| `aws_db_instance.engine == "mysql"`                                             | `MYSQL_<major>_<minor>` matching source (same rule as aurora-mysql)                                                                                                                                                                                                                                                                | n/a                                                   |
| `aws_db_instance.engine == "postgres"`                                          | `POSTGRES_<major>` matching source major (e.g. `13.x` -> `POSTGRES_13`)                                                                                                                                                                                                                                                            | `POSTGRES_<major>`                                    |
| `aws_db_instance.engine == "mariadb"`                                           | Nearest `MYSQL_*` major (Cloud SQL has no MariaDB; document substitution in `rationale`; note DMS does not support MariaDB sources — dump/import path)                                                                                                                                                                             | n/a                                                   |
| `aws_db_instance.engine == "sqlserver-*"`                                       | `SQLSERVER_<year>_<EDITION>` matching the SOURCE year + edition (2019/2022/2025 exist as of mid-2026 — verify live; do not downgrade a 2022 source to 2019)                                                                                                                                                                        | n/a                                                   |
| `aws_db_instance.engine == "oracle-*"`                                          | Present a trade-off card: **Oracle Database@Google Cloud** (Exadata / Autonomous Database in Google Cloud data centers — keeps Oracle, no schema conversion) vs **Cloud SQL for PostgreSQL** (with schema conversion). Set `human_expertise_required: true` either way; no `google_sql_database_instance` for the Oracle-keep path | n/a                                                   |
| Engine field missing / cluster member (`aws_db_instance` inside Aurora cluster) | Inherit from parent `aws_rds_cluster.engine` via cluster context                                                                                                                                                                                                                                                                   | Inherit from parent                                   |

**Rules:**

1. If `gcp_config.database_version` cannot be confidently derived, pick the CURRENT default major for the engine family from the live supported-versions list and add a `warnings[]` entry: `"database_version inferred for <aws_address>; verify engine version before apply"`. Do not hard-code a fallback from memory.
2. **Never** leave `database_version` as `null` or absent. The output validation checklist in `design-infra.md` should reject this.
3. When the source is `aws_rds_cluster` with `engine_version` like `8.0.mysql_aurora.3.04.0`, parse the major.minor (`8.0`) and map to the matching Cloud SQL version (`MYSQL_8_0`).
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
    "User Preference: database_preference=cloud-sql",
    "Feature Parity: Full (extensions, replication)",
    "Cluster Context: Consistent with app tier",
    "Simplicity: Cloud SQL (managed, HA)"
  ]
}
```
