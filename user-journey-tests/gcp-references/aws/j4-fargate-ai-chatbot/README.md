# j4-fargate-ai-chatbot — known-good GCP reference

Hand-made migration target for `user-journey-tests/aws/j4-fargate-ai-chatbot/` (the fictional support desk's `fac-api` FAQ assistant). This is the **answer key**: it is never referenced from inside the journey directory, and agents under test must not be able to find it from their cwd.

Project `aws-migration-501814` (override with `GCP_PROJECT`), region `asia-northeast1`. Every `gcloud` invocation passes `--project` explicitly because the box's default project is different.

## AWS → GCP mapping

| AWS (journey) | GCP (this reference) | Notes |
| --- | --- | --- |
| ECS Fargate service `fac-api-service` (1 task, public task IP, no LB) | Cloud Run service `fac-api` | `--allow-unauthenticated`, min 0 / max 2; Cloud Run's managed HTTPS URL **fixes the journey's direct-IP wart** — the URL is stable across deploys |
| ECR `fac-api` | Artifact Registry `fac/fac-api` | Docker format, asia-northeast1 |
| DynamoDB `fac-conversations` (PK `conversation_id`, SK `ts`) | Firestore **named database** `fac-conversations` (Native mode) | Layout: `conversations/<id>/turns/<ts>`; the app's `TABLE_NAME` env var becomes the database id |
| S3 `fac-transcripts-<account>` (private, SSE-S3, 90d expiry) | GCS `fac-transcripts-<project>` | Uniform bucket-level access, public-access prevention, 90-day lifecycle on `transcripts/`; Google-managed encryption is the default |
| Bedrock Nova Micro via `apac.amazon.nova-micro-v1:0` (Converse API) | Vertex AI Gemini `gemini-2.5-flash-lite` via google-genai (verified 2026-07) | `MODEL_ID` env-overridable; Vertex calls use the `global` endpoint (`VERTEX_LOCATION`), other resources stay regional |
| IAM task role (DynamoDB CRUD, S3 object rw, bedrock invoke) | SA `fac-api-sa` | `roles/datastore.user` + `roles/aiplatform.user` (project), `roles/storage.objectAdmin` (bucket-scoped) |
| STS `get_caller_identity` ping | ADC token refresh (SA email) | Backs the `sts` key on `/admin/aws-check` |
| CloudWatch Logs `/ecs/fac-api` | Cloud Logging | Automatic for Cloud Run, no setup step |
| SG `fac-api-sg` (tcp/8000 open) | Cloud Run public ingress | Platform-managed TLS; no port to open |

`app-overlay/` holds the only four files that differ from the journey app: `main.py`, `llm.py`, `gcp_clients.py` (replaces `aws_clients.py`, which `build.sh` deletes from the image), and `requirements.txt`. The Dockerfile is reused unchanged.

## Deploy order

```bash
cd user-journey-tests/gcp-references/aws/j4-fargate-ai-chatbot

./deploy/01-enable-apis.sh         # run, AR, firestore, storage, aiplatform, iam
./deploy/02-service-account.sh     # fac-api-sa + datastore.user, aiplatform.user
./deploy/03-firestore.sh           # named DB fac-conversations (asia-northeast1)
./deploy/04-bucket.sh              # bucket + 90d lifecycle + objectAdmin grant
./deploy/05-artifact-registry.sh   # docker repo "fac"
./deploy/06-build-image.sh         # journey app + overlay -> build + push (../build.sh)
./deploy/07-cloud-run.sh           # deploy; prints BASE_URL
```

All steps are idempotent (describe-or-create / create-or-revise); re-run any of them freely. `00-vars.sh` is sourced by every step and makes no cloud calls.

## Parity verification

The journey's smoke test must pass **unmodified** against the Cloud Run URL printed by step 07:

```bash
BASE_URL=$(gcloud run services describe fac-api --region asia-northeast1 \
  --project "${GCP_PROJECT:-aws-migration-501814}" --format 'value(status.url)')

../../../../user-journey-tests/aws/j4-fargate-ai-chatbot/scripts/seed.sh       "$BASE_URL"   # optional
../../../../user-journey-tests/aws/j4-fargate-ai-chatbot/scripts/smoke-test.sh "$BASE_URL"
```

- `/admin/aws-check` keeps its four AWS-named keys (`s3`, `dynamodb`, `bedrock`, `sts`) as a stable schema; behind them the overlay pings GCS (object list), Firestore (limit-1 read), Vertex (`count_tokens` on `MODEL_ID` — free, proves model access), and ADC identity.
- This side runs `LLM_MODE=live` (Vertex quota is available here), while the AWS deploy runs `stub`; the smoke test asserts `llm_mode` is *present*, not any particular value, so it passes on both. Flip this side to stub parity with `gcloud run services update fac-api --update-env-vars LLM_MODE=stub --region asia-northeast1 --project <project>` — stub replies are byte-identical across clouds.
- Note: `seed.sh` sources `~/.aws/journeys.env` for its account guard; it only speaks HTTP, so it works against the Cloud Run URL from the harness box unchanged.

## Teardown

```bash
./deploy/99-teardown.sh    # type "yes", or FORCE_TEARDOWN=1; reverse order, skip-if-absent
```
