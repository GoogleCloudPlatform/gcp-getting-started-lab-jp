# Category H — Workload Sizing (Access-Pattern Decision)

This file covers **Category H**, the access-pattern decision that drives every GCP sizing choice downstream. Without this, Design falls back to 1:1 source-IaC mapping or dev-tier defaults, and the resulting Cloud Run instance counts / Cloud SQL tier / Memorystore memory have no grounding in actual traffic. The user must explicitly pick one of four paths — there is no silent default.

_Fire when:_ Any compute, database, or cache resource is present in `aws-resource-inventory.json` (essentially: any non-trivial workload). Skip only when the inventory is empty.

---

## Q_SIZING1 — How should I learn how your workload is actually used today, so I can size GCP correctly?

_Fire when:_ At least one of the following resource types appears in `aws-resource-inventory.json`:

- compute: `aws_ecs_service`, `aws_lambda_function`, `aws_eks_*`, `aws_instance`, `aws_autoscaling_group`
- database: `aws_db_instance`, `aws_rds_cluster`, `aws_dynamodb_table`
- cache: `aws_elasticache_cluster`, `aws_elasticache_replication_group`
- load balancer / message queue with non-trivial throughput: `aws_lb`, `aws_kinesis_*`

**Rationale:** Cloud Run `min_instances` / `max_instances` / `concurrency`, Cloud SQL `tier`, Memorystore `memory_size_gb`, and any autoscaling configuration depend on actual traffic patterns — peak RPS, request duration, peak/avg ratio, working set size. AWS source IaC doesn't capture these (Fargate `desired_count=2` says nothing about whether the app sees 5 RPS or 5000 RPS). If the skill guesses, the user pays for over-provisioned GCP infra or hits saturation during real load. This question forces the user to commit to a sizing-data source up front so every downstream decision can be traced back to evidence.

**Context for user:** Be honest that this question shapes the entire sizing of the migrated workload. Explain the four paths so the user understands the trade-off between effort and accuracy:

- **(A) CloudWatch direct query** — Most accurate when AWS metrics are flowing. Skill runs `aws cloudwatch get-metric-statistics` for each resource, captures 7-day max/avg/p95, and feeds those into sizing formulas. Requires AWS CLI + credentials accessible from where the skill is running.
- **(B) Other observability tool** — Same idea, but you paste/export data from Datadog / New Relic / Grafana / Prometheus / Honeycomb / etc. Skill tells you which metrics matter per resource type.
- **(C) Verbal description** — You describe traffic in plain language. Useful when no metrics are available (new workload, no monitoring deployed yet, lost access to the source account).
- **(D) Conservative defaults** — Skill uses 2× source IaC for compute, dev-tier for DB, ½ GB Memorystore, and embeds `# TODO: tune based on actual traffic` comments inline in the generated Terraform. Pick this when you accept post-migration tuning as part of the cutover plan.

> I can size your GCP resources from real access patterns instead of guessing from source IaC. Pick the path that matches what's available:
>
> A) Let me query CloudWatch directly — I'll shell out to `aws cloudwatch get-metric-statistics` for each resource using your existing AWS credentials. Requires `aws` CLI on PATH, an active `AWS_PROFILE` or env credentials, and the `cloudwatch:GetMetricStatistics` + `cloudwatch:GetMetricData` IAM permissions on the source account.
> B) I have a different observability tool — Datadog, New Relic, Grafana, Prometheus, CloudWatch Container Insights, Honeycomb, or Other. You name the tool, I'll list the equivalent metric names per AWS resource type, you paste/export.
> C) I'll describe traffic patterns in text — structured form: peak RPS, avg request duration, peak/avg ratio, p95 target, peak traffic hours/day, peak DB connections, peak Redis working set size.
> D) Use conservative defaults — 2× source IaC for compute, dev-tier DB, ½ GB Memorystore. Every default gets a `# TODO: tune based on actual traffic` comment inline in generated Terraform so you can adjust post-migration.
> E) I don't know — guide me

