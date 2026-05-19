# Category B — Configuration Gaps + Category C — Compute Model

This file covers two related categories:

- **Category B** — Configuration gaps for billing-source inventories (factual questions to fill inferred data)
- **Category C** — Compute model questions (platform and traffic pattern decisions)

---

## Category B — Configuration Gaps (Billing-Only Mode)

_Fire when:_ `billing-profile.json` exists AND `aws-resource-inventory.json` does NOT exist (billing-only mode).
_Skip when:_ `aws-resource-inventory.json` exists (Terraform/IaC/CloudFormation provides configuration directly).

These fill factual gaps that billing data alone cannot answer. Answers update the inventory understanding — they do not produce design constraints directly.

Each question fires only when the matching `aws_service_type` appears in `billing-profile.json -> services[]`:

- **RDS HA**: Single-AZ or Multi-AZ? _(fire if `aws_db_instance` in billing services)_
  > Default: assume Single-AZ is intentional.
- **ECS service count**: How many distinct services? _(fire if `aws_ecs_service` in billing services)_
  > Default: assume 1 service.
- **ElastiCache memory size**: How much memory (GB)? _(fire if `aws_elasticache_cluster` in billing services)_
  > Default: estimate from usage amount.
- **Lambda runtime**: Node.js, Python, Go, or Java? _(fire if `aws_lambda_function` in billing services)_
  > Default: assume Node.js.

Record Category B answers in `metadata.inventory_clarifications`.

---

## Category C — Compute Model (If Compute Resources Present)

_Fire when:_ Compute resources present (ECS, Lambda, EKS, EC2).

---

## Q8 — What is your preferred container orchestration approach on GCP?

_Fire when:_ ECS or EKS present AND Q5 did not already decide container orchestration via early exit. Skip when: Q5 already resolved (e.g., Q5 = GKE Autopilot) or no ECS/EKS in inventory.

**Rationale:** When container services are detected in AWS, the user's preference for GKE Autopilot, GKE Standard, or Cloud Run determines the target compute platform. This is subjective and cannot be inferred from IaC alone.

**Context for user:** When asking, frame it practically so the user gives an honest answer rather than aspirational:

- **GKE Autopilot** — Google manages everything: nodes, scaling, security patches. You deploy pods and pay per pod resource request.
- **GKE Standard** — Full Kubernetes control: custom node pools, GPU nodes, taints/tolerations, DaemonSets. More operational overhead.
- **Cloud Run** — Fully serverless containers: no cluster at all. Deploy container images, auto-scale to zero. Best for stateless HTTP services.

> Your container platform preference determines whether we recommend GKE (managed Kubernetes) or Cloud Run (serverless containers) for your migrated workloads.
>
> A) GKE Autopilot — fully managed, no node management
> B) GKE Standard — full control over nodes and configuration
> C) Cloud Run — fully serverless, no cluster management
> D) N/A — We don't use containers
> E) I don't know

| Answer         | Recommendation Impact                                                                                        |
| -------------- | ------------------------------------------------------------------------------------------------------------ |
| GKE Autopilot  | GKE Autopilot recommended — preserves Kubernetes workloads with zero node management overhead                |
| GKE Standard   | GKE Standard recommended — full control for workloads requiring custom node pools, GPUs, or DaemonSets       |
| Cloud Run      | **Strong Cloud Run recommendation** — eliminates cluster management entirely; simpler operational model      |

_Note: If Q5 already decided container orchestration (e.g., GKE Autopilot), this question is skipped._

Interpret:

```
A -> container_orchestration: "gke-autopilot" — GKE Autopilot, zero node management
B -> container_orchestration: "gke-standard" — GKE Standard, full Kubernetes control
C -> container_orchestration: "cloud-run" — Cloud Run, fully serverless containers
D -> (no constraint written — no container workloads)
E -> same as default (A) — assume GKE Autopilot for managed simplicity
```

Default: A — `container_orchestration: "gke-autopilot"`.

---

## Q9 — What is your preferred serverless compute approach for event-driven workloads?

_Fire when:_ Lambda present in inventory OR event-driven workloads detected.

**Rationale:** AWS Lambda workloads usually map to Cloud Run. Source-code functions can use Cloud Run functions; containerized services, custom runtimes, and longer-running work should use Cloud Run services or jobs. The choice affects packaging, cold start behavior, and event integration.

