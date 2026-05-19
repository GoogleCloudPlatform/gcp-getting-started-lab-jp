# Phase 2: Clarify Requirements

**Phase 2 of 6** — Ask adaptive questions before design begins, then interpret answers into ready-to-apply design constraints.

> **HARD GATE — Clarify before Design:** Do not load `references/phases/design/design.md` (or any later phase) until this phase finishes **and** `$MIGRATION_DIR/.phase-status.json` records `phases.clarify` as `"completed"`. Writing `preferences.json` without updating phase status is a protocol violation. If the user asks to skip questions, use documented defaults and still complete this phase (including phase status).

The output — `preferences.json` — is consumed directly by Design and Estimate without any further interpretation.

Questions are organized into **seven named categories (A–G)** with documented firing rules. Up to 25 questions across categories, depending on which discovery artifacts exist and which AWS services are detected. A standalone **AI-Only** flow exists for migrations that only move AI/LLM calls to Vertex AI.

## Category Reference Files

| File                  | Category                     | Questions       | Loaded When                                       |
| --------------------- | ---------------------------- | --------------- | ------------------------------------------------- |
| `clarify-global.md`   | A — Global/Strategic         | Q1–Q7           | Always                                            |
| `clarify-compute.md`  | B — Config Gaps, C — Compute | Q8–Q11          | Compute or billing-source resources present       |
| `clarify-database.md` | D — Database                 | Q12–Q13         | Database resources present                        |
| `clarify-ai.md`       | F — AI/Vertex AI             | Q14–Q22         | `ai-workload-profile.json` exists                 |
| _(inline below)_      | G — Logging & Analytics      | Q_LOG1–Q_LOG3   | Logging/analytics AWS resources present (see G firing rule below) |
| `clarify-ai-only.md`  | _(standalone)_               | Q1–Q10          | AI-only migration (no infrastructure artifacts)   |

---

## Step 0: Prior Run Check

If `$MIGRATION_DIR/preferences.json` already exists:

> "I found existing migration preferences from a previous run. Would you like to:"
>
> A) Re-use these preferences and skip questions
> B) Start fresh and re-answer all questions

- If A: Run Step 2 item 6 only (BigQuery detection) on current discovery artifacts. If `bigquery_present` is **true**, output the Step 4 **BigQuery / deferred analytics** advisory block once (even though questions are skipped), then skip to Validation Checklist with the existing `preferences.json`.
- If B: continue to Step 1.

---

## Step 1: Read Inventory and Determine Migration Type

Read `$MIGRATION_DIR/` and check which discovery outputs exist:

- `aws-resource-inventory.json` + `aws-resource-clusters.json` — infrastructure discovered
- `ai-workload-profile.json` — AI workloads detected
- `billing-profile.json` — billing data parsed

At least one discovery artifact must exist to proceed.

### Migration Type Detection

- **Full migration**: `aws-resource-inventory.json` or `billing-profile.json` exists (may also have `ai-workload-profile.json`)
- **AI-only migration**: ONLY `ai-workload-profile.json` exists (no infrastructure or billing artifacts)

**If AI-only**: Read `clarify-ai-only.md` NOW and follow that flow. Skip all remaining steps below.

> **HARD GATE — AI-Only Path:** You MUST read `clarify-ai-only.md` before presenting any questions. The question text, answer options, and interpretation rules are ONLY in that file — they are NOT in this file. Do NOT fabricate questions from the summaries above.

### Discovery Summary

Present a discovery summary:

**If `aws-resource-inventory.json` exists:**

> **Infrastructure discovered:** [total resources] AWS resources across [cluster count] clusters
> **Top resource types:** [list top 3–5 types]

**If `ai-workload-profile.json` exists:**

> **AI workloads detected:** [from `models[].model_id`]
> **Capabilities in use:** [from `integration.capabilities_summary` where true]
> **Integration pattern:** [from `integration.pattern`] via [from `integration.primary_sdk`]

**If `billing-profile.json` exists:**

> **Monthly AWS spend:** $[total_monthly_spend]
> **Top services by cost:** [top 3–5 from billing data]

---

## Step 1.4: Migration Intent (MANDATORY — runs before ambiguities + Category A)

Before anything else in Clarify, ask the user which kind of migration they want. Cutover vs PoC clone produce radically different artifacts; the skill cannot guess.

```
Q_INTENT: What is the migration's intent?

  [A] Cutover — production migration with DNS flip, data migration scripts, traffic-shift mechanics, rollback procedures. Generate phase will produce data-migration shell scripts (mysqldump → Cloud SQL, gsutil S3→GCS), a cutover runbook, a rollback runbook, and DNS/load-balancer change instructions.

  [B] PoC clone — parallel deployment for validation only. NO production traffic, NO DNS changes, NO data migration scripts (a single seeding script is acceptable). The intent is to deploy a working clone on GCP so the team can poke it, measure cost, and compare behavior side-by-side with the still-live AWS deployment. Generate phase will skip cutover/rollback artifacts.

  [C] Hybrid (dual-write window) — for an extended migration window, the app writes to BOTH AWS and GCP simultaneously. Generate phase will produce app-level dual-write adapters AND replication/sync scripts. This is the most complex path and assumes the app code can be modified.
```