| Answer                       | Recommendation Impact                                                                                                                |
| ---------------------------- | ------------------------------------------------------------------------------------------------------------------------------------ |
| (A) CloudWatch direct query  | Highest accuracy. Sizing formulas use real max/avg/p95. Skill will print the exact commands before running and ask for confirmation. |
| (B) Other observability tool | High accuracy if you can export equivalent metrics. Skill normalizes to the same `access_pattern_data` shape regardless of tool.     |
| (C) Verbal description       | Medium accuracy. Sizing uses what you say; assumptions documented in `MIGRATION_GUIDE.md`.                                           |
| (D) Conservative defaults    | Lowest accuracy by design — explicitly chosen. Generated Terraform carries TODO markers so you can tune after migration.             |

Interpret:

```
A -> access_pattern_source: "cloudwatch_autonomous" — skill will query CloudWatch via aws CLI during this Clarify run
B -> access_pattern_source: "observability_tool" — skill will ask which tool, then collect via paste/export
C -> access_pattern_source: "verbal" — skill will present a structured form for the user to fill
D -> access_pattern_source: "conservative_defaults" — Design uses 2x source IaC + TODO comments
E -> Show the four options again with one-paragraph explanations, then re-ask Q_SIZING1
```

Default: NONE in interactive sessions — Clarify STOPs until the user explicitly picks; D is a conscious choice, not a silent fallback. **Headless exception (SKILL.md > Headless / unattended runs):** when no interactive user is present, resolve to D (`conservative_defaults`) with `chosen_by: "headless-default"`, and surface a prominent banner in the Clarify summary, `MIGRATION_GUIDE.md`, and the run README: "Sizing used conservative defaults — no access-pattern data was collected (headless run). Re-run Clarify interactively for metric-based sizing."

Write to `preferences.json.design_constraints.access_pattern_source` with `value` and `chosen_by: "user"`.

---

## Q_SIZING2 — Collect the access-pattern data (follow-up, branches on Q_SIZING1 answer)

This is not one question — it's the data-collection workflow that follows Q_SIZING1. Take the path matching the user's Q_SIZING1 answer.

### Path A — Autonomous CloudWatch query

This path runs the AWS CLI from inside the skill's Bash tool. The skill is reaching into the user's AWS account to read metrics — announce the plan and get explicit confirmation before any AWS API call.

**Step A.1 — Pre-flight.** Before any `aws` command, present the plan and confirm:

```
About to query AWS CloudWatch using your current credentials:
  AWS account: <from `aws sts get-caller-identity` → Account>
  AWS region:  <from $AWS_REGION or `aws configure get region` or "ap-northeast-1" if neither set>
  Resources I'll query (<N> total):
    - aws_ecs_service.example-web-production (4 metrics)
    - aws_rds_cluster.example-prod-aurora (6 metrics)
    - aws_elasticache_replication_group.example-prod-redis (5 metrics)
    ...
  Time window: last 7 days
  IAM permissions needed: cloudwatch:GetMetricStatistics, cloudwatch:GetMetricData

Confirm to proceed [y/N]:
```

If user declines or says "n": STOP and OFFER to fall back to path B, C, or D — do NOT silently degrade to defaults.

**Step A.2 — Run queries per resource.** Use the metric matrix below. For each AWS resource type detected in inventory, run the listed `aws cloudwatch get-metric-statistics` commands. Aggregate by Maximum + Average + p95.0 over 7 days, period = 3600s.

**CRITICAL: `--statistics` and `--extended-statistics` are mutually exclusive in a single call.** AWS rejects requests that specify both. You must issue **two separate calls per metric** and merge the results in memory:

