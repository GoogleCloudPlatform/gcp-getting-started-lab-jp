# Category D — Database Model (If Database Resources Present)

_Fire when:_ Database resources present (RDS, Aurora, DynamoDB, ElastiCache).

Relational database preference and NoSQL strategy determine the GCP target services — Cloud SQL, AlloyDB, Spanner, Firestore, or Bigtable.

---

## Database Engine Detection

Before asking questions, detect the database engine from IaC (`engine` in `aws_db_instance` or `aws_rds_cluster`). State what was found:

> "I see RDS for PostgreSQL (or MySQL, or Aurora) in your Terraform/CloudFormation."

Handle migration targets:

| Detected Engine          | Migration Target                                                  | Notes                                |
| ------------------------ | ----------------------------------------------------------------- | ------------------------------------ |
| Aurora PostgreSQL        | Cloud SQL for PostgreSQL or AlloyDB                               | AlloyDB for high-performance needs   |
| Aurora MySQL             | Cloud SQL for MySQL                                               | Direct migration path                |
| RDS for PostgreSQL       | Cloud SQL for PostgreSQL or AlloyDB                               | AlloyDB for high-performance needs   |
| RDS for MySQL            | Cloud SQL for MySQL                                               | Direct migration path                |
| RDS for SQL Server       | Cloud SQL for SQL Server                                          | Direct migration path                |
| RDS for Oracle           | **Cloud SQL for PostgreSQL** (with migration) or Bare Metal       | Requires schema conversion           |
| DynamoDB                 | Firestore (document model) or Bigtable (wide-column, high-throughput) | Migration path differs significantly |
| ElastiCache (Redis)      | Memorystore for Redis                                             | Direct migration path                |
| ElastiCache (Memcached)  | Memorystore for Memcached                                         | Direct migration path                |
| Amazon Keyspaces         | Cloud Bigtable                                                    | Wide-column store migration          |

If the engine requires schema conversion (e.g., Oracle), note the additional complexity and flag for specialist review. Ask the user to confirm if detection is ambiguous.

---

## Q12 — What is your preferred relational database service on GCP?

_Fire when:_ RDS or Aurora present in inventory. Skip when: no RDS/Aurora.

**Rationale:** GCP offers multiple relational database options with different performance characteristics and pricing models. Cloud SQL is the simplest path, AlloyDB offers PostgreSQL-compatible high performance, and Cloud Spanner provides global strong consistency at scale.

**Context for user:** When asking, give concrete descriptions so the user can match to their needs:

- **Cloud SQL** — Fully managed MySQL, PostgreSQL, or SQL Server; closest equivalent to RDS; simplest migration path
- **AlloyDB** — PostgreSQL-compatible, 4x faster for transactional workloads, 100x faster for analytical queries vs standard PostgreSQL; best for high-performance needs
- **Cloud Spanner** — Globally distributed, strongly consistent relational database; unlimited scale; best for global applications requiring strong consistency

> Understanding your relational database preference helps me recommend the right GCP target — Cloud SQL for simplicity, AlloyDB for high performance, or Cloud Spanner for global scale.
>
> A) Cloud SQL — fully managed, closest to RDS, simplest migration
> B) AlloyDB — PostgreSQL-compatible, high-performance (4x transactional, 100x analytical)
> C) Cloud Spanner — globally distributed, strongly consistent, unlimited scale
> D) N/A — We don't use relational databases
> E) I don't know

| Answer        | Recommendation Impact                                                                                            |
| ------------- | ---------------------------------------------------------------------------------------------------------------- |
| Cloud SQL     | Cloud SQL for PostgreSQL/MySQL; straightforward migration from RDS/Aurora; standard HA with regional config      |
| AlloyDB       | AlloyDB for PostgreSQL; higher performance; columnar engine for analytical queries; requires PostgreSQL source    |
| Cloud Spanner | **Cloud Spanner** for global active-active; schema adaptation required; architecture review flagged               |

Interpret:

```
A -> database_preference: "cloud-sql" — Cloud SQL; straightforward RDS/Aurora migration
B -> database_preference: "alloydb" — AlloyDB for PostgreSQL; high-performance; requires PostgreSQL compatibility
C -> database_preference: "spanner" — Cloud Spanner; global strong consistency; schema adaptation required
D -> (no constraint written)
E -> same as default (A) — assume Cloud SQL for simplest migration path
```

Default: A — `database_preference: "cloud-sql"`.

---

## Q13 — What is your preferred NoSQL service on GCP?

_Fire when:_ DynamoDB or other NoSQL services present in inventory. Skip when: no NoSQL services detected.

**Rationale:** DynamoDB workloads can map to either Firestore (document-oriented, serverless, real-time sync) or Bigtable (wide-column, high-throughput, analytics-ready). The choice depends on access patterns and scale requirements.

**Context for user:** When asking, give concrete descriptions so the user can match to their needs:

- **Firestore** — Serverless document database with real-time sync, offline support, and automatic scaling; best for web/mobile apps with document-oriented data
- **Bigtable** — High-throughput, low-latency NoSQL for large analytical and operational workloads; best for time-series, IoT, and heavy read/write patterns at scale

> Understanding your NoSQL needs helps me recommend the right GCP service — Firestore for document-oriented workloads or Bigtable for high-throughput wide-column needs.
>
> A) Firestore — serverless document DB, real-time sync, offline support
> B) Bigtable — high-throughput, low-latency, wide-column store
> C) N/A — We don't use NoSQL databases
> D) I don't know

| Answer    | Recommendation Impact                                                                     |
| --------- | ----------------------------------------------------------------------------------------- |
| Firestore | Firestore in Native mode; DynamoDB item-to-document mapping; real-time listeners available |
| Bigtable  | Cloud Bigtable; schema redesign for row key optimization; high-throughput at scale         |

Interpret:

```
A -> nosql_preference: "firestore" — Firestore Native mode; document-oriented; real-time sync
B -> nosql_preference: "bigtable" — Cloud Bigtable; wide-column; high-throughput at scale
C -> (no constraint written)
D -> same as default (A) — assume Firestore for document-oriented workloads
```

Default: A — `nosql_preference: "firestore"`.