Record the answer in `preferences.json.design_constraints.migration_intent = {"value": "cutover"|"poc_clone"|"hybrid", "chosen_by": "user"}`. Design and Generate both branch on this field — see `references/phases/generate/generate.md` "Intent-driven artifact gating".

## Step 1.45: Cross-Cloud Connection Confirmation (MANDATORY when intent ∈ {poc_clone, hybrid})

For `poc_clone` and `hybrid` intents, the generated GCP services may legitimately need to read from AWS endpoints during the validation window (e.g. GCP Cloud Run reads the still-live AWS Aurora; GCP Pub/Sub bridges from Kinesis Firehose). For `cutover` intent, cross-cloud connections are usually ONE-SHOT (data migration scripts) and not ongoing.

**For every cross-cloud connection the skill is about to recommend, ASK the user before recording it in `gcp-design.json` or generating Terraform.** Examples that REQUIRE confirmation:

- GCP `google_cloud_run_v2_service` env var referencing an AWS endpoint (e.g. `AURORA_HOST=*.rds.amazonaws.com`)
- `google_database_migration_service_*` configured to pull from AWS RDS continuously
- `google_storage_transfer_job` reading from S3 on a schedule (vs one-shot)
- Pub/Sub or Eventarc subscribed to AWS SNS / SQS / Kinesis via a bridge
- Cloud Run service that calls AWS SDK at runtime (the `code-patches/` would tell us; if patches removed all AWS SDK calls, no runtime call expected)
- Any IAM permission on the GCP side that grants access TO AWS, OR any AWS IAM that grants access TO GCP

Format:

```
Cross-cloud connection #N: <gcp_resource> -> <aws_resource>
  Why this connection is being proposed: <reason>
  Direction: <gcp_to_aws|aws_to_gcp|bidirectional>
  Lifetime: <one_shot|ongoing>
  Confirm (Y/N) — if N, the GCP target will be configured standalone and the user is responsible for data seeding / sync separately:
```

Record each confirmed/denied connection in `preferences.json.design_constraints.cross_cloud_connections[]` with `{aws_resource, gcp_resource, confirmed, denied_reason?}`. Design MUST NOT emit ANY cross-cloud reference that was denied OR was not surfaced for confirmation.

