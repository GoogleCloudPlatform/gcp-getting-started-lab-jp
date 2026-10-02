# Compute Services Design Rubric

**Applies to:** EC2, Lambda, ECS (Fargate), EKS, Auto Scaling Groups

**Table lookup first:** Check `fast-path.md` **Direct Mappings** for this Terraform type. **EC2 (`aws_instance`) IS in Direct Mappings** (confidence `deterministic` -> `google_compute_instance`). **Lambda, ECS/Fargate, EKS, and Auto Scaling Groups are not** in Direct Mappings -- go straight to the rubric below (confidence will be **`inferred`**).

## Companion skill (google/skills)

Before applying this rubric or shaping the GCP-side configuration:

- **Cloud Run targets** (ECS/Fargate, most Lambda mappings, EC2 re-platformed to Cloud Run): read the latest version of **`cloud-run-basics`** at `~/.claude/skills/cloud-run-basics/SKILL.md` (fallback `~/.agents/skills/cloud-run-basics/SKILL.md`). Use its canonical templates for CPU/memory, concurrency, min/max instances, secrets, IAM, and VPC connector wiring as the source of truth.
- **GKE targets** (EKS, EC2 fleets requiring Kubernetes): read the latest version of **`gke-basics`** at the same paths. Use its Autopilot vs Standard guidance, Workload Identity setup, and node-pool recipes.
- **Compute Engine / Managed Instance Group targets** (EC2 preserved as VMs): no dedicated google/skill -- use this file's rubric directly.

This rubric is the AWS -> GCP **decision** layer (eliminators, signals, 6 criteria). The google/skill is the **how** layer for the chosen GCP target. If neither google/skill is installed, fall back to the configuration tips below and add a `warnings[]` entry per the protocol in `references/shared/companion-skills.md`.

## Eliminators (Hard Blockers)

| AWS Service   | GCP                 | Blocker                                                                                                                                                                                                                                                                                                                                                                                 |
| ------------- | ------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Lambda        | Cloud Run functions | Work actually needs longer than request-oriented serverless execution -> use Cloud Run jobs or Batch                                                                                                                                                                                                                                                                                    |
| ECS (Fargate) | Cloud Run           | Non-GPU service needing >8 vCPU or >32 GB memory -> use GKE or Compute Engine. GPU alone is NOT a blocker anymore: Cloud Run GPUs are GA (services and jobs; single GPU per instance, instance-based billing, limited GPU types — verify the current supported set at cloud.google.com/run/docs/configuring/services/gpu). Multi-GPU or unsupported GPU types -> GKE or Compute Engine. |
| Lambda        | Cloud Run functions | Runtime or packaging not supported by source functions -> use Cloud Run service with a custom container                                                                                                                                                                                                                                                                                 |
| EKS           | GKE                 | Custom CRI incompatible -> manual workaround or Cloud Run                                                                                                                                                                                                                                                                                                                               |
| Any           | App Engine          | **Prefer Cloud Run** (default), Cloud Run functions (event-driven source functions), or GKE (K8s required) for stronger ecosystem integration.                                                                                                                                                                                                                                          |

## Signals (Decision Criteria)

### ECS (Fargate) / Elastic Beanstalk

- **Hosts a detected agent workload** (`ai-workload-profile.json` -> `agent_workloads[].aws_host` matches this resource) -> do NOT map with this rubric; the design-infra Pass 2 agent gate applies (`design-refs/agent-runtime.md`)
- **Pull-based queue worker with NO inbound traffic** (Sidekiq / Shoryuken / Kafka consumer / Pub/Sub-pull worker; recognizable as an `aws_ecs_service` with no load-balancer target group and no service-registry consumers) -> **Cloud Run worker pool** (GA; purpose-built for always-on non-HTTP consumers). Do NOT wrap it in a Cloud Run _service_ — that forces a dummy HTTP listener and a request autoscaler that never sees requests. Worker pools scale manually by default; use Cloud Run External Metrics Autoscaling (CREMA) for queue-depth-based autoscaling. Terraform: `google_cloud_run_v2_worker_pool`.
- **Always-on** or **cold-start sensitive** HTTP service -> Cloud Run service (min-instances=1)
- **Stateless microservice** (serves requests) -> Cloud Run service
- **HTTP-only** + **container-native** -> Cloud Run preferred (better dev/prod parity)

