# j2-three-tier-web: online shop (fictional) migration test bed

This directory is **realistic test material for the `migration-to-gcp` skill** in this repository. It models "the online shop" (fictional), a Nagoya used-book shop whose web store was built by a contractor in 2016 on a classic VM stack in AWS ap-northeast-1 and has barely been touched since, described in [`architecture.md`](./architecture.md).

Difficulty: **medium** — no containers anywhere: a CloudFront-fronted ALB, an Auto Scaling group of two plain EC2 instances that bootstrap themselves in UserData, RDS PostgreSQL, S3, Secrets Manager, and CloudWatch. The migration has to reason about VM bootstrap scripts and a five-stack CloudFormation set with cross-stack exports, not a Dockerfile.

## What's in here

| Path              | Purpose                                                                                          | Used by                                                            |
| ----------------- | ------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------ |
| `cloudformation/` | Authoritative, deployable IaC — five stacks with fixed names wired together by `Fn::ImportValue`  | AWS deploy AND the skill's Discover phase                          |
| `app/`            | Real Flask storefront: catalog pages from PostgreSQL, covers streamed from S3, ops endpoints      | Packed into `app.tar.gz` by `scripts/deploy.sh`; pulled at boot by every ASG instance |
| `scripts/`        | `deploy.sh`, `seed.sh`, `smoke-test.sh`, `teardown.sh`, plus `make-covers.py` (deterministic PNGs) | Operator / harness orchestration                                   |
| `.migration/`     | Created by the skill at runtime — do not commit, do not gitignore                                 | Phase outputs: resource inventory, target design, generated IaC    |
| `.iteration-log/` | One subdirectory per harness iteration                                                            | Observation logs and transcripts for the outer iteration loop      |

## Out-of-scope dependencies

These appear in `architecture.md` but are NOT modeled as AWS resources here:

- **Third-party marketplace sync** (retired 2019): the used-book marketplace the shop once synced inventory to. Only its API-key secret (`ttw-legacy-api-key`) survives; the app displays the secret's status on `/admin/aws-check` and never reads the value.
- **Shoppers**: simulated with plain `curl` / `scripts/smoke-test.sh` against the ALB or CloudFront domain.

## Deployment

```bash
# Pre-flight: ~/.aws/journeys.env must define EXPECTED_ACCOUNT_ID and
# AUTOTEARDOWN_DATE. Every script sources it and aborts on account mismatch.
aws sts get-caller-identity   # confirm the right account before any create

./scripts/deploy.sh           # five stacks in dependency order + bundle upload
                              # prints BASE_URL (ALB) and CDN_URL (CloudFront)
```

First deploy takes ~20-25 minutes (RDS dominates). Stack names are **load-bearing** — the templates import each other's exports by the fixed names `ttw-security-stack`, `ttw-data-stack`, `ttw-compute-stack`.

There is no separate data-seeding step: every instance runs `db.bootstrap()` at boot (schema + the same 12 deterministic books, `ON CONFLICT DO NOTHING`). `scripts/seed.sh` only re-uploads the bundle/covers; add `--refresh` to roll the ASG onto a new bundle.

```bash
./scripts/smoke-test.sh "$BASE_URL"     # PASS/FAIL per check, nonzero exit on failure
./scripts/smoke-test.sh "$CDN_URL"      # same checks through CloudFront
```

## Verification endpoints

- `GET /health` — dependency substatus JSON (`database`, `s3`), never raises.
- `GET /admin/aws-check` — per-service SDK ping dashboard `{s3, secret_db, secret_legacy, database, cloudwatch, sts}`; `scripts/smoke-test.sh` asserts all six are `ok`.

## Running the migration skill (Claude Code)

```bash
# Interactive run against this test bed
cd user-journey-tests/aws/j2-three-tier-web
claude --plugin-dir ../../../features/migration-to-gcp
# In the session: type "migrate from AWS to GCP"

# Headless run (time-boxed harness iteration)
claude --plugin-dir ../../../features/migration-to-gcp -p "migrate from AWS to GCP" \
  --permission-mode acceptEdits
```

The skill's outputs land in `.migration/<MMDD-HHMM>/`.

## Resource tagging convention

Every taggable AWS resource carries:

- `Owner=migration-test`
- `CostCenter=test-journeys`
- `AutoTeardown=YYYY-MM-DD` (from `AUTOTEARDOWN_DATE` at deploy time)
- `Journey=j2-three-tier-web`

To find every resource later: `aws resourcegroupstaggingapi get-resources --tag-filters Key=Journey,Values=j2-three-tier-web --region ap-northeast-1`.

## Teardown

```bash
./scripts/teardown.sh   # type "yes" at the prompt, or FORCE_TEARDOWN=1
```

Empties the assets bucket, then deletes the five stacks in reverse order with waiters (the CloudFront disable+delete step is the slow one, 10-20 minutes). The default VPC and its subnets are only ever referenced as parameters and are never touched.