For `cutover` intent: this step is skipped (cutover intent assumes a clean cut, no ongoing cross-cloud at runtime; data-migration scripts are one-shot and don't count).

## Step 1.5: Process Inventory Ambiguities (MANDATORY — runs before Category A questions)

Read `$MIGRATION_DIR/aws-resource-inventory.json` and inspect the top-level `ambiguities[]` array (written by `discover-iac.md` Step 7.5).

**If `ambiguities[]` is absent or empty:** skip this step entirely and continue to Step 2.

**If `ambiguities[]` is non-empty:**

1. **Present each ambiguity as a multiple-choice question, BEFORE Category A.** Use the entry's `suggested_clarify_question` as the question text and the entry's `options[]` array as the answer choices (preserve the `id`/`label` shown by Discover). Use this format:

   ```
   --- Section 0: Resolve discovery ambiguities ---

   The Discover phase flagged [N] resources where the AWS topology is ambiguous.
   I need your input before I can pick GCP targets — I will NOT guess.

   Ambiguity 1 of [N]: <suggested_clarify_question>
     Resource: <aws_address> (<aws_type>)
     Why I'm asking: <detail>
     A) <option A label>
     B) <option B label>
     ...

   Ambiguity 2 of [N]: ...
   ```

2. **Wait for the user's answer to every ambiguity.** Do NOT default these — they are explicit topology gaps, not preferences. If the user says "I don't know" for an ambiguity, record the answer as `null` and add an entry to `preferences.json.metadata.inventory_clarifications_unresolved[]` (Design will then mark the affected resource `Deferred — specialist engagement`).

3. **Record every answer in `preferences.json.metadata.inventory_clarifications`** keyed by `aws_address`. Each entry has shape:

   ```json
   "aws_kinesis_firehose_delivery_stream.ProductionPumaFirehose": {
     "ambiguity_type": "missing_destination",
     "selected_option_id": "A",
     "selected_option_label": "S3 (archive)",
     "implies_gcp": "Pub/Sub → Dataflow → Cloud Storage",
     "chosen_by": "user"
   }
   ```

4. **Design integration (binding rule).** Design's mapping rubric MUST read `preferences.json.metadata.inventory_clarifications` FIRST, before any other classification rule. For each entry:
   - The selected option's `implies_gcp` text becomes a **forced override** that Design MUST respect.
   - If Design's rubric would otherwise map the resource to a different target, it MUST use the user-provided one and append to that resource's `rationale`: `"user-clarified during Phase 2"` (semicolon-delimited from the rest of the rationale).
   - For entries in `inventory_clarifications_unresolved[]`, Design MUST set `gcp_service: "Deferred — specialist engagement"` for the affected resource with rationale `"ambiguity not resolved during Phase 2"`.

After processing all ambiguities, continue to Step 2.

---

## Step 2: Extract Known Information

Before generating questions, scan the inventory to extract values that are already known:

1. **AWS regions (MANDATORY discovery-aware default for Q1)** — You **MUST** perform region derivation, not pick a literal from any example block:
   1. Read `aws-resource-inventory.json`. Try (in order): `metadata.source_region`, `metadata.region`, top-level `region`. If absent, scan resources for `region`, `aws_region`, `availability_zone`, or `AvailabilityZone` fields and take the most common AWS region (strip the trailing AZ letter from values like `ap-northeast-1a`).
   2. Look that AWS region up in the **AWS-to-GCP Region Mapping Reference** table in `clarify-global.md` (Q1 section). Use that GCP region as the `target_region` default.
   3. **NEVER** default to `us-east1` unless the source region is `us-east-1`. The literal value `us-east1` appearing anywhere in an example JSON block in this file is **not** a default — it is illustrative only and has been replaced with `<...>` placeholders.
   4. When Q1 is defaulted (user did not answer) and the region was derived this way, record `target_region.chosen_by` as **`"derived"`** (NOT `"default"`). When Q1 is explicitly answered by the user, record `"user"`.
   5. If the AWS source region cannot be determined from the inventory at all (no metadata and no scannable region/AZ fields), fall back to `us-east1` with `chosen_by: "default"` AND add a warning to the discovery summary: "Source AWS region could not be determined from inventory; defaulted target_region to us-east1."
2. **Resource types present** — Build a set of resource types: compute (ECS, Lambda, EKS, EC2), database (RDS, Aurora, DynamoDB, ElastiCache), storage (S3), messaging (SNS, SQS).
3. **Billing line items** — If `billing-profile.json` exists, check if any line item reveals storage class, HA configuration, or other answerable questions.
4. **Billing-only mode** — If `billing-profile.json` exists and `aws-resource-inventory.json` does NOT exist, check `billing-profile.json -> services[]` for Category B question matching.
5. **AI framework detection** — If `ai-workload-profile.json` exists, check `integration.gateway_type` and `integration.frameworks` for auto-detection of Q14 answer.
6. **Redshift / analytics warehouse** — Set `redshift_present` to **true** if **any** of: (a) a resource in `aws-resource-inventory.json` has `aws_type` (or equivalent type field) starting with `aws_redshift_`; (b) `billing-profile.json` lists a service/SKU that clearly indicates **Redshift** (e.g., service name or SKU contains `Redshift`). Otherwise `redshift_present` is **false**.

Record extracted values. Questions whose answers are fully determined by extraction will be skipped and the extracted value used directly with `chosen_by: "extracted"`.

---

## Step 3: Generate Questions by Category

### Category Definitions and Firing Rules

| Category | Name               | Firing Rule                                                                    | Reference File        | Questions                                                                                                           |
| -------- | ------------------ | ------------------------------------------------------------------------------ | --------------------- | ------------------------------------------------------------------------------------------------------------------- |
| **A**    | Global/Strategic   | **Always fires**                                                               | `clarify-global.md`   | Q1 (location), Q2 (compliance), Q3 (AWS spend), Q4 (GCP org structure), Q5 (Kubernetes), Q6 (uptime), Q7 (IaC) |
| **B**    | Configuration Gaps | `billing-profile.json` exists AND `aws-resource-inventory.json` does NOT exist | `clarify-compute.md`  | RDS HA, ECS service count, ElastiCache memory, Lambda runtime                                                    |
| **C**    | Compute Model      | Compute resources present (ECS, Lambda, EKS, EC2)                              | `clarify-compute.md`  | Q8 (container orchestration), Q9 (serverless), Q10 (VM family), Q11 (committed use)                                 |
| **D**    | Database Model     | Database resources present (RDS, Aurora, DynamoDB, ElastiCache)                | `clarify-database.md` | Q12 (relational DB), Q13 (NoSQL)                                                                                    |
| **E**    | Migration Posture  | **Disabled by default** — requires explicit user opt-in                        | _(inline below)_      | HA upgrades, right-sizing                                                                                           |
| **F**    | AI/Vertex AI       | `ai-workload-profile.json` exists                                              | `clarify-ai.md`       | Q14–Q22                                                                                                             |
| **G**    | Logging & Analytics | Fires when inventory contains any `aws_kinesis_firehose_*`, `aws_glue_*`, `aws_athena_*`, `aws_msk_*`, `aws_opensearch_*`, OR `aws_cloudwatch_log_group` with destinations that can't be unambiguously determined. | _(inline in this file — see Category G section)_ | Q_LOG1, Q_LOG2, Q_LOG3                                                                                              |

**Apply firing rules to determine which categories are active:**

1. Category A is always active.
2. Check for billing-only mode — if `billing-profile.json` exists and `aws-resource-inventory.json` does NOT, Category B is active.
3. Check for compute resources — if present, Category C is active. Within C, skip Q8 if no ECS/EKS present. Skip Q10/Q11 if no EC2 present.
4. Check for database resources — if present, Category D is active.
5. Category E is disabled by default. After presenting all other categories, offer opt-in: "Would you also like HA upgrade and right-sizing recommendations based on your billing data?" If user declines or does not respond, apply Category E defaults (no HA upgrades, no right-sizing).
6. Check for `ai-workload-profile.json` — if present, Category F is active.
7. Check for logging/analytics resources — Category G is active when the inventory contains any `aws_kinesis_firehose_*`, `aws_glue_*`, `aws_athena_*`, `aws_msk_*`, `aws_opensearch_*`, OR `aws_cloudwatch_log_group` with destinations that can't be unambiguously determined. Within G, fire Q_LOG1 only if `aws_kinesis_firehose_*` is present, Q_LOG2 only if `aws_glue_job` is present, and Q_LOG3 only if `aws_athena_*` is present.

**If no IaC, billing data, or code is available** (empty discovery): only Category A is active. All service-specific categories are skipped.

### HARD GATE — Read Category Files Before Proceeding

> **STOP. You MUST read each active category's file NOW, before moving to Step 4.**
>
> The exact question wording, answer options, context rationale, and interpretation rules exist ONLY in the category files listed below. They are NOT in this file. The table above is a summary index only — do NOT use it to fabricate questions.
>
> **Read these files based on which categories are active:**
>
> | Active Category | File to Read                                                    |
> | --------------- | --------------------------------------------------------------- |
> | A (always)      | `clarify-global.md`                                             |
> | B or C          | `clarify-compute.md`                                            |
> | D               | `clarify-database.md`                                           |
> | F               | `clarify-ai.md`                                                 |
> | G               | _(inline in this file — see Category G section below);_ also read `references/design-refs/logging-analytics.md` for the rubric impact of each Q_LOG answer |
>
> **Do NOT proceed to Step 4 until you have read every applicable file above.**

### Early-Exit Rules

Apply these before presenting questions:

- **Q5 = "GKE Autopilot"** — Immediately record `container_orchestration: "gke-autopilot"`. Skip Q8 (container orchestration) — already decided.
- **Q10/Q11 N/A** — EC2 not present, auto-skip.
- **Q12/Q13 N/A** — RDS/Aurora not present, auto-skip.
- **Q14 auto-detected** — If `integration.gateway_type` is non-null OR `integration.frameworks` is non-empty in `ai-workload-profile.json`, skip Q14. Set `ai_framework` from the detected values with `chosen_by: "extracted"`.

---

## Category E — Migration Posture (Disabled by Default)

_Fire when:_ User explicitly opts in.
_Default behavior when disabled:_ Apply conservative defaults — no HA upgrades, no right-sizing.

If the user opts in, present after all other categories:

### Q24 — Should we recommend upgrading single-zone to multi-zone where possible?

> A) Yes — upgrade to multi-zone for higher availability | B) No — keep current topology

