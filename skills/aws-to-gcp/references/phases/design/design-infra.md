# Design Phase: Infrastructure Mapping

> Loaded by `design.md` when `aws-resource-inventory.json` and `aws-resource-clusters.json` exist.

**Execute ALL steps in order. Do not skip or optimize.**

## Step 0: Validate Inputs

Read `preferences.json`. If missing: **STOP**. Output: "Phase 2 (Clarify) not completed. Run Phase 2 first."

Read `aws-resource-clusters.json`.

## Step 0.5: Probe Companion Skills (google/skills)

Before mapping any cluster, probe whether each potentially-relevant google/skill is installed. This produces an in-memory `companion_skills_available` map (skill-name -> path-found-or-null) that subsequent mapping steps consult.

Skills to probe (one Read attempt per path, stop at first hit per skill):

- `cloud-run-basics`, `cloud-sql-basics`, `alloydb-basics`, `gke-basics`, `firebase-basics`, `gemini-api`, `gemini-interactions-api`, `google-cloud-networking-observability`, `google-cloud-recipe-auth`, `google-cloud-recipe-onboarding`, `google-cloud-waf-security`, `google-cloud-waf-reliability`, `google-cloud-waf-cost-optimization`, `bigquery-basics`

For each, attempt to Read:

1. `~/.claude/skills/<skill-name>/SKILL.md`
2. `~/.agents/skills/<skill-name>/SKILL.md`
3. `.claude/skills/<skill-name>/SKILL.md` (project-local)

If the Read tool returns a file, record the resolved path for that skill. If all three paths fail (ENOENT or equivalent), record `null`. **Do not fail the phase** if a skill is missing -- this is graceful degradation. See `references/shared/companion-skills.md` for the resolution protocol.

For every skill that resolves to `null`, prepare a one-line warning to surface in Step 4's `warnings[]` array (if a resource ends up needing that skill). The warning format is:
`"google/skills/<skill-name> not installed; used aws-to-gcp fallback rubric. Install with: npx skills add google/skills"`

Only emit warnings for skills that were actually needed during this design run (avoid spamming the user about skills unrelated to their workload).

## Step 1: Order Clusters

Sort clusters by `creation_order_depth` (lowest first, representing foundational infrastructure).

## Step 2: Two-Pass Mapping per Cluster

For each cluster, process `primary_resources` first, then `secondary_resources` (as classified during discover phase -- see `aws-resource-clusters.json`).

### Pass 1: Fast-Path Lookup (Direct Mappings table only)

For each PRIMARY resource in the cluster:

1. Extract AWS type (e.g., `aws_instance`)
2. Look up in `design-refs/fast-path.md` -> **Direct Mappings** table (not the Preferred Target table -- that applies later in Pass 2).
3. If found and conditions match: assign GCP service with confidence = **`deterministic`**. Set `human_expertise_required: false` (no Direct Mapping row requires it).
4. If not found: proceed to Pass 2 (confidence will be **`inferred`** after rubric, or **`billing_inferred`** on the billing-only path).

**Definitions:** See the top of `design-refs/fast-path.md` for **`deterministic` vs `inferred` vs `billing_inferred`** and the note that **index.md "Typical GCP target" is not deterministic**.

### Pass 2: Rubric-Based Selection

For resources not covered by fast-path:

**0. Redshift specialist gate (mandatory -- before rubric):** If `aws_type` **starts with** `aws_redshift_` (e.g. `aws_redshift_cluster`, `aws_redshift_subnet_group`, `aws_redshift_parameter_group`, `aws_redshift_scheduled_action`):

1. **Do not** recommend a specific GCP analytics or warehouse service (BigQuery, Dataproc, Dataflow, or a prescribed "data lake on GCS" architecture). This holds even if `bigquery-basics` is installed -- the specialist gate overrides the companion-skill protocol for Redshift.
2. Set `gcp_service` to **`Deferred -- specialist engagement`**, `human_expertise_required` to **`true`**, `confidence` to **`inferred`**, and `gcp_config` to include `specialist_engagement` (text: engage **GCP account team** and/or **data analytics migration partner** before choosing any GCP target) and `no_automated_gcp_target`: `true`. Set `rubric_applied` to `["Redshift specialist gate -- no automated GCP service target"]`.
3. **Skip** rubric steps 1-6 and the Preferred GCP target check for this resource.

