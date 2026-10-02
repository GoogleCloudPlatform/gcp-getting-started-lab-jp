# Companion Skills: google/skills Integration

This skill (`azure-to-gcp`) is designed to work alongside Google's official
[`google/skills`](https://github.com/google/skills) package. When installed, those skills provide the
**canonical, version-current** GCP service guidance that the agent should treat as the source of truth
during the **Design** and **Generate** phases.

This file is the single, authoritative Azure -> GCP -> google/skill mapping. `references/shared/service-map.md`
and the design/generate phase files link here to keep one place to update. The sibling `aws-to-gcp`
skill maintains the same table for AWS sources; where a GCP target appears in both, the google/skill
entry is intentionally identical — the companion skill describes the GCP side, which does not care what
the source cloud was.

---

## Install (if not already installed)

```bash
npx skills add google/skills
```

Both Claude- and agent-style install paths are searched (see "How to use" below). If the user has not
installed google/skills, the skill continues to work using its own `references/shared/service-map.md`
rubric as a fallback and emits a one-line warning suggesting installation.

---

## How to use (Design and Generate phases)

For each Azure resource being mapped, **before** applying this skill's rubric or generating a Terraform
block:

1. Look up the Azure service in the mapping table below to find the matching **google/skill** name
   (for example `cloud-run-basics`).
2. Resolve the skill's `SKILL.md` from these paths, in order:
   - `~/.claude/skills/<skill-name>/SKILL.md` (Claude default install path)
   - `~/.agents/skills/<skill-name>/SKILL.md` (agent-neutral install path used by other agent runtimes)
   - `.claude/skills/<skill-name>/SKILL.md` (project-local install, if present)
3. If one is found:
   - Use **its** templates, configuration recipes, and best-practice fields (CPU, memory, IAM bindings,
     scaling, secrets, prerequisites) as the **primary** source for that GCP service.
   - In `gcp-design.json`, include the phrase `"sourced from google/skills/<skill-name> SKILL.md"` in the
     resource's `rationale`.
   - When generating Terraform, use the canonical resource block shape and any prerequisites or companion
     resources the skill calls out.
4. If **not** found (graceful degradation):
   - Fall back to this skill's own `references/shared/service-map.md` rubric.
   - Add a one-line warning to `gcp-design.json.warnings`:
     `"google/skills/<skill-name> not installed; used azure-to-gcp fallback rubric. Install with: npx skills add google/skills"`
   - Use the same wording verbatim in the user-facing Design summary (one line per missing skill is fine).

This pattern keeps `azure-to-gcp` migration-focused (Azure -> GCP translation, gating, dependency
ordering, cost) while delegating GCP-specific service expertise to skills Google maintains.

**A companion skill never overrides a gate.** If `Q_ANALYTICS` deferred a Synapse estate, having
`bigquery-basics` installed does not make BigQuery an automated target — same rule the sibling skill
applies to its Redshift gate.

---

## Azure -> GCP -> google/skill mapping

| Azure source                                                                     | GCP target                                               | google/skill (canonical guidance)                                                                                                    |
| -------------------------------------------------------------------------------- | -------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------ |
| Container Apps / Container Instances                                             | Cloud Run                                                | `cloud-run-basics`                                                                                                                   |
| App Service (when the card picks Cloud Run)                                      | Cloud Run                                                | `cloud-run-basics`                                                                                                                   |
| App Service (when the card picks App Engine)                                     | App Engine                                               | _no dedicated google/skill — use this skill's rubric_                                                                                |
| Functions                                                                        | Cloud Run functions (a Cloud Run product)                | `cloud-run-basics`                                                                                                                   |
| AKS                                                                              | GKE (Autopilot or Standard)                              | `gke-basics`                                                                                                                         |
| VM Scale Sets / Virtual Machines                                                 | Compute Engine, managed instance group                   | _no dedicated google/skill — use this skill's rubric_                                                                                |
| Azure SQL Database / SQL Managed Instance                                        | Cloud SQL for SQL Server                                 | `cloud-sql-basics`                                                                                                                   |
| Azure Database for MySQL Flexible Server                                         | Cloud SQL for MySQL                                      | `cloud-sql-basics`                                                                                                                   |
| Azure Database for PostgreSQL Flexible Server (Cloud SQL branch)                 | Cloud SQL for PostgreSQL                                 | `cloud-sql-basics`                                                                                                                   |
| Azure Database for PostgreSQL Flexible Server (AlloyDB branch)                   | AlloyDB for PostgreSQL                                   | `alloydb-basics`                                                                                                                     |
| Cosmos DB (Firestore branch)                                                     | Firestore                                                | `firebase-basics`                                                                                                                    |
| Cosmos DB (Bigtable branch)                                                      | Bigtable                                                 | `bigtable-basics`                                                                                                                    |
| Cosmos DB (Spanner branch)                                                       | Spanner                                                  | `spanner-basics`                                                                                                                     |
| Cosmos DB (AlloyDB branch, Cosmos DB for PostgreSQL)                             | AlloyDB for PostgreSQL                                   | `alloydb-basics`                                                                                                                     |
| Blob Storage                                                                     | Cloud Storage                                            | `google-cloud-storage-basics`                                                                                                        |
| Azure Files (NFS) / Azure Files (SMB) / Azure NetApp Files                       | Filestore / Google Cloud NetApp Volumes                  | _no dedicated google/skill — use this skill's rubric_                                                                                |
| Service Bus / Event Hubs / Storage Queues                                        | Pub/Sub or Cloud Tasks                                   | _no dedicated google/skill — use this skill's rubric_                                                                                |
| Event Grid                                                                       | Eventarc                                                 | _no dedicated google/skill — use this skill's rubric_                                                                                |
| Key Vault                                                                        | Secret Manager / Cloud KMS                               | _no dedicated google/skill — use this skill's rubric_                                                                                |
| Container Registry                                                               | Artifact Registry                                        | _no dedicated google/skill — use this skill's rubric_                                                                                |
| Virtual Network / Load Balancer / DNS / Front Door / CDN                         | VPC, Cloud Load Balancing, Cloud DNS, Cloud CDN          | `google-cloud-networking-observability`                                                                                              |
| Azure WAF / DDoS Protection                                                      | Cloud Armor                                              | `google-cloud-waf-security`                                                                                                          |
| Application Insights / Azure Monitor                                             | Cloud Trace, Cloud Monitoring, Cloud Logging             | `google-cloud-networking-observability`                                                                                              |
| Azure OpenAI / Azure AI services                                                 | Vertex AI                                                | `gemini-api`, `gemini-interactions-api`                                                                                              |
| Entra ID -> Cloud Identity federation; Entra WIF -> Workload Identity Federation | Cloud Identity, IAM, Workload Identity Federation        | `google-cloud-recipe-auth`                                                                                                           |
| Synapse / Fabric / Databricks / ADX / Stream Analytics / Data Factory            | **`Deferred — specialist engagement`** (do not auto-map) | _specialist gate applies; `bigquery-basics` is **background reading for the specialist conversation only**, not an automated target_ |
| Cost-optimization review of the generated design                                 | (cross-cutting)                                          | `google-cloud-waf-cost-optimization`                                                                                                 |
| Reliability / SLO review of the generated design                                 | (cross-cutting)                                          | `google-cloud-waf-reliability`                                                                                                       |
| First-time-to-GCP onboarding (new organization or project)                       | (cross-cutting)                                          | `google-cloud-recipe-onboarding`                                                                                                     |

**Notes:**

- "Companion skill" means the agent should consult that skill's `SKILL.md` and follow its guidance when
  shaping the GCP-side design or Terraform. It does **not** change the Azure -> GCP target decisions
  encoded in `references/shared/service-map.md`, and it never resolves a trade-off card — the card is a
  user decision.
- Several Azure services have no current dedicated google/skill (Compute Engine, Filestore, messaging,
  Artifact Registry, Secret Manager). For those, apply this skill's rubric.
- Use stable, name-based references ("the latest version of `cloud-run-basics`"). Do not pin a version —
  google/skills evolves independently.

---

## Cross-cutting skills (apply once per design, not per resource)

- **`google-cloud-recipe-onboarding`** — when the customer is new to Google Cloud (no existing project or
  organization), follow this skill's onboarding sequence before the Terraform instructions. Azure
  estates frequently arrive with no Google Cloud footprint at all, so this fires more often here than in
  the AWS sibling.
- **`google-cloud-recipe-auth`** — consult before recommending anything in the identity design: Cloud
  Identity federation with Entra ID, Workforce Identity Federation, Workload Identity Federation for
  GKE, or Managed Service for Microsoft AD. The `Q_IDENTITY` gate decision comes first; this skill
  informs how to implement it.
- **`google-cloud-networking-observability`** — when the design includes VPC, Cloud Load Balancing,
  Cloud DNS, Cloud CDN, Cloud Armor, or Cloud Monitoring/Logging wiring.
- **`google-cloud-waf-security`**, **`google-cloud-waf-reliability`**,
  **`google-cloud-waf-cost-optimization`** — Google Cloud Well-Architected Framework reviews. After
  Design produces `gcp-design.json`, optionally cross-check against the pillars and surface findings as
  Design `warnings[]` or in the Generate-phase migration guide. These are reviews, not gates: a WAF
  finding never silently changes a recorded design choice.

---

## Quick reference (one-liner per skill, fallback when a `SKILL.md` cannot be resolved)

| google/skill                            | One-line scope                                                                                                         |
| --------------------------------------- | ---------------------------------------------------------------------------------------------------------------------- |
| `alloydb-basics`                        | AlloyDB for PostgreSQL setup, sizing, HA, columnar engine, IAM                                                         |
| `bigquery-basics`                       | BigQuery dataset/table setup, partitioning, IAM, slots, BI Engine                                                      |
| `bigtable-basics`                       | Bigtable instance/cluster sizing, row-key design, app profiles                                                         |
| `cloud-run-basics`                      | Cloud Run services, jobs and functions: container deploy, CPU/memory/concurrency, scaling, secrets, IAM, VPC connector |
| `cloud-sql-basics`                      | Cloud SQL (MySQL / PostgreSQL / SQL Server): instance tiers, HA, backups, private IP, IAM                              |
| `firebase-basics`                       | Firebase project bootstrap, Firestore, Authentication, Hosting                                                         |
| `gemini-api`                            | Calling Gemini models via Vertex AI / Gemini API: SDK setup, auth, streaming                                           |
| `gemini-interactions-api`               | Interaction and conversation surfaces built on the Gemini API                                                          |
| `gke-basics`                            | GKE cluster (Autopilot or Standard) setup, node pools, Workload Identity, networking                                   |
| `google-cloud-networking-observability` | VPC, Cloud Load Balancing, Cloud DNS, Cloud Monitoring and Logging best practices                                      |
| `google-cloud-recipe-auth`              | Auth recipes: Identity Platform, Firebase Auth, IAP, Workload Identity Federation                                      |
| `google-cloud-recipe-onboarding`        | First-time Google Cloud onboarding (project, billing, org policies, baseline IAM)                                      |
| `google-cloud-storage-basics`           | Cloud Storage buckets: storage classes, lifecycle rules, IAM, versioning, transfer                                     |
| `google-cloud-waf-cost-optimization`    | Well-Architected cost optimization review (committed use discounts, right-sizing, tiering)                             |
| `google-cloud-waf-reliability`          | Well-Architected reliability review (HA, multi-region, SLOs, error budgets)                                            |
| `google-cloud-waf-security`             | Well-Architected security review (Cloud Armor, IAM, KMS, VPC SC, audit logging)                                        |
| `spanner-basics`                        | Spanner instance/database setup, schema and split design, IAM, regional vs multi-region                                |