```bash
# Call 1 — basic stats (Maximum + Average)
aws cloudwatch get-metric-statistics \
  --namespace AWS/ECS \
  --metric-name CPUUtilization \
  --dimensions Name=ServiceName,Value=<service_name> Name=ClusterName,Value=<cluster_name> \
  --start-time $(date -u -d '7 days ago' +%Y-%m-%dT%H:%M:%SZ) \
  --end-time   $(date -u +%Y-%m-%dT%H:%M:%SZ) \
  --period 3600 \
  --statistics Maximum Average \
  --output json

# Call 2 — extended (p95) — DO NOT combine with --statistics
aws cloudwatch get-metric-statistics \
  --namespace AWS/ECS \
  --metric-name CPUUtilization \
  --dimensions Name=ServiceName,Value=<service_name> Name=ClusterName,Value=<cluster_name> \
  --start-time $(date -u -d '7 days ago' +%Y-%m-%dT%H:%M:%SZ) \
  --end-time   $(date -u +%Y-%m-%dT%H:%M:%SZ) \
  --period 3600 \
  --extended-statistics p95.0 \
  --output json
```

Merge per-datapoint: Call 1 gives `Datapoints[].Maximum` + `Average`; Call 2 gives `Datapoints[].ExtendedStatistics["p95.0"]`. Match by `Datapoints[].Timestamp` and combine. Alternative: instead of two calls per metric, use one `aws cloudwatch get-metric-data` call (the newer API) with a `MetricDataQuery[]` array that includes both `Stat: "Maximum"`, `Stat: "Average"`, and `Stat: "p95"` queries — but `get-metric-statistics` with two calls is the simplest path and works on every awscli version.

### Metric matrix per AWS resource type (REQUIRED — used by both Path A and Path B)

| AWS resource type                                                       | CloudWatch namespace | Required metrics                                                                                                | Required dimensions                             |
| ----------------------------------------------------------------------- | -------------------- | --------------------------------------------------------------------------------------------------------------- | ----------------------------------------------- |
| `aws_ecs_service`                                                       | `AWS/ECS`            | `CPUUtilization`, `MemoryUtilization`                                                                           | `ClusterName`, `ServiceName`                    |
| `aws_ecs_service` (via target group)                                    | `AWS/ApplicationELB` | `RequestCountPerTarget`, `TargetResponseTime`, `HTTPCode_Target_2XX_Count`, `HTTPCode_Target_5XX_Count`         | `TargetGroup`, `LoadBalancer`                   |
| `aws_rds_cluster` / `aws_db_instance`                                   | `AWS/RDS`            | `CPUUtilization`, `DatabaseConnections`, `ReadIOPS`, `WriteIOPS`, `FreeableMemory`, `BufferCacheHitRatio`       | `DBClusterIdentifier` or `DBInstanceIdentifier` |
| `aws_elasticache_cluster` / `aws_elasticache_replication_group` (Redis) | `AWS/ElastiCache`    | `CPUUtilization`, `EngineCPUUtilization`, `BytesUsedForCache`, `CurrItems`, `NetworkBytesIn`, `NetworkBytesOut` | `CacheClusterId` (per-node)                     |
| `aws_lb` (ALB)                                                          | `AWS/ApplicationELB` | `RequestCount`, `TargetResponseTime`, `ActiveConnectionCount`, `NewConnectionCount`                             | `LoadBalancer`                                  |
| `aws_lambda_function`                                                   | `AWS/Lambda`         | `Invocations`, `Duration`, `Errors`, `ConcurrentExecutions`, `Throttles`                                        | `FunctionName`                                  |
| `aws_kinesis_firehose_delivery_stream`                                  | `AWS/Firehose`       | `IncomingBytes`, `IncomingRecords`, `DeliveryToS3.Success`, `DeliveryToS3.DataFreshness`                        | `DeliveryStreamName`                            |
| `aws_kinesis_stream`                                                    | `AWS/Kinesis`        | `IncomingBytes`, `IncomingRecords`, `GetRecords.IteratorAgeMilliseconds`, `WriteProvisionedThroughputExceeded`  | `StreamName`                                    |
| `aws_dynamodb_table`                                                    | `AWS/DynamoDB`       | `ConsumedReadCapacityUnits`, `ConsumedWriteCapacityUnits`, `SuccessfulRequestLatency`, `ThrottledRequests`      | `TableName`                                     |
| `aws_autoscaling_group`                                                 | `AWS/AutoScaling`    | `GroupDesiredCapacity`, `GroupInServiceInstances`                                                               | `AutoScalingGroupName`                          |

