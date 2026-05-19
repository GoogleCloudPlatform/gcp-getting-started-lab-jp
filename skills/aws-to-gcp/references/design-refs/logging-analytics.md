# Logging & Analytics Services Design Rubric

**Applies to:** CloudWatch Logs, CloudWatch Alarms, SNS-for-alarms, Kinesis Firehose, Kinesis Data Streams, Glue (Catalog / Job / Crawler / Workflow), Athena, EMR, MSK, OpenSearch

**Quick lookup (no rubric):** Check `fast-path.md` first. The following rows from this category are in Direct Mappings (`deterministic`):

- `aws_cloudwatch_log_group` -> `google_logging_log_bucket`

Everything else in this file is `inferred` and goes through the rubric below.

## Companion skill (google/skills)

- **Cloud Logging / Cloud Monitoring targets** (CloudWatch Logs, CloudWatch Alarms, log-based metrics, alert policies, notification channels): when the `google-cloud-networking-observability` skill is installed (`~/.claude/skills/google-cloud-networking-observability/SKILL.md`, fallback `~/.agents/skills/...`), read it for the canonical observability templates (log bucket retention, log router / sinks, `google_monitoring_alert_policy` condition shape, notification channel wiring). Treat it as the source of truth for the GCP-side configuration per the protocol in `references/shared/companion-skills.md`. If not installed, fall back to this file and add a `warnings[]` entry.
- **Pub/Sub targets** (Kinesis Streams, SNS-for-alarms message bus, Firehose ingestion front door): there is no dedicated google/skill for Pub/Sub. Use `messaging.md` for the Pub/Sub configuration recipes and this file for the analytics-side wiring.
- **BigQuery / Dataflow / Dataproc / Cloud Workflows targets** (Glue Catalog/Tables, Glue Jobs, Glue Workflows, Athena, EMR): there are no dedicated google/skills for these. Use this file directly. If the customer has chosen Cloud Workflows as a target, also consult `messaging.md` (Step Functions -> Workflows section) for the workflow-definition recipes.
- **Specialist gates:** OpenSearch and MSK (Kafka API preservation), Firehose with Splunk/OpenSearch destinations, and Redshift-adjacent analytics paths require human review. Do not auto-map them without the relevant Category G clarify answers.

## Deterministic Mapping

**CloudWatch Log Group (`aws_cloudwatch_log_group`) -> Cloud Logging log bucket (`google_logging_log_bucket`)**

Confidence: `deterministic` (always 1:1, no decision tree)

**Behavior preservation:**

- `retention_in_days` -> `retention_days` (Cloud Logging supports 1-3650 days; clamp values above the GCP max and emit a warning).
- `kms_key_id` -> `cmek_settings.kms_key_name` (Cloud Logging supports CMEK at the log bucket level).
- Log group name -> log bucket `bucket_id` (must be unique within project + location; sanitize to satisfy GCP naming rules).
- Multi-region log groups -> pick the log bucket `location` that matches `design_constraints.target_region`; fall back to `global` only if the source group spans regions.

`aws_cloudwatch_log_stream` has **no separate GCP resource** — log streams are an AWS-side organizational concept inside a log group. Cloud Logging organizes entries by `logName` instead. **Drop these resources from the GCP design** (do not emit Terraform); record a `warnings[]` entry: "Dropped `<N>` aws_cloudwatch_log_stream resources — implicit in Cloud Logging log buckets."

## Mapping Tables

### Logging path

| AWS                              | GCP equivalent                                                                              | Confidence      | Notes                                                                                                          |
| -------------------------------- | ------------------------------------------------------------------------------------------- | --------------- | -------------------------------------------------------------------------------------------------------------- |
| `aws_cloudwatch_log_group`       | Cloud Logging log bucket (`google_logging_log_bucket`)                                      | `deterministic` | Direct mapping; preserve retention, CMEK, location. Listed in `fast-path.md` Direct Mappings.                  |
| `aws_cloudwatch_log_stream`      | _(implicit in log bucket; no separate resource)_                                            | `deterministic` | Drop -- do not emit Terraform. Add `warnings[]` entry.                                                          |
| `aws_cloudwatch_metric_alarm`    | `google_monitoring_alert_policy`                                                            | `inferred`      | Translate `metric_name + threshold + comparison_operator + evaluation_periods` into one alert policy condition. |
| `aws_sns_topic` (alarm target)   | `google_pubsub_topic` + `google_monitoring_notification_channel`                            | `inferred`      | Two-step: Pub/Sub topic for messages, notification channel (type `pubsub`) for alert routing.                  |
| `aws_sns_topic_subscription` (alarm) | `google_monitoring_notification_channel` (email/SMS/webhook) **or** Pub/Sub subscription | `inferred`      | If subscription is email/SMS, prefer a dedicated channel of that type instead of going through Pub/Sub.        |

