# Category A — Global/Strategic (Always Fires)

These foundational constraints gate everything downstream — region selection, service catalog, data residency, organization structure, compute platform, availability topology, and migration strategy.

Present questions with a conversational tone and brief context explaining why each matters.

---

## Q1 — Where are your users located?

**Rationale:** Geography drives GCP region selection and CDN strategy. It does NOT by itself justify multi-region architecture or Cloud Spanner — those decisions require understanding write patterns and RTO/RPO requirements from Q6 (uptime) and Q7 (IaC tool). Recommending multi-region based on geography alone would over-engineer most architectures and significantly increase cost.

> I need to understand your user base to recommend the right GCP region and CDN strategy.
>
> A) Single region (e.g., US-only, EU-only)
> B) Multi-region (2–3 regions, e.g., US + EU)
> C) Global (users worldwide, latency critical)
> D) I don't know

| Answer        | Recommendation Impact                                                                                                                                                                                                                     |
| ------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Single region | Deploy in closest GCP region to users; standard Cloud DNS routing                                                                                                                                                                          |
| Multi-region  | Primary region closest to majority; Cloud CDN for static assets and API caching; Cloud DNS latency-based routing — multi-region infrastructure deferred to Q6                                                                             |
| Global        | Primary region by largest user concentration; Cloud CDN globally distributed; Cloud DNS geolocation routing — Cloud Spanner and multi-region compute only if Q6 = Catastrophic AND write latency is a confirmed hard requirement |

Interpret:

```
A -> target_region: "<closest GCP region to AWS source region — derived via clarify.md Step 2 item 1 + the mapping table below>"; chosen_by: "derived" if auto-derived without user input, "user" if user explicitly chose A
B -> target_region: "<closest GCP region to AWS source region>", replication: "cross-region"
C -> target_region: "<closest GCP region to AWS source region>", replication: "cross-region", cdn: "required"
D -> same as default (A)
```

> **DO NOT** hardcode `us-east1` (or any literal region) as the answer to Q1. The value MUST come from the discovery-aware derivation in `clarify.md` Step 2 item 1 applied against the mapping table below.

**AWS-to-GCP Region Mapping Reference (authoritative — used by `clarify.md` Step 2 item 1):**

| AWS Region        | GCP Region              |
| ----------------- | ----------------------- |
| us-east-1         | us-east1                |
| us-east-2         | us-east4                |
| us-west-1         | us-west2                |
| us-west-2         | us-west1                |
| eu-west-1         | europe-west2            |
| eu-west-2         | europe-west2            |
| eu-west-3         | europe-west9            |
| eu-central-1      | europe-west3            |
| eu-central-2      | europe-west12           |
| eu-north-1        | europe-north1           |
| eu-south-1        | europe-southwest1       |
| ap-northeast-1    | asia-northeast1         |
| ap-northeast-2    | asia-northeast3         |
| ap-northeast-3    | asia-northeast2         |
| ap-southeast-1    | asia-southeast1         |
| ap-southeast-2    | australia-southeast1    |
| ap-southeast-3    | asia-southeast2         |
| ap-south-1        | asia-south1             |
| ap-south-2        | asia-south2             |
| ap-east-1         | asia-east2              |
| ca-central-1      | northamerica-northeast1 |
| ca-west-1         | northamerica-northeast2 |
| sa-east-1         | southamerica-east1      |
| me-south-1        | me-central1             |
| me-central-1      | me-central1             |
| af-south-1        | africa-south1           |

**Fallback:** If the AWS source region is not in the table above, fall back to `us-east1` AND surface a warning so the user can override. Do **not** silently default to `us-east1` for known regions — that is a bug. The discovery-aware derivation in `clarify.md` Step 2 item 1 is the authoritative source of the default; pick literal `us-east1` ONLY when the source AWS region is `us-east-1` (or unknown).

Default: A — single region, closest GCP region to AWS source region in inventory (derived from this table). When auto-derived without user input, set `chosen_by: "derived"`.

---

## Q2 — Do you have any compliance or regulatory requirements?