1. Determine service category (via `design-refs/index.md`):
   - `aws_instance` -> compute
   - `aws_lambda_function` -> compute
   - `aws_db_instance` -> database
   - `aws_s3_bucket` -> storage
   - `aws_vpc` -> networking
   - etc.

   **Catch-all for unknown types**: If resource type not found in `index.md`:
   - Check resource name pattern (e.g., "scheduler" -> orchestration, "log" -> monitoring, "metric" -> monitoring)
   - If pattern match: use that category
   - If no pattern match: **STOP**. Output: "Unknown AWS resource type: [type]. Not in fast-path.md or index.md. Cannot auto-map. Please file an issue with this resource type."

2. Load rubric from corresponding `design-refs/*.md` file (e.g., `compute.md`, `database.md`)

3. Evaluate 6 criteria (1-sentence each):
   - **Eliminators**: Feature incompatibility (hard blocker)
   - **Operational Model**: Managed vs self-hosted fit
   - **User Preference**: From `preferences.json` design_constraints
   - **Feature Parity**: AWS feature -> GCP feature availability
   - **Cluster Context**: Affinity with other resources in this cluster
   - **Simplicity**: Prefer fewer resources / less config

4. Select best-fit GCP service. Confidence = `inferred`

5. **Companion-skill enrichment (companion google/skills):** Before finalizing `gcp_config` for this resource:

   1. Look up the **google/skill** column for the selected `gcp_service` in `design-refs/index.md` (or `references/shared/companion-skills.md` for the authoritative table).
   2. Check the in-memory `companion_skills_available` map built in **Step 0.5**.
   3. **If the skill resolved to a path** (e.g. `~/.claude/skills/cloud-run-basics/SKILL.md`):
      - Read it (if not already read this turn) and apply its canonical templates and best-practice fields when shaping `gcp_config`. Prefer its fields and field defaults over the rubric's example shapes for service-specific decisions (CPU, memory, scaling, IAM, secrets, prerequisites, etc.).
      - Append to the resource's `rationale` (separated by a semicolon): `"sourced from google/skills/<skill-name> SKILL.md"`.
   4. **If the skill resolved to `null`** (not installed):
      - Use this skill's `design-refs/<category>.md` configuration tips and the GCP-side defaults already in the rubric.
      - Add to the `warnings[]` array at the top level of `gcp-design.json` (deduplicate so each missing skill yields one warning per design): `"google/skills/<skill-name> not installed; used aws-to-gcp fallback rubric. Install with: npx skills add google/skills"`.
   5. **If the design-ref column shows _none_** (no google/skill exists for this target): no action needed -- this skill's rubric is already the canonical source.

   The Redshift specialist gate (step 0 above) takes precedence: do not apply companion-skill enrichment to `aws_redshift_*` resources.

6. **Set `human_expertise_required`**: If the Redshift specialist gate applied, already `true`. Otherwise set `false` unless another rubric explicitly requires it. This field is REQUIRED on every resource in the output.

7. **Preferred GCP target check**: **Skip** if `gcp_service` is **`Deferred -- specialist engagement`**. Otherwise verify the selected `gcp_service` aligns with the Preferred GCP Target Services table in `design-refs/fast-path.md`. If a non-preferred service is selected, substitute the preferred alternative. Add a note to the rationale: "Preferred target: [alternative] selected for stronger ecosystem integration."

