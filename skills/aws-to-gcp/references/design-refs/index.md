# AWS Service -> Design Reference Mapping

> **Column note:** **Typical GCP target** is the usual rubric outcome for that Terraform type. It is **not** the same as **`deterministic` confidence** in `gcp-design.json`. Only resource types listed in **`fast-path.md` -> Direct Mappings** get `deterministic`; everything else in this table is mapped via rubric -> `inferred` (unless `billing_inferred` on the billing-only path).

> **Companion skill column:** The **google/skill** column points to a skill in [`google/skills`](https://github.com/google/skills) that provides the canonical GCP-side guidance for the target. If that skill is installed (`~/.claude/skills/<name>/SKILL.md` or `~/.agents/skills/<name>/SKILL.md`), the agent should read and follow it as the source of truth for the GCP service-specific configuration. If not installed, fall back to this skill's own design-ref file and emit a warning. See `references/shared/companion-skills.md` for the full protocol and the authoritative mapping table.

## Compute Services

| AWS Service              | Resource Type                      | Reference File | Typical GCP target              | google/skill                |
| ------------------------ | ---------------------------------- | -------------- | ------------------------------- | --------------------------- |
| EC2                      | `aws_instance`                     | `compute.md`   | Compute Engine or Cloud Run     | `cloud-run-basics` (if re-platformed to Cloud Run); none for Compute Engine |
| Lambda                   | `aws_lambda_function`              | `compute.md`   | Cloud Run functions or Cloud Run | `cloud-run-basics`         |
| ECS (Fargate)            | `aws_ecs_service`                  | `compute.md`   | Cloud Run                       | `cloud-run-basics`          |
| ECS Task Definition      | `aws_ecs_task_definition`          | `compute.md`   | Cloud Run                       | `cloud-run-basics`          |
| EKS                      | `aws_eks_cluster`                  | `compute.md`   | GKE                             | `gke-basics`                |
| Auto Scaling Group       | `aws_autoscaling_group`            | `compute.md`   | Managed Instance Group          | _none_                      |

## Database Services

| AWS Service                | Resource Type               | Reference File | Typical GCP target                | google/skill            |
| -------------------------- | --------------------------- | -------------- | --------------------------------- | ----------------------- |
| RDS (PostgreSQL)           | `aws_db_instance`           | `database.md`  | Cloud SQL PostgreSQL              | `cloud-sql-basics`      |
| RDS (MySQL)                | `aws_db_instance`           | `database.md`  | Cloud SQL MySQL                   | `cloud-sql-basics`      |
| RDS (SQL Server)           | `aws_db_instance`           | `database.md`  | Cloud SQL SQL Server              | `cloud-sql-basics`      |
| Aurora (PostgreSQL)        | `aws_rds_cluster`           | `database.md`  | AlloyDB                           | `alloydb-basics`        |
| Aurora (MySQL)             | `aws_rds_cluster`           | `database.md`  | Cloud SQL MySQL (HA)              | `cloud-sql-basics`      |
| DynamoDB                   | `aws_dynamodb_table`        | `database.md`  | Firestore or Bigtable             | `firebase-basics` (Firestore only); none for Bigtable |
| Redshift                   | `aws_redshift_*`            | `database.md`  | **`Deferred -- specialist engagement`** only (see `design-infra.md` Redshift gate) | _specialist gate; `bigquery-basics` is background reading for the specialist conversation only_ |
| ElastiCache (Redis)        | `aws_elasticache_cluster`   | `database.md`  | Memorystore (Redis)               | _none_                  |
| ElastiCache (Replication)  | `aws_elasticache_replication_group` | `database.md` | Memorystore (Redis)          | _none_                  |

## Storage Services

| AWS Service     | Resource Type       | Reference File | Typical GCP target | google/skill |
| --------------- | ------------------- | -------------- | ------------------- | ------------ |
| S3              | `aws_s3_bucket`     | `storage.md`   | GCS                 | _none_       |
| EFS             | `aws_efs_file_system` | `storage.md` | Filestore           | _none_       |
| EBS             | `aws_ebs_volume`    | `storage.md`   | Persistent Disk     | _none_       |

## Networking Services

| AWS Service        | Resource Type               | Reference File  | Typical GCP target            | google/skill                              |
| ------------------ | --------------------------- | --------------- | ----------------------------- | ----------------------------------------- |
| VPC                | `aws_vpc`                   | `networking.md` | VPC Network (GLOBAL)          | `google-cloud-networking-observability`   |
| Security Group     | `aws_security_group`        | `networking.md` | Firewall Rules                | `google-cloud-networking-observability`   |
| ALB                | `aws_lb` (application)      | `networking.md` | Cloud Load Balancing (HTTP/S) | `google-cloud-networking-observability`   |
| NLB                | `aws_lb` (network)          | `networking.md` | Cloud Load Balancing (TCP/UDP)| `google-cloud-networking-observability`   |
| Route 53           | `aws_route53_zone`          | `networking.md` | Cloud DNS                     | `google-cloud-networking-observability`   |
| CloudFront         | `aws_cloudfront_distribution` | `networking.md` | Cloud CDN                   | `google-cloud-networking-observability`   |
| AWS WAF            | `aws_wafv2_web_acl`         | `networking.md` | Cloud Armor                   | `google-cloud-waf-security`               |
| Direct Connect     | `aws_dx_connection`          | `networking.md` | Cloud Interconnect            | `google-cloud-networking-observability`   |
| Subnet             | `aws_subnet`                | `networking.md` | Subnet (regional in GCP)      | `google-cloud-networking-observability`   |

## Messaging Services

| AWS Service  | Resource Type                | Reference File | Typical GCP target      | google/skill |
| ------------ | ---------------------------- | -------------- | ----------------------- | ------------ |
| SNS          | `aws_sns_topic`              | `messaging.md` | Pub/Sub                 | _none_       |
| SQS          | `aws_sqs_queue`              | `messaging.md` | Pub/Sub (pull) or Cloud Tasks | _none_ |
| EventBridge  | `aws_cloudwatch_event_rule`  | `messaging.md` | Eventarc                | _none_       |
| Step Functions | `aws_sfn_state_machine`    | `messaging.md` | Workflows               | _none_       |

## AI/ML Services

| AWS Service                 | Resource Type       | Reference File              | Typical GCP target          | google/skill                          |
| --------------------------- | ------------------- | --------------------------- | --------------------------- | ------------------------------------- |
| Bedrock (LLM/Claude)       | (generative models) | `ai-bedrock-to-vertex.md`   | Vertex AI (Gemini)          | `gemini-api`, `gemini-interactions-api` |
| OpenAI (in AWS env)         | (openai SDK)        | `ai-openai-to-vertex.md`    | Vertex AI (Gemini)          | `gemini-api`, `gemini-interactions-api` |
| SageMaker (traditional ML)  | (custom endpoints)  | `ai.md`                     | Vertex AI                   | _none_                                |
| SageMaker Pipelines         | (custom config)     | `ai.md`                     | Vertex AI Pipelines         | _none_                                |
| Rekognition                 | (managed API)       | `ai.md`                     | Cloud Vision API            | _none_                                |
| Textract                    | (managed API)       | `ai.md`                     | Document AI                 | _none_                                |

## Logging Services

| AWS Service                  | Resource Type                  | Reference File          | Typical GCP target                                                  | google/skill                            |
| ---------------------------- | ------------------------------ | ----------------------- | ------------------------------------------------------------------- | --------------------------------------- |
| CloudWatch Logs              | `aws_cloudwatch_log_group`     | `logging-analytics.md`  | Cloud Logging log bucket (`google_logging_log_bucket`)              | `google-cloud-networking-observability` |
| CloudWatch Log Stream        | `aws_cloudwatch_log_stream`    | `logging-analytics.md`  | _(implicit in log bucket; dropped, no Terraform emit)_              | `google-cloud-networking-observability` |
| CloudWatch Alarms            | `aws_cloudwatch_metric_alarm`  | `logging-analytics.md`  | `google_monitoring_alert_policy`                                    | `google-cloud-networking-observability` |
| SNS (alarm target)           | `aws_sns_topic` (alarm)        | `logging-analytics.md`  | `google_pubsub_topic` + `google_monitoring_notification_channel`    | `google-cloud-networking-observability` |

## Analytics & Streaming Services

| AWS Service                      | Resource Type                                | Reference File          | Typical GCP target                                                                                  | google/skill |
| -------------------------------- | -------------------------------------------- | ----------------------- | --------------------------------------------------------------------------------------------------- | ------------ |
| Kinesis Firehose                 | `aws_kinesis_firehose_delivery_stream`       | `logging-analytics.md`  | Pub/Sub + Dataflow (Pub/Sub-to-GCS or vendor template) + sink (GCS / Elasticsearch / Splunk)         | _none_       |
| Kinesis Data Streams             | `aws_kinesis_stream`                         | `logging-analytics.md`  | `google_pubsub_topic` + pull subscriptions (ordering keys for per-shard order)                       | _none_       |
| Glue Data Catalog (DB)           | `aws_glue_catalog_database`                  | `logging-analytics.md`  | `google_bigquery_dataset`                                                                            | _none_       |
| Glue Data Catalog (Table)        | `aws_glue_catalog_table`                     | `logging-analytics.md`  | `google_bigquery_table` (external definition over GCS Parquet/Avro/JSON)                             | _none_       |
| Glue Crawler                     | `aws_glue_crawler`                           | `logging-analytics.md`  | GCS Object Notifications + Cloud Functions, OR manual schema declaration on `google_bigquery_table` | _none_       |
| Glue Job                         | `aws_glue_job`                               | `logging-analytics.md`  | Dataproc (preserve Spark) OR Dataflow / Beam (rewrite) — gated by **Q_LOG2**                          | _none_       |
| Glue Workflow                    | `aws_glue_workflow`                          | `logging-analytics.md`  | `google_cloudworkflows_workflow`                                                                     | _none_       |
| Athena                           | `aws_athena_*`                               | `logging-analytics.md`  | BigQuery (external tables on GCS) — gated by **Q_LOG3**                                              | _none_       |
| EMR                              | `aws_emr_cluster`                            | `logging-analytics.md`  | Dataproc cluster                                                                                     | _none_       |
| MSK (Kafka)                      | `aws_msk_cluster`, `aws_msk_serverless_cluster` | `logging-analytics.md` | Pub/Sub (default) OR self-managed Kafka on GCE/GKE (Kafka API preservation)                          | _none_       |
| OpenSearch                       | `aws_opensearch_domain`                      | `logging-analytics.md`  | Elasticsearch on GKE (specialist engagement; no managed equivalent)                                  | _none_       |

## Secondary/Infrastructure Services

| AWS Service   | Resource Type     | Reference File    | Typical GCP target  | google/skill                            |
| ------------- | ----------------- | ----------------- | ------------------- | --------------------------------------- |
| IAM Roles     | `aws_iam_role`    | `networking.md`   | Service Accounts    | `google-cloud-recipe-auth`              |
| CloudWatch    | (managed)         | See `logging-analytics.md` for log groups / alarms; other CloudWatch surfaces remain out of v1.0 scope | Cloud Monitoring    | `google-cloud-networking-observability` |

---

**Usage:**

1. Extract AWS resource type from Terraform
2. Find in table above
3. If resource found in `fast-path.md` Direct Mappings table: use that mapping (confidence = deterministic)
4. Otherwise: load Reference File listed above and apply 6-criteria rubric (confidence = inferred)
5. **Before applying the design-ref's rubric or generating Terraform:** check the **google/skill** column. If a skill is listed and installed, read it first per the protocol in `references/shared/companion-skills.md` and treat its guidance as the canonical source for GCP-side configuration.

**User-facing labels** for chat and reports: see `fast-path.md` -> **User-facing vocabulary** (e.g. **Standard pairing** / **Tailored to your setup** / **Estimated from billing only**).

---

## Source-Code SDK Call-Site Mapping

The above tables are for **infrastructure** (Terraform / CloudFormation resources). For **application source-code** rewrites — translating `aws-sdk-*` / `boto3` / `@aws-sdk/*` call sites in Ruby, Python, JS/TS, Java, Kotlin, and Go to `google-cloud-*` equivalents — see:

- `sdk-mapping.md` — per-language, per-operation rewrite rubric (Ruby is the v1 priority; other languages stubbed)

`sdk-mapping.md` is consumed by `design-infra.md` Step 4.7 to produce `sdk-migration-plan.json` and by `generate-artifacts-infra.md` Step 4.8 to emit unified-diff patches under `$MIGRATION_DIR/code-patches/`.
