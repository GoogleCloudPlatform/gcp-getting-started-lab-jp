# Discover Phase: App SDK Call-Site Discovery

> Self-contained app source-code scanner that inventories every `aws-sdk-*` / `boto3` / `@aws-sdk/*` / `software.amazon.awssdk.*` / `aws/aws-sdk-go` call site so the Design and Generate phases can rewrite them to `google-cloud-*` equivalents.
>
> **Scope vs `discover-app-code.md`:** `discover-app-code.md` exists primarily to detect AI workloads (Bedrock, SageMaker, OpenAI, etc.) and emits `ai-workload-profile.json`. This file is the **complement** — it inventories **non-AI** AWS SDK call sites (S3, SNS, SQS, Firehose, CloudWatch, Secrets Manager, DynamoDB, KMS, SES, Lambda invoke, RDS data API, etc.) and emits `aws-sdk-usage.json`. The two scanners may both run on the same codebase without conflict; AI signals already detected by `discover-app-code.md` are tagged but NOT removed from this inventory (a Bedrock SDK call still needs a source-code rewrite, just one that targets Vertex AI rather than a generic GCP service).
>
> **Dead-end handling:** If this file exits without producing artifacts (no source code found, or no AWS SDK call sites detected), report to the parent orchestrator what extensions/manifests were scanned and the empty result. Other sub-discovery files may still produce artifacts.

**Execute ALL steps in order. Do not skip or optimize.**

---

## Step 0: Self-Scan for Source Code

Re-use the same glob set as `discover-app-code.md > Step 0`:

**Source code extensions:**

- `**/*.rb` (Ruby — added here because Rails / Sinatra apps are a primary migration target)
- `**/*.py` (Python)
- `**/*.js`, `**/*.ts`, `**/*.jsx`, `**/*.tsx`, `**/*.mjs`, `**/*.cjs` (JavaScript / TypeScript)
- `**/*.go` (Go)
- `**/*.java`, `**/*.kt`, `**/*.scala` (JVM)
- `**/*.rs` (Rust)

**Dependency manifests** (used to confirm the `aws-sdk-*` dependency actually ships with the app — a stale require with no gem in `Gemfile.lock` is a false positive):

- `Gemfile`, `Gemfile.lock`, `*.gemspec` (Ruby)
- `requirements.txt`, `setup.py`, `pyproject.toml`, `Pipfile`, `Pipfile.lock` (Python)
- `package.json`, `package-lock.json`, `yarn.lock`, `pnpm-lock.yaml` (JavaScript)
- `go.mod`, `go.sum` (Go)
- `pom.xml`, `build.gradle`, `build.gradle.kts` (JVM)
- `Cargo.toml`, `Cargo.lock` (Rust)

**Exit gate:** If NO source files AND NO manifests are found, exit cleanly. Do NOT write `aws-sdk-usage.json`.

---

## Step 0.5: Auth SDK Exclusion (re-use list from discover-app-code.md)

Apply the same Auth SDK Exclusion List from `discover-app-code.md > Step 0.5`. Auth SDKs are **excluded** from `aws-sdk-usage.json` — they carry no AWS service identity and no GCP rewrite recommendation.

---

## Step 1: Detect AWS SDK Imports and Call Sites

Scan each source file with Grep. Record matches per the per-language patterns below. Capture, for each match: `file` (project-relative path), `line`, `language`, `aws_service`, `aws_sdk_module` (gem / package / module name), `aws_op` (best-effort), and `snippet` (the matched line, trimmed to ~120 chars).

### Ruby

**Require / import patterns** (match in any source file or Gemfile entry):

