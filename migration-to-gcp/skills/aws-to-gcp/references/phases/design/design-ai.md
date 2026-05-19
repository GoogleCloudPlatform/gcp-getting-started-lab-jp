# Design Phase: AI Workloads (Vertex AI)

> Loaded by `design.md` when `ai-workload-profile.json` exists.

**Execute ALL steps in order. Do not skip or optimize.**

---

## Step 0: Load Inputs

Read `$MIGRATION_DIR/ai-workload-profile.json`:

- `summary.ai_source` -- `"bedrock"`, `"openai"`, `"both"`, `"other"`
- `models[]` -- Detected AI models with service, capabilities, evidence
- `integration` -- SDK, frameworks, languages, gateway type, capability summary
- `infrastructure[]` -- Terraform resources related to AI (may be empty)
- `current_costs` -- Present only if billing data was provided

Read `$MIGRATION_DIR/preferences.json` -> `ai_constraints` (if present). If absent: use defaults (prefer managed Vertex AI, no latency constraint, no budget cap).

**Load source-specific design reference based on `ai_source`:**

- `"bedrock"` -> load `references/design-refs/ai-bedrock-to-vertex.md`
- `"openai"` -> load `references/design-refs/ai-openai-to-vertex.md`
- `"both"` -> load both files
- `"other"` or absent -> load `references/design-refs/ai.md` (traditional ML rubric)

---

## Part 1: Vertex AI Model Selection

For each model in `models[]`, select the best-fit Vertex AI model using the loaded design reference mapping tables. Do NOT use a hardcoded mapping -- the design-ref files contain tier-organized tables with pricing and competitive analysis.

**Apply user preference overrides from `ai_constraints`:**

| Preference                | Override                                                 |
| ------------------------- | -------------------------------------------------------- |
| `ai_priority = "cost"`    | Prefer "Winner" column; flag if source is cheaper        |
| `ai_priority = "quality"` | Prefer Gemini 3.1 Pro Preview regardless of cost                 |
| `ai_priority = "speed"`   | Prefer Gemini 3 Flash Preview (latest Flash-class preview); use Gemini 2.5 Flash if GA-only is required |
| `ai_latency = "critical"` | Prefer smaller/faster Flash-class models (Gemini 3 Flash Preview first) |
| `ai_latency = "flexible"` | Any model; flag Batch API for cost savings               |

**Stay-or-migrate assessment per model:**

- Vertex AI cheaper -> `"strong_migrate"`
- Vertex AI within 25% of source AND priority != cost -> `"moderate_migrate"`
- Source > 25% cheaper AND priority = cost -> `"weak_migrate"` or `"recommend_stay"`

Overall assessment = weakest across all models. If any `"recommend_stay"`, flag prominently.

**Model comparison table** (include in output and user summary): Model, Provider, Max Context, Input/Output Price per 1M, Price Comparison, Streaming, Function Calling, Assessment.

---

## Part 1B: Volume-Based Strategy

If `ai_token_volume` is `"high"`, generate a `tiered_strategy`:

| Tier | Traffic | Model Selection                  | Use Cases                                            |
| ---- | ------- | -------------------------------- | ---------------------------------------------------- |
| 1    | 60%     | Gemini 3 Flash Preview            | Classification, extraction, short answers, routing   |
| 2    | 30%     | Gemini 3.1 Pro Preview or Llama 3.3 70B | Summarization, moderate generation, Q&A with context |
| 3    | 10%     | Gemini 3.1 Pro Preview (thinking mode)   | Reasoning, long-form, agentic tasks, tool use        |

Set `tiered_strategy: null` for low/medium volume.

---

## Part 2: Feature Parity Validation

For each capability in `integration.capabilities_summary` that is `true`, check Vertex AI parity:

| Capability        | Amazon Bedrock                   | Vertex AI                         | Parity  |
| ----------------- | -------------------------------- | --------------------------------- | ------- |
| Text Generation   | Converse API                     | GenerativeModel API               | Full    |
| Streaming         | InvokeModelWithResponseStream    | stream_generate_content           | Full    |
| Function Calling  | Tool use in Converse API         | Tool declarations                 | Full    |
| Embeddings        | Titan Embeddings via InvokeModel | Text Embedding API                | Full    |
| Vision/Multimodal | Claude multimodal messages       | Gemini multimodal input           | Full    |
| Batch Processing  | Batch Inference (async)          | BatchPredictionJob                | Full    |
| Fine-tuning       | Bedrock Custom Model             | Vertex AI Tuning                  | Full    |
| Grounding / RAG   | Bedrock Knowledge Bases          | Vertex AI Search & Grounding      | Full    |
| Agents            | Bedrock Agents                   | Vertex AI Agent Builder (Agentspace) | Full |

Record `capability_gaps[]` for any Partial or None parity.

---

## Part 3: Analyze Detected Workloads

For each model in `models[]`, record:

- **Workload type**: text generation, embeddings, vision, code generation, custom model
- **Integration pattern mapping**:

| AWS Pattern                    | GCP Pattern                      | Effort |
| ------------------------------ | -------------------------------- | ------ |
| `direct_sdk` (boto3)           | Vertex AI SDK (google-cloud-aiplatform) | Medium |
| `framework` (LangChain+Bedrock) | LangChain + Vertex AI           | Low    |
| `rest_api`                     | Vertex AI REST API               | Medium |
| `mixed`                        | Match per-model                  | Varies |

- **Migration complexity**: Low / Medium / High

---

## Part 4: Infrastructure Mapping

Map AWS AI infrastructure to GCP equivalents:

| AWS Resource                              | GCP Equivalent                                     |
| ----------------------------------------- | -------------------------------------------------- |
| Bedrock Model Access (serverless)         | Vertex AI Endpoint (serverless, no infra)           |
| OpenSearch Serverless / Bedrock KB        | Vertex AI Vector Search or Vertex AI Search         |
| SageMaker Feature Store                   | Vertex AI Feature Store                             |
| S3 + Bedrock training job config          | Vertex AI Dataset + GCS                             |
| Step Functions + Bedrock                  | Vertex AI Pipelines                                 |

IAM roles with Bedrock/SageMaker permissions -> Google Service Account with Vertex AI roles. Confidence = `inferred`.

---

## Part 5: Code Migration Plan

For each detected `integration.pattern` and `ai_source`, generate before/after migration examples.

**Patterns to include (matched to detected language and source):**

| Pattern              | Source                  | Target                      | Key Change                                      |
| -------------------- | ----------------------- | --------------------------- | ----------------------------------------------- |
| Direct SDK           | boto3 Converse API      | Vertex AI SDK               | `converse()` -> `generate_content()`            |
| Direct SDK           | OpenAI SDK              | Vertex AI SDK               | `completions.create()` -> `generate_content()`  |
| LangChain            | ChatBedrock / ChatOpenAI| ChatVertexAI                | Swap import and model_id                        |
| LlamaIndex           | Bedrock / OpenAI LLM    | Vertex AI LLM               | Swap import                                     |
| LLM Router (LiteLLM) | Any                     | Config change               | `model="vertex_ai/<model_id>"` (1 line)         |
| Embeddings           | Titan Embeddings v2     | Text Embedding API          | `embed_content()` with model name               |
| Streaming            | `converse_stream`       | `stream_generate_content`   | Iterate over `GenerationResponse` chunks        |

Generate concrete code examples using actual model IDs from the selected Vertex AI models. Only include patterns matching the detected integration.

---

## Part 6: Generate Output

Write `gcp-design-ai.json` to `$MIGRATION_DIR/`.

**Schema -- top-level fields:**

| Field                                  | Type        | Description                                                                                                                                                                                          |
| -------------------------------------- | ----------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `metadata`                             | object      | `phase`, `focus`, `ai_source`, `vertex_models_selected`, `timestamp`                                                                                                                                 |
| `ai_architecture.honest_assessment`    | string      | `"strong_migrate"`, `"moderate_migrate"`, `"weak_migrate"`, `"recommend_stay"`                                                                                                                       |
| `ai_architecture.tiered_strategy`      | object/null | Tiered model routing (null for low/medium volume)                                                                                                                                                    |
| `ai_architecture.vertex_models`        | array       | Per-model: `aws_model_id`, `gcp_model_id`, `capabilities_matched[]`, `capability_gaps[]`, `honest_assessment`, `source_provider_price`, `vertex_price`, `price_comparison`, `migration_complexity`   |
| `ai_architecture.capability_mapping`   | object      | Per-capability: `parity` (full/partial/none), `notes`                                                                                                                                                |
| `ai_architecture.code_migration`       | object      | `primary_pattern`, `framework`, `files_to_modify[]`, `dependency_changes`                                                                                                                            |
| `ai_architecture.infrastructure`       | array       | AWS resource -> GCP equivalent mappings with confidence                                                                                                                                              |
| `ai_architecture.services_to_migrate`  | array       | AWS service -> GCP service with effort and notes                                                                                                                                                     |

## Validation Checklist

- [ ] `metadata.ai_source` matches `summary.ai_source` from input
- [ ] Every model in `models[]` has a corresponding `vertex_models` entry
- [ ] Every `vertex_models[]` entry has pricing (`source_provider_price`, `vertex_price`, `price_comparison`)
- [ ] `capability_mapping` covers every `true` capability from `capabilities_summary`
- [ ] `code_migration.primary_pattern` matches `integration.pattern`
- [ ] All model IDs use current Vertex AI identifiers
- [ ] `honest_assessment` logic is consistent (weakest model drives overall)

## Present Summary

After writing `gcp-design-ai.json`, present under 25 lines:

1. Overall honest assessment
2. Model comparison table (source -> Vertex AI, price comparison, assessment per model)
3. Integration pattern and migration complexity
4. Capability gaps (if any)
5. If weak_migrate or recommend_stay: flag prominently with cost justification