**Rationale:** Compliance requirements gate entire service categories and regions. A HIPAA customer cannot use the same architecture as an unconstrained startup.

> Compliance requirements determine which GCP services, regions, and configurations are available to you. This gates the entire architecture.
>
> A) None — No specific compliance requirements
> B) SOC 2 / ISO 27001 — Security and availability standards
> C) PCI DSS — Payment card data handling
> D) HIPAA — Healthcare data
> E) FedRAMP / Government — Federal compliance
> F) GDPR / Data residency — EU data sovereignty requirements
> G) CCPA / CPRA — California Consumer Privacy Act / California Privacy Rights Act
> H) I don't know
>
> _(Multiple selections allowed)_

| Answer            | Recommendation Impact                                                                                                                      |
| ----------------- | ------------------------------------------------------------------------------------------------------------------------------------------ |
| None              | Full service catalog available, any region                                                                                                 |
| SOC 2 / ISO 27001 | Cloud Audit Logs, Security Command Center enabled by default; encryption at rest required via Cloud KMS                                    |
| PCI DSS           | Dedicated VPC with strict segmentation, Cloud Armor required, no shared tenancy for cardholder data, specific Cloud SQL encryption config   |
| HIPAA             | BAA-eligible services only, encryption in transit and at rest mandatory, specific logging requirements, us-east1/us-central1 preferred      |
| FedRAMP           | Assured Workloads required, FedRAMP-compliant environment, limited service catalog                                                         |
| GDPR              | EU regions required (europe-west1, europe-west3), data residency constraints, no cross-region replication outside EU without explicit consent |
| CCPA / CPRA       | Consumer privacy posture: data inventory, access/deletion workflows, opt-out of sale/sharing where applicable, retention minimization, encryption and audit logging (Cloud Audit Logs); prefer documenting data flows and subprocessors — confirm target regions with legal review |

Interpret:

```
A -> (no constraint written — full service catalog available, any region)
B -> compliance: ["soc2"] — Cloud Audit Logs, Security Command Center enabled; encryption at rest required
C -> compliance: ["pci"] — Dedicated VPC, Cloud Armor required, strict segmentation
D -> compliance: ["hipaa"] — BAA-eligible services only, encryption mandatory, us-east1/us-central1 preferred
E -> compliance: ["fedramp"] — Assured Workloads required, FedRAMP-compliant environment
F -> compliance: ["gdpr"] — EU regions required (europe-west1, europe-west3), data residency constraints
G -> compliance: ["ccpa"] — CCPA/CPRA: logging, retention, consumer-request readiness; document data flows; align region/subprocessor choices with legal review
H -> same as default (A) — no constraint assumed; verify with compliance team before production
```

Default: A — no constraint.

---

## Q3 — Approximately how much are you spending on AWS per month in total?

**Rationale:** Total AWS spend is the primary input for sizing GCP equivalents and determines committed use discount eligibility. Also provides a sanity check for cost estimates when billing data is not uploaded.

> Total AWS spend helps me estimate GCP committed use discount eligibility and provides a cost baseline for the migration plan.
>
> A) < $1,000/month
> B) $1,000–$5,000/month
> C) $5,000–$20,000/month
> D) $20,000–$100,000/month
> E) > $100,000/month
> F) I don't know

**Billing enrichment:** If `billing-profile.json` exists, show:

> Your billing data shows ~$[total_monthly_spend]/month. Does this match your expectation?

| Answer                 | Recommendation Impact                                                                                                        |
| ---------------------- | ---------------------------------------------------------------------------------------------------------------------------- |
| < $1,000/month         | GCP free tier and startup credits eligibility; cost estimates use conservative ranges                                         |
| $1,000–$5,000/month    | Committed use discounts at basic tier; mid-range estimates                                                                     |
| $5,000–$20,000/month   | Committed use discounts analysis; resource-based CUDs recommended                                                             |
| $20,000–$100,000/month | Significant committed use discounts; spend-based CUDs; GCP Partner consultation eligible                                     |
| > $100,000/month       | Enterprise agreement eligibility; dedicated migration support; GCP Premium Support tier                                      |