### Streaming / ETL path (Firehose, Kinesis, Glue)

| AWS                                                        | GCP equivalent                                                                                                 | Confidence | Notes                                                                                                                                 |
| ---------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------- | ---------- | ------------------------------------------------------------------------------------------------------------------------------------- |
| `aws_kinesis_firehose_delivery_stream` (S3 destination)    | `google_pubsub_topic` (ingest) + `google_dataflow_job` using the Pub/Sub-to-GCS template + `google_storage_bucket` (sink) | `inferred` | Requires destination disambiguation in Clarify (**Q_LOG1**). Preserve buffering interval / size by tuning Dataflow windowing.         |
| `aws_kinesis_firehose_delivery_stream` (OpenSearch dest)   | Pub/Sub + Dataflow (Pub/Sub-to-Elasticsearch template) + Elasticsearch on GCE/GKE                              | `inferred` | Rare; flag specialist (no managed OpenSearch). Confirm with **Q_LOG1** + OpenSearch gate.                                              |
| `aws_kinesis_firehose_delivery_stream` (Splunk dest)       | Pub/Sub + Splunk Dataflow Connector                                                                            | `inferred` | Specialist gate -- requires Splunk HEC token + Dataflow job parameters. Confirm with **Q_LOG1**.                                       |
| `aws_kinesis_firehose_delivery_stream` (Redshift dest)     | _(no automated target)_                                                                                        | `inferred` | Pipes into a warehouse target -> defer to Redshift specialist gate per `database.md`. Do not auto-map.                                 |
| `aws_kinesis_stream` (Kinesis Data Streams)                | `google_pubsub_topic` + pull subscription(s) (durable stream model)                                            | `inferred` | Order-per-shard caveat: use Pub/Sub ordering keys to approximate per-partition order. Replay window differs (Pub/Sub max 31 days).    |
| `aws_glue_catalog_database`                                | `google_bigquery_dataset`                                                                                      | `inferred` | Catalog moves into BigQuery; one dataset per Glue database.                                                                            |
| `aws_glue_catalog_table`                                   | `google_bigquery_table` with `external_data_configuration` (Parquet/Avro/JSON on GCS)                          | `inferred` | Preserve schema + partition columns. For Parquet on S3, plan a staging copy to GCS as part of cutover.                                 |
| `aws_glue_crawler`                                         | Cloud Storage Object Notifications + Cloud Functions (or manual schema declaration in `google_bigquery_table`) | `inferred` | Crawlers have **no direct GCP equivalent**. Prefer explicit schema declaration; only build the Notifications + Functions wiring when the source schema genuinely drifts. |
| `aws_glue_job` (Spark ETL)                                 | `google_dataproc_job` (Spark on Dataproc) **or** `google_dataflow_job` (Apache Beam)                            | `inferred` | Requires Clarify (**Q_LOG2**): preserve Spark with Dataproc, or rewrite to Beam on Dataflow for stronger GCP integration.              |
| `aws_glue_workflow`                                        | `google_cloudworkflows_workflow`                                                                                | `inferred` | Translate Glue triggers + dependencies into Workflows YAML. Cross-link to `messaging.md` Step Functions guidance.                      |
| `aws_glue_trigger`                                         | Cloud Scheduler (cron triggers) or Eventarc (event-based triggers)                                              | `inferred`  | Choose Scheduler for cron / Eventarc for event-driven; mirrors the SNS/EventBridge split in `messaging.md`.                            |

### Analytics surface

