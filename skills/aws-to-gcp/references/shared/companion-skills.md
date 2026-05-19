# Companion Skills: google/skills Integration

This skill (`aws-to-gcp`) is designed to work alongside Google's official [`google/skills`](https://github.com/google/skills) package. When installed, those skills provide the **canonical, version-current** GCP service guidance that the agent should treat as the source of truth during the **Design** and **Generate** phases.

This file is the single, authoritative AWS -> GCP -> google/skill mapping. All `design-refs/*.md` files and the design/generate phase docs link here to keep one place to update.

---

## Install (if not already installed)

```bash
npx skills add google/skills
```

Both Claude- and agent-style install paths are searched (see "How to Use" below). If the user has not installed google/skills, the skill continues to work using its own inline `design-refs/*.md` rubrics as a fallback and emits a one-line warning suggesting installation.

---

## How to use (Design and Generate phases)

For each AWS resource being mapped, **before** applying this skill's rubric or generating a Terraform block:

1. Look up the AWS service in the mapping table below to find the matching **google/skill** name (e.g. `cloud-run-basics`).
2. Try to read the skill's `SKILL.md` from these paths, in order:
   - `~/.claude/skills/<skill-name>/SKILL.md` (Claude default install path)
   - `~/.agents/skills/<skill-name>/SKILL.md` (agent-neutral install path used by other agent runtimes; see skills.sh)
   - `.claude/skills/<skill-name>/SKILL.md` (project-local install, if present)
3. If a `SKILL.md` is found:
   - Use **its** templates, configuration recipes, and best-practice fields (CPU, memory, IAM bindings, scaling, secrets, prerequisites, etc.) as the **primary** source for that GCP service.
   - In `gcp-design.json`, set `resources[].rationale` to include the phrase `"sourced from google/skills/<skill-name> SKILL.md"`.
   - When generating Terraform in `generate-artifacts-infra.md`, use the canonical resource block shape and any prerequisites/companion resources the skill calls out.
4. If **not** found (graceful degradation):
   - Fall back to this skill's own `design-refs/<category>.md` rubric.
   - Add a one-line warning to `gcp-design.json.warnings`:
     `"google/skills/<skill-name> not installed; used aws-to-gcp fallback rubric. Install with: npx skills add google/skills"`
   - Use the same wording verbatim in the user-facing Design summary (one line per missing skill is fine).

This pattern keeps `aws-to-gcp` migration-focused (AWS -> GCP translation, clustering, dependency ordering, cost) while delegating GCP-specific service expertise to skills Google maintains.

---

## AWS -> GCP -> google/skill Mapping

| AWS source                                                          | GCP target                                              | google/skill (canonical guidance)                                                |
| ------------------------------------------------------------------- | ------------------------------------------------------- | -------------------------------------------------------------------------------- |
| ECS / Fargate                                                       | Cloud Run                                               | `cloud-run-basics`                                                               |
| Lambda (event-driven source function)                               | Cloud Run functions (a Cloud Run product)               | `cloud-run-basics`                                                               |
| Lambda (custom runtime, HTTP service, batch)                        | Cloud Run service / Cloud Run jobs                      | `cloud-run-basics`                                                               |
| EKS                                                                 | GKE                                                     | `gke-basics`                                                                     |
| EC2 (workload moved to managed containers)                          | Cloud Run or GKE                                        | `cloud-run-basics` or `gke-basics`                                               |
| EC2 / Auto Scaling Group (VMs preserved)                            | Compute Engine / Managed Instance Group                 | _no dedicated google/skill -- use `aws-to-gcp` rubric in `compute.md`_           |
| RDS MySQL / PostgreSQL / SQL Server                                 | Cloud SQL                                               | `cloud-sql-basics`                                                               |
| Aurora PostgreSQL                                                   | AlloyDB                                                 | `alloydb-basics`                                                                 |
| Aurora MySQL                                                        | Cloud SQL MySQL (HA)                                    | `cloud-sql-basics`                                                               |
| Redshift                                                            | **Deferred -- specialist engagement** (do not auto-map) | _Specialist gate applies; see `design-infra.md`. `bigquery-basics` is **background reading only** for the specialist conversation, not an automated target._ |
| Large analytics workloads (non-Redshift, user-requested)            | BigQuery                                                | `bigquery-basics`                                                                |
| DynamoDB / S3 / EFS / EBS                                           | Firestore, Bigtable, GCS, Filestore, Persistent Disk    | _no dedicated google/skill -- use `aws-to-gcp` rubrics in `database.md` / `storage.md`_ |
| Cognito / IAM Identity Center / Amplify auth (when migrating auth)  | Firebase Auth or Identity Platform                      | `firebase-basics`, `google-cloud-recipe-auth`                                    |
| ALB / NLB / VPC routing                                             | Cloud Load Balancing / VPC                              | `google-cloud-networking-observability`                                          |
| AWS WAF + Shield                                                    | Cloud Armor                                             | `google-cloud-waf-security`                                                      |
| Bedrock / OpenAI / foundation models                                | Vertex AI Gemini / Gemini API                           | `gemini-api`, `gemini-interactions-api`                                          |
| Cost-optimization review of generated design                        | (cross-cutting)                                         | `google-cloud-waf-cost-optimization`                                             |
| Reliability / SLO review of generated design                        | (cross-cutting)                                         | `google-cloud-waf-reliability`                                                   |
| First-time-to-GCP onboarding (new-account setup)                    | (cross-cutting)                                         | `google-cloud-recipe-onboarding`                                                 |

