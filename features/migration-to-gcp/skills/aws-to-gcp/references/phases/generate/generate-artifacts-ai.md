# Generate Phase: AI Artifact Generation

> Loaded by generate.md when generation-ai.json and gcp-design-ai.json exist.

**Execute ALL steps in order. Do not skip or optimize.**

## Overview

Generate migration artifacts from the AI migration plan and design. Artifacts vary by gateway type detected in discovery.

**Outputs (all users):**

- `ai-migration/setup_agent_platform.sh` -- Gemini Enterprise Agent Platform (GEAP; formerly Vertex AI) API enablement and service account setup
- `ai-migration/test_comparison.py` -- A/B test harness (always Python; skipped when `model_migration_needed` is false — see Step 0)

**Outputs (direct SDK users -- `ai_framework` = `"direct"`):**

- `ai-migration/provider_adapter.{py,js,go}` -- Provider abstraction with feature flag

**Outputs (gateway users -- `ai_framework` != `"direct"`):**

- `ai-migration/gateway_config.{yaml,py,json}` -- Gateway-specific configuration snippet

**Outputs (if user opted into model evaluation in generate-ai.md Part 0):**

- `ai-migration/eval-prompts.jsonl` -- Evaluation prompt dataset
- `ai-migration/run-evaluation.sh` -- GEAP Evals job script

**Outputs (agent workloads -- `gcp-design-ai.json` -> `agent_placement[]` non-empty):**

- `ai-migration/agent-runtime-migration.md` -- agents-cli redeploy runbook (emitted by Step 3D)

## Prerequisites

Read from `$MIGRATION_DIR/`:

- `gcp-design-ai.json` (REQUIRED) -- AI architecture with model mappings and code migration plan
- `generation-ai.json` (REQUIRED) -- AI migration plan with timeline and rollback strategy
- `ai-workload-profile.json` (REQUIRED) -- AI workload profile with models, languages, and capabilities

If any required file is missing: **STOP**. Output: "Missing required artifact: [filename]. Complete the prior phase that produces it."

---

## Step 0: Determine Artifact Path

Check `preferences.json` -> `ai_constraints.ai_framework.value`:

- `"direct"` or absent -> Generate provider adapter (Step 1) + setup (Step 3) + test harness (Step 2)
- `"llm_router"`, `"api_gateway"`, `"voice_platform"`, or `"framework"` -> Skip Step 1, generate gateway config (Step 3B) instead
- `"adk"` alone selects neither branch above — it routes to Step 3D (no SDK/provider swap to generate).

Compute `model_migration_needed` = any `gcp-design-ai.json` -> `vertex_models[]` entry WITHOUT `already_on_target: true`. If `false`, SKIP Steps 1, 2, 3B, and 3C (there is no provider swap to adapt or A/B-test) — still run Step 3 (setup) and Step 3D.

**Determine language** (direct SDK users only): Read `ai-workload-profile.json` -> `integration.languages` array. Use the first entry: `"python"` -> `.py`, `"javascript"`/`"typescript"` -> `.js`, `"go"` -> `.go`, `"php"` -> `.php`, other/unknown -> `.py`. Never silently emit a different language than the estate uses — a PHP estate gets a PHP adapter (with the PHP support-boundary warning below), not a Python one.

---

## Step 1: Generate Provider Adapter (Direct SDK Only)

Generate `ai-migration/provider_adapter.{py,js,go}` -- an abstraction layer that lets the user switch between the source AI provider and Agent Platform via an environment variable.

**Requirements:**

- Read `AI_PROVIDER` env var to select provider: `bedrock` (current), `vertex_ai` (target), `shadow` (both -- return source response, log Agent Platform response)
- Expose only the methods matching capabilities in `ai-workload-profile.json` -> `integration.capabilities_summary`:
  - `text_generation: true` -> `generate(prompt) -> str`
  - `streaming: true` -> `generate_stream(prompt) -> Iterator[str]`
  - `embeddings: true` -> `embed(text) -> list[float]`