8. **Database engine preservation gate (MANDATORY for database resources -- BLOCKS Design completion)**:

   Applies to every `aws_rds_cluster`, `aws_rds_cluster_instance`, `aws_db_instance`, `aws_elasticache_replication_group`, `aws_elasticache_cluster`, and `aws_dynamodb_table` mapped during Pass 1 or Pass 2.

   1. Read the source engine from `aws_config.engine` (e.g. `aurora-mysql`, `aurora-postgresql`, `mysql`, `postgres`, `mariadb`, `redis`, `memcached`).
   2. Apply the **Engine Preservation** table in `design-refs/database.md` to determine the correct `gcp_config.database_version` (or `gcp_config.redis_version` / `gcp_config.memcached_version`).
   3. Apply the engine -> target service rule:
      - `aurora-mysql`, `mysql`, `mariadb` -> `gcp_service` MUST be `Cloud SQL MySQL` (not `Cloud SQL PostgreSQL`, never `AlloyDB` -- AlloyDB is PostgreSQL-only)
      - `aurora-postgresql`, `postgres` -> `gcp_service` MAY be `Cloud SQL PostgreSQL` OR `AlloyDB` per user preference; engine is preserved either way
      - `redis` -> `gcp_service` MUST be `Memorystore Redis` with `redis_version` matching source major
   4. Write the result into the resource's `gcp_config`. The fields `database_version` / `redis_version` MUST NOT be `null`, `""`, or missing.
   5. **Common bug this gate prevents**: in earlier iterations, Aurora MySQL sources were incorrectly mapped to Cloud SQL **PostgreSQL** with `database_version = "POSTGRES_15"`. That is wrong; PostgreSQL is not engine-compatible with MySQL. The above mapping table is binding.

   Worked examples:
   - `aws_rds_cluster.ProductionAuroraCluster` with `aws_config.engine = "aurora-mysql"` and `engine_version = "8.0.mysql_aurora.3.08.2"` -> `gcp_service: "Cloud SQL MySQL"`, `gcp_config.database_version: "MYSQL_8_0"`.
   - `aws_elasticache_replication_group.ProductionRedis` with `aws_config.engine = "redis"`, `engine_version = "7.1"` -> `gcp_service: "Memorystore Redis"`, `gcp_config.redis_version: "REDIS_7_X"`.

   **Self-check at end of Pass 2 (before moving to Step 3):** iterate over every resource where `aws_type` matches one of the database types above. For each, verify `gcp_config.database_version` (or `redis_version` / `memcached_version`) is present and that the `gcp_service` engine matches the source engine per the rule above. If ANY violation: rewrite the offending resource's `gcp_config` and `gcp_service` before proceeding to Step 3. Design MUST NOT advance to Step 3 with engine mismatches.

## Step 3: Handle Secondary Resources

For each SECONDARY resource:

1. Use `design-refs/index.md` for category
2. Apply fast-path (most secondaries have deterministic mappings)
3. If rubric needed: apply the **Redshift specialist gate** (Pass 2 step 0) first when `aws_type` starts with `aws_redshift_`; otherwise apply the same 6-criteria approach as Pass 2

## Step 3.5: Validate GCP Architecture (using official Google Cloud sources)

If `gcp_service` is **`Deferred -- specialist engagement`**, **do not** validate against concrete GCP analytics SKUs; add a `warnings[]` entry that specialist engagement is required.

**Validation checks** (if `google-developer-knowledge`, `gcloud` MCP, or official Google Cloud documentation lookup is available):

For each mapped GCP service, verify:

1. **Regional Availability**: Is the service available in the target region (e.g., `us-central1`)?
   - Prefer `google-developer-knowledge`; use `gcloud` or official Google Cloud documentation if needed to check regional support
   - If unavailable: add warning, suggest fallback region

2. **Feature Parity**: Do required features exist in GCP service?
   - Match AWS features from `preferences.json` design_constraints
   - Check GCP feature availability via `google-developer-knowledge`, `gcloud`, or official Google Cloud documentation
   - If feature missing: add warning, suggest alternative service

3. **Service Compatibility**: Are there known issues or constraints?
   - Check best practices and gotchas via `google-developer-knowledge` or official Google Cloud documentation
   - Add to warnings if applicable

**If validation tooling is unavailable:**

- Set `validation_status: "skipped"` in output
- Note in summary: "Architecture validation unavailable (non-critical)"
- Continue with design (validation is informational, not blocking)

**If validation succeeds:**

