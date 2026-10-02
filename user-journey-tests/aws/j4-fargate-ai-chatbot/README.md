# j4-fargate-ai-chatbot: the support desk (fictional) migration test bed

This directory is **realistic test material for the `migration-to-gcp` skill** in this repository. It models "the support desk (fictional)", a support-desk SaaS at the pilot site that bolted an AI FAQ assistant onto its desk product in 2025 — one containerized FastAPI service (`fac-api`) in AWS ap-northeast-1, described in [`architecture.md`](./architecture.md).

Difficulty: **medium** — small resource count, but it exercises the AI migration path (Amazon Bedrock model calls via the Converse API) alongside NoSQL persistence, object storage, and containerized compute.

## What's in here

| Path              | Purpose                                                                                   | Used by                                                              |
| ----------------- | ----------------------------------------------------------------------------------------- | -------------------------------------------------------------------- |
| `terraform/`      | Authoritative, deployable IaC for every AWS resource in architecture.md's diagram          | AWS deploy AND the skill's Discover phase                            |
| `app/`            | Real FastAPI app: chat with an LLM assistant, conversation persistence, transcript archive | Built into the Docker image by `scripts/deploy.sh`; runs on Fargate  |
| `scripts/`        | `deploy.sh`, `seed.sh`, `smoke-test.sh`, `teardown.sh`                                     | Operator / harness orchestration                                     |
| `.migration/`     | Created by the skill at runtime — do not commit, do not gitignore                          | Phase outputs: resource inventory, target design, generated IaC      |
| `.iteration-log/` | One subdirectory per harness iteration                                                     | Observation logs and transcripts for the outer iteration loop        |

## Out-of-scope dependencies

These appear in `architecture.md` but are NOT modeled as AWS resources here:

- **Support-desk front-end (fictional)** (mermaid Internet subgraph): the SaaS UI that support agents use. Simulated by `scripts/seed.sh` and plain `curl` against the API.
- **Amazon Bedrock foundation model** (Nova Micro): a fully managed model consumed through the `apac.amazon.nova-micro-v1:0` cross-region inference profile — there is no model infrastructure to deploy, only IAM permissions and the runtime API calls in `app/llm.py`.

## Deployment

```bash
# Pre-flight: ~/.aws/journeys.env must define EXPECTED_ACCOUNT_ID and
# AUTOTEARDOWN_DATE. Every script sources it and aborts on account mismatch.
aws sts get-caller-identity   # confirm the right account before any create

./scripts/deploy.sh           # terraform apply + image build/push + rollout
                              # prints BASE_URL=http://<task-public-ip>:8000

./scripts/seed.sh   "$BASE_URL"   # 3 deterministic FAQ conversations
./scripts/smoke-test.sh "$BASE_URL"   # PASS/FAIL per check, nonzero exit on failure
```

There is no load balancer: `deploy.sh` resolves the running task's public IP and prints it as `BASE_URL`. **The IP changes on every deployment** — re-run `deploy.sh` (or re-resolve the task ENI) after any rollout.

### Deployment notes (lab account)

- `deploy.sh` exports `TF_VAR_llm_mode=stub`. Bedrock **model-invocation quotas are zero in this harness's lab account**, so live `converse()` calls would throttle; the deployed instance therefore runs the app's deterministic stub reply path. Everything else — persistence, archiving, health checks, and the real Bedrock *control-plane* ping on `/admin/aws-check` — is exercised for real. In the customer's production posture `LLM_MODE=live` (the Terraform default) and replies come from Nova Micro.
- Costs are near-zero at idle: one 0.25 vCPU Fargate task, PAY_PER_REQUEST DynamoDB, and a private S3 bucket with a 90-day expiry.

## Verification endpoints

- `GET /health` — dependency substatus JSON (never raises).
- `GET /admin/aws-check` — per-service SDK ping dashboard `{s3, dynamodb, bedrock, sts}`; `scripts/smoke-test.sh` asserts all four are `ok`.

## Running the migration skill (Claude Code)

```bash
# Interactive run against this test bed
cd user-journey-tests/aws/j4-fargate-ai-chatbot
claude --plugin-dir ../../../features/migration-to-gcp
# In the session: type "migrate from AWS to GCP"

# Headless run (time-boxed harness iteration)
claude --plugin-dir ../../../features/migration-to-gcp -p "migrate from AWS to GCP" \
  --permission-mode acceptEdits
```

The skill's outputs land in `.migration/<MMDD-HHMM>/`.

## Resource tagging convention

Every AWS resource carries (via the provider's `default_tags`):

- `Owner=migration-test`
- `CostCenter=test-journeys`
- `AutoTeardown=YYYY-MM-DD` (from `AUTOTEARDOWN_DATE` at deploy time)
- `Journey=j4-fargate-ai-chatbot`

To find every resource later: `aws resourcegroupstaggingapi get-resources --tag-filters Key=Journey,Values=j4-fargate-ai-chatbot --region ap-northeast-1`.

## Teardown

```bash
./scripts/teardown.sh   # type "yes" at the prompt, or FORCE_TEARDOWN=1
```

Reverse-order destroy via the Terraform graph; the default VPC and its subnets are referenced as data sources and are never touched.