**Notes:**

- "Companion skill" means the agent should read that skill's `SKILL.md` and follow its guidance when shaping the GCP-side design or Terraform. It does **not** change the AWS -> GCP target mapping decisions encoded in `fast-path.md` / `design-refs/`.
- Some AWS services have no current dedicated google/skill (EC2/Compute Engine, DynamoDB, S3, EFS, EBS, messaging, traditional ML). For those, continue to apply this skill's rubric.
- Use stable, name-based references ("the latest version of `cloud-run-basics`"). Do not pin to a specific version -- google/skills evolves independently.
- The **Redshift specialist gate** is unaffected by `bigquery-basics` being installed. Even if `bigquery-basics` is available, `aws_redshift_*` resources still resolve to `Deferred -- specialist engagement` in `gcp-design.json`. Specialists may consult `bigquery-basics` during their own engagement.

---

## Cross-cutting skills (apply once per design, not per resource)

The following google/skills are not tied to any specific AWS->GCP service mapping. Consult them once during the Design or Generate phase if installed:

- **`google-cloud-recipe-onboarding`** -- If `preferences.json` indicates the customer is new to GCP (no existing project, or `design_constraints.gcp_experience == "new"`), follow this skill's onboarding sequence before/alongside `terraform apply` instructions.
- **`google-cloud-recipe-auth`** -- When migrating any identity/auth surface (Cognito, IAM Identity Center, third-party auth being replaced), consult before recommending Firebase Auth or Identity Platform.
- **`google-cloud-networking-observability`** -- When the design includes any of: VPC, Cloud Load Balancing, Cloud DNS, Cloud Armor, Cloud Monitoring/Logging integration, consult for canonical setup and observability wiring.
- **`google-cloud-waf-security`**, **`google-cloud-waf-reliability`**, **`google-cloud-waf-cost-optimization`** -- These are Google Cloud Well-Architected Framework reviews. After the Design phase produces `gcp-design.json`, optionally cross-check the design against the WAF pillars: security (Cloud Armor, IAM, encryption), reliability (HA, multi-zone), cost (Committed Use Discounts, right-sizing). Surface findings as Design `warnings[]` or in the Generate-phase `MIGRATION_GUIDE.md`.

---

## Quick reference (one-liner per skill, fallback when SKILL.md cannot be read)

| google/skill                              | One-line scope                                                                                  |
| ----------------------------------------- | ----------------------------------------------------------------------------------------------- |
| `alloydb-basics`                          | AlloyDB for PostgreSQL setup, sizing, HA, columnar engine, IAM                                  |
| `bigquery-basics`                         | BigQuery dataset/table setup, partitioning, IAM, slots, BI Engine                               |
| `cloud-run-basics`                        | Cloud Run service + jobs + functions: container deploy, CPU/memory/concurrency, scaling, secrets, IAM, VPC connector |
| `cloud-sql-basics`                        | Cloud SQL (MySQL / PostgreSQL / SQL Server): instance tiers, HA, backups, private IP, IAM       |
| `firebase-basics`                         | Firebase project bootstrap, Firestore, Authentication, Hosting                                  |
| `gemini-api`                              | Calling Gemini models via Vertex AI / Gemini API: SDK setup, auth, streaming                    |
| `gemini-interactions-api`                 | Interactions / conversation surfaces built on top of Gemini API                                 |
| `gke-basics`                              | GKE cluster (Autopilot or Standard) setup, node pools, Workload Identity, networking            |
| `google-cloud-networking-observability`   | VPC, Cloud Load Balancing, Cloud DNS, Cloud Monitoring + Logging best practices                 |
| `google-cloud-recipe-auth`                | Auth recipes: Identity Platform, Firebase Auth, IAP, Workload Identity Federation               |
| `google-cloud-recipe-onboarding`          | First-time GCP onboarding (project, billing, org policies, baseline IAM)                        |
| `google-cloud-waf-cost-optimization`      | Well-Architected cost optimization review (Committed Use Discounts, right-sizing, tiering)      |
| `google-cloud-waf-reliability`            | Well-Architected reliability review (HA, multi-region, SLOs, error budgets)                     |
| `google-cloud-waf-security`               | Well-Architected security review (Cloud Armor, IAM, KMS, VPC SC, audit logging)                 |