- Set `validation_status: "completed"` in output
- List validated services in summary

## Step 4: Write Design Output

**File 1: `gcp-design.json`**

```json
{
  "clusters": [
    {
      "cluster_id": "ec2_instance_us-east-1_001",
      "aws_region": "us-east-1",
      "gcp_region": "us-central1",
      "resources": [
        {
          "aws_address": "aws_instance.web",
          "aws_type": "aws_instance",
          "aws_config": {
            "instance_type": "t3.medium",
            "availability_zone": "us-east-1a",
            "root_block_device_size_gb": 100
          },
          "gcp_service": "Compute Engine",
          "gcp_config": {
            "machine_type": "e2-medium",
            "boot_disk_size_gb": 100,
            "region": "us-central1"
          },
          "confidence": "deterministic",
          "human_expertise_required": false,
          "rationale": "Fast-path: aws_instance -> Compute Engine from the Direct Mappings table",
          "rubric_applied": [
            "Direct mapping: aws_instance -> Compute Engine"
          ]
        }
      ]
    },
    {
      "cluster_id": "ecs_service_us-east-1_001",
      "aws_region": "us-east-1",
      "gcp_region": "us-central1",
      "resources": [
        {
          "aws_address": "aws_ecs_service.api",
          "aws_type": "aws_ecs_service",
          "aws_config": {"cpu": 512, "memory": 1024, "desired_count": 2},
          "gcp_service": "Cloud Run",
          "gcp_config": {
            "cpu": "1",
            "memory": "1Gi",
            "min_instances": 2,
            "region": "us-central1"
          },
          "confidence": "inferred",
          "human_expertise_required": false,
          "rationale": "Rubric: Fargate (stateless, containerized) -> Cloud Run (managed, serverless containers); sourced from google/skills/cloud-run-basics SKILL.md",
          "rubric_applied": [
            "Eliminators: PASS",
            "Operational Model: Managed preferred",
            "User Preference: N/A",
            "Feature Parity: Full",
            "Cluster Context: Cloud Run affinity",
            "Simplicity: Cloud Run (1 service)"
          ]
        }
      ]
    }
  ],
  "warnings": [
    "service X not fully supported in us-central1; fallback to us-east1",
    "google/skills/cloud-sql-basics not installed; used aws-to-gcp fallback rubric. Install with: npx skills add google/skills"
  ]
}
```

**Companion-skill traceability:** The `rationale` field is the audit trail for companion-skill enrichment. If a resource's `gcp_config` was shaped by reading a google/skill, the rationale **must** include the literal phrase `sourced from google/skills/<skill-name> SKILL.md` (semicolon-delimited from the rest of the rationale). Missing-skill warnings live at the top-level `warnings[]` array, one per skill, deduplicated.

## Step 4.5: Generate `gcp-architecture.mmd` mermaid diagram of the target GCP architecture

**BLOCKING — Design phase MUST NOT mark `phases.design = "completed"` until `$MIGRATION_DIR/gcp-architecture.mmd` exists and contains at least one valid `flowchart TB` line and at least one node per mapped resource in `gcp-design.json`.** This step is not optional and not "best-effort" — past iterations skipped it silently when the buffer ran low. If you cannot emit the file, you cannot complete the Design phase. Write the file before any summary or status update.

Write a Mermaid `flowchart TB` diagram to `$MIGRATION_DIR/gcp-architecture.mmd` that mirrors the AWS diagram's structure but with GCP services. One node per `google_*` resource decided in this phase, edges preserved from the corresponding AWS edges (translated by service mapping). Use GCP service emoji/icons where natural (e.g. 🗄️ for Cloud SQL / AlloyDB, 📦 for GCS, 🚀 for Cloud Run, 🌐 for Cloud LB, 🔑 for IAM, ⚡ for Cloud Functions, 📨 for Pub/Sub).

