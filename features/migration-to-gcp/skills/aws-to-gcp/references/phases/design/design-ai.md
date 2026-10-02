# Design Phase: AI Workloads (Gemini Enterprise Agent Platform — GEAP; formerly Vertex AI)

> Loaded by `design.md` when `ai-workload-profile.json` exists.

**Execute ALL steps in order. Do not skip or optimize.**

---

## Step 0: Load Inputs

Read `$MIGRATION_DIR/ai-workload-profile.json`:

- `summary.ai_source` -- `"bedrock"`, `"openai"`, `"both"`, `"other"`
- `summary.agent_workloads_detected` + `agent_workloads[]` -- Detected agent-framework workloads; drives Part 4B (absent means false)
- `models[]` -- Detected AI models with service, capabilities, evidence
- `integration` -- SDK, frameworks, languages, gateway type, capability summary
- `infrastructure[]` -- Terraform resources related to AI (may be empty)
- `current_costs` -- Present only if billing data was provided

Read `$MIGRATION_DIR/preferences.json` -> `ai_constraints` (if present). If absent: use defaults (prefer managed Agent Platform, no latency constraint, no budget cap).

**Load source-specific design reference based on `ai_source`:**

- `"bedrock"` -> load `references/design-refs/ai-bedrock-to-agent-platform.md`
- `"openai"` -> load `references/design-refs/ai-openai-to-agent-platform.md`
- `"both"` -> load both files
- `"other"` or absent -> load `references/design-refs/ai.md` (traditional ML rubric)

---

## Part 1: Agent Platform Model Selection

For each model in `models[]`, select the best-fit Agent Platform model using the loaded design reference mapping tables. Do NOT use a hardcoded mapping -- the design-ref files contain tier-organized tables with pricing and competitive analysis.

**Apply user preference overrides from `ai_constraints`:**

| Preference                | Override                                                                                                                                                  |
| ------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `ai_priority = "cost"`    | Prefer "Winner" column; flag if source is cheaper                                                                                                         |
| `ai_priority = "quality"` | Prefer gemini-3.7-flash (newest GA — beats the older-gen 3.1 Pro Preview broadly); reserve gemini-3.1-pro-preview (thinking) for extended-reasoning needs |
| `ai_priority = "speed"`   | Prefer the newest GA Flash (gemini-3.7-flash as of 2026-08-28 — verify the Flash line live)                                                               |
| `ai_latency = "critical"` | Prefer smaller/faster Flash-class models (gemini-3.7-flash first, then gemini-3.5-flash-lite)                                                             |
| `ai_latency = "flexible"` | Any model; flag Batch API for cost savings                                                                                                                |

**Already on target:** if a detected model is already a Gemini model (`model_id` starts with `gemini-`), skip the design-reference model lookup for it (this matters when `ai_source` is `"other"` and the traditional-ML rubric was loaded): set `already_on_target: true` on its `vertex_models[]` entry, `gcp_model_id` = the same model, `price_comparison` = `"n/a — already on target"`, and note in the summary that no model migration is required. Common for Google ADK estates.

**Stay-or-migrate assessment per model:**

- Agent Platform cheaper -> `"strong_migrate"`
- Agent Platform within 25% of source AND priority != cost -> `"moderate_migrate"`
- Source > 25% cheaper AND priority = cost -> `"weak_migrate"` or `"recommend_stay"`

Overall assessment = weakest across all models. If any `"recommend_stay"`, flag prominently.

**Model comparison table** (include in output and user summary): Model, Provider, Max Context, Input/Output Price per 1M, Price Comparison, Streaming, Function Calling, Assessment. For `already_on_target` entries set `source_provider_price` and `vertex_price` to `null` (no fabricated pricing) with `price_comparison` = `"n/a — already on target"`.

---

## Part 1B: Volume-Based Strategy

If `ai_token_volume` is `"high"`, generate a `tiered_strategy`:

| Tier | Traffic | Model Selection                        | Use Cases                                            |
| ---- | ------- | -------------------------------------- | ---------------------------------------------------- |
| 1    | 60%     | Gemini 3.5 Flash-Lite (or 3.7 Flash)   | Classification, extraction, short answers, routing   |
| 2    | 30%     | Gemini 3.7 Flash or Llama 4 Maverick   | Summarization, moderate generation, Q&A with context |
| 3    | 10%     | Gemini 3.1 Pro Preview (thinking mode) | Reasoning, long-form, agentic tasks, tool use        |

Set `tiered_strategy: null` for low/medium volume.

---

## Part 2: Feature Parity Validation

For each capability in `integration.capabilities_summary` that is `true`, check Agent Platform parity:

| Capability        | Amazon Bedrock                   | Agent Platform                                | Parity                                      |
| ----------------- | -------------------------------- | --------------------------------------------- | ------------------------------------------- |
| Text Generation   | Converse API                     | GenerativeModel API                           | Full                                        |
| Streaming         | InvokeModelWithResponseStream    | stream_generate_content                       | Full                                        |
| Function Calling  | Tool use in Converse API         | Tool declarations                             | Full                                        |
| Embeddings        | Titan Embeddings via InvokeModel | Text Embedding API                            | Full                                        |
| Vision/Multimodal | Claude multimodal messages       | Gemini multimodal input                       | Full                                        |
| Batch Processing  | Batch Inference (async)          | BatchPredictionJob                            | Full                                        |
| Fine-tuning       | Bedrock Custom Model             | GEAP Managed Training                         | Full                                        |
| Grounding / RAG   | Bedrock Knowledge Bases          | Agent Search & Grounding                      | Full                                        |
| Agents            | Bedrock Agents                   | Rebuild as Google ADK agents on Agent Runtime | Partial (rebuild — code, not config import) |

Record `capability_gaps[]` for any Partial or None parity.

---

## Part 3: Analyze Detected Workloads

For each model in `models[]`, record:

- **Workload type**: text generation, embeddings, vision, code generation, custom model
- **Integration pattern mapping**:

| AWS Pattern                     | GCP Pattern                                  | Effort |
| ------------------------------- | -------------------------------------------- | ------ |
| `direct_sdk` (boto3)            | Agent Platform SDK (google-cloud-aiplatform) | Medium |
| `framework` (LangChain+Bedrock) | LangChain + Agent Platform                   | Low    |
| `rest_api`                      | Agent Platform REST API                      | Medium |
| `mixed`                         | Match per-model                              | Varies |

- **Migration complexity**: Low / Medium / High

---

## Part 4: Infrastructure Mapping

Map AWS AI infrastructure to GCP equivalents:

| AWS Resource                          | GCP Equivalent                                |
| ------------------------------------- | --------------------------------------------- |
| Bedrock Model Access (serverless)     | GEAP Endpoint (serverless, no infra)          |
| OpenSearch Serverless / Bedrock KB    | Vector Search on GEAP or Agent Search         |
| SageMaker Feature Store               | Feature Store on GEAP                         |
| S3 + Bedrock training job config      | GEAP Dataset + GCS                            |
| Step Functions + Bedrock              | GEAP Pipelines                                |
| Bedrock Agents (`aws_bedrockagent_*`) | Google ADK agents on Agent Runtime (rebuild)  |
| Bedrock AgentCore runtime             | Agent Runtime (direct managed-runtime analog) |

IAM roles with Bedrock/SageMaker permissions -> Google Service Account with Agent Platform roles (`roles/aiplatform.user`). Confidence = `inferred`.

---

## Part 4B: Agent Workload Placement

**Gate: run only when `summary.agent_workloads_detected` is `true`.**

Load `references/design-refs/agent-runtime.md`. For each `agent_workloads[]` entry:

1. Run the rubric's eliminators; apply its priority rule (Agent Runtime default; trade-off card with Agent Runtime listed first as "Recommended (default)"; headless default; record the pick in `preferences.json.design_choices[]`).
2. Write one `ai_architecture.agent_placement[]` entry: `framework`, `language`, `aws_host`, `gcp_service` (`"Agent Runtime"` / `"Cloud Run"` / `"GKE"`), `eliminator_applied` (string or `null`), `session_state_migration`, `model_rebinding`, `sizing` (`cpu`, `memory`, `concurrency`, `min_instances`, `max_instances`), `rationale`, `confidence`.
   - `model_rebinding` — join the workload's `model_binding` (from `agent_workloads[]`) to its `vertex_models[]` entry: `null` when the bound model is `already_on_target` (or `model_binding` is `null`); otherwise `{from, to, change}` where `from` is the source binding (e.g. `LiteLlm(model="bedrock/anthropic.claude-sonnet-4-6")`), `to` is the mapped binding, and `change` is the one-line edit — LiteLLM route `bedrock/<id>` → `vertex_ai/<gcp_model_id>` (partner models stay on LiteLLM), or drop the wrapper for the framework-native string when the mapped target is a Gemini model. A Bedrock/OpenAI-bound agent still places on Agent Runtime — the rebinding travels WITH the placement, never blocks it.
3. **Consistency check:** if the host resource also appears in `gcp-design.json` (design-infra ran first and applied its agent gate), the two `gcp_service` values MUST match. On mismatch: add a `warnings[]` entry and defer to the rubric's answer.
4. If `aws_host` is `null` (code-only discovery), still emit the placement with `aws_host: null` plus a warning that the agent redeploy is planned independently of any VM/container mapping — no silent loss.

---

## Part 5: Code Migration Plan

For each detected `integration.pattern` and `ai_source`, generate before/after migration examples.

**Patterns to include (matched to detected language and source):**

| Pattern              | Source                                             | Target                                          | Key Change                                                                                                                                   |
| -------------------- | -------------------------------------------------- | ----------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------- |
| Direct SDK           | boto3 Converse API                                 | Agent Platform SDK                              | `converse()` -> `generate_content()`                                                                                                         |
| Direct SDK           | OpenAI SDK                                         | Agent Platform SDK                              | `completions.create()` -> `generate_content()`                                                                                               |
| Direct SDK (PHP)     | aws-sdk-php `invokeModel`/`converse` or openai-php | `google/cloud-ai-platform` GAPIC (official, GA) | `$client->converse([...])` -> `PredictionServiceClient::generateContent()`; no official Gen AI PHP SDK — GAPIC/REST only, see PHP rule below |
| LangChain            | ChatBedrock / ChatOpenAI                           | ChatVertexAI                                    | Swap import and model_id                                                                                                                     |
| LlamaIndex           | Bedrock / OpenAI LLM                               | Agent Platform LLM                              | Swap import                                                                                                                                  |
| LLM Router (LiteLLM) | Any                                                | Config change                                   | `model="vertex_ai/<model_id>"` (1 line)                                                                                                      |
| Embeddings           | Titan Embeddings v2                                | Text Embedding API                              | `embed_content()` with model name                                                                                                            |
| Streaming            | `converse_stream`                                  | `stream_generate_content`                       | Iterate over `GenerationResponse` chunks                                                                                                     |

Generate concrete code examples using actual model IDs from the selected Agent Platform models. Only include patterns matching the detected integration.

**PHP support-boundary rule (BINDING — applies when `integration.languages` includes `php`):**

- Migrated PHP code may depend ONLY on **official `google/*` Composer packages** (Packagist vendor `google`): `google/cloud-ai-platform` (LLM — GA GAPIC), `google/cloud-storage`, `google/cloud-firestore`, `google/cloud-pubsub`, `google/cloud-secret-manager`, `google/cloud-tasks`, etc. Verify the specific package exists and is GA at design time; NEVER recommend community Gemini/Vertex PHP SDKs.
- **There is no official Google Gen AI PHP SDK and no PHP ADK** (verified 2026-08-28). For every capability the estate needs, check the official PHP path; where none exists, add a `warnings[]` entry — `"PHP support gap: <capability> has no official Google Cloud PHP surface; options: REST with ADC, or move this component to a supported language"` — and surface it prominently in the user summary. Do not silently downgrade or omit the capability.
- **PHP agent workloads** (`agent_workloads[].language = "php"`, framework `custom`): Agent Runtime hosts custom containers ("any language works" — all three targets are container-based), but ADK benefits (scaffolding, managed-session wiring, agents-cli templates) are Python/TS/Go/Java only. Present the trade-off explicitly: custom-container PHP agent on Agent Runtime vs Cloud Run, or rebuild as a (Python/TS/Go/Java) ADK agent — with a warning either way, never a silent default.

