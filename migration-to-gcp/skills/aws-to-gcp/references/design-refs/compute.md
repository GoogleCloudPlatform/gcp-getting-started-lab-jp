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

| AWS Service         | GCP                             | Blocker                                                                                                              |
| ------------------- | ------------------------------- | -------------------------------------------------------------------------------------------------------------------- |
| Lambda              | Cloud Run functions             | Work actually needs longer than request-oriented serverless execution -> use Cloud Run jobs or Batch                  |
| ECS (Fargate)       | Cloud Run                       | GPU workload or >8 vCPU or >32 GB memory -> use GKE or Compute Engine                                               |
| Lambda              | Cloud Run functions             | Runtime or packaging not supported by source functions -> use Cloud Run service with a custom container               |
| EKS                 | GKE                             | Custom CRI incompatible -> manual workaround or Cloud Run                                                            |
| Any                 | App Engine                      | **Prefer Cloud Run** (default), Cloud Run functions (event-driven source functions), or GKE (K8s required) for stronger ecosystem integration. |

## Signals (Decision Criteria)

### ECS (Fargate) / Elastic Beanstalk

- **Always-on** or **cold-start sensitive** -> Cloud Run (min-instances=1)
- **Stateless microservice** -> Cloud Run service
- **HTTP-only** + **container-native** -> Cloud Run preferred (better dev/prod parity)

### Lambda

- **Event-driven source-code function** + supported runtime -> Cloud Run functions with Eventarc trigger
- **Custom runtime, container package, framework app, or HTTP service** -> Cloud Run service
- **Batch/long-running unit of work** -> Cloud Run jobs or Batch
- **Always-on or cold-start sensitive** -> Cloud Run service with `min_instances`

### EC2 (VMs)

- **Always-on workload** -> Compute Engine (committed use discounts or on-demand based on cost sensitivity)
- **Batch/periodic jobs** -> Compute Engine with Managed Instance Group (scale to 0 in dev)
- **Windows-only workload** -> Compute Engine (Cloud Run does not run Windows containers)

### EKS

- **Kubernetes orchestration** required -> GKE
- **No K8s requirement** + **microservices** -> Cloud Run (simpler, no cluster overhead)

### Auto Scaling Group

- **EC2-backed auto scaling** -> Managed Instance Group (MIG) with autoscaler
- **Predictive scaling** -> MIG with predictive autoscaling

## 6-Criteria Rubric

Apply in order; first match wins:

1. **Eliminators**: Does AWS config violate GCP constraints? If yes: switch to alternative
2. **Operational Model**: Managed (Cloud Run, Cloud Run functions) vs Self-Hosted (Compute Engine, GKE)?
   - Prefer managed unless: Always-on + high baseline cost -> Compute Engine
3. **User Preference**: From `preferences.json`: `design_constraints.kubernetes`, `design_constraints.cost_sensitivity`?
   - If `kubernetes = "gke-managed"` -> GKE (preserves K8s investment)
   - If `kubernetes = "cloud-run"` -> Cloud Run (simpler managed containers)
   - If `cost_sensitivity` present and high -> prefer Cloud Run (lower operational cost)
4. **Feature Parity**: Does AWS config require GCP-unsupported features?
   - Example: Fargate with Graviton (ARM) -> Cloud Run supports ARM via Ampere Altra (T2A machine type)
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
