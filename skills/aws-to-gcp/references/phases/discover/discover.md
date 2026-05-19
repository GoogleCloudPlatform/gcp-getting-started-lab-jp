# Phase 1: Discover AWS Resources

Lightweight orchestrator that delegates to domain-specific discoverers. Each sub-discovery file is self-contained — it scans for its own input, processes what it finds, and exits cleanly if nothing is relevant.
**Execute ALL steps in order. Do not skip or deviate.**

## Sub-Discovery Files

- **discover-iac.md** → `aws-resource-inventory.json` + `aws-resource-clusters.json` (if Terraform or CloudFormation found)
- **discover-app-code.md** → `ai-workload-profile.json` (if source code with AI signals found)
- **discover-app-sdk.md** → `aws-sdk-usage.json` (if source code with `aws-sdk-*` / `boto3` / `@aws-sdk/*` call sites found — runs alongside `discover-app-code.md` on the same source tree)
- **discover-billing.md** → `billing-profile.json` (if billing data found)

Multiple artifacts can be produced in a single run — they are not mutually exclusive.

## Step 0: Initialize Migration State

1. Check for existing `.migration/` directory at the project root.
   - **If existing runs found:** List them with their phase status and ask:
     - `[A] Resume: Continue with [latest run]`
     - `[B] Fresh: Create new migration run`
     - `[C] Cancel`
   - **If resuming:** Set `$MIGRATION_DIR` to the selected run's directory. Read its `.phase-status.json` and skip to the appropriate phase per the State Machine in SKILL.md.
   - **If fresh or no existing runs:** Continue to step 2.
