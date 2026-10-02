# j1-serverless-task-api: task-reminder service (fictional) migration test bed

Realistic test material for AWS→GCP migration evaluations. The workload owner is a fictional 12-person Tokyo startup whose internal task/reminder API — built in 2023 by a single engineer — runs fully serverless in ap-northeast-1, described in [`architecture.md`](./architecture.md). Difficulty tier: **easy**.

## What's in here

| Subdirectory | Purpose | Used by |
|---|---|---|
| `terraform/` | Terraform for every AWS resource in architecture.md's diagram | Authoritative source for the AWS deploy AND for a migration tool's discovery scan |
| `app/` | Python 3.12 Lambda handlers + the `aws_clients.py` SDK funnel | Zipped per-function by `scripts/deploy.sh`; `build/` is generated, never edited |
| `scripts/` | `deploy.sh`, `seed.sh`, `smoke-test.sh`, `teardown.sh` | Run locally; all source `~/.aws/journeys.env` and guard on `EXPECTED_ACCOUNT_ID` |
| `.migration/` | Created by a migration skill at runtime — not committed | Skill phase outputs |
| `.iteration-log/` | One subdirectory per evaluation run | Observation logs |

## Out-of-scope dependencies

- **Slack notifications** (architecture.md mentions a webhook): stubbed out — the export worker only writes to S3; no external calls.
- **The old ops EC2 box**: decommissioned 2024-11. Referenced in code comments only; not modeled here.

## Deployment

```bash
aws sts get-caller-identity        # confirm the journeys lab account
./scripts/deploy.sh                # terraform apply + prints BASE_URL
./scripts/seed.sh                  # 5 deterministic tasks
./scripts/smoke-test.sh "$BASE_URL"
```

## Verification

`scripts/smoke-test.sh BASE_URL` runs 5 checks (health, create, list, complete, `/admin/aws-check` dependency dashboard) and exits nonzero on any failure. The same script, unmodified, is the acceptance test for any migrated deployment of this workload.

## Running the migration skill (Claude Code)

```bash
# Interactive run against this test bed
cd user-journey-tests/aws/j1-serverless-task-api
claude --plugin-dir ../../../features/migration-to-gcp
# In the session: type "migrate from AWS to GCP"

# Headless run (time-boxed harness iteration)
claude --plugin-dir ../../../features/migration-to-gcp -p "migrate from AWS to GCP" \
  --permission-mode acceptEdits
```

The skill's outputs land in `.migration/<MMDD-HHMM>/`.

## Resource tagging

Every resource carries `Owner=migration-test`, `CostCenter=test-journeys`, `AutoTeardown=<from env>`, `Journey=j1-serverless-task-api`. Find them later:
`aws resourcegroupstaggingapi get-resources --tag-filters Key=Journey,Values=j1-serverless-task-api --region ap-northeast-1`

## Cleanup

```bash
./scripts/teardown.sh   # gated; FORCE_TEARDOWN=1 to skip the prompt
```