- One `subgraph` per cluster (group by `cluster_id`)
- One node per mapped resource (label: `<gcp_service short>: <aws_address>` — keep the AWS address as the stable key so the AWS and GCP diagrams line up visually)
- Edges translated from `aws-resource-clusters.json.clusters[].edges[]`; preserve `relationship_type` as the edge label
- For any resource where `gcp_service` is `Deferred -- specialist engagement`, render the node with a dashed border and label `⚠️ Deferred: <aws_address>` so the diagram makes the open decision visible
- Start with `flowchart TB` on line 1; no surrounding ` ```mermaid ` fence — the file is `.mmd` not `.md`

**Post-write validation (BLOCKING):** After writing the file, Read it back from disk. Verify (a) line 1 starts with the literal string `flowchart TB`, (b) the count of node declarations is at least equal to the count of mapped resources in `gcp-design.json.clusters[].resources[]`. If either check fails, regenerate the file before proceeding. Refuse to update `.phase-status.json` until both checks pass.

## Step 4.6: Emit Architecture Decision Records to `$MIGRATION_DIR/adrs/`

For every Design decision where `confidence` is `inferred` or `billing_inferred` (i.e. anywhere the skill chose between two or more valid GCP targets), write one ADR file: `$MIGRATION_DIR/adrs/<NNN>-<short-title>.md` (e.g. `001-aurora-mysql-to-cloud-sql.md`, `002-ecs-fargate-to-cloud-run.md`). Number sequentially in the order resources were mapped.

**Resource address normalization (MANDATORY):** Resource references in ADR text (Context, Decision, Consequences sections) MUST use the Terraform-normalized address — for example `aws_rds_cluster.ProductionAuroraCluster` — NOT the CloudFormation logical-id form `AWS::RDS::DBCluster.ProductionAuroraCluster`. The address comes from `aws-resource-inventory.json.resources[].address` (which is already normalized to Terraform-style during Discover Step 1b for CloudFormation-sourced resources), never from raw CloudFormation template parse. If you find yourself about to write `AWS::<Service>::<Type>.<LogicalId>` in an ADR, STOP — look up the matching entry in `aws-resource-inventory.json` by logical-id (the substring after the dot in the CFN address) and use its normalized `address` field instead. The ADR filename's short-title may use any descriptive slug, but resource references inside the ADR body MUST be Terraform-normalized.

Each ADR follows the Michael Nygard format (4 sections, ~200-400 words):

```markdown
# ADR <NNN>: <short title>

## Status

Accepted (by aws-to-gcp migration skill, Phase 3 Design, on <date>)

## Context

The source workload uses <AWS service> (<aws_address>). On GCP, the candidate targets are <list 2-4 plausible options>. The decision is which target to use and why.

## Decision

We will use <GCP service>, configured as `<gcp_service> { database_version = "<value>", ... }`.

## Consequences