| Pattern | Maps to `aws_service` |
| --- | --- |
| `require "aws-sdk-s3"` / `gem "aws-sdk-s3"` / `Aws::S3::Client` / `Aws::S3::Resource` | `s3` |
| `require "aws-sdk-sns"` / `gem "aws-sdk-sns"` / `Aws::SNS::Client` | `sns` |
| `require "aws-sdk-sqs"` / `gem "aws-sdk-sqs"` / `Aws::SQS::Client` | `sqs` |
| `require "aws-sdk-firehose"` / `gem "aws-sdk-firehose"` / `Aws::Firehose::Client` | `firehose` |
| `require "aws-sdk-kinesis"` / `gem "aws-sdk-kinesis"` / `Aws::Kinesis::Client` | `kinesis` |
| `require "aws-sdk-cloudwatch"` / `gem "aws-sdk-cloudwatch"` / `Aws::CloudWatch::Client` | `cloudwatch` (metrics) |
| `require "aws-sdk-cloudwatchlogs"` / `gem "aws-sdk-cloudwatchlogs"` / `Aws::CloudWatchLogs::Client` | `cloudwatchlogs` |
| `require "aws-sdk-secretsmanager"` / `gem "aws-sdk-secretsmanager"` / `Aws::SecretsManager::Client` | `secretsmanager` |
| `require "aws-sdk-dynamodb"` / `gem "aws-sdk-dynamodb"` / `Aws::DynamoDB::Client` / `Aws::DynamoDB::Resource` | `dynamodb` |
| `require "aws-sdk-ses"` / `gem "aws-sdk-ses"` / `Aws::SES::Client` / `Aws::SESV2::Client` | `ses` |
| `require "aws-sdk-kms"` / `gem "aws-sdk-kms"` / `Aws::KMS::Client` | `kms` |
| `require "aws-sdk-lambda"` / `gem "aws-sdk-lambda"` / `Aws::Lambda::Client` | `lambda` |
| `require "aws-sdk-rds"` / `gem "aws-sdk-rds"` / `Aws::RDS::Client` | `rds` (control plane only; data plane uses `mysql2` / `pg` and is excluded) |
| `require "aws-sdk-sfn"` / `gem "aws-sdk-states"` / `Aws::States::Client` | `stepfunctions` |
| `require "aws-sdk-eventbridge"` / `gem "aws-sdk-eventbridge"` / `Aws::EventBridge::Client` | `eventbridge` |

**Call-site patterns:** Greedily match `<Receiver>.<op>(` where `<Receiver>` is either an `Aws::<Svc>::Client.new` instance variable OR the project's own wrapper module (e.g. `AwsClients.<svc>` in the sample Rails project — see `sample-project/app/config/initializers/00_aws.rb`). For each match, record the file/line, the operation name (the token after the `.`), and the full snippet.

Examples (all from the test bed at `sample-project/app/`):

- `AwsClients.secrets.get_secret_value(secret_id: ...)` → `aws_service=secretsmanager`, `aws_op=get_secret_value`
- `AwsClients.s3.put_object(bucket: ..., key: ..., body: ...)` → `aws_service=s3`, `aws_op=put_object`
- `AwsClients.s3.delete_object(bucket:, key:)` → `aws_service=s3`, `aws_op=delete_object`
- `AwsClients.s3.list_objects_v2(bucket:, max_keys: 1)` → `aws_service=s3`, `aws_op=list_objects_v2`
- `AwsClients.sns.publish(topic_arn: ..., message: ...)` → `aws_service=sns`, `aws_op=publish`
- `AwsClients.sns.list_topics` → `aws_service=sns`, `aws_op=list_topics`
- `AwsClients.firehose.put_record(delivery_stream_name: ..., record: { data: ... })` → `aws_service=firehose`, `aws_op=put_record`
- `AwsClients.firehose.describe_delivery_stream(delivery_stream_name: ...)` → `aws_service=firehose`, `aws_op=describe_delivery_stream`
- `AwsClients.cloudwatch.put_metric_data(namespace: ..., metric_data: [...])` → `aws_service=cloudwatch`, `aws_op=put_metric_data`
- `AwsClients.secrets.describe_secret(secret_id:)` → `aws_service=secretsmanager`, `aws_op=describe_secret`