Interpret -> `ha_upgrade`: A -> `true`, B -> `false`. Default: B -> `false`.

### Q25 — Should we use billing utilization data to right-size machine types?

> A) Yes — right-size based on utilization | B) No — match current capacity

Interpret -> `right_sizing`: A -> `true`, B -> `false`. Default: B -> `false`.

---

## Category G — Logging & Analytics

_Fire when:_ inventory contains any `aws_kinesis_firehose_*`, `aws_glue_*`, `aws_athena_*`, `aws_msk_*`, `aws_opensearch_*`, OR `aws_cloudwatch_log_group` with destinations that can't be unambiguously determined.

These questions drive row selection in `references/design-refs/logging-analytics.md`. Each question fires only when the matching AWS resource type is present.

### Q_LOG1 — Firehose destination semantics

_Fire when:_ `aws_kinesis_firehose_delivery_stream` is present. Skip when: no Firehose in inventory.

**Rationale:** Firehose's S3 / OpenSearch / Splunk / Redshift destinations each require a different GCP target shape. Cloud Logging is a viable consolidation when the data is "just logs" and the customer doesn't need the same downstream analytics integrations.

**Context for user:** When asking, name the actual Firehose resource(s) and destination(s) detected, e.g. "Your Firehose `puma-logs-firehose` writes to S3 bucket `tunag-education-logs`."

> Your Firehose `<name>` writes to `<destination>`. How should we model this on GCP?
>
> A) Preserve the same destination semantics on GCP via Dataflow -> equivalent sink (Pub/Sub + Dataflow Pub/Sub-to-GCS template for S3; Pub/Sub + Splunk Dataflow Connector for Splunk; etc.)
> B) Consolidate into Cloud Logging (only suitable when the Firehose data is application/operational logs)
> C) I don't know