2. Create `.migration/[MMDD-HHMM]/` directory (e.g., `.migration/0226-1430/`) using current timestamp (MMDD = month/day, HHMM = hour/minute). Set `$MIGRATION_DIR` to this new directory.
3. Create `.migration/.gitignore` file (if not already present) with exact content:

   ```
   # Migration runtime state. Add `.migration/` to your project's root .gitignore
   # to keep these artifacts out of source control. We do NOT put a `*` pattern
   # here because Gemini CLI and other agentic CLIs honor `.gitignore` for their
   # file-read sandbox — a `*` here would block the skill from reading its own
   # outputs (aws-resource-inventory.json, gcp-design.json, etc.) in later phases.
   ```

   This is a comment-only file. To actually keep `.migration/` out of git,
   add the line `.migration/` to the **project root** `.gitignore` (the skill
   does NOT modify the project root `.gitignore`; that is the user's responsibility).

4. Write `.phase-status.json` with exact schema:

   ```json
   {
     "migration_id": "[MMDD-HHMM]",
     "last_updated": "[ISO 8601 timestamp]",
     "phases": {
       "discover": "in_progress",
       "clarify": "pending",
       "design": "pending",
       "estimate": "pending",
       "generate": "pending",
       "feedback": "pending"
     }
   }
   ```

5. Confirm both `.migration/.gitignore` and `.phase-status.json` exist before proceeding to Step 1.

## Step 1: Scan for Input Sources and Run Sub-Discoveries

Scan the project directory for each input type. Only load sub-discovery files when their input files are present.

**1a. Check for Terraform files:**
Glob for: `**/*.tf`, `**/*.tfvars`, `**/*.tfstate`, `**/.terraform.lock.hcl`

- If found → Load `references/phases/discover/discover-iac.md`
- If not found → Continue to 1a-ii.

**1a-ii. Check for CloudFormation templates:**
Glob for: `**/*.json`, `**/*.yaml`, `**/*.yml`, `**/*.template`

For each matched file, check if it contains `AWSTemplateFormatVersion` or `AWS::` resource type declarations.

- If found → Load `references/phases/discover/discover-iac.md`
- If not found → Skip. Log: "No Terraform or CloudFormation files found — skipping IaC discovery."

**1b. Check for source code / dependency manifests:**
Glob for: `**/*.rb`, `**/*.py`, `**/*.js`, `**/*.ts`, `**/*.jsx`, `**/*.tsx`, `**/*.mjs`, `**/*.cjs`, `**/*.go`, `**/*.java`, `**/*.scala`, `**/*.kt`, `**/*.rs`, `**/Gemfile`, `**/Gemfile.lock`, `**/*.gemspec`, `**/requirements.txt`, `**/setup.py`, `**/pyproject.toml`, `**/Pipfile`, `**/package.json`, `**/go.mod`, `**/pom.xml`, `**/build.gradle`, `**/Cargo.toml`

- If found → Load `references/phases/discover/discover-app-code.md` (AI workload detection) **AND** `references/phases/discover/discover-app-sdk.md` (AWS SDK call-site inventory). Run both — they target different artifacts (`ai-workload-profile.json` vs `aws-sdk-usage.json`) and do not conflict.
- If not found → Skip. Log: "No source code found — skipping app code discovery."

**1c. Check for billing data:**
Glob for: `**/*billing*.csv`, `**/*billing*.json`, `**/*cost*.csv`, `**/*cost*.json`, `**/*usage*.csv`, `**/*usage*.json`, `**/*CUR*.csv`, `**/*CUR*.json`

- If not found → Skip. Log: "No billing files found — skipping billing discovery."
- If found AND **no** Terraform/CloudFormation files from 1a → Load `references/phases/discover/discover-billing.md` (billing is the primary source — needs full processing for the billing-only design path).
- If found AND Terraform/CloudFormation files **were** found in 1a → Use lightweight extraction below. Do **not** load `discover-billing.md`.

**Lightweight billing extraction (when IaC is the primary source):**

When Terraform or CloudFormation is present, billing data is supplementary — only service-level costs and AI signal detection are needed. Extract via a script to avoid reading the raw file into context.

1. Use Bash to read only the **first line** of the billing file to identify column headers.
2. Write a script to `$MIGRATION_DIR/_extract_billing.py` (or `.js` / shell — use whatever runtime is available) that:
   - Reads the billing CSV/JSON file
   - Groups line items by service description, sums cost per service
   - Extracts top 3 SKU descriptions per service by cost
   - Scans service and SKU descriptions (case-insensitive) for AI keywords: `bedrock`, `sagemaker`, `comprehend`, `rekognition`, `textract`, `polly`, `transcribe`, `lex`, `personalize`, `forecast`, `kendra`, `lookout`, `healthlake`, `titan`
   - Outputs JSON to stdout matching the schema in step 4
3. Run the script: try `python3 _extract_billing.py` first. If `python3` is not found, try `python _extract_billing.py`. If neither is available, delete the script and fall back to loading `references/phases/discover/discover-billing.md`.
4. Write the script's JSON output to `$MIGRATION_DIR/billing-profile.json` with this exact schema:

   ```json
   {
     "summary": { "total_monthly_spend": 0.00 },
     "services": [
       {
         "aws_service": "Amazon EC2",
         "monthly_cost": 450.00,
         "top_skus": [
           { "sku_description": "EC2 - m5.xlarge On-Demand Linux", "monthly_cost": 300.00 }
         ]
       }
     ],
     "ai_signals": { "detected": false }
   }
   ```

   Services sorted descending by `monthly_cost`. Only include services with cost > 0.

5. Delete the script file after successful execution.

**Critical:** Do **not** Read the billing file with the Read tool. Do **not** load `discover-billing.md` or `schema-discover-billing.md`.

**If NONE of the three checks found files**: STOP and output: "No AWS sources detected. Provide at least one source type (Terraform files, CloudFormation templates, application code, or AWS billing exports) and try again."

## Step 2: Check Outputs

After all loaded sub-discoveries complete, check what artifacts were produced in `$MIGRATION_DIR/`:

1. Check for output files:
   - `aws-resource-inventory.json` — IaC discovery succeeded
   - `aws-resource-clusters.json` — IaC discovery produced clusters
   - `ai-workload-profile.json` — App code discovery detected AI workloads
   - `aws-sdk-usage.json` — App SDK discovery detected non-AI AWS SDK call sites needing source-code rewrite
   - `app-routes.json` — App code discovery extracted HTTP routing topology (always written when source code with a recognized routing file is found; the file may contain `{"framework": null, "routes": []}` when no routes file is locatable)
   - `billing-profile.json` — Billing data parsed
2. **If NO artifacts were produced** (sub-discoveries ran but produced no output): STOP and output: "Discovery ran but produced no artifacts. Check that your input files contain valid AWS resources and try again."

## Step 3: Update Phase Status

In the **same turn** as the output message below, use the Phase Status Update Protocol (Write tool) to write `.phase-status.json` with `phases.discover` set to `"completed"` and all other phases unchanged from their initial values.

Output to user — build message from whichever artifacts exist:

- If `aws-resource-inventory.json` exists: "Discovered X total resources across Y clusters."
- If `ai-workload-profile.json` exists: "Detected AI workloads (source: [ai_source])."
- If `aws-sdk-usage.json` exists: "Found N AWS SDK call sites across L languages — source-code rewrite required."
- If `billing-profile.json` exists: "Parsed billing data ($Z/month across N services)."

Format: "Discover phase complete. [artifact summaries joined by space] Next required step: Phase 2 — Clarify. Load `references/phases/clarify/clarify.md` now. Do not load Design, Estimate, or Generate until Clarify completes and `.phase-status.json` marks `phases.clarify` as `completed`."

## Output Files

**Discover phase writes files to `$MIGRATION_DIR/`. Possible outputs (depending on what sub-discoverers find):**

1. `aws-resource-inventory.json` — from discover-iac.md
2. `aws-resource-clusters.json` — from discover-iac.md
3. `aws-architecture.mmd` — from discover-iac.md (Mermaid topology diagram of source AWS architecture)
4. `ai-workload-profile.json` — from discover-app-code.md
5. `aws-sdk-usage.json` — from discover-app-sdk.md (non-AI AWS SDK call sites for source-code rewrite)
6. `app-routes.json` — from discover-app-code.md (HTTP routing topology consumed by the Generate phase's user-journey synthesis)
7. `billing-profile.json` — from discover-billing.md

**No other files must be created:**

- No README.md
- No discovery-summary.md
- No EXECUTION_REPORT.txt
- No discovery-log.md
- No documentation or report files

All user communication via output messages only.

## Error Handling

- **Missing `.migration` directory**: Create it (Step 0)
- **Missing `.migration/.gitignore`**: Create it automatically (Step 0) — prevents accidental commits
- **No input files found for any sub-discoverer**: STOP with error message (Step 2)
- **Sub-discoveries ran but produced no artifacts**: STOP with error message (Step 3)
- **Sub-discoverer fails**: STOP and report exact failure point and which sub-discoverer failed
- **Output file validation fails**: STOP and report schema errors
- **Extra files created (README, reports, etc.)**: Failure. Discover must produce ONLY the JSON artifact files.

## Scope Boundary

**This phase covers Discover & Analysis ONLY.**

FORBIDDEN — Do NOT include ANY of:

- GCP service names, recommendations, or equivalents
- Migration strategies, phases, or timelines
- Terraform generation for GCP
- Cost estimates or comparisons
- Effort estimates

**Your ONLY job: Inventory what exists in AWS. Nothing else.**