- **Source provider class**: Use SDK imports from `ai-workload-profile.json` -> `integration.sdk_imports`. Use model IDs from `ai-workload-profile.json` -> `models[].model_id`.
- **Agent Platform provider class**: Use the `google-cloud-aiplatform` SDK (`GenerativeModel.generate_content` for generate, streaming variant for streaming, `TextEmbeddingModel.get_embeddings` for embeddings). Use model IDs from `gcp-design-ai.json` -> `ai_architecture.vertex_models[].gcp_model_id`. Use region from `preferences.json` -> `design_constraints.target_region`.
- **Shadow mode**: Send requests to both providers, return source response, log Agent Platform response for comparison.
- Include error handling and logging for API calls.

For JS: use `@google-cloud/vertexai` + `@aws-sdk/client-bedrock-runtime`. For Go: use `cloud.google.com/go/aiplatform` + `github.com/aws/aws-sdk-go-v2/service/bedrockruntime`.

**For PHP** (`aws/aws-sdk-php` as the source class): the Agent Platform provider class uses the **official GA GAPIC `google/cloud-ai-platform`** (`Google\Cloud\AIPlatform\V1\Client\PredictionServiceClient` — `generateContent`/`streamGenerateContent` against `publishers/google/models/<model>`; verify the surface at generation time) or plain REST with ADC. **There is NO official Google Gen AI PHP SDK** (verified 2026-08-28: none among the `google/*` Packagist vendor packages) — NEVER emit a community Gemini/Vertex PHP package into generated code. **MANDATORY PHP warning** (in the adapter header comment AND the phase summary): "PHP support boundary: Google's official PHP surface for Gemini is the low-level `google/cloud-ai-platform` GAPIC / REST — no official high-level Gen AI PHP SDK exists. This adapter uses the official GAPIC only. Capabilities without an official PHP surface are listed below and require REST or a service in a supported language." List each needed capability lacking an official PHP path.

---

## Step 2: Generate Test Comparison Harness

Generate `ai-migration/test_comparison.py` -- always Python regardless of adapter language.

**Requirements:**

- Accept prompts from a JSON file (`--prompts`) or use built-in defaults (`--quick`)
- Run each prompt against both the source provider and Agent Platform
- Measure per-prompt: latency (ms), success/failure, response text (truncated to 500 chars)
- Compute summary statistics: p50/p95/mean latency per provider, quality score (trait matching against expected traits), pass/fail criteria
- Pass criteria: Agent Platform latency <= 2x source latency, mean quality score >= 0.9
- Output structured JSON to `--output` (default: `comparison_results.json`)
- Built-in test prompts: include 3-5 prompts based on `ai-workload-profile.json` -> `models[].usage_context` covering the primary use case
- Import the provider adapter via `from provider_adapter import get_provider`

---

## Step 3: Generate Agent Platform Setup Script

Generate `ai-migration/setup_agent_platform.sh`.

**Requirements:**

- Dry-run by default (`--execute` flag to run for real)
- Step 1 -- Enable the Agent Platform API: `gcloud services enable aiplatform.googleapis.com`
- Step 2 -- Create service account: Create a service account with `roles/aiplatform.user` for Agent Platform access
- Step 3 -- Print required environment variables: `GOOGLE_CLOUD_PROJECT`, `GOOGLE_CLOUD_REGION`, `AI_PROVIDER=vertex_ai`, model IDs
- Step 4 -- Verification: Test Agent Platform access with a simple `generate_content` call using the primary model
- If `$MIGRATION_DIR/terraform/` exists, print coordination note: "Ensure the service account is referenced in compute.tf service configurations"
- Use region from `preferences.json` -> `design_constraints.target_region`

---

## Step 3B: Generate Gateway Configuration (Gateway Users Only)

Skip if `ai_framework` = `"direct"` or absent. Read `preferences.json` -> `ai_constraints.ai_framework.value` to determine format.

**`"llm_router"`** -> Generate `gateway_config.yaml` (LiteLLM format):