Interpret:

```
A -> firehose_strategy: "preserve-via-dataflow" — emit Pub/Sub + Dataflow per logging-analytics.md
B -> firehose_strategy: "cloud-logging" — route the producer to Cloud Logging directly; drop the Firehose resource with a warnings[] entry
C -> same as default (A) — preserve sink semantics; safest assumption
```

Default: A — `firehose_strategy: "preserve-via-dataflow"`.

### Q_LOG2 — Glue job migration approach

_Fire when:_ `aws_glue_job` is present. Skip when: no Glue jobs (Glue Catalog without Jobs still goes to BigQuery via the rubric).

**Rationale:** Glue Jobs run PySpark or Scala/Java Spark. Dataproc preserves Spark and minimizes code change. Dataflow (Apache Beam) is more GCP-native but requires a rewrite. Customers with a large existing Spark codebase usually want Dataproc; greenfield ETL or simple jobs benefit from Beam.

**Context for user:** When asking, name the language detected from `command.name` and `command.python_version` (e.g. "Your Glue jobs use `pyspark`.").

> Your Glue jobs use `<language: pyspark | scala>`. How should we migrate them?
>
> A) Migrate as-is to Dataproc — Spark-compatible, minimal code change, preserves existing JARs
> B) Rewrite as Apache Beam on Dataflow — more GCP-native, better autoscaling, requires code changes
> C) I don't know

Interpret:

```
A -> glue_job_strategy: "dataproc" — emit google_dataproc_job per logging-analytics.md
B -> glue_job_strategy: "dataflow-beam" — emit google_dataflow_job; flag rewrite effort in design output
C -> same as default (A) — preserve Spark on Dataproc; lower migration risk
```

Default: A — `glue_job_strategy: "dataproc"`.

### Q_LOG3 — Athena -> BigQuery acceptance

_Fire when:_ any `aws_athena_*` resource is present. Skip when: no Athena.

**Rationale:** BigQuery has the same SQL surface concept as Athena (query data on object storage) but a different cost model (slot-based or on-demand bytes scanned, with reservations available). Some customers cannot accept the cost model change without finance review.

**Context for user:** When asking, name the number of workgroups detected.

> You have `<N>` Athena workgroups. Acceptable to replace with BigQuery (same SQL surface, different cost model)?
>
> A) Yes — replace with BigQuery (external tables on GCS Parquet/Avro)
> B) No — defer this decision and mark Athena as `Deferred -- specialist engagement`
> C) I don't know

Interpret:

```
A -> athena_strategy: "bigquery" — emit google_bigquery_dataset + tables per logging-analytics.md
B -> athena_strategy: "deferred" — mark with gcp_service: "Deferred -- specialist engagement"; do not auto-design BigQuery resources
C -> same as default (A) — accept BigQuery as the replacement
```

Default: A — `athena_strategy: "bigquery"`.

---

## Step 4: Present Questions

**Redshift / deferred analytics (mandatory callout):** If Step 2 set `redshift_present` to **true**, output this block **once**, **before** any questions (same turn), then continue with the question flow:

> **Redshift / analytics warehouse:** Your discovery inputs include Redshift. This skill **does not** select a GCP analytics or data-warehouse target (no BigQuery, Dataflow, Dataproc, or Looker recommendation from the plugin). **Before** warehouse, data lake, SQL analytics, or BI cutover planning, engage your **GCP account team** and/or a **data analytics migration partner** to assess query patterns, data volumes, ETL/ELT, and downstream consumers. Design will mark these resources as **`Deferred — specialist engagement`**.

Show all generated questions at once, grouped by section. Use a conversational tone with brief context explaining why each question matters. Show a progress indicator: **"Question N of M"** where M is the total number of questions being asked (after filtering).

```
Before mapping your infrastructure to GCP, I have some questions to tailor the migration plan.
You can answer each, skip individual ones (I'll use sensible defaults),
or say "use all defaults" to proceed with all recommendations.

--- Section 1: About Your Users & Requirements ---

Question 1 of [M]: [Q1 text with context]
Question 2 of [M]: [Q2 text with context]
...

--- Section 2: Your Infrastructure ---
[Only if Categories C/D fire]

Question [N] of [M]: [Q8 text with context]
...

--- Section 3: AI Workloads ---
[Only if Category F fires]

Question [N] of [M]: [Q14 text with context]
...
```

Wait for the user's response. Do NOT proceed to Design without a response or an explicit "use all defaults".

---

## Answer Combination Triggers

