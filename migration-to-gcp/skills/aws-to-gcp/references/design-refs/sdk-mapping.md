# AWS SDK -> GCP SDK Call-Site Mapping

> Used by **Design Step 4.7** (`design-infra.md`) to translate each `aws-sdk-usage.json` call site into a `sdk-migration-plan.json` entry, and by **Generate Step 6** (`generate-artifacts-infra.md`) to emit unified-diff code patches.
>
> **Scope:** non-AI AWS SDK calls (S3, SNS, SQS, Firehose, CloudWatch, Secrets Manager, DynamoDB, KMS, SES, Lambda invoke, RDS data API). AI SDK calls (Bedrock, SageMaker, Comprehend, etc.) are routed to the AI plan in `design-refs/ai-bedrock-to-vertex.md` and `design-refs/ai-openai-to-vertex.md` instead.
>
> **Auth note:** none of the per-call mappings below require code-level auth changes. On GCP, all the listed clients pick up Application Default Credentials (ADC) at boot; binding ADC to a Workload Identity service account is a **deployment-time** change (handled by Terraform / `generate-artifacts-infra.md`), not a code change. The Generate step still emits an `auth_change` note per call so the developer can audit the runtime identity at deployment time.

---

## How to Use This File

1. Read the row for the source `aws_service` + language combination.
2. Pick the row's **Target GCP gem/package** and **Target op**.
3. Apply the **Request shape diff** (renamed kwargs, restructured nested params).
4. Apply the **Response shape diff** so downstream code that consumes the response still works.
5. Note any **Idiom diff** (paginators, retries, presigned URLs, batch APIs).
6. If the **Confidence** column says `inferred`, mark `confidence: "inferred"` and `manual_review: true` in `sdk-migration-plan.json` — the rewrite is a starting point but not safe to apply blindly.

---

## Ruby — `aws-sdk-*` -> `google-cloud-*`

This is the **v1 target language** because the sample test bed at `sample-project/app/` is Rails. Other languages below are stubbed; extend per customer.

### Top-level gem mapping (informational — see per-operation tables for the actual rewrite)

| `aws-sdk-*` gem | `google-cloud-*` gem | Notes |
| --- | --- | --- |
| `aws-sdk-s3` | `google-cloud-storage` | Bucket + Object model. Presigned URL APIs differ (see S3 table). |
| `aws-sdk-sns` | `google-cloud-pubsub` | SNS publishes to a topic; Pub/Sub publishes to a topic. Subscribers in SNS are configured per-topic; in Pub/Sub each subscription is its own first-class resource and must be created separately (Terraform handles that — Generate emits `google_pubsub_subscription` blocks). |
| `aws-sdk-firehose` | `google-cloud-pubsub` (raw stream) OR `google-cloud-logging` (app-log stream) | Pick per `discover-app-sdk.md`'s flagged destination — usually Pub/Sub when the Firehose delivery target is S3/Redshift/OpenSearch (raw event stream), Cloud Logging when the delivery target is CloudWatch Logs (app log shipping). |
| `aws-sdk-cloudwatch` (metrics) | `google-cloud-monitoring` | `put_metric_data` -> `create_time_series`. Namespace concept maps to a metric descriptor under the project. |
| `aws-sdk-cloudwatchlogs` | `google-cloud-logging` | `put_log_events` -> `write_log_entries`. Log groups -> log names (no separate group resource). |
| `aws-sdk-secretsmanager` | `google-cloud-secret_manager` | `get_secret_value` -> `access_secret_version` with a fully-qualified `projects/<p>/secrets/<s>/versions/latest` name. |
| `aws-sdk-dynamodb` | `google-cloud-firestore` (NoSQL document model) OR `google-cloud-bigtable` (wide-column) | Decision lives in Clarify (`clarify-database.md`); if Clarify said Firestore, all rows route to `google-cloud-firestore`. Otherwise Bigtable. Default if Clarify never asked: `google-cloud-firestore`, with `confidence: inferred` and `manual_review: true`. |
| `aws-sdk-sqs` | `google-cloud-pubsub` (pull subscription) OR `google-cloud-tasks` (short-lived RPC-style HTTP delivery) | Pull subscription is the default; Cloud Tasks only when the SQS queue is consumed by an HTTP worker / Lambda fronted by API Gateway. |
| `aws-sdk-kms` | `google-cloud-kms` | `encrypt` / `decrypt` semantics are very similar — key resource names differ (`projects/<p>/locations/<l>/keyRings/<r>/cryptoKeys/<k>`). |
| `aws-sdk-ses` / `aws-sdk-sesv2` | (no first-class GCP equivalent) | Recommend a third-party (SendGrid, Mailgun, Postmark) OR Gmail API for low-volume internal mail. Emit a `# MANUAL: GCP has no SES equivalent — choose a third-party email provider` comment in the patch. |
| `aws-sdk-lambda` (cross-service `invoke`) | `google-cloud-run` (Cloud Run + HTTP trigger) OR `Net::HTTP` to the Cloud Run service URL | The Cloud Run service replaces the Lambda function; direct `invoke` is replaced by an authenticated HTTPS POST. |
| `aws-sdk-rds` (control plane) | (no equivalent — use `gcloud sql ...` via shell OR Terraform) | Most apps never call the RDS control plane from runtime code. If they do, treat as `manual_review: true`. |
| `aws-sdk-states` (Step Functions) | `google-cloud-workflows` | `start_execution` -> `execute_workflow`. State machine ARNs -> workflow resource names. |
| `aws-sdk-eventbridge` | `google-cloud-eventarc` (Eventarc) OR `google-cloud-pubsub` | Eventarc for system events; Pub/Sub for custom events. Decision in Clarify. |

