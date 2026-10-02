# j1-serverless-task-api — GCP reference implementation

Hand-built, known-good migration target for `user-journey-tests/aws/j1-serverless-task-api` (fictional task-reminder service). Agents under test must NOT be shown this directory.

## AWS → GCP mapping

| AWS (journey) | GCP (this reference) | Notes |
|---|---|---|
| API Gateway HTTP API + Lambda `sta-tasks-api` | Cloud Run function `sta-tasks-api` (public) | function URL replaces the API GW edge |
| Lambda `sta-export-worker` + EventBridge cron | Cloud Run function (auth) + Cloud Scheduler `sta-daily-export` (OIDC) | 00:00 UTC preserved |
| Lambda `sta-cleanup-legacy` (no trigger) | Cloud Run function, **no scheduler** | orphan preserved deliberately |
| DynamoDB `sta-tasks` + GSI | Firestore Native, **named DB `sta-tasks`**, collection `sta-tasks` | named DB keeps the shared project clean; status filter needs no composite index |
| S3 `sta-exports-*` | GCS `sta-exports-<project>` | exports/YYYY-MM-DD.json layout preserved |
| IAM per-function roles | Function runtime SA (default compute) + scheduler invoker SA | invoker limited to `roles/run.invoker` |

## Deploy

```bash
cd deploy
./00-vars.sh && ./01-data.sh && ./02-functions.sh && ./03-scheduler.sh
```

`02-functions.sh` prints `BASE_URL=` — the tasks-api function URL.

## Parity check

Run the journey's own smoke test, unmodified:

```bash
../../../../user-journey-tests/aws/j1-serverless-task-api/scripts/smoke-test.sh "$BASE_URL"
```

`/admin/aws-check` keeps its AWS-named check keys (`dynamodb`, `s3`, `sts`) mapped to Firestore/GCS/ADC pings so the same assertions hold.

## Teardown

```bash
./deploy/99-teardown.sh   # gated; FORCE_TEARDOWN=1 to skip prompt
```