**Wrapper detection heuristic:** If the codebase defines a single-file SDK wrapper (e.g. `module AwsClients ... end` in `config/initializers/*.rb`), the wrapper file itself is recorded as ONE entry per `Aws::<Svc>::Client.new` line (so the Generate phase rewrites the wrapper to construct `Google::Cloud::*` clients), AND every downstream `AwsClients.<svc>.<op>(...)` call site is recorded as a separate entry. Both are needed: rewriting only the wrapper leaves call sites with the wrong keyword arguments (e.g. `bucket:` vs `bucket_name:`).

### Python

| Pattern | `aws_service` |
| --- | --- |
| `import boto3` / `from boto3 import` / `boto3.client('s3')` / `boto3.resource('s3')` | `s3` |
| `boto3.client('sns')` | `sns` |
| `boto3.client('sqs')` | `sqs` |
| `boto3.client('firehose')` | `firehose` |
| `boto3.client('kinesis')` | `kinesis` |
| `boto3.client('cloudwatch')` | `cloudwatch` |
| `boto3.client('logs')` | `cloudwatchlogs` |
| `boto3.client('secretsmanager')` | `secretsmanager` |
| `boto3.client('dynamodb')` / `boto3.resource('dynamodb')` | `dynamodb` |
| `boto3.client('ses')` / `boto3.client('sesv2')` | `ses` |
| `boto3.client('kms')` | `kms` |
| `boto3.client('lambda')` | `lambda` |
| `boto3.client('stepfunctions')` | `stepfunctions` |
| `boto3.client('events')` | `eventbridge` |

**Call-site capture:** the line after a client/resource construction in the same file that invokes `<client_var>.<op>(...)`. Operation = the token after the dot.

### JavaScript / TypeScript

| Pattern | `aws_service` |
| --- | --- |
| `@aws-sdk/client-s3` (`import { S3Client, PutObjectCommand } from "@aws-sdk/client-s3"`) | `s3` |
| `@aws-sdk/client-sns` | `sns` |
| `@aws-sdk/client-sqs` | `sqs` |
| `@aws-sdk/client-firehose` | `firehose` |
| `@aws-sdk/client-kinesis` | `kinesis` |
| `@aws-sdk/client-cloudwatch` | `cloudwatch` |
| `@aws-sdk/client-cloudwatch-logs` | `cloudwatchlogs` |
| `@aws-sdk/client-secrets-manager` | `secretsmanager` |
| `@aws-sdk/client-dynamodb` (+ `@aws-sdk/lib-dynamodb`) | `dynamodb` |
| `@aws-sdk/client-ses` / `@aws-sdk/client-sesv2` | `ses` |
| `@aws-sdk/client-kms` | `kms` |
| `@aws-sdk/client-lambda` | `lambda` |
| `@aws-sdk/client-sfn` | `stepfunctions` |
| `@aws-sdk/client-eventbridge` | `eventbridge` |

Also catch the legacy SDK v2: `const AWS = require("aws-sdk")`, `new AWS.S3()`, `new AWS.SNS()`, etc.

**Call-site capture:** `client.send(new <Op>Command({ ... }))` in v3, or `client.<op>(params).promise()` in v2. Operation = the command name (strip the `Command` suffix) or the function name.

### Java / Kotlin (JVM)

| Pattern | `aws_service` |
| --- | --- |
| `software.amazon.awssdk.services.s3` | `s3` |
| `software.amazon.awssdk.services.sns` | `sns` |
| `software.amazon.awssdk.services.sqs` | `sqs` |
| `software.amazon.awssdk.services.firehose` | `firehose` |
| `software.amazon.awssdk.services.kinesis` | `kinesis` |
| `software.amazon.awssdk.services.cloudwatch` | `cloudwatch` |
| `software.amazon.awssdk.services.cloudwatchlogs` | `cloudwatchlogs` |
| `software.amazon.awssdk.services.secretsmanager` | `secretsmanager` |
| `software.amazon.awssdk.services.dynamodb` | `dynamodb` |
| `software.amazon.awssdk.services.ses` / `sesv2` | `ses` |
| `software.amazon.awssdk.services.kms` | `kms` |
| `software.amazon.awssdk.services.lambda` | `lambda` |