**Step A.3 — Parse + record.** For each metric, you'll have two response sets (Call 1 = basic, Call 2 = extended). For the basic set, take `max(Datapoints[].Maximum)` and `mean(Datapoints[].Average)`. For the extended set, take `max(Datapoints[].ExtendedStatistics["p95.0"])`. Write a structured entry to `preferences.json.design_constraints.access_pattern_data[<aws_address>]` keyed by AWS address:

```json
"access_pattern_data": {
  "aws_ecs_service.example-web-production": {
    "source": "cloudwatch_autonomous",
    "window": "7d",
    "fetched_at": "2026-05-19T12:00:00Z",
    "metrics": {
      "CPUUtilization":         { "max": 78.2, "avg": 22.5, "p95": 65.1 },
      "MemoryUtilization":      { "max": 81.0, "avg": 54.3, "p95": 73.2 },
      "RequestCountPerTarget":  { "max": 4321, "avg": 432,  "p95": 3210 },
      "TargetResponseTime":     { "max": 1.23, "avg": 0.18, "p95": 0.92 }
    },
    "evidence": "aws cloudwatch get-metric-statistics --namespace AWS/ECS --metric-name CPUUtilization ... → Datapoints[0]: {Maximum: 78.2, Average: 22.5, ExtendedStatistics: {p95.0: 65.1}}"
  }
}
```

The `evidence` field MUST contain the actual command (first 100 chars) + the first line of response so Design can verify the data is grounded. This mirrors the pricing-evidence pattern from `estimate-infra.md` — if the user audits, they can trace every sizing number to a real CloudWatch call.

**Step A.4 — On failure, offer fallback (do NOT silently degrade).** Common failures:

- `aws` CLI not on PATH → "AWS CLI not installed. Install AWS CLI v2 via the official platform installer (docs.aws.amazon.com/cli — `pip install awscli` installs the legacy v1 and is no longer the recommended method), or fall back to path B/C/D?"
- `Unable to locate credentials` → "No AWS credentials found. Set `AWS_PROFILE` or run `aws configure`, then re-confirm. Or fall back to path B/C/D."
- `AccessDenied` on `cloudwatch:GetMetricStatistics` → "Your IAM principal can't read CloudWatch metrics. Attach a policy with `cloudwatch:GetMetricStatistics` + `cloudwatch:GetMetricData`, OR fall back to path B/C/D."
- Specific resource returns empty `Datapoints[]` → "No data for `<resource>` in the last 7 days — was it recently created or idle? Pick: skip this resource (use conservative defaults for just this one), extend the window to 30 days, or fall back to path C/D for sizing."

Each failure must be visible to the user with a remediation option. NEVER silently fill the resource with defaults.

### Path B — Other observability tool

**Step B.1 — Ask which tool:**

> Which observability tool do you use? I'll list the equivalent metric names so you can export/paste them.
>
> A) Datadog
> B) New Relic
> C) Grafana / Prometheus
> D) CloudWatch Container Insights
> E) Honeycomb
> F) Other — please name it

**Step B.2 — Translate the metric matrix above into the tool's metric names** using this translation table for the common ones:

| AWS metric                          | Datadog                                | New Relic                           | Prometheus                                     | Container Insights              | Honeycomb               |
| ----------------------------------- | -------------------------------------- | ----------------------------------- | ---------------------------------------------- | ------------------------------- | ----------------------- |
| `AWS/ECS CPUUtilization`            | `aws.ecs.cpuutilization`               | `aws.ecs.CPUUtilization`            | `aws_ecs_cpuutilization_average`               | `ContainerInsights.CpuUtilized` | (varies by integration) |
| `AWS/RDS DatabaseConnections`       | `aws.rds.database_connections`         | `aws.rds.DatabaseConnections`       | `aws_rds_database_connections_average`         | n/a                             | (varies)                |
| `AWS/ElastiCache BytesUsedForCache` | `aws.elasticache.bytes_used_for_cache` | `aws.elasticache.BytesUsedForCache` | `aws_elasticache_bytes_used_for_cache_average` | n/a                             | (varies)                |
| `AWS/ApplicationELB RequestCount`   | `aws.applicationelb.request_count`     | `aws.alb.RequestCount`              | `aws_applicationelb_request_count_sum`         | n/a                             | (varies)                |