Positive: <list>
Negative: <list>
Future-changeable: <conditions under which we'd revisit, e.g. "if global multi-region is needed, migrate to Spanner">.
Affects: <comma-separated list of user-journey names this resource participates in, e.g. "Signup journey, File upload journey">.
```

The `Affects:` line is **MANDATORY**. It anchors the trade-off in user-visible business terms instead of leaving the impact abstract. Source the journey names from the Generate phase's `user-journeys/index.md` when it exists; during Design (which runs before Generate), derive the same list by walking `aws-sdk-usage.json.call_sites[]` for any call whose `aws_service` plausibly targets this resource and grouping by controller — the names must match the journey naming patterns in `references/phases/generate/generate-artifacts-journeys.md > Step 2`. If no journey touches this resource (e.g. a backing IAM role consumed only by infra glue), write `Affects: none (infrastructure-only resource; not on a user-visible path)`. NEVER invent journey names — only emit names you can trace back to a route in `app-routes.json` (or to the journey-naming pattern table if `app-routes.json` is absent).

ADRs are **skipped** for `deterministic` confidence (no decision to record) and for `Deferred -- specialist engagement` resources (the ADR for those is "specialist will decide" — record it as a single line in `$MIGRATION_DIR/adrs/000-deferred-decisions.md` instead of a full Nygard ADR).

Add to the design summary: `Architecture decisions are recorded under $MIGRATION_DIR/adrs/. Review them before $MIGRATION_DIR/MIGRATION_GUIDE.md to understand the trade-offs.`

## Step 4.7: Map `aws-sdk-*` Call Sites to GCP SDK Equivalents

**Gate:** Only run this step if `$MIGRATION_DIR/aws-sdk-usage.json` exists (produced by `references/phases/discover/discover-app-sdk.md`). If it does not exist, skip this step entirely — there are no app-level SDK call sites to translate.

For every entry in `aws-sdk-usage.json.call_sites`, produce one translation entry in `$MIGRATION_DIR/sdk-migration-plan.json`. The mapping table lives in `references/design-refs/sdk-mapping.md` — Read it once at the start of this step and consult per call site.

**Procedure (per call site):**

1. Look up the source `aws_service` + `language` row in `sdk-mapping.md` (e.g. Ruby + `s3` -> `google-cloud-storage`; Python + `secretsmanager` -> `google-cloud-secret-manager`).
2. Look up the source `aws_op` in the per-service operation table to determine the target `gcp_op` and the request/response shape diff.
3. If the row says `# MANUAL:` (e.g. SES, DynamoDB, any TODO-stub language combo), set `confidence: "inferred"` AND `manual_review: true`. Otherwise default to `confidence: "deterministic"` AND `manual_review: false`.
4. Compose the target snippet using the `gcp_op` signature from the mapping table, substituting the source's actual arguments where they line up 1:1 (e.g. `bucket: "foo"` -> `storage.bucket("foo")`). Where the shape diverges (e.g. `secret_id: "x"` -> `name: "projects/${var.gcp_project}/secrets/x/versions/latest"`), use the literal `${var.gcp_project}` placeholder so Generate can substitute the real project ID later.
5. Set `auth_change` to a single short sentence summarizing the runtime identity change for this service (most commonly: `"AWS IAM role -> GCP service account via Workload Identity Federation (no SDK-level code change; service account binding is configured at deployment time in Terraform)"`).

**Wrapper handling:** If `aws-sdk-usage.json.summary.wrapper_detected.present` is `true`, the wrapper file gets a special translation entry whose target is a full rewrite of the wrapper module (constructing one `Google::Cloud::*` client per AWS service). Generate will use this entry to produce a single coherent patch for the wrapper file plus per-call-site patches for everything downstream.

**Output schema** for `sdk-migration-plan.json`:

```json
{
  "metadata": {
    "source_artifact": "aws-sdk-usage.json",
    "mapping_reference": "references/design-refs/sdk-mapping.md",
    "design_timestamp": "2026-05-18T12:00:00Z"
  },
  "summary": {
    "total_translations": 12,
    "deterministic": 9,
    "inferred": 3,
    "manual_review_required": 3,
    "languages": ["ruby"]
  },
  "translations": [
    {
      "source": {
        "file": "app/config/initializers/01_secrets.rb",
        "line": 20,
        "language": "ruby",
        "aws_service": "secretsmanager",
        "aws_sdk_module": "aws-sdk-secretsmanager",
        "aws_op": "get_secret_value",
        "snippet": "resp = AwsClients.secrets.get_secret_value(secret_id: secret_id)"
      },
      "target": {
        "gcp_sdk": "google-cloud-secret_manager",
        "gcp_op": "access_secret_version",
        "snippet": "resp = SecretClients.secrets.access_secret_version(name: \"projects/${var.gcp_project}/secrets/#{secret_id}/versions/latest\")"
      },
      "confidence": "deterministic",
      "auth_change": "AWS IAM role -> GCP service account via Workload Identity Federation (no SDK-level code change; service account binding is configured at deployment time in Terraform)",
      "manual_review": false,
      "notes": "Response shape changes: resp.secret_string -> resp.payload.data.force_encoding('UTF-8'). Update the line below that calls JSON.parse(resp.secret_string)."
    }
  ]
}
```

**Required fields per translation entry:** `source` (mirrors the `aws-sdk-usage.json.call_sites[i]` shape), `target` (`gcp_sdk`, `gcp_op`, `snippet`), `confidence`, `auth_change`, `manual_review`.