| Scenario                     | Key Answers                                  | Recommendation                                              |
| ---------------------------- | -------------------------------------------- | ----------------------------------------------------------- |
| Low-spend startup            | Q3 < $5K                                     | GCP free tier and startup credits eligibility               |
| Growth-stage credits         | Q3 >= $20K                                   | GCP committed use discounts or enterprise agreement         |
| GKE Autopilot decided        | Q5 = GKE Autopilot                           | GKE Autopilot only, no Cloud Run for containers             |
| Kubernetes-averse            | Q5 = Cloud Run + Q8 = Cloud Run preferred    | Cloud Run strongly recommended                              |
| Serverless preference        | Q9 = Cloud Run functions                     | Cloud Run functions for event-driven source functions       |
| Low-traffic Lambda           | Q10 = general-purpose + Q11 = none           | Recommend Compute Engine with standard machine type         |
| High I/O database            | Q12 = AlloyDB                                | AlloyDB for PostgreSQL-compatible high-performance workloads |
| Global distributed DB        | Q6 = Catastrophic + Q12 = Spanner            | Cloud Spanner for global strong consistency                 |
| NoSQL workload               | Q13 = Bigtable                               | Cloud Bigtable for high-throughput NoSQL                    |
| Zero downtime required       | Q7 = Terraform                               | Terraform-managed blue/green + Database Migration Service   |
| HIPAA compliance             | Q2 = HIPAA                                   | HIPAA-compliant services only, specific regions             |
| FedRAMP required             | Q2 = FedRAMP                                 | Assured Workloads required                                  |
| CCPA / CPRA                  | Q2 = G (CCPA / CPRA)                         | Consumer privacy, logging/retention, data-inventory posture |
| Gateway-only AI              | Q14 = B only (LLM router/gateway)            | Config change only; skip SDK migration                      |
| LangChain/LangGraph AI       | Q14 includes C                               | Provider swap via ChatVertexAI; 1–3 days                    |
| OpenAI Agents SDK            | Q14 includes E                               | Highest AI effort; Vertex AI Agent Builder; 2–4 weeks       |
| Multi-agent + MCP            | Q14 = D + F                                  | Vertex AI Agent Builder to unify orchestration + MCP        |
| Voice platform AI            | Q14 includes G                               | Check native Vertex AI support; Chirp/Speech-to-Text        |
| GPT-4 Turbo migration        | Q19 = GPT-4 Turbo                            | Gemini 2.5 Pro — competitive pricing                        |
| o-series migration           | Q19 = o-series                               | Gemini 3.1 Pro Preview with thinking mode                    |
| High-volume cost-critical AI | Q18 = High + cost critical                   | Gemini 3 Flash Preview + provisioned throughput             |
| Reasoning/agent workload     | Q17 = Extended thinking                      | Gemini 3.1 Pro Preview with thinking                        |
| Speech-to-speech AI          | Q17 = Real-time speech                       | Chirp 3 / Cloud Speech-to-Text                              |
| RAG workload                 | Q17 = RAG optimization                       | Vertex AI Search + Vertex AI Embeddings                     |
| Vision workload              | Q20 = Vision required                        | Gemini 2.5 Pro (multimodal)                                 |
| Latency-critical AI          | Q21 = Critical                               | Gemini 2.5 Flash + streaming                                |
| Complex reasoning tasks      | Q22 = Complex                                | Gemini 3.1 Pro Preview with thinking                        |

---

## Step 5: Interpret and Write preferences.json

Apply the interpret rule for every answered question (defined in each category file). For skipped questions, apply the documented default. Write `$MIGRATION_DIR/preferences.json`:

> **EXAMPLE ONLY — DO NOT COPY LITERAL VALUES.** The block below shows the **shape** of `preferences.json`. Every `"value"` is a placeholder pattern wrapped in `<...>` to make it obvious you must compute the real value from inventory + user answers. **Never** treat the example's literal strings (region names, spend buckets, etc.) as defaults. Defaults are defined in the **Defaults Table** further down and the per-question **Interpret** sections in each category file.