- Map each model from `gcp-design-ai.json` to a `vertex_ai/MODEL_ID` entry with `vertex_project` and `vertex_location`
- Include embedding model entry if embeddings are used
- Note required env vars: `GOOGLE_APPLICATION_CREDENTIALS` or Workload Identity configuration

**`"framework"`** -> Generate `gateway_config.py`:

- Show before/after import swap for the detected framework (`ai-workload-profile.json` -> `integration.sdk_imports`)
- LangChain: `langchain_aws.ChatBedrock` -> `langchain_google_vertexai.ChatVertexAI` (or `langchain_openai.ChatOpenAI` -> `langchain_google_vertexai.ChatVertexAI`)
- LlamaIndex: `llama_index.llms.bedrock_converse` -> `llama_index.llms.vertex.Vertex`
- Include pip install note for the Google Cloud package

**`"voice_platform"`** -> Generate `gateway_config.json`:

- Dashboard configuration steps: add Agent Platform as provider, set model ID, set project/region, test before switching production
- Include the Agent Platform model ID and region from design artifacts

**`"api_gateway"`** -> Generate `gateway_config.yaml`:

- Upstream URL: `https://{region}-aiplatform.googleapis.com`
- Auth: GCP OAuth2 or service account key
- Note: the Gemini generateContent endpoint is `POST /v1/projects/{project}/locations/{region}/publishers/google/models/{model}:generateContent`
- Include gateway-specific notes (Kong plugin, Apigee proxy)

---

## Step 3C: Generate Evaluation Artifacts (If User Opted In)

Skip if the user did not opt into model evaluation in `generate-ai.md` Part 0.

**`eval-prompts.jsonl`**: Generate 10-20 domain-specific prompts in JSONL format (`{"prompt": "...", "referenceResponse": "", "category": "..."}`). Base prompts on `ai-workload-profile.json` -> `models[].usage_context`. Include function-calling prompts if `capabilities_summary.function_calling` is true, retrieval prompts if RAG patterns were detected. Include 2-3 edge case prompts.

**`run-evaluation.sh`**: Dry-run by default. Creates GCS bucket, uploads prompts, runs evaluation using the GEAP Evals SDK, downloads results. Use the same model IDs and region as `setup_agent_platform.sh`.

---

## Step 3D: Generate Agent Runtime Migration Runbook

**Gate:** `gcp-design-ai.json` -> `ai_architecture.agent_placement[]` is non-empty with at least one `gcp_service: "Agent Runtime"`. Otherwise skip.

Emit `ai-migration/agent-runtime-migration.md` containing, per placement:

1. **Source -> target line**: framework, `aws_host` -> Agent Runtime on the Gemini Enterprise Agent Platform.
2. **Prerequisites**: `uv tool install google-agents-cli` (installs `agents-cli`); a Dockerfile for the agent service (if missing: `agents-cli scaffold enhance . --deployment-target agent_runtime`).
3. **Deploy command with real values** (from `agent_placement[].sizing`, `preferences.json` -> `design_constraints.target_region`, and the run's GCP project): `agents-cli deploy --deployment-target agent_runtime --project <gcp_project> --region <target_region> --cpu <cpu> --memory <memory> --concurrency <n> --min-instances <n> --max-instances <n>`, plus `--secrets ENV=SECRET_ID` pairs for detected secret-backed env vars — EXCLUDING source-provider credentials (AWS access keys, Bedrock/OpenAI model keys made obsolete by step 4): porting them re-creates the cross-cloud model dependency the migration removes. Note: deploys take 5-10 minutes — use `--no-wait` and poll with `--status`.
4. **Model rebinding (when `agent_placement[].model_rebinding` is non-null)**: the agent code still binds the source provider's model — apply the one-line `model_rebinding.change` BEFORE deploying: LiteLLM route `LiteLlm(model="bedrock/<id>")` -> `LiteLlm(model="vertex_ai/<gcp_model_id>")` (Claude and other partner models keep the LiteLLM wrapper), or drop the wrapper for the framework-native string (`model="<gemini-model-id>"`) when the mapped target is a Gemini model. Model auth is ambient on Agent Runtime (ADC) — no API-key secret replaces the Bedrock credentials. An agent left calling Bedrock from Agent Runtime is a rollback posture, not a target state: if the user wants it temporarily, it needs the AWS credentials as explicit `--secrets` plus a removal date in the runbook.
5. **Session-state migration**: self-managed store (DynamoDB/ElastiCache) -> managed Sessions (`VertexAiSessionService`). Spell out the export/backfill vs start-fresh decision and leave it to the user.
6. **Testing**: `agents-cli run --url <service-url> "prompt"` smoke check.
7. **Rollback plan (MANDATORY)**: two mechanisms, spell out both — (a) Agent Runtime supports runtime revisions (v1 `reasoningEngines.runtimeRevisions`; verify the org's rollback command surface live at generation time), and (b) each `agents-cli deploy` creates a new engine while the previous one keeps serving until deleted, so re-pointing the caller is an instant blue/green fallback. Git-based fix-forward remains the CI path. Keep the AWS-side agent running until validation passes.
8. **Ops notes**: logs via `resource.type="aiplatform.googleapis.com/ReasoningEngine"`; grant Secret Manager access to the platform service agent (`gcp-sa-aiplatform-re`).
9. **Governance & registration** (per `design-refs/agent-governance.md`): register the agent (and any MCP servers/tool endpoints it calls) in **Agent Registry**; surface to business users via `agents-cli publish gemini-enterprise` (see `google-agents-cli-publish`). When the AWS estate had controls on the agent's path (API GW authorizer, task-role scoping, egress rules, Guardrails), map them to **Agent Gateway** + Agent Identity (`--enable-agent-identity`, `--agent-gateway[-egress]`) with IAP `roles/iap.egressor` per tool and Model Armor content screening — staged **deploy → register → DRY_RUN → enforce**, never enforcement-first. No Terraform is emitted for governance resources; the runbook carries the commands.

No Terraform is generated for Agent Runtime placements (no gcloud/Terraform deploy surface in this plugin) — `generate-artifacts-infra.md` emits a comment reference instead.

---

## Step 4: Self-Check

Verify all generated artifacts:

- [ ] Provider adapter (or gateway config) uses actual model IDs from `gcp-design-ai.json` -- no placeholders
- [ ] Only capabilities present in `capabilities_summary` have methods/tests generated
- [ ] Feature flag (`AI_PROVIDER` env var) controls provider selection in adapter
- [ ] Test harness includes domain-specific prompts from `usage_context`
- [ ] Test harness produces structured JSON output with latency and quality metrics
- [ ] Setup script has correct region from `preferences.json`
- [ ] Setup script service account follows least privilege
- [ ] All scripts default to dry-run mode
- [ ] Evaluation artifacts (if generated) have correct model IDs and region
- [ ] Agent runbook (if generated) uses real project/region/sizing values from design artifacts — no placeholders; includes the rollback plan (runtime revisions + previous-engine fallback — never a "no rollback" claim); carries the model-rebinding step whenever any `agent_placement[].model_rebinding` is non-null, and its `--secrets` list contains no source-provider credentials
- [ ] No hardcoded credentials in any file

## Phase Completion

Report generated files to the parent orchestrator. **Do NOT update `.phase-status.json`** -- the parent `generate.md` handles phase completion.

Output:

```
Generated AI migration artifacts:
- ai-migration/setup_agent_platform.sh
- ai-migration/test_comparison.py
- ai-migration/provider_adapter.{py|js|go}    # Direct SDK users only
- ai-migration/gateway_config.{yaml|py|json}  # Gateway users only
- ai-migration/eval-prompts.jsonl              # If evaluation opted in
- ai-migration/run-evaluation.sh               # If evaluation opted in
- ai-migration/agent-runtime-migration.md      # Agent workloads only

Gateway type: [ai_framework value]
Language: [detected language]
Models to migrate: [count] models
Capabilities covered: [list from capabilities_summary]
```