**Optional fields:** `notes` (short, plain-English description of any non-obvious shape diff the developer needs to handle).

**Validation:** After writing `sdk-migration-plan.json`, verify:

- `summary.total_translations == len(translations) == aws-sdk-usage.json.summary.total_call_sites`
- Every translation's `source` block matches an entry in `aws-sdk-usage.json.call_sites` exactly (by `file` + `line`)
- Every translation has a non-empty `target.gcp_sdk` and `target.gcp_op`
- Every `manual_review: true` translation has either a `# MANUAL:` comment in `target.snippet` OR a `notes` field explaining the manual step

If the project has only one call site and the row in `sdk-mapping.md` is TODO-stubbed for that language, set `confidence: "inferred"`, `manual_review: true`, and put a `notes` value of `"sdk-mapping.md row for <language> + <aws_service> is TODO-stubbed; rewrite snippet is a best-effort starting point"`.

Add to the design summary: `App SDK rewrites planned: N call sites across L languages. Plan: $MIGRATION_DIR/sdk-migration-plan.json. Patches will be generated in Phase 5.`

## Output Validation Checklist

- `clusters` array is non-empty
- Every cluster has `cluster_id` matching a cluster from `aws-resource-clusters.json`
- Every cluster has `aws_region` and `gcp_region`
- Every resource has `aws_address`, `aws_type`, `aws_config`, `gcp_service`, `gcp_config`
- For every database resource (`aws_db_instance`, `aws_rds_cluster`) mapped to **Cloud SQL** or **AlloyDB**: `gcp_config.database_version` is a non-null string derived per the **Engine Preservation** table in `design-refs/database.md`. Reject the output if `database_version` is `null`, missing, or an empty string.
- Every resource has `human_expertise_required` (boolean) -- `true` for all `aws_redshift_*` resources (specialist gate); `false` for others unless a rubric explicitly requires it
- Every `aws_redshift_*` resource has `gcp_service` exactly **`Deferred -- specialist engagement`** (not BigQuery, Dataproc, Dataflow, etc.) regardless of whether `bigquery-basics` is installed
- All `confidence` values are either `"deterministic"` or `"inferred"`
- All `rationale` fields are non-empty
- For every resource whose `gcp_service` has a non-_none_ entry in the `design-refs/index.md` google/skill column **and** that skill resolved to a path in Step 0.5: the `rationale` contains the literal substring `sourced from google/skills/<skill-name> SKILL.md`
- Every "google/skills/... not installed" warning in `warnings[]` is unique (deduplicated)
- Every resource from every evaluated cluster appears in the output
- No duplicate `aws_address` values across clusters
- Output is valid JSON

## Present Summary

After writing `gcp-design.json`, present a concise summary to the user:

1. Total resources mapped and cluster count
2. Per-cluster table: AWS resource -> GCP service (one line each). For how each mapping was chosen, use **plain English** from `design-refs/fast-path.md` -> **User-facing vocabulary** -- **Standard pairing** (`deterministic`), **Tailored to your setup** (`inferred`), or **Estimated from billing only** (`billing_inferred`). Lead with the bold phrase; include the JSON value in parentheses only if the user is technical.
3. Any warnings (regional fallbacks; call out **Tailored to your setup** rows that deserve extra review)
4. **Companion-skill status**: If any "google/skills/... not installed" warnings appear in `warnings[]`, surface a single optional line: "Tip: install Google's canonical guidance with `npx skills add google/skills` and re-run Design for richer configuration." If all relevant skills were found, optionally note "Used canonical guidance from google/skills: <comma-list>" so the user knows the design draws on Google's templates.
5. If any resource has **`Deferred -- specialist engagement`**: state **prominently** that **no GCP analytics target was chosen**. Direct the user to **their GCP account team and/or a data analytics migration partner**. Do **not** recommend BigQuery, Dataproc, or Dataflow in the chat summary, even if `bigquery-basics` is installed.

Keep it under 20 lines. The user can ask for details or re-read `gcp-design.json` at any time.