### Lambda

- **Hosts a detected agent workload** (`ai-workload-profile.json` -> `agent_workloads[].aws_host` matches this resource) -> do NOT map with this rubric; the design-infra Pass 2 agent gate applies (`design-refs/agent-runtime.md`)
- **Event-driven source-code function** + supported runtime -> Cloud Run functions with Eventarc trigger
- **Custom runtime, container package, framework app, or HTTP service** -> Cloud Run service
- **Batch/long-running unit of work** -> Cloud Run jobs or Batch
- **Always-on or cold-start sensitive** -> Cloud Run service with `min_instances`

### EC2 (VMs)

- **Hosts a detected agent workload** (`ai-workload-profile.json` -> `agent_workloads[].aws_host` matches this resource) -> do NOT map with this rubric; the fast-path `aws_instance` Conditions exception + design-infra Pass 2 agent gate apply (`design-refs/agent-runtime.md`)
- **Always-on workload** -> Compute Engine (committed use discounts or on-demand based on cost sensitivity)
- **Batch/periodic jobs** -> Compute Engine with Managed Instance Group (scale to 0 in dev)
- **Windows-only workload** -> Compute Engine (Cloud Run does not run Windows containers)

### EKS

- **Kubernetes orchestration** required -> GKE
- **No K8s requirement** + **microservices** -> Cloud Run (simpler, no cluster overhead)

### Auto Scaling Group

- **EC2-backed auto scaling** -> Managed Instance Group (MIG) with autoscaler
- **Predictive scaling** -> MIG with predictive autoscaling

## Sizing from access-pattern data (MANDATORY)

After the rubric selects the GCP target service (Cloud Run, Compute Engine, GKE), size it from `preferences.json.design_constraints.access_pattern_data` rather than 1:1-mapping the source IaC. Design Step 1.5 already loaded this into in-memory state.

**Lookup order per resource:**

1. `access_pattern_data[<aws_address>]` — per-resource data (path A or B from Q_SIZING2)
2. `access_pattern_data["cluster:<cluster_name>"]` — cluster-level data (path C)
3. Conservative defaults — 2× source IaC sizing + emit `# TODO: tune based on actual traffic — sizing chosen from conservative defaults` comment inline in generated Terraform (path D or fallback)

**Cloud Run sizing formulas** (apply only when path A/B/C data is present):

| GCP field       | Formula                                                                                                                                                                                                                                         | Source metric                                              |
| --------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------- |
| `concurrency`   | `min(80, ceil(avg_request_duration_ms / 50))`                                                                                                                                                                                                   | `TargetResponseTime.avg` (ms) from `AWS/ApplicationELB`    |
| `min_instances` | `max(1, ceil(avg_rps / concurrency))`                                                                                                                                                                                                           | `RequestCountPerTarget.avg` / 60 from `AWS/ApplicationELB` |
| `max_instances` | `ceil(peak_rps / concurrency * 1.5)` (1.5× headroom)                                                                                                                                                                                            | `RequestCountPerTarget.max` / 60                           |
| `cpu` (vCPU)    | `ceil(fargate_cpu / 1024 * (peak_cpu_pct / 70))` rounded to nearest Cloud Run-supported size. Supported values (as strings): `"0.5"`, `"1"`, `"2"`, `"4"`, `"6"`, `"8"`. Fractional values `0.08`–`0.99` are also allowed (in 0.01 increments). | Fargate task `cpu` × `CPUUtilization.max` / 70             |
| `memory` (GiB)  | `ceil(fargate_memory / 1024 * (peak_memory_pct / 70))` rounded to nearest Cloud Run-supported size, expressed as `"<N>Gi"` or `"<N>Mi"`                                                                                                         | Fargate task `memory` × `MemoryUtilization.max` / 70       |