| AWS                            | GCP equivalent                                                       | Confidence | Notes                                                                                                                  |
| ------------------------------ | -------------------------------------------------------------------- | ---------- | ---------------------------------------------------------------------------------------------------------------------- |
| `aws_athena_workgroup`         | BigQuery (no Terraform-managed equivalent for the workgroup itself)  | `inferred` | Translate Athena workgroups into BigQuery reservations / projects. Confirm with **Q_LOG3**.                            |
| `aws_athena_database`          | `google_bigquery_dataset`                                            | `inferred` | Athena uses the Glue Catalog -> usually merges with the Glue-derived BigQuery datasets above (deduplicate by name).    |
| `aws_athena_named_query`       | `google_bigquery_saved_query` (or scripted assets)                   | `inferred` | Direct SQL conceptual swap; Athena SQL dialect close to BigQuery Standard SQL but not identical.                       |
| `aws_emr_cluster`              | Dataproc cluster (`google_dataproc_cluster`)                         | `inferred` | Preserve Spark/Hadoop version; map EMR release label to Dataproc image version.                                        |
| `aws_msk_cluster`              | Pub/Sub (preferred) **or** self-managed Kafka on GCE/GKE             | `inferred` | Gate via Clarify: preserve native Kafka API? If yes -> self-managed; if no -> Pub/Sub.                                  |
| `aws_msk_serverless_cluster`   | Pub/Sub                                                              | `inferred` | Serverless MSK is closer to Pub/Sub semantically. Confirm with Q_LOG (Kafka API question).                              |
| `aws_opensearch_domain`        | Elasticsearch on GKE (no managed equivalent)                         | `inferred` | Specialist note. GCP has no managed OpenSearch / Elasticsearch service in v1.0 scope.                                  |

## Eliminators (Hard Blockers)

| AWS Service                         | GCP                            | Blocker                                                                                                                                                                          |
| ----------------------------------- | ------------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `aws_kinesis_firehose_delivery_stream` (Splunk) | Pub/Sub + Dataflow              | Splunk HEC token / cluster details not in IaC -> **specialist gate**; do not auto-generate Dataflow without the missing parameters.                                              |
| `aws_kinesis_firehose_delivery_stream` (OpenSearch) | Pub/Sub + Dataflow + Elasticsearch on GKE | OpenSearch has no managed GCP target -> specialist gate (treat like Redshift in `database.md`: emit `Deferred -- specialist engagement` if customer cannot accept self-managed). |
| `aws_glue_job` (custom Scala libs)  | Dataflow                       | Custom Scala JARs not portable to Beam -> route to Dataproc (preserve Spark) per **Q_LOG2** answer A.                                                                            |
| `aws_msk_cluster` (Kafka API required) | Pub/Sub                     | Kafka client compatibility required (e.g. existing producers/consumers cannot change SDK) -> self-managed Kafka on GCE/GKE; Pub/Sub does not speak the Kafka wire protocol.       |
| `aws_opensearch_domain`             | _(no managed target)_          | No managed OpenSearch on GCP -> Elasticsearch on GKE with specialist engagement; do not emit a managed-service Terraform resource.                                                |
| `aws_cloudwatch_log_group` (retention > 3650 days) | `google_logging_log_bucket` | Cloud Logging max retention is 3650 days -> route long-tail archive to GCS via a log sink (`google_logging_project_sink`).                                                    |

## Signals (Decision Criteria)

### CloudWatch Logs

- **Standard application logs** -> Cloud Logging log bucket (fast-path).
- **Long-term retention (>3650 days) or compliance archive** -> add a log sink to GCS with Object Lifecycle for cold storage.
- **Cross-account log aggregation** -> log routing to a central project + organization-level sink.

### CloudWatch Alarms / SNS

- **Single-metric threshold alarm** -> single `google_monitoring_alert_policy` with a `threshold` condition.
- **Composite alarm (`aws_cloudwatch_composite_alarm`)** -> alert policy with multiple conditions combined via `combiner`.
- **SNS topic used only for alarms** -> emit `google_monitoring_notification_channel` (type: pubsub, email, sms, slack) **plus** a Pub/Sub topic if downstream consumers also exist. Do not emit a standalone Pub/Sub topic when the SNS topic is alarm-only.
- **SNS topic used by both alarms AND application** -> emit a Pub/Sub topic (consumed by app) AND a notification channel of type `pubsub` pointing at the same topic.

