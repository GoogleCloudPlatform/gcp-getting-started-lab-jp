# j3-event-driven-fanout: photo pipeline (fictional) migration test bed

Realistic test material for AWS→GCP migration evaluations. The workload owner is a fictional photo-sharing app whose upload post-processing pipeline — built in 2021, original team long gone — runs fully event-driven in ap-northeast-1, described in [`architecture.md`](./architecture.md). Difficulty tier: **medium**.

## What's in here

| Subdirectory | Purpose | Used by |
|---|---|---|
| `sam/` | One SAM template (`Transform: AWS::Serverless-2016-10-31`) for every resource | Authoritative source for the AWS deploy AND for a migration tool's discovery scan |
| `app/` | Node 22 function code + the `awsClients.mjs` SDK funnel | Bundled per-function by `scripts/deploy.sh` into `build/` (generated, never edited) |
| `scripts/` | `deploy.sh`, `seed.sh`, `smoke-test.sh`, `teardown.sh` | Run locally; all source `~/.aws/journeys.env` and guard on `EXPECTED_ACCOUNT_ID` |
| `.migration/` | Created by a migration skill at runtime — not committed | Skill phase outputs |
| `.iteration-log/` | One subdirectory per evaluation run | Observation logs |

## No sam CLI required

The template is plain CloudFormation with the Serverless transform. Deploy uses `aws cloudformation package` (uploads the `CodeUri` bundles) + `aws cloudformation deploy --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM CAPABILITY_AUTO_EXPAND` (expands the transform server-side). `scripts/deploy.sh` does all of it.

## Out-of-scope dependencies

- **An external analytics vendor**: pulls ingest metrics via the cross-account role `edf-vendor-analytics-role` from their AWS account `999988887777`. Their side is not modeled here.
- **PagerDuty**: the moderation-alerts hook was decommissioned in 2023; the SNS topic remains (see architecture.md).
- **The mobile/web uploader**: simulated by `seed.sh` / `smoke-test.sh` dropping objects into `incoming/`.

## Deployment

```bash
aws sts get-caller-identity        # confirm the journeys lab account
./scripts/deploy.sh                # bundle + package + deploy the stack
./scripts/seed.sh                  # 2 PNGs + 1 text file into incoming/
./scripts/smoke-test.sh aws
```

## Verification

`scripts/smoke-test.sh aws|gcp` (provider-arg mode — this journey has no HTTP edge): uploads a uniquely-keyed fixture, polls the photo store for its metadata row, checks the `thumbnails/` copy, and (aws) asserts the DLQ is empty. The same script, unmodified, is the acceptance test for any migrated deployment.

## Running the migration skill (Claude Code)

```bash
cd user-journey-tests/aws/j3-event-driven-fanout
claude --plugin-dir ../../../features/migration-to-gcp
# In the session: type "migrate from AWS to GCP"
```

Outputs land in `.migration/<MMDD-HHMM>/`.

## Resource tagging

Every resource carries `Owner=migration-test`, `CostCenter=test-journeys`, `AutoTeardown=<from env>`, `Journey=j3-event-driven-fanout`. Find them later:
`aws resourcegroupstaggingapi get-resources --tag-filters Key=Journey,Values=j3-event-driven-fanout --region ap-northeast-1`

## Cleanup

```bash
./scripts/teardown.sh   # gated; FORCE_TEARDOWN=1 to skip the prompt
```