The `/70` divisor leaves 30% headroom on top of observed peak — standard right-sizing buffer. If `peak_cpu_pct < 30`, the formula will under-shoot Fargate's allocation; cap at `cpu >= "1"` to satisfy Cloud Run's CPU-always-allocated constraint when `min_instance_count >= 1`.

**Terraform field-name mapping** (the skill uses intermediate names in `gcp_config`; Generate translates to Terraform): `min_instances` → `template.scaling.min_instance_count`, `max_instances` → `template.scaling.max_instance_count`, `concurrency` → `template.max_instance_request_concurrency`, `cpu` → `template.containers[].resources.limits.cpu` (string), `memory` → `template.containers[].resources.limits.memory` (string with `"Gi"`/`"Mi"` suffix). Generate phase MUST use these Terraform field names in the emitted HCL.

**Compute Engine / Managed Instance Group sizing** (analogous): use `peak_cpu_pct` from `AWS/EC2 CPUUtilization` to choose a smaller/larger machine type than the AWS instance. Use `GroupDesiredCapacity.max` from `AWS/AutoScaling` to set MIG `target_size` and autoscaler `max_replicas`.

**GKE Autopilot sizing**: per-pod `resources.requests.cpu/memory` from the same `(peak / 70)` formula applied to the pod's container limits. Autopilot scales node pools automatically; no node-pool sizing needed.

**When path D (conservative defaults) is chosen** OR a specific metric is missing from path A/B/C data:

- Cloud Run: `min_instances = source desired_count * 2`, `max_instances = source desired_count * 4`, `concurrency = 80`, `cpu = max(1, ceil(fargate_cpu / 1024))`, `memory = max(0.5, ceil(fargate_memory / 1024))`.
- Emit comment inline in generated Terraform: `# TODO: tune based on actual traffic — sizing chosen from conservative defaults (Clarify Q_SIZING1 = D)`.
- For specific missing metrics with other paths: `# TODO: tune <field> — no <metric_name> in CloudWatch data (resource may be idle or recently created)`.

**Record `sizing_source` per resource** in `gcp-design.json` (per the Step 1.5 audit-trail rule): `"access_pattern_data: <aws_address>"`, `"access_pattern_data: cluster:<cluster_name>"`, or `"conservative_defaults"`.

## 6-Criteria Rubric

Apply in order; first match wins:

1. **Eliminators**: Does AWS config violate GCP constraints? If yes: switch to alternative
2. **Operational Model**: Managed (Cloud Run, Cloud Run functions) vs Self-Hosted (Compute Engine, GKE)?
   - Prefer managed unless: Always-on + high baseline cost -> Compute Engine
3. **User Preference**: From `preferences.json`: `design_constraints.container_orchestration` (the key Clarify actually writes — values `gke-autopilot`, `gke-standard`, `cloud-run`, `gke-autopilot-or-cloud-run`; the last means per-workload choice, apply the rest of this rubric):
   - If `container_orchestration = "gke-autopilot"` or `"gke-standard"` -> GKE in that mode (preserves K8s investment)
   - If `container_orchestration = "cloud-run"` -> Cloud Run (simpler managed containers)
   - If `design_constraints.aws_monthly_spend` indicates strong cost sensitivity -> prefer Cloud Run / worker pools (scale-to-zero, lower operational cost)
4. **Feature Parity**: Does AWS config require GCP-unsupported features?
   - Example: Fargate with Graviton (ARM) -> Cloud Run does NOT run ARM containers (the runtime contract requires linux/amd64; multi-arch manifests must include linux/amd64). Plan an amd64 rebuild/cross-compile of the image, or keep ARM by targeting GKE Arm node pools / Compute Engine T2A instances.
5. **Cluster Context**: Are other resources in this cluster using GKE/Compute Engine/Cloud Run?
   - Prefer same platform (affinity)
6. **Simplicity**: Fewer resources = higher score
   - Cloud Run (1 service) > Compute Engine (N services for MIG + monitoring)

## Examples

### Example 1: ECS Fargate (stateless API)