For F (Other): ask the user to map the AWS metric names to whatever their tool calls them, then proceed.

**Step B.3 — Collect values from user.** Print a fill-in template per resource (the same shape as Path A's output) and ask the user to paste max/avg/p95 over 7 days. Validate the JSON they paste; if malformed, show the expected shape and re-ask.

**Step B.4 — Record in `access_pattern_data` with `source: "observability_tool"` + `tool_name: "<datadog|newrelic|...>"`.** The `evidence` field for this path is the user's paste verbatim (truncated to ~200 chars) so Design can verify it parsed correctly.

### Path C — Verbal description

Print a structured form per primary cluster (clusters identified in `aws-resource-clusters.json`) and ask the user to fill each field. Use plain prose, not JSON — the user is describing, not structured-input.

```
For cluster "<cluster_name>" (which contains <list of compute/db/cache resources>):

  Peak requests per second (your busiest minute):   ____
  Average requests per second (typical hour):       ____
  Peak / average ratio:                              ____ (e.g. 10 if peak is 10x average)
  Average request duration (ms):                    ____
  p95 latency target (ms):                          ____
  Peak traffic hours per day (e.g. business hours): ____
  Peak concurrent DB connections:                   ____
  Peak Redis working set size (GB):                 ____ (skip if no Redis)
```

Record per-cluster (not per-resource) under `access_pattern_data["cluster:<cluster_name>"]` with `source: "verbal"`. Each field stored as a number. Skip any field the user can't answer with a `null` value — Design then uses conservative defaults for just that field with a TODO comment in the generated Terraform.

### Path D — Conservative defaults

No data collection needed. Set `access_pattern_data: {}` (empty object) and `access_pattern_source: "conservative_defaults"`. Design uses 2× source IaC capacity for compute, dev-tier for DB, and ½ GB for Memorystore. Every default emitted into generated Terraform gets an inline comment: `# TODO: tune based on actual traffic — sizing chosen from conservative defaults in Clarify Q_SIZING1`.

---

## Records produced

After Q_SIZING1 + Q_SIZING2:

- `preferences.json.design_constraints.access_pattern_source` — enum: `"cloudwatch_autonomous" | "observability_tool" | "verbal" | "conservative_defaults"` with `value` + `chosen_by: "user"`
- `preferences.json.design_constraints.access_pattern_tool_name` — string (only when source == `observability_tool`)
- `preferences.json.design_constraints.access_pattern_data` — object keyed by `aws_address` (paths A/B) or `cluster:<name>` (path C), or empty `{}` for path D. Each entry has `source`, `window` (paths A/B), `fetched_at`, `metrics` (object of metric_name → {max, avg, p95}) or per-cluster fields (path C), and `evidence`.

## Design integration (binding rule)

Design phase Step 1.5 reads `preferences.json.design_constraints.access_pattern_source`. If missing, Design STOPs with: "Clarify must capture sizing-data source via Q_SIZING1 before Design can run. Re-run Clarify." Design's compute/database/cache sizing rubrics consult `access_pattern_data` per-resource before applying any default. See `references/design-refs/compute.md` "Sizing from access-pattern data" and the equivalent sections in `database.md` and the Memorystore design-ref.

## Validation Checklist (sizing-specific)

- [ ] `preferences.json.design_constraints.access_pattern_source` is one of: `"cloudwatch_autonomous"`, `"observability_tool"`, `"verbal"`, `"conservative_defaults"` (NOT missing, NOT null).
- [ ] If `access_pattern_source == "observability_tool"`, `access_pattern_tool_name` is non-empty.
- [ ] If `access_pattern_source != "conservative_defaults"`, `access_pattern_data` is non-empty.
- [ ] Every entry in `access_pattern_data` has `source`, `fetched_at`, and `evidence` populated.
- [ ] For Path A entries, the `evidence` string contains the literal `aws cloudwatch get-metric-statistics` substring — proof the call was actually made and not recalled.