```json
{
  "metadata": {
    "migration_type": "full",
    "timestamp": "<ISO timestamp>",
    "discovery_artifacts": ["aws-resource-inventory.json", "ai-workload-profile.json"],
    "questions_asked": [
      "Q1",
      "Q2",
      "Q3",
      "Q5",
      "Q6",
      "Q7",
      "Q16",
      "Q17",
      "Q19",
      "Q21",
      "Q22"
    ],
    "questions_defaulted": ["Q9"],
    "questions_skipped_extracted": ["Q14"],
    "questions_skipped_early_exit": ["Q8"],
    "questions_skipped_not_applicable": ["Q4", "Q10", "Q11", "Q12", "Q13"],
    "category_e_enabled": false,
    "inventory_clarifications": {
      "<aws_address>": {
        "ambiguity_type": "<from-inventory-ambiguities-entry>",
        "selected_option_id": "<A|B|C|...>",
        "selected_option_label": "<label-from-options>",
        "implies_gcp": "<implies_gcp-from-selected-option — Design MUST honor>",
        "chosen_by": "user"
      }
    },
    "inventory_clarifications_unresolved": []
  },
  "design_constraints": {
    "target_region": { "value": "<derived-from-source-region — e.g. asia-northeast1 if source ap-northeast-1>", "chosen_by": "derived" },
    "compliance": { "value": ["<compliance-or-omit-key>"], "chosen_by": "user" },
    "aws_monthly_spend": { "value": "<spend-bucket-from-Q3-or-billing — e.g. $5K-$20K>", "chosen_by": "user" },
    "gcp_org_structure": { "value": "<single-project|multi-project|multi-project-shared-vpc>", "chosen_by": "user" },
    "availability": { "value": "<single-zone|multi-zone|multi-zone-ha|multi-region>", "chosen_by": "default" },
    "iac_tool": { "value": "<terraform|pulumi|deployment-manager|manual>", "chosen_by": "user" },
    "container_orchestration": { "value": "<gke-autopilot|gke-standard|cloud-run|gke-autopilot-or-cloud-run>", "chosen_by": "user" },
    "database_preference": { "value": "<cloud-sql|alloydb|spanner>", "chosen_by": "user" },
    "nosql_preference": { "value": "<firestore|bigtable>", "chosen_by": "user" },
    "logging_analytics": {
      "firehose_strategy": { "value": "<preserve-via-dataflow|cloud-logging>", "chosen_by": "user" },
      "glue_job_strategy": { "value": "<dataproc|dataflow-beam>", "chosen_by": "user" },
      "athena_strategy": { "value": "<bigquery|deferred>", "chosen_by": "user" }
    }
  },
  "ai_constraints": {
    "ai_framework": { "value": ["<detected-frameworks-or-Q14-answer>"], "chosen_by": "extracted" },
    "ai_monthly_spend": { "value": "<spend-bucket-from-Q15 — e.g. $500-$2K>", "chosen_by": "user" },
    "ai_priority": { "value": "<cost|quality|latency|balanced — from Q16>", "chosen_by": "user" },
    "ai_critical_feature": { "value": "<feature-from-Q17-or-omit-key>", "chosen_by": "user" },
    "ai_token_volume": { "value": "<low|medium|high — from Q18>", "chosen_by": "user" },
    "ai_model_baseline": { "value": "<detected-model-or-Q19-answer>", "chosen_by": "user" },
    "ai_vision": { "value": "<text-only|vision-required — from Q20>", "chosen_by": "user" },
    "ai_latency": { "value": "<important|critical|tolerant — from Q21>", "chosen_by": "user" },
    "ai_complexity": { "value": "<simple|moderate|complex — from Q22>", "chosen_by": "user" },
    "ai_capabilities_required": {
      "value": ["<union-of-detected-and-Q17-Q20-capabilities>"],
      "chosen_by": "derived"
    }
  }
}
```

### Schema Rules

1. Every entry in `design_constraints` and `ai_constraints` is an object with `value` and `chosen_by` fields.
2. `chosen_by` values: `"user"` (explicitly answered), `"default"` (system default applied — includes "I don't know" answers), `"extracted"` (inferred from inventory), `"derived"` (computed from combination of answers + detected capabilities).
3. Only write a key to `design_constraints` / `ai_constraints` if the answer produces a constraint. Absent keys mean "no constraint — Design decides."
4. Do not write null values.
5. `metadata.inventory_clarifications` records (a) Step 1.5 ambiguity answers, keyed by `aws_address` with `ambiguity_type`, `selected_option_id`, `selected_option_label`, `implies_gcp`, `chosen_by` fields; and (b) for billing-source inventories, Category B answers. The two record types coexist in the same object. `metadata.inventory_clarifications_unresolved` is an array of `aws_address` strings for ambiguities the user could not answer; Design treats these as `Deferred — specialist engagement`.
6. `metadata.questions_skipped_early_exit` records questions skipped due to early-exit logic (e.g., Q8 skipped because Q5=GKE Autopilot).
7. `metadata.questions_skipped_extracted` records questions skipped because inventory already provided the answer.
8. `metadata.questions_skipped_not_applicable` records questions skipped because the relevant service wasn't in the inventory.
9. `ai_constraints` section is present ONLY if Category F fired. Omit entirely if no AI artifacts exist.
10. `ai_constraints.ai_capabilities_required` is the UNION of detected capabilities from `ai-workload-profile.json` + critical feature from Q17 + vision from Q20. `chosen_by` is `"derived"`.
11. `ai_constraints.ai_framework` is an array (Q14 is select-all-that-apply). If auto-detected, `chosen_by` is `"extracted"`.

---

## Defaults Table