> Your serverless preference affects how we migrate Lambda functions. Cloud Run functions keep a function-style source deployment model, while Cloud Run services/jobs offer more flexibility with container-based deployment.
>
> A) Cloud Run functions — event-driven source functions on Cloud Run
> B) Cloud Run services/jobs — containers, custom runtimes, or longer-running work with Eventarc/Workflows
> C) I don't know

| Answer          | Recommendation Impact                                                         |
| --------------- | ----------------------------------------------------------------------------- |
| Cloud Run functions | Function-style source deployment on Cloud Run; Eventarc integration |
| Cloud Run services/jobs | Container flexibility, custom runtimes, and better fit for complex or long-running services |

Interpret:

```
A -> serverless: "cloud-run-functions" — Cloud Run functions; function-style source deployment
B -> serverless: "cloud-run" — Cloud Run services/jobs with Eventarc triggers; container flexibility
C -> same as default (B) — assume Cloud Run for flexibility
```

Default: B — `serverless: "cloud-run"`.

---

## Q10 — What machine family preference do you have for VM workloads?

_Fire when:_ EC2 instances present in inventory. Skip when: no EC2.

**Rationale:** GCP offers multiple machine families optimized for different workloads. The right choice depends on workload characteristics — general-purpose covers most needs, but compute-optimized or memory-optimized families can provide better price-performance for specific use cases.

> GCP offers different machine families optimized for different workloads. Understanding your workload helps me recommend the right family for cost and performance.
>
> A) General-purpose (E2/N2/N2D) — balanced compute, memory, and networking
> B) Compute-optimized (C2/C2D/C3) — high-performance computing, gaming, media transcoding
> C) Memory-optimized (M2/M3) — large in-memory databases, in-memory analytics
> D) Accelerator-optimized (A2/A3/G2) — ML training, GPU workloads
> E) N/A — We don't use VMs
> F) I don't know

| Answer              | Recommendation Impact                                                                     |
| ------------------- | ----------------------------------------------------------------------------------------- |
| General-purpose     | E2 (cost-optimized) or N2/N2D (balanced) machine types; standard recommendation           |
| Compute-optimized   | C2/C2D/C3 machine types; higher per-core performance                                      |
| Memory-optimized    | M2/M3 machine types; for SAP HANA, large caches, in-memory databases                      |
| Accelerator-optimized | A2/A3 with NVIDIA GPUs or G2 with L4 GPUs; for ML training and inference                 |

Interpret:

```
A -> vm_machine_family: "general-purpose" — E2/N2/N2D machine types
B -> vm_machine_family: "compute-optimized" — C2/C2D/C3 machine types
C -> vm_machine_family: "memory-optimized" — M2/M3 machine types
D -> vm_machine_family: "accelerator-optimized" — A2/A3/G2 with GPUs
E -> (no constraint written)
F -> same as default (A) — assume general-purpose
```

Default: A — `vm_machine_family: "general-purpose"`.

---

## Q11 — Are you interested in committed use discounts (CUDs) for GCP?

_Fire when:_ EC2 instances or significant compute resources present in inventory. Skip when: no EC2/compute.

**Rationale:** GCP committed use discounts offer significant savings (up to 57% for 3-year) but require commitment. Understanding interest level early determines whether CUD analysis is included in cost estimates.

> GCP committed use discounts can save up to 57% on compute costs but require a 1-year or 3-year commitment. This helps me include the right cost analysis in your migration plan.
>
> A) 1-year commitment — up to 37% discount on compute
> B) 3-year commitment — up to 57% discount on compute
> C) No commitment — prefer on-demand pricing for flexibility
> D) I don't know

| Answer          | Recommendation Impact                                                            |
| --------------- | -------------------------------------------------------------------------------- |
| 1-year          | Include 1-year CUD pricing in estimates; resource-based CUD recommendations      |
| 3-year          | Include 3-year CUD pricing in estimates; maximum savings analysis                |
| No commitment   | On-demand pricing only; recommend sustained use discounts (automatic)             |

Interpret:

```
A -> committed_use: "1yr" — 1-year CUD analysis included; up to 37% savings
B -> committed_use: "3yr" — 3-year CUD analysis included; up to 57% savings
C -> (no constraint written — on-demand pricing; sustained use discounts apply automatically)
D -> same as default (C) — assume no commitment for flexibility
```

Default: C — no constraint (on-demand with automatic sustained use discounts).