Legacy SDK v1 (`com.amazonaws.services.*`) maps to the same services.

### Go

| Pattern | `aws_service` |
| --- | --- |
| `github.com/aws/aws-sdk-go-v2/service/s3` / `github.com/aws/aws-sdk-go/service/s3` | `s3` |
| `github.com/aws/aws-sdk-go-v2/service/sns` | `sns` |
| (and so on per the JVM/Python tables) | |

> TODO: extend per-language table for Rust and other languages as customers request them. Ruby is the priority target for v1 because the sample test bed (`sample-project/app/`) is a Rails monolith.

---

## Step 2: Confirm via Dependency Manifest

For each AWS SDK module detected in Step 1, confirm it is declared in the language's manifest:

- Ruby — gem in `Gemfile` (or `Gemfile.lock`)
- Python — package in `requirements.txt` / `pyproject.toml` / `Pipfile`
- JS/TS — package in `package.json.dependencies` / `devDependencies`
- JVM — dependency in `pom.xml` / `build.gradle`
- Go — module in `go.mod`

If a call site references an SDK module that is NOT declared in the manifest, still record the call site but add `"confirmed_in_manifest": false` to the entry — the developer probably needs to add the dep before the migration runs, or the call site is dead code. Default `confirmed_in_manifest: true` when the dep is present.

---

## Step 3: Merge AI Overlap (if discover-app-code.md already ran)

If `$MIGRATION_DIR/ai-workload-profile.json` exists, mark any call site whose `aws_service` is `bedrock`, `bedrockruntime`, `sagemaker`, `comprehend`, `rekognition`, `textract`, `translate`, `polly`, `transcribe`, or `lex-runtime` with `"ai_overlap": true` in `aws-sdk-usage.json`. The Generate phase will route these to the AI migration plan (`generate-ai.md`) instead of the generic SDK rewrite path.

A call site can appear in BOTH `ai-workload-profile.json` and `aws-sdk-usage.json` — that is by design. `ai-workload-profile.json` carries model-level detail (model ID, capabilities) used by Vertex AI design; `aws-sdk-usage.json` carries the call-site coordinates used by Generate's code-patch step.

---

## Step 4: Write `aws-sdk-usage.json`

**After scanning, before writing `aws-sdk-usage.json`, compute the `summary` object's required fields and populate them inline:**

- `summary.total_call_sites` — integer count of entries in `call_sites[]`.
- `summary.by_service` — an object mapping `service-name -> count` (one key per distinct `aws_service` seen across `call_sites[]`, value = how many call sites reference that service). MUST be an object, never `null`.
- `summary.by_language` — an object mapping `language -> count`.
- `summary.languages` — a deduped array of language strings (the unique key set of `by_language`).