Interpret:

```
A -> aws_monthly_spend: "<$1K" — GCP free tier and startup credits eligibility
B -> aws_monthly_spend: "$1K-$5K" — Committed use discounts at basic tier
C -> aws_monthly_spend: "$5K-$20K" — Committed use discount analysis; resource-based CUDs
D -> aws_monthly_spend: "$20K-$100K" — Spend-based CUDs; GCP Partner consultation eligible
E -> aws_monthly_spend: ">$100K" — Enterprise agreement eligibility; dedicated migration support
F -> same as default (B)
```

Default: B — `aws_monthly_spend: "$1K-$5K"`.

---

## Q4 — How would you like to organize your GCP projects?

**Rationale:** GCP's organizational model (projects, folders, organization) differs fundamentally from AWS's account structure. Understanding the desired structure early determines IAM configuration, billing, and resource isolation patterns.

> GCP organizes resources into projects, which can be grouped under folders and an organization node. This affects IAM, billing, and resource isolation.
>
> A) Single project — all resources in one project (simplest for small teams)
> B) Multi-project — separate projects per environment (dev/staging/prod)
> C) Multi-project with shared VPC — centralized networking across projects
> D) I don't know

| Answer                      | Recommendation Impact                                                                                                |
| --------------------------- | -------------------------------------------------------------------------------------------------------------------- |
| Single project              | Simplest setup; all resources and IAM in one project; suitable for small teams or single-environment deployments      |
| Multi-project               | Separate projects for dev/staging/prod; independent IAM and billing per project; standard enterprise pattern         |
| Multi-project + shared VPC  | Centralized networking team manages VPC; service projects consume shared subnets; best for large organizations        |

Interpret:

```
A -> gcp_org_structure: "single-project" — All resources in one project
B -> gcp_org_structure: "multi-project" — Separate projects per environment
C -> gcp_org_structure: "multi-project-shared-vpc" — Centralized networking with shared VPC
D -> same as default (A) — assume single project for simplicity
```

Default: A — `gcp_org_structure: "single-project"`.

---

## Q5 — What is your preferred approach for running containerized workloads?

**Rationale:** Kubernetes preference is an early decision point that shapes the entire compute architecture. GKE Autopilot eliminates node management entirely, GKE Standard provides full control, and Cloud Run offers a fully serverless container platform.

> Your container platform preference shapes the entire compute architecture. GKE Autopilot manages nodes automatically, GKE Standard gives full control, and Cloud Run provides fully serverless containers.
>
> A) GKE Autopilot — fully managed, no node management
> B) GKE Standard — full control over nodes and configuration
> C) Cloud Run — fully serverless containers, no cluster management
> D) I don't know

| Answer         | Recommendation Impact                                                                                                |
| -------------- | -------------------------------------------------------------------------------------------------------------------- |
| GKE Autopilot  | **Immediate GKE Autopilot recommendation** — Google manages nodes, security patching, scaling. Skip Q8.              |
| GKE Standard   | Full Kubernetes control with custom node pools, GPUs, taints/tolerations                                             |
| Cloud Run      | Serverless containers with automatic scaling to zero; best for stateless HTTP services                               |

Interpret:

```
A -> container_orchestration: "gke-autopilot" — EARLY EXIT: skip Q8
B -> container_orchestration: "gke-standard" — Full control over Kubernetes configuration
C -> container_orchestration: "cloud-run" — Fully serverless containers
D -> same as default (A) — assume GKE Autopilot for managed simplicity
```

Default: A — `container_orchestration: "gke-autopilot"`.

---

## Q6 — If your application went down unexpectedly right now, what would happen?

**Rationale:** Availability requirements drive database engine selection, deployment topology, and whether multi-zone is mandatory. Cloud Spanner and multi-region compute are only recommended when Catastrophic is selected AND Q1 confirms global users — both signals are required.

**Context for user:** When asking, include these descriptions so the user can self-select accurately:

- **Inconvenient** — users can wait, no revenue impact (e.g., internal tool, dev/staging environment, hobby project)
- **Significant Issue** — users notice and complain, some revenue impact, but workarounds exist (e.g., B2B SaaS with email support SLA)
- **Mission-Critical** — direct revenue loss per minute of downtime, SLA obligations to customers, needs fast recovery (e.g., e-commerce checkout, paid API)
- **Catastrophic** — regulatory, safety, or major financial consequences; every minute of downtime is measurable loss (e.g., financial transactions, healthcare systems, real-time trading)

> Availability requirements drive database engine selection, deployment topology, and whether multi-zone is mandatory.
>
> A) INCONVENIENT — Users can wait, brief outages tolerable (5–30 min)
> B) SIGNIFICANT ISSUE — Customers frustrated, revenue loss
> C) MISSION-CRITICAL — Cannot tolerate outages, SLA violations
> D) CATASTROPHIC — Regulatory, safety, or major financial consequences per minute of downtime
> E) I don't know

| Answer            | Recommendation Impact                                                                                                                                                                                                                                  |
| ----------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Inconvenient      | Single-zone Cloud SQL acceptable, standard GKE/Cloud Run deployment, no special HA requirements                                                                                                                                                        |
| Significant Issue | Multi-zone Cloud SQL (regional) required, Cloud Load Balancing with health checks, managed instance groups                                                                                                                                              |
| Mission-Critical  | Cloud SQL with HA (regional), multi-zone mandatory, Cloud Load Balancing health checks; single-region with fast failover is sufficient for most mission-critical workloads                                                                              |
| Catastrophic      | If Q1 = Global: Cloud Spanner (global strong consistency) + multi-region GKE + Cloud DNS failover routing; If Q1 = Single/Multi-region: Cloud SQL HA (regional) with aggressive RTO/RPO targets is sufficient — global infrastructure not warranted without global users |

Interpret:

```
A -> availability: "single-zone" — Single-zone Cloud SQL acceptable, standard deployment
B -> availability: "multi-zone" — Regional Cloud SQL required, Cloud Load Balancing with health checks
C -> availability: "multi-zone-ha" — Cloud SQL HA (regional), multi-zone mandatory, health checks
D -> IF Q1 = C (Global): availability: "multi-region" — Cloud Spanner + multi-region GKE + Cloud DNS failover
     IF Q1 = A or B: availability: "multi-zone-ha" — Cloud SQL HA with aggressive RTO/RPO (global infra not warranted without global users)
E -> same as default (B) — assume multi-zone for safety
```

Default: B — `availability: "multi-zone"`.

---

## Q7 — What is your preferred Infrastructure-as-Code tool?

**Rationale:** Determines which IaC templates and migration tooling are recommended. Terraform is the most portable and widely used, Pulumi offers programming language flexibility, and Deployment Manager is GCP-native.

> The IaC tool determines which templates and migration automation we generate. This affects the entire output of the migration plan.
>
> A) Terraform — industry standard, multi-cloud capable
> B) Pulumi — programming language-native IaC (TypeScript, Python, Go)
> C) Deployment Manager — GCP-native declarative IaC
> D) None — manual setup or scripts
> E) I don't know

| Answer             | Recommendation Impact                                                                                                |
| ------------------ | -------------------------------------------------------------------------------------------------------------------- |
| Terraform          | HCL templates generated; Google provider configuration; state management in Cloud Storage                            |
| Pulumi             | Pulumi program generated in preferred language; GCP native provider                                                  |
| Deployment Manager | YAML/Jinja2 templates generated; GCP-native but limited service coverage                                             |
| None               | Step-by-step gcloud CLI commands and Console instructions; recommend adopting Terraform for repeatability             |

Interpret:

```
A -> iac_tool: "terraform" — HCL templates; Google provider; Cloud Storage state backend
B -> iac_tool: "pulumi" — Pulumi program; GCP native provider
C -> iac_tool: "deployment-manager" — YAML/Jinja2 templates; GCP-native
D -> iac_tool: "manual" — gcloud CLI commands; recommend adopting Terraform
E -> same as default (A) — assume Terraform
```

Default: A — `iac_tool: "terraform"`.