### Kinesis Firehose

- **S3 destination, near-real-time analytics** -> Pub/Sub + Dataflow Pub/Sub-to-GCS template (Parquet/Avro/JSON to GCS). Tune Dataflow windowing to match Firehose buffering hints (interval / size).
- **OpenSearch destination** -> specialist gate (see Eliminators).
- **Splunk destination** -> specialist gate (Splunk Dataflow Connector).
- **Redshift destination** -> defer to Redshift specialist gate per `database.md`. Do not auto-design.
- **Transformations enabled (Lambda transform)** -> port the Lambda function to a Dataflow ParDo or a Cloud Run job invoked from the pipeline.

### Kinesis Data Streams

- **Single consumer, append-only stream** -> Pub/Sub topic + pull subscription with ordering keys (one key per shard equivalent).
- **Multiple competing consumers** -> Pub/Sub topic + multiple subscriptions (each is its own consumer group).
- **Strict per-shard ordering** -> Pub/Sub ordering keys. Document the caveat: ordering is per-key, not per-topic, and slows throughput.
- **Replay > 31 days required** -> Pub/Sub cannot match (max 31 days). Add a Dataflow job that archives to GCS for long replays.

### Glue (Catalog / Job / Crawler / Workflow)

- **Glue Catalog database + tables** -> BigQuery dataset + tables. Use `external_data_configuration` when the data stays on GCS; load it into native BigQuery storage when query performance matters and the data is bounded.
- **Glue Job, PySpark, lightweight transforms** -> Dataflow (Beam) is the more GCP-native path; ask via **Q_LOG2**.
- **Glue Job, PySpark with large existing codebase or Scala/Java JARs** -> Dataproc preserves the Spark surface and minimizes rewrite cost.
- **Glue Crawler against well-known schemas (Parquet, Avro)** -> declare the schema in `google_bigquery_table.external_data_configuration` directly; skip the GCS Notifications + Cloud Functions wiring entirely.
- **Glue Crawler against drifting JSON/CSV** -> GCS Notifications -> Pub/Sub -> Cloud Function that updates the BigQuery external table schema. Document this as a specialist follow-up.
- **Glue Workflow (DAG of jobs)** -> Cloud Workflows YAML; one Workflows resource per Glue workflow.

### Athena

- **Athena workgroup + named queries** -> BigQuery + saved queries. Different cost model (BigQuery is on-demand bytes scanned OR slot-based; Athena is on-demand bytes scanned). Confirm with **Q_LOG3**.
- **Athena Federated Query** -> BigQuery + BigQuery Omni / BigLake (specialist note; depends on the federated source).

### EMR

- **EMR Spark / Hadoop cluster** -> Dataproc with matching image version. Preserve bootstrap actions where possible by porting to Dataproc initialization actions.
- **EMR Serverless** -> Dataproc Serverless for Spark.
- **EMR on EKS** -> Dataproc on GKE.

### MSK / OpenSearch

- **MSK with Kafka API preservation required** -> self-managed Kafka on GCE/GKE (no managed Pub/Sub-for-Kafka equivalent inside scope).
- **MSK as a generic durable stream (no Kafka SDK dependency)** -> Pub/Sub.
- **OpenSearch domain** -> always specialist; Elasticsearch on GKE is the only path inside this skill.

## 6-Criteria Rubric

Apply in order; first match wins. This mirrors the rubric convention used in `messaging.md`, `database.md`, and `compute.md`.

1. **Eliminators** — Does the AWS config require GCP-unsupported features (Splunk HEC, custom Scala JARs in Glue, Kafka API on MSK, managed OpenSearch, > 3650 day retention)? If yes: switch target per the Eliminators table or route to specialist gate.
2. **Operational Model** — Managed (Cloud Logging, Cloud Monitoring, Pub/Sub, BigQuery, Dataflow, Dataproc, Cloud Workflows) vs Self-hosted (Kafka on GCE, Elasticsearch on GKE)?
   - Prefer managed unless an Eliminator forces self-hosted.