If no call sites were found (scan ran but matched zero AWS SDK references), write `summary: {"total_call_sites": 0, "by_service": {}, "by_language": {}, "languages": []}` explicitly — **never `null`**, **never an absent `summary` field**. (Note: in this zero-result case, Step 4's "Empty result" rule still applies and the file is NOT written — but if any other reason forces writing the file with zero call sites, the rule above stands.)

**Discover phase MUST NOT mark `phases.discover = "completed"` if `aws-sdk-usage.json` exists on disk and its `summary` field is `null`, missing, or any of `summary.total_call_sites`, `summary.by_service`, or `summary.languages` is `null` or absent.** Re-write the file with a populated summary before allowing Discover to complete.

Write to `$MIGRATION_DIR/aws-sdk-usage.json`. Use this exact schema:

```json
{
  "metadata": {
    "scanned_extensions": ["rb", "py", "js", "ts", "go", "java", "kt", "rs"],
    "scan_timestamp": "2026-05-18T12:00:00Z",
    "ai_overlap_merged": true
  },
  "summary": {
    "total_call_sites": 12,
    "by_service": {
      "s3": 4,
      "sns": 2,
      "firehose": 2,
      "cloudwatch": 2,
      "secretsmanager": 2
    },
    "by_language": { "ruby": 12 },
    "languages": ["ruby"],
    "wrapper_detected": {
      "present": true,
      "file": "app/config/initializers/00_aws.rb",
      "module": "AwsClients"
    }
  },
  "call_sites": [
    {
      "file": "app/config/initializers/01_secrets.rb",
      "line": 20,
      "language": "ruby",
      "aws_service": "secretsmanager",
      "aws_sdk_module": "aws-sdk-secretsmanager",
      "aws_op": "get_secret_value",
      "snippet": "resp = AwsClients.secrets.get_secret_value(secret_id: secret_id)",
      "confirmed_in_manifest": true,
      "ai_overlap": false,
      "via_wrapper": "AwsClients.secrets"
    },
    {
      "file": "app/app/controllers/attachments_controller.rb",
      "line": 14,
      "language": "ruby",
      "aws_service": "s3",
      "aws_sdk_module": "aws-sdk-s3",
      "aws_op": "put_object",
      "snippet": "AwsClients.s3.put_object(bucket: bucket, key: key, body: io)",
      "confirmed_in_manifest": true,
      "ai_overlap": false,
      "via_wrapper": "AwsClients.s3"
    }
  ]
}
```

**Required fields per call_site entry:** `file`, `line`, `language`, `aws_service`, `aws_sdk_module`, `aws_op`, `snippet`, `confirmed_in_manifest`, `ai_overlap`.

**Optional fields:** `via_wrapper` (set when the call goes through a project-owned wrapper module, e.g. `AwsClients.s3`).

**Empty result:** If `call_sites` would be empty (no AWS SDK references in the project), DO NOT write the file. Report to the parent orchestrator: "No AWS SDK call sites detected. No source-code rewrite needed."

---

## Output Validation Checklist — aws-sdk-usage.json

- `summary` field is present and is a non-null object (never `null`, never absent)
- `summary.total_call_sites` is a non-null integer and equals `len(call_sites)`
- `summary.by_service` is a non-null object (may be empty `{}` only when `total_call_sites == 0`) and its values sum to `total_call_sites`
- `summary.by_language` is a non-null object (may be empty `{}` only when `total_call_sites == 0`) and its values sum to `total_call_sites`
- `summary.languages` is a non-null array (may be empty `[]` only when `total_call_sites == 0`) and equals the deduped key set of `by_language`
- Every `call_sites[i].aws_service` is one of the documented values in the per-language tables (or a TODO-stub language has been opened upstream)
- Every `call_sites[i].file` is a project-relative path (no leading `/` and no leading `./`)
- Every `call_sites[i].line` is a positive integer
- `wrapper_detected.present` is `true` whenever the discover scan found a single-file SDK wrapper module; the `file` field is set in that case

---

## Design Phase Integration

The Design phase's new Step 4.7 (see `references/phases/design/design-infra.md`) consumes `aws-sdk-usage.json` and produces `sdk-migration-plan.json` per the mapping table in `references/design-refs/sdk-mapping.md`.

The Generate phase's new Step N (see `references/phases/generate/generate-artifacts-infra.md`) consumes `sdk-migration-plan.json` and emits one unified-diff patch per source file under `$MIGRATION_DIR/code-patches/`, plus a roll-up `$MIGRATION_DIR/code-migration-summary.md` listing every patch and its risk level.

---

## Scope Boundary

**This phase covers Discover & Analysis ONLY.**

FORBIDDEN — Do NOT include ANY of:

- GCP service names, recommendations, or equivalents (those live in the Design phase mapping)
- Migration strategies, timelines, or rewritten code (those live in the Generate phase)
- Cost estimates

**Your ONLY job: inventory AWS SDK call sites. Nothing else.**