- AWS: `aws_ecs_service` + `aws_ecs_task_definition` (cpu=512, memory=1024, desired_count=2)
- Signals: HTTP, stateless, always-on, containerized
- Criterion 1 (Eliminators): PASS (512 CPU / 1024 MB within Cloud Run limits)
- Criterion 2 (Operational Model): Cloud Run preferred (managed, serverless containers)
- -> **GCP: Cloud Run (1 vCPU, 1 GiB memory, min-instances=2)**
- Confidence: `inferred` (rubric-based -- Fargate is not in fast-path)

### Example 2a: Lambda (event processor, source function)

- AWS: `aws_lambda_function` (runtime=python3.11, timeout=540)
- Signals: Event-driven, 540s = 9 minutes (< 15min limit)
- Criterion 1 (Eliminators): PASS on timeout (540s < 900s)
- Criterion 2 (Operational Model): Cloud Run functions preferred for event-driven source functions
- -> **GCP: Cloud Run functions with Eventarc trigger**
- Confidence: `inferred`

### Example 2b: Lambda (batch processor that may outgrow Lambda limits)

- AWS: `aws_lambda_function` (runtime=python3.11, timeout=900)
- Signals: Event-driven, 900s = 15 minutes (at Lambda limit), may need longer batch processing after migration
- Criterion 1 (Eliminators): Batch/long-running risk -> Cloud Run jobs if processing should not be tied to an HTTP request
- Criterion 2 (Operational Model): Cloud Run jobs remain managed and container-friendly
- -> **GCP: Cloud Run jobs triggered by Eventarc/Workflows**
- Note: If the function is truly short-running and source-code oriented, use Cloud Run functions instead.
- Confidence: `inferred`

### Example 3: EC2 (background job)

- AWS: `aws_instance` (instance_type=t3.medium, availability_zone=us-east-1a, user_data=...)
- Signals: Periodic batch job (inferred from user_data), always-on
- Criterion 1 (Eliminators): PASS
- Criterion 2 (Operational Model): Compute Engine (explicit compute control)
- Criterion 3 (User Preference): If `design_constraints.aws_monthly_spend` indicates cost sensitivity, prefer auto-scaling -> Compute Engine + MIG (scale to 0)
- -> **GCP: Compute Engine e2-medium + Managed Instance Group (min=0 in dev)**
- Confidence: `deterministic` (EC2 is in Direct Mappings -> Compute Engine)

### Example 4: EKS Cluster

- AWS: `aws_eks_cluster` (version=1.28, node_groups=[managed])
- Signals: Kubernetes workload, managed node groups
- Criterion 1 (Eliminators): PASS
- Criterion 2 (Operational Model): GKE (managed Kubernetes)
- -> **GCP: GKE Autopilot (managed nodes, auto-scaling)**
- Confidence: `inferred`

### Example 5: Auto Scaling Group

- AWS: `aws_autoscaling_group` (min_size=2, max_size=10, launch_template=t3.large)
- Signals: Horizontal scaling, EC2-based
- Criterion 1 (Eliminators): PASS
- -> **GCP: Managed Instance Group with Autoscaler (min=2, max=10, e2-standard-2)**
- Confidence: `inferred`

## Output Schema

```json
{
  "aws_type": "aws_ecs_service",
  "aws_address": "example-service",
  "aws_config": {
    "cpu": 512,
    "memory": 1024,
    "desired_count": 2
  },
  "gcp_service": "Cloud Run",
  "gcp_config": {
    "cpu": "1",
    "memory": "1Gi",
    "min_instances": 2,
    "region": "us-central1"
  },
  "confidence": "inferred",
  "rationale": "Rubric: Fargate (stateless, containerized) -> Cloud Run (managed, serverless containers)",
  "rubric_applied": [
    "Eliminators: PASS",
    "Operational Model: Managed preferred",
    "User Preference: N/A",
    "Feature Parity: Full",
    "Cluster Context: Cloud Run affinity",
    "Simplicity: Cloud Run (1 service)"
  ]
}
```