3. **User Preference** — From `preferences.json`:
   - `design_constraints.availability` -> Pub/Sub is multi-region by default; Cloud Logging log buckets are regional, pick a region near the workload.
   - `design_constraints.target_region` -> BigQuery dataset `location`, Dataflow job region, Dataproc cluster region.
   - **Category G answers** (Q_LOG1, Q_LOG2, Q_LOG3) when present -> these are authoritative; do not re-derive.
4. **Feature Parity** — Does the AWS config use features unavailable in GCP?
   - Firehose dynamic partitioning -> Dataflow side-output by key (requires Beam code).
   - Glue Job bookmarks -> Dataflow state + Pub/Sub ack tracking (different model).
   - Athena `CREATE TABLE AS SELECT` (CTAS) -> BigQuery `CREATE TABLE ... AS SELECT` (close, but watch for partition syntax differences).
5. **Cluster Context** — Are other resources in the cluster using BigQuery / Pub/Sub / Cloud Logging? Match the family (don't mix Dataflow and Dataproc within a single workflow unless rubric forces it).
6. **Simplicity** — Prefer the smaller surface area: Pub/Sub + Dataflow (Beam) is generally simpler than Pub/Sub + Dataproc (Spark) when the customer doesn't have a Spark codebase to preserve.

## Required Clarify Questions (Category G)

These questions live in `references/phases/clarify/clarify.md` under **Category G — Logging & Analytics**. They fire only when the matching AWS resource types appear in the inventory. The full question text, answer options, and interpret rules are documented there; this file lists the IDs and the rubric impact only.

- **Q_LOG1** — Firehose destination semantics (preserve via Dataflow-to-equivalent-sink, or consolidate into Cloud Logging?). Fires when `aws_kinesis_firehose_delivery_stream` is present. Drives the row choice in the **Streaming / ETL path** table above.
- **Q_LOG2** — Glue job migration approach (Dataproc preserving Spark, or Dataflow / Apache Beam rewrite?). Fires when `aws_glue_job` is present. Drives the Glue Job row choice in the same table.
- **Q_LOG3** — Athena -> BigQuery acceptance (yes/no). Fires when `aws_athena_*` is present. If `no`, mark as `Deferred -- specialist engagement` instead of emitting BigQuery resources.

If a Category G question is **not asked** because the inventory does not contain the relevant resource, this rubric proceeds without the user input and the answer defaults documented in `clarify.md` apply.

## Output Schema

### Example 1: CloudWatch Log Group -> Cloud Logging log bucket

```json
{
  "aws_type": "aws_cloudwatch_log_group",
  "aws_address": "/ecs/education-production",
  "aws_config": {
    "retention_in_days": 30,
    "kms_key_id": null
  },
  "gcp_service": "Cloud Logging",
  "gcp_config": {
    "name": "projects/<project>/locations/asia-northeast1/buckets/ecs-education-production",
    "location": "asia-northeast1",
    "retention_days": 30
  },
  "confidence": "deterministic",
  "rationale": "aws_cloudwatch_log_group is in fast-path.md Direct Mappings; 1:1 to google_logging_log_bucket with retention preserved."
}
```

### Example 2: CloudWatch Metric Alarm + SNS -> Alert Policy + Notification Channel

```json
{
  "aws_type": "aws_cloudwatch_metric_alarm",
  "aws_address": "puma-running-task-count",
  "aws_config": {
    "metric_name": "RunningTaskCount",
    "comparison_operator": "LessThanThreshold",
    "threshold": 2,
    "evaluation_periods": 1,
    "alarm_actions": ["arn:aws:sns:ap-northeast-1:123456789012:tunag-education-alert"]
  },
  "gcp_service": "Cloud Monitoring",
  "gcp_config": {
    "alert_policy": {
      "display_name": "puma-running-task-count",
      "combiner": "OR",
      "conditions": [{
        "display_name": "RunningTaskCount < 2",
        "condition_threshold": {
          "filter": "metric.type=\"run.googleapis.com/container/instance_count\"",
          "comparison": "COMPARISON_LT",
          "threshold_value": 2,
          "duration": "60s"
        }
      }],
      "notification_channels": ["projects/<project>/notificationChannels/<channel-id>"]
    },
    "notification_channel": {
      "display_name": "tunag-education-alert",
      "type": "pubsub",
      "labels": { "topic": "projects/<project>/topics/tunag-education-alert" }
    },
    "pubsub_topic": "tunag-education-alert"
  },
  "confidence": "inferred",
  "rationale": "CloudWatch alarm + SNS fan-out -> Cloud Monitoring alert policy + Pub/Sub-backed notification channel; preserves the alarm threshold and routes notifications via Pub/Sub for downstream consumers."
}
```

### Example 3: Kinesis Firehose (S3 destination) -> Pub/Sub + Dataflow + GCS

```json
{
  "aws_type": "aws_kinesis_firehose_delivery_stream",
  "aws_address": "puma-logs-firehose",
  "aws_config": {
    "destination": "extended_s3",
    "extended_s3_configuration": {
      "bucket_arn": "arn:aws:s3:::tunag-education-logs",
      "buffering_interval": 60,
      "buffering_size": 5
    }
  },
  "gcp_service": "Pub/Sub + Dataflow + GCS",
  "gcp_config": {
    "pubsub_topic": "puma-logs-firehose",
    "dataflow_job": {
      "template_gcs_path": "gs://dataflow-templates/latest/Cloud_PubSub_to_GCS_Text",
      "parameters": {
        "inputTopic": "projects/<project>/topics/puma-logs-firehose",
        "outputDirectory": "gs://tunag-education-logs/firehose/",
        "windowDuration": "1m"
      },
      "region": "asia-northeast1"
    },
    "gcs_bucket": "tunag-education-logs"
  },
  "confidence": "inferred",
  "rationale": "Firehose with S3 destination -> Pub/Sub (ingest) + Dataflow Pub/Sub-to-GCS template (delivery). Q_LOG1 answer was A (preserve sink semantics)."
}
```

### Example 4: Glue Job -> Dataflow (Beam)

```json
{
  "aws_type": "aws_glue_job",
  "aws_address": "rds-to-parquet-etl",
  "aws_config": {
    "command": { "name": "glueetl", "python_version": "3" },
    "glue_version": "4.0"
  },
  "gcp_service": "Dataflow",
  "gcp_config": {
    "job_name": "rds-to-parquet-etl",
    "template_gcs_path": "gs://dataflow-templates/latest/<job-template>",
    "region": "asia-northeast1",
    "parameters": { "inputTable": "...", "outputBucket": "..." }
  },
  "confidence": "inferred",
  "rationale": "Glue PySpark job; Q_LOG2 answer was B (rewrite as Beam on Dataflow). Code-rewrite effort flagged in design output."
}
```

### Example 5: Glue Catalog -> BigQuery dataset + external tables

```json
{
  "aws_type": "aws_glue_catalog_database",
  "aws_address": "tunag_education_rds",
  "gcp_service": "BigQuery",
  "gcp_config": {
    "dataset_id": "tunag_education_rds",
    "location": "asia-northeast1",
    "tables": [
      {
        "table_id": "users",
        "external_data_configuration": {
          "source_format": "PARQUET",
          "source_uris": ["gs://tunag-education-rds/users/*.parquet"],
          "autodetect": false
        }
      }
    ]
  },
  "confidence": "inferred",
  "rationale": "Glue Catalog -> BigQuery dataset; tables as external BigQuery tables over GCS Parquet (mirroring S3 Parquet layout)."
}
```

## Notes

- `aws_cloudwatch_log_stream` is intentionally **not** in the Skip Mappings table in `fast-path.md` (which is reserved for whole-service skips like CloudWatch as a category). Streams are dropped at the resource level inside this rubric, with a `warnings[]` entry; the parent log group still emits.
- When **both** the Redshift specialist gate (`database.md`) AND Category G fire (e.g. Firehose -> Redshift), the Redshift gate wins: emit `Deferred -- specialist engagement` for the Firehose target and do **not** auto-design a Pub/Sub + Dataflow pipeline that lands in a non-existent warehouse.
- All Glue-derived BigQuery datasets and tables inherit the customer's `target_region` from `preferences.json`. Do **not** hard-code `us-central1` or `US`.
- Cloud Logging log buckets are **regional** (or `global`). Match `target_region`. If the source CloudWatch log group spans regions, fall back to `global` and add a `warnings[]` entry.