### Per-operation rewrite tables (Ruby)

#### S3 (`aws-sdk-s3` -> `google-cloud-storage`)

| aws op | gcp op | Request shape diff | Response shape diff | Idiom diff |
| --- | --- | --- | --- | --- |
| `put_object(bucket:, key:, body:, content_type:, metadata:)` | `bucket.create_file(file_io, key, content_type:, metadata:)` | `bucket:` (string) -> `bucket = storage.bucket("...")` (object); `key:` -> positional `path` arg; `body:` -> positional `file` arg | `resp.etag`, `resp.version_id` -> `file.etag`, `file.generation` | The `create_file` call uploads in one shot; multipart -> `bucket.create_file(...).resumable_upload` |
| `delete_object(bucket:, key:)` | `bucket.file(key).delete` | as above; `key` is a positional method arg | returns `true` on success vs the AWS `DeleteObjectOutput` | — |
| `get_object(bucket:, key:)` | `bucket.file(key).download` | as above | `resp.body.read` -> `file.download(io); io.string` | GCS download returns the content directly into the given IO; rewind before reading |
| `list_objects_v2(bucket:, prefix:, max_keys:)` | `bucket.files(prefix: "...", max: ...)` | `max_keys:` -> `max:` | `resp.contents.each { |o| o.key }` -> `files.each { |f| f.name }` | Pagination is lazy iteration on the returned `Google::Cloud::Storage::File::List`; no explicit `next_token` |
| `head_object(bucket:, key:)` | `bucket.file(key, skip_lookup: false)` | as above | `resp.content_length`, `resp.content_type` -> `file.size`, `file.content_type` | Returns `nil` if the file does not exist (no equivalent of S3's `NotFound` exception); guard with `if file` |
| `copy_object(bucket:, key:, copy_source:)` | `source_bucket.file(src_key).copy(dest_bucket, dest_key)` | source/dest are separate args | returns the destination `Google::Cloud::Storage::File` | — |
| presigned URL (`Aws::S3::Presigner.new.presigned_url(:get_object, ...)`) | `file.signed_url(method: "GET", expires: 3600)` | — | URL string returned in both | Cloud Storage signed URLs require a service account JSON key or a signer policy; document this as `# AUTH: GCS signed URLs require either a JSON key or IAM SignBlob permission for the service account` |

#### SNS (`aws-sdk-sns` -> `google-cloud-pubsub`)

| aws op | gcp op | Request shape diff | Response shape diff | Idiom diff |
| --- | --- | --- | --- | --- |
| `publish(topic_arn:, message:, message_attributes:, subject:)` | `topic.publish(message, attrs)` | `topic_arn:` (ARN) -> `topic = pubsub.topic("topic-name")`; `message:` -> positional `data` arg (UTF-8 string OR bytes); `message_attributes:` (typed `{ DataType:, StringValue: }`) -> plain `attrs` hash `{ "key" => "value" }`; `subject:` has no equivalent — fold into `attrs["subject"]` | `resp.message_id` -> `message.message_id` | Pub/Sub `publish` returns immediately; use `topic.publish_async(...)` for batched throughput |
| `list_topics` | `pubsub.topics` | no args | `resp.topics.map(&:topic_arn)` -> `topics.map(&:name)` | Pub/Sub returns full resource names `projects/<p>/topics/<t>` not ARNs |
| `subscribe(topic_arn:, protocol:, endpoint:)` | `topic.subscribe("sub-name", endpoint: ..., push_config: ...)` | `protocol:` mostly redundant on Pub/Sub (push vs pull is implied by `push_config`) | returns subscription object | Subscriptions in Pub/Sub are first-class resources — usually created via Terraform, NOT runtime code. Flag `manual_review: true` if found in app code. |

#### Firehose (`aws-sdk-firehose` -> `google-cloud-pubsub` OR `google-cloud-logging`)

| aws op | gcp op (Pub/Sub variant) | gcp op (Logging variant) | Notes |
| --- | --- | --- | --- |
| `put_record(delivery_stream_name:, record: { data: })` | `topic.publish(record_data)` | `logger.info(record_data)` or `entries_client.write_log_entries([entry])` | The choice between Pub/Sub and Logging depends on the Firehose destination (S3/Redshift/OpenSearch -> Pub/Sub; CloudWatch Logs -> Logging). Generate emits the chosen variant per `sdk-migration-plan.json.translations[].target.gcp_sdk`. |
| `put_record_batch(delivery_stream_name:, records: [ { data: }, ... ])` | `topic.publish_async(...)` in a loop | `entries_client.write_log_entries([entry, ...])` (Logging API supports batching natively) | — |
| `describe_delivery_stream(delivery_stream_name:)` | `pubsub.topic("name")` (existence check) | `entries_client.list_log_entries(filter: "logName=...")` | Cloud Logging has no separate "delivery stream" concept; the log name IS the stream. |

#### CloudWatch metrics (`aws-sdk-cloudwatch` -> `google-cloud-monitoring`)

| aws op | gcp op | Request shape diff | Response shape diff | Idiom diff |
| --- | --- | --- | --- | --- |
| `put_metric_data(namespace:, metric_data: [ { metric_name:, value:, unit:, dimensions:, timestamp: } ])` | `metric_client.create_time_series(name: "projects/<p>", time_series: [Google::Cloud::Monitoring::V3::TimeSeries])` | `namespace:` -> embedded in metric `type` (`custom.googleapis.com/<namespace>/<metric_name>`); `dimensions:` -> `metric.labels` map; `unit:` -> `metric_descriptor.unit` (must be pre-registered) | no return value | Metrics in Cloud Monitoring must be **declared** (via `MetricDescriptor`) before `create_time_series` will accept points if they use custom labels. Generate emits a one-time `metric_client.create_metric_descriptor(...)` setup snippet next to the first `put_metric_data` rewrite per namespace. |

#### Secrets Manager (`aws-sdk-secretsmanager` -> `google-cloud-secret_manager`)

| aws op | gcp op | Request shape diff | Response shape diff | Idiom diff |
| --- | --- | --- | --- | --- |
| `get_secret_value(secret_id:)` | `secret_client.access_secret_version(name: "projects/<p>/secrets/<s>/versions/latest")` | `secret_id:` (short name) -> fully-qualified `name:` path | `resp.secret_string` -> `resp.payload.data` (bytes — call `.force_encoding("UTF-8")` for string content) | The `projects/<p>` prefix needs `<p>` injected — Generate substitutes `${var.gcp_project}` literal at patch time so the user picks the project ID. |
| `describe_secret(secret_id:)` | `secret_client.get_secret(name: "projects/<p>/secrets/<s>")` | same path rewrite | `resp.arn`, `resp.kms_key_id` -> `resp.name`, `resp.replication.user_managed.replicas` | — |
| `create_secret(name:, secret_string:)` | `secret_client.create_secret(parent: "projects/<p>", secret_id: name, secret: {...})` + `secret_client.add_secret_version(parent: "projects/<p>/secrets/<name>", payload: { data: secret_string })` | requires two API calls (create + add version) | — | Usually creation lives in Terraform; flag `manual_review: true` if found in app code. |

#### DynamoDB (`aws-sdk-dynamodb` -> `google-cloud-firestore` OR `google-cloud-bigtable`)

This mapping is **inferred** for every row — the data model differences are large enough that no rewrite is safe without per-table review.

| aws op | gcp op (Firestore variant) | gcp op (Bigtable variant) | manual_review |
| --- | --- | --- | --- |
| `get_item(table_name:, key:)` | `firestore.col(table).doc(key).get` | `bigtable.instance(...).table(table).read_row(key)` | true |
| `put_item(table_name:, item:)` | `firestore.col(table).doc(key).set(item)` | `table.mutate_row(Google::Cloud::Bigtable::MutationEntry.new(key).set_cell(...))` | true |
| `query(...)`, `scan(...)` | Firestore queries (`.where(field, op, value)`) | Bigtable row range scans | true |

For each DynamoDB call site, the patch contains a `# MANUAL: Firestore data model differs from DynamoDB — review keys, indexes, and query patterns` comment.

#### SQS (`aws-sdk-sqs` -> `google-cloud-pubsub` pull subscription)

| aws op | gcp op | Notes |
| --- | --- | --- |
| `send_message(queue_url:, message_body:)` | `topic.publish(body)` | Producer side. |
| `receive_message(queue_url:, max_number_of_messages:, wait_time_seconds:)` | `subscription.pull(immediate: false, max: N)` (use a streaming pull subscriber for production) | Consumer side. Long-poll `wait_time_seconds` maps to Pub/Sub streaming pull naturally. |
| `delete_message(queue_url:, receipt_handle:)` | `received_message.ack` | Ack semantics are similar; both are explicit. |

#### KMS (`aws-sdk-kms` -> `google-cloud-kms`)

| aws op | gcp op | Notes |
| --- | --- | --- |
| `encrypt(key_id:, plaintext:)` | `key_client.encrypt(name: key_path, plaintext: bytes)` | `key_id` (alias or ARN) -> full `projects/<p>/locations/<l>/keyRings/<r>/cryptoKeys/<k>` path. |
| `decrypt(ciphertext_blob:)` | `key_client.decrypt(name: key_path, ciphertext: bytes)` | Cloud KMS requires the key path on `decrypt` too (AWS infers it from the blob). |

#### SES (`aws-sdk-ses` -> third-party)

`# MANUAL: GCP has no first-class SES equivalent. Pick one of:`
- `# - SendGrid / Mailgun / Postmark (recommended for transactional mail)`
- `# - Gmail API (only for low-volume internal mail; subject to daily quota)`

Generate emits the call site as a TODO with the comment above; no automatic rewrite.

#### Lambda invoke (`aws-sdk-lambda` -> `Net::HTTP` to Cloud Run)

| aws op | gcp op | Notes |
| --- | --- | --- |
| `invoke(function_name:, payload:)` | `Net::HTTP.post(URI(cloud_run_url), payload, headers_with_id_token)` | Requires an ID token from the metadata server: `Google::Auth::Credentials.new.fetch_access_token` for service-to-service authentication. Generate emits a helper `cloud_run_invoke(name, payload)` method. |

---

## Python — `boto3` -> `google-cloud-*`

> TODO: extend per-language table. Ruby is the v1 target; Python rows below cover the same 12 services at a high level. Per-operation request/response diffs are filled in on first customer need.

| boto3 service | google-cloud package | High-level notes |
| --- | --- | --- |
| `s3` | `google-cloud-storage` | `bucket('name').upload_from_filename(...)`; `bucket.get_blob(name).download_to_filename(...)`. |
| `sns` | `google-cloud-pubsub` | `publisher.publish(topic_path, data, **attrs)`. |
| `sqs` | `google-cloud-pubsub` | `subscriber.pull(subscription_path, max_messages=N)`. |
| `firehose` | `google-cloud-pubsub` OR `google-cloud-logging` | Same destination-based routing as Ruby. |
| `cloudwatch` (metrics) | `google-cloud-monitoring` | `client.create_time_series(name='projects/<p>', time_series=[...])`. |
| `logs` | `google-cloud-logging` | `client.write_entries([entry])`. |
| `secretsmanager` | `google-cloud-secret-manager` | `client.access_secret_version(name='projects/<p>/secrets/<s>/versions/latest')`. |
| `dynamodb` | `google-cloud-firestore` OR `google-cloud-bigtable` | manual_review: true on every row. |
| `kms` | `google-cloud-kms` | `client.encrypt(name=key_path, plaintext=bytes)`. |
| `ses` / `sesv2` | (third-party) | MANUAL comment, no auto-rewrite. |
| `lambda` (invoke) | HTTP to Cloud Run | helper function. |
| `events` (EventBridge) | `google-cloud-eventarc` OR `google-cloud-pubsub` | per-Clarify decision. |

---

## JavaScript / TypeScript — `@aws-sdk/*` -> `@google-cloud/*`

> TODO: extend per-language table. High-level package mapping for v1:

| `@aws-sdk/*` package | `@google-cloud/*` package | Notes |
| --- | --- | --- |
| `@aws-sdk/client-s3` | `@google-cloud/storage` | `storage.bucket(name).file(key).save(buffer, { contentType })`. |
| `@aws-sdk/client-sns` | `@google-cloud/pubsub` | `pubsub.topic(name).publishMessage({ data, attributes })`. |
| `@aws-sdk/client-sqs` | `@google-cloud/pubsub` | pull subscription via `subscription.on('message', ...)`. |
| `@aws-sdk/client-firehose` | `@google-cloud/pubsub` OR `@google-cloud/logging` | destination-based. |
| `@aws-sdk/client-cloudwatch` | `@google-cloud/monitoring` | `metricClient.createTimeSeries({ name, timeSeries: [...] })`. |
| `@aws-sdk/client-cloudwatch-logs` | `@google-cloud/logging` | `log.write(entry)`. |
| `@aws-sdk/client-secrets-manager` | `@google-cloud/secret-manager` | `client.accessSecretVersion({ name: 'projects/<p>/secrets/<s>/versions/latest' })`. |
| `@aws-sdk/client-dynamodb` | `@google-cloud/firestore` OR `@google-cloud/bigtable` | manual_review: true. |
| `@aws-sdk/client-kms` | `@google-cloud/kms` | `client.encrypt({ name: keyPath, plaintext: buf })`. |
| `@aws-sdk/client-ses` / `client-sesv2` | (third-party) | MANUAL comment. |
| `@aws-sdk/client-lambda` | HTTP fetch to Cloud Run | helper function `invokeCloudRun(name, payload)`. |
| `@aws-sdk/client-eventbridge` | `@google-cloud/eventarc` OR `@google-cloud/pubsub` | per-Clarify decision. |

---

## Java / Kotlin — `software.amazon.awssdk.*` -> `com.google.cloud.*`

> TODO: extend per-language table. High-level package mapping:

| AWS package | GCP package | Notes |
| --- | --- | --- |
| `software.amazon.awssdk.services.s3` | `com.google.cloud.storage` | `Storage.create(BlobInfo, bytes)`. |
| `software.amazon.awssdk.services.sns` | `com.google.cloud.pubsub.v1` | `Publisher.newBuilder(topicName).build().publish(msg)`. |
| `software.amazon.awssdk.services.sqs` | `com.google.cloud.pubsub.v1` | `Subscriber.newBuilder(subscription, MessageReceiver)` pull. |
| `software.amazon.awssdk.services.firehose` | `com.google.cloud.pubsub.v1` OR `com.google.cloud.logging` | destination-based. |
| `software.amazon.awssdk.services.cloudwatch` | `com.google.cloud.monitoring.v3` | `MetricServiceClient.createTimeSeries(...)`. |
| `software.amazon.awssdk.services.cloudwatchlogs` | `com.google.cloud.logging` | `Logging.write(...)`. |
| `software.amazon.awssdk.services.secretsmanager` | `com.google.cloud.secretmanager.v1` | `SecretManagerServiceClient.accessSecretVersion(name)`. |
| `software.amazon.awssdk.services.dynamodb` | `com.google.cloud.firestore` OR `com.google.cloud.bigtable` | manual_review: true. |
| `software.amazon.awssdk.services.kms` | `com.google.cloud.kms.v1` | `KeyManagementServiceClient.encrypt(name, plaintext)`. |
| `software.amazon.awssdk.services.lambda` | HTTP to Cloud Run | helper class. |

---

## Go — `github.com/aws/aws-sdk-go-v2/service/*` -> `cloud.google.com/go/*`

> TODO: extend per-language table. High-level package mapping:

| AWS package | GCP package | Notes |
| --- | --- | --- |
| `service/s3` | `cloud.google.com/go/storage` | `client.Bucket(name).Object(key).NewWriter(ctx)`. |
| `service/sns` | `cloud.google.com/go/pubsub` | `client.Topic(name).Publish(ctx, &pubsub.Message{Data: ...})`. |
| `service/sqs` | `cloud.google.com/go/pubsub` | `subscription.Receive(ctx, func(...) { ... })`. |
| `service/firehose` | `cloud.google.com/go/pubsub` OR `cloud.google.com/go/logging` | destination-based. |
| `service/cloudwatch` | `cloud.google.com/go/monitoring/apiv3` | `MetricClient.CreateTimeSeries(...)`. |
| `service/cloudwatchlogs` | `cloud.google.com/go/logging` | `logger.Log(...)`. |
| `service/secretsmanager` | `cloud.google.com/go/secretmanager/apiv1` | `client.AccessSecretVersion(ctx, req)`. |
| `service/dynamodb` | `cloud.google.com/go/firestore` OR `cloud.google.com/go/bigtable` | manual_review: true. |
| `service/kms` | `cloud.google.com/go/kms/apiv1` | `client.Encrypt(ctx, req)`. |
| `service/lambda` | HTTP to Cloud Run | helper function. |

---

## Confidence Heuristic

Set `confidence: "deterministic"` for a translation when ALL of:

1. The source `aws_service` has a 1:1 GCP target (no Clarify branch needed).
2. The operation appears in the per-op table above with both request and response shape diffs documented.
3. No `# MANUAL:` comment appears in the rewrite snippet.

Otherwise set `confidence: "inferred"` AND `manual_review: true`. DynamoDB, SES, and any TODO-stub language combination are always `inferred + manual_review: true`.

---

## Files That Consume This Mapping

- `references/phases/design/design-infra.md` Step 4.7 — writes `sdk-migration-plan.json` per call site.
- `references/phases/generate/generate-artifacts-infra.md` Step 6 — emits unified-diff `.patch` files plus `code-migration-summary.md`.