---

## Part 6: Generate Output

Write `gcp-design-ai.json` to `$MIGRATION_DIR/`.

**Schema -- top-level fields:**

| Field                                 | Type        | Description                                                                                                                                                                                                                                                                                         |
| ------------------------------------- | ----------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `metadata`                            | object      | `phase`, `focus`, `ai_source`, `vertex_models_selected`, `timestamp`                                                                                                                                                                                                                                |
| `ai_architecture.honest_assessment`   | string      | `"strong_migrate"`, `"moderate_migrate"`, `"weak_migrate"`, `"recommend_stay"`                                                                                                                                                                                                                      |
| `ai_architecture.tiered_strategy`     | object/null | Tiered model routing (null for low/medium volume)                                                                                                                                                                                                                                                   |
| `ai_architecture.vertex_models`       | array       | Per-model: `aws_model_id`, `gcp_model_id`, `capabilities_matched[]`, `capability_gaps[]`, `honest_assessment`, `source_provider_price`, `vertex_price`, `price_comparison`, `migration_complexity`                                                                                                  |
| `ai_architecture.capability_mapping`  | object      | Per-capability: `parity` (full/partial/none), `notes`                                                                                                                                                                                                                                               |
| `ai_architecture.code_migration`      | object      | `primary_pattern`, `framework`, `files_to_modify[]`, `dependency_changes`                                                                                                                                                                                                                           |
| `ai_architecture.infrastructure`      | array       | AWS resource -> GCP equivalent mappings with confidence                                                                                                                                                                                                                                             |
| `ai_architecture.services_to_migrate` | array       | AWS service -> GCP service with effort and notes                                                                                                                                                                                                                                                    |
| `ai_architecture.agent_placement`     | array       | Per agent workload: `framework`, `language`, `aws_host`, `gcp_service` (Agent Runtime/Cloud Run/GKE), `eliminator_applied`, `session_state_migration`, `model_rebinding` (`null` when already on a Agent Platform model), `sizing`, `rationale`, `confidence`. Empty array when no agent workloads. |

## Validation Checklist

- [ ] `metadata.ai_source` matches `summary.ai_source` from input
- [ ] Every model in `models[]` has a corresponding `vertex_models` entry
- [ ] Every `vertex_models[]` entry has pricing (`source_provider_price`, `vertex_price`, `price_comparison`) — for `already_on_target` entries the two prices are `null` and `price_comparison` is `"n/a — already on target"`
- [ ] `capability_mapping` covers every `true` capability from `capabilities_summary`
- [ ] `code_migration.primary_pattern` matches `integration.pattern`
- [ ] All model IDs use current Agent Platform model identifiers
- [ ] `honest_assessment` logic is consistent (weakest model drives overall)
- [ ] When `agent_workloads_detected`: every `agent_workloads[]` entry has a matching `agent_placement[]` entry; `gcp_service` is `Agent Runtime` unless `eliminator_applied` is set
- [ ] Every agent workload whose `model_binding` names a non-Agent-Platform model (Bedrock/OpenAI/Azure) has a non-null `agent_placement[].model_rebinding` consistent with its `vertex_models[]` mapping
- [ ] `already_on_target` models have no fabricated migration pricing

## Present Summary

After writing `gcp-design-ai.json`, present under 25 lines:

1. Overall honest assessment
2. Model comparison table (source -> Agent Platform, price comparison, assessment per model)
3. Integration pattern and migration complexity
4. Capability gaps (if any)
5. If weak_migrate or recommend_stay: flag prominently with cost justification
6. Agent placement: [framework] on [aws_host] -> [gcp_service] (default Agent Runtime; eliminators listed if applied)