| Question                | Default              | Constraint                                         |
| ----------------------- | -------------------- | -------------------------------------------------- |
| Q1 — Location           | A (single region)    | `target_region`: closest GCP region to AWS source region (derived per Step 2 item 1; `chosen_by: "derived"`). **Never** literal `us-east1` unless source region is `us-east-1`. |
| Q2 — Compliance         | A (none)             | no constraint                                      |
| Q3 — AWS spend          | B ($1K–$5K)          | `aws_monthly_spend: "$1K-$5K"`                     |
| Q4 — GCP org structure  | A (single project)   | `gcp_org_structure: "single-project"`              |
| Q5 — Kubernetes         | A (GKE Autopilot)    | `container_orchestration: "gke-autopilot"`         |
| Q6 — Uptime             | B (significant)      | `availability: "multi-zone"`                       |
| Q7 — IaC tool           | A (Terraform)        | `iac_tool: "terraform"`                            |
| Q8 — Container orch.    | A (GKE Autopilot)    | `container_orchestration: "gke-autopilot"`         |
| Q9 — Serverless         | B (Cloud Run)        | `serverless: "cloud-run"`                          |
| Q10 — VM family         | A (general-purpose)  | `vm_machine_family: "general-purpose"`             |
| Q11 — Committed use     | C (none)             | no constraint                                      |
| Q12 — Relational DB     | A (Cloud SQL)        | `database_preference: "cloud-sql"`                 |
| Q13 — NoSQL             | A (Firestore)        | `nosql_preference: "firestore"`                    |
| Q14 — AI framework      | _(auto-detect)_      | `ai_framework` from code detection                 |
| Q15 — AI spend          | B ($500–$2K)         | `ai_monthly_spend: "$500-$2K"`                     |
| Q16 — AI priority       | E (balanced)         | `ai_priority: "balanced"`                          |
| Q17 — Critical feature  | J (none)             | no additional override                             |
| Q18 — Volume + cost     | A (low + quality)    | `ai_token_volume: "low"`                           |
| Q19 — Current model     | _(auto-detect)_      | `ai_model_baseline` from code detection            |
| Q20 — Input types       | A (text only)        | no constraint                                      |
| Q21 — AI latency        | B (important)        | `ai_latency: "important"`                          |
| Q22 — Task complexity   | B (moderate)         | `ai_complexity: "moderate"`                        |
| Q_LOG1 — Firehose strategy | A (preserve-via-dataflow) | `logging_analytics.firehose_strategy: "preserve-via-dataflow"` |
| Q_LOG2 — Glue job strategy | A (Dataproc)         | `logging_analytics.glue_job_strategy: "dataproc"`  |
| Q_LOG3 — Athena -> BigQuery | A (yes)             | `logging_analytics.athena_strategy: "bigquery"`    |

---

## Validation Checklist

Before handing off to Design:

- [ ] If `redshift_present` was **true**, the Step 4 Redshift specialist advisory was shown before questions — **or**, if Step 0 option A (reuse preferences), the same advisory was shown after Redshift detection
- [ ] `preferences.json` written to `$MIGRATION_DIR/`
- [ ] `design_constraints.target_region` is populated with `value` and `chosen_by`
- [ ] `design_constraints.availability` is populated (if Q6 was asked or defaulted)
- [ ] Only keys with non-null values are present in `design_constraints`
- [ ] Every entry in `design_constraints` and `ai_constraints` has `value` and `chosen_by` fields
- [ ] Config gap answers recorded in `metadata.inventory_clarifications` (billing mode only)
- [ ] If `aws-resource-inventory.json.ambiguities[]` was non-empty, EVERY ambiguity has either an entry in `metadata.inventory_clarifications` (answered) or in `metadata.inventory_clarifications_unresolved` (skipped) — no ambiguity is silently dropped
- [ ] Each `metadata.inventory_clarifications` entry has `ambiguity_type`, `selected_option_id`, `selected_option_label`, `implies_gcp`, `chosen_by` fields
- [ ] Early-exit skips recorded in `metadata.questions_skipped_early_exit`
- [ ] `ai_constraints` section present ONLY if Category F fired
- [ ] If Category F fired, `ai_constraints.ai_framework` is populated (from detection or Q14)
- [ ] If Category F fired, `ai_capabilities_required` is derived from detection + Q17 + Q20
- [ ] `ai_constraints.ai_framework` is an array (Q14 is multi-select)
- [ ] If Category G fired, `design_constraints.logging_analytics` contains only the keys for questions that actually fired (e.g. omit `glue_job_strategy` when no `aws_glue_job` was in the inventory)
- [ ] Output is valid JSON

---

## Step 6: Update Phase Status

In the **same turn** as the output message below, use the Phase Status Update Protocol (Write tool) to write `.phase-status.json` with `phases.clarify` set to `"completed"`.

Output to user: "Clarification complete. Proceeding to Phase 3: Design GCP Architecture."

---

## Scope Boundary

**This phase covers requirements gathering ONLY.**

FORBIDDEN — Do NOT include ANY of:

- Detailed GCP architecture or service configurations
- Code migration examples or SDK snippets
- Detailed cost calculations
- Migration timelines or execution plans
- Terraform generation

**Your ONLY job: Understand what the user needs. Nothing else.**
