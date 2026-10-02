# j3-event-driven-fanout — GCP reference implementation

Hand-built, known-good migration target for `user-journey-tests/aws/j3-event-driven-fanout` (fictional event-driven photo pipeline). Agents under test must NOT be shown this directory.

## AWS → GCP mapping

| AWS (journey) | GCP (this reference) | Notes |
|---|---|---|
| S3 `edf-uploads-*` (incoming/thumbnails/reports) | GCS `edf-uploads-<project>` | same prefix layout |
| S3 event → SNS `edf-uploads` → SQS `edf-thumbnails-q` (+DLQ) | **Eventarc** GCS object-finalized trigger → Cloud Run function | the whole SNS/SQS chain collapses into the trigger; retry semantics come from Cloud Run/Eventarc redelivery, no explicit DLQ |
| Lambda `edf-worker` (nodejs22.x, SQS batch) | Cloud Run function `edf-worker` (nodejs22, CloudEvent) | `incoming/` filter moves into code (trigger covers the bucket) |
| Lambda `edf-digest` + EventBridge rate(1 day) | Cloud Run function (HTTP, auth) + Cloud Scheduler `edf-nightly-digest` (OIDC) | |
| SNS `edf-moderation-alerts` (no subscribers) | Pub/Sub topic `edf-moderation-alerts` (**no subscription**) | the void is preserved faithfully |
| DynamoDB `edf-photos` | Firestore Native, **named DB `edf-photos`** | doc id = URL-encoded object key (Firestore ids can't contain `/`) |
| IAM `edf-vendor-analytics-role` (trusts 999988887777) | **out of scope** | vendor cross-account read; GCP equivalent would be an IAM conditional grant to the vendor's identity — documented, not deployed |

## Deploy

```bash
cd deploy
./00-vars.sh && ./01-data.sh && ./02-functions.sh && ./03-scheduler.sh
```

`02-functions.sh` includes the Eventarc prerequisite grants (GCS service agent → `pubsub.publisher`, compute SA → `eventarc.eventReceiver`).

## Parity check

```bash
../../../../user-journey-tests/aws/j3-event-driven-fanout/scripts/smoke-test.sh gcp
```

Unmodified journey smoke test in provider mode: upload fixture → Firestore metadata document → `thumbnails/` copy.

## Teardown

```bash
./deploy/99-teardown.sh   # gated; FORCE_TEARDOWN=1 to skip prompt
```
