# Generate Phase: AI Migration Plan

> Loaded by generate.md when estimation-ai.json exists.

**Execute ALL steps in order. Do not skip or optimize.**

## Prerequisites

Read from `$MIGRATION_DIR/`:

- `gcp-design-ai.json` (REQUIRED) -- AI architecture design from Phase 3
- `estimation-ai.json` (REQUIRED) -- AI cost estimates from Phase 4
- `ai-workload-profile.json` (REQUIRED) -- AI workload profile from Phase 1
- `preferences.json` (REQUIRED) -- User migration preferences from Phase 2

If any required file is missing: **STOP**. Output: "Missing required artifact: [filename]. Complete the prior phase that produces it."

## Part 1: Fast-Track Timeline

Check `preferences.json` -> `ai_constraints.ai_framework` to determine timeline:

**Gateway users (1-3 days)** -- `ai_framework` includes `llm_router`, `api_gateway`, `voice_platform`, or `framework`:

| Gateway Type                      | Migration Action                                                       | Effort            |
| --------------------------------- | ---------------------------------------------------------------------- | ------------------ |
| LLM Router (LiteLLM, OpenRouter)  | Change model string to `vertex_ai/<model_id>`                         | 1 config line     |
| API Gateway (Kong, Apigee)        | Add Vertex AI upstream + OAuth2/service account auth                   | 1-2 config files  |
| Voice Platform (Vapi, Bland.ai)   | Check native Vertex AI support, update dashboard                       | Dashboard config  |
| Framework (LangChain, LlamaIndex) | Swap provider import (e.g., `ChatVertexAI` for `ChatBedrock`)         | 1-5 lines of code |

**Direct SDK users (1-3 weeks)** -- `ai_framework` = `direct`:

- **Week 1:** Enable Vertex AI access, create service account, develop provider adapter with feature flag, unit test
- **Week 2:** Deploy to staging, run A/B comparison, measure latency/quality/cost, tune prompts
- **Week 3:** Gradual rollout (10% -> 50% -> 100%), monitor, disable source provider after 48h stable

**Timeline adjustments:** Single model = shorter; multiple models = +1 week; framework integration = 1-2 weeks; custom inference pipeline = 3 weeks; if alongside infra migration, align with Weeks 3-8.

---

## Part 2: Step-by-Step Migration Guide

Based on `ai-workload-profile.json` -> `integration.pattern` and `integration.languages`, generate SDK migration examples.

**Migration patterns to include (matched to detected language and source):**

| Source SDK             | Target                                    | Key Change                                                                |
| ---------------------- | ----------------------------------------- | ------------------------------------------------------------------------- |
| Bedrock (Python/boto3) | google-cloud-aiplatform                   | `bedrock.converse()` -> `GenerativeModel.generate_content()`              |
| Bedrock (JS)           | @google-cloud/vertexai                    | `ConverseCommand()` -> `model.generateContent()`                          |
| Bedrock (Go)           | cloud.google.com/go/aiplatform            | `bedrockruntime.Converse()` -> `genai.GenerateContent()`                  |
| Bedrock (Java)         | com.google.cloud.aiplatform               | `BedrockRuntimeClient.converse()` -> `GenerativeModel.generateContent()` |
| OpenAI SDK             | google-cloud-aiplatform                   | `client.chat.completions.create()` -> `model.generate_content()`         |
| LiteLLM                | LiteLLM config change                     | `model="bedrock/claude-sonnet"` -> `model="vertex_ai/gemini-2.5-pro"`   |
| LangChain              | langchain_google_vertexai                 | `ChatBedrock`/`ChatOpenAI` -> `ChatVertexAI`                             |
| LlamaIndex             | llama_index.llms.vertex                   | `BedrockConverse` -> `Vertex`                                             |

For each detected language and pattern, generate before/after code examples using actual model IDs from `gcp-design-ai.json`.

Include streaming migration if `capabilities_summary.streaming = true`.

Include embeddings migration (text-embedding-005 via Vertex AI) if `capabilities_summary.embeddings = true`.

---

## Part 3: Rollback Plan

**Feature flag strategy:** `AI_PROVIDER` env var controls routing:

- `bedrock` (default) -- existing provider
- `vertex_ai` -- switch to Vertex AI
- `shadow` -- send to both, return source response (for comparison)

**Rollback triggers:** quality below threshold, P95 latency > 2x baseline, error rate > 1% for 5 min, cost per request > 3x source.

**Rollback steps:** Set `AI_PROVIDER=bedrock` (instant), verify source traffic, monitor 1 hour, investigate, re-attempt.

---

## Part 4: Monitoring and Observability

**Key metrics and alert thresholds:**

| Metric            | Alert Threshold                | Severity |
| ----------------- | ------------------------------ | -------- |
| Error rate        | > 5% for 2 min -> auto-rollback | Critical |
| Latency P95       | > 3x baseline for 5 min        | High     |
| Daily cost        | > 2x projected                 | Medium   |
| Token usage trend | > 120% of estimate             | Low      |
| Response quality  | < 90% of source score          | High     |

**Dashboard panels:** Request volume by provider, latency comparison (P50/P95/P99), error rates, token usage, cost tracking, quality scores.

---

## Part 5: Production Readiness Checklist

- [ ] Vertex AI API enabled in GCP project
- [ ] Service account with `roles/aiplatform.user`
- [ ] Provider adapter deployed and tested in staging
- [ ] A/B test with >= 100 representative prompts
- [ ] Response quality >= 90% of source baseline
- [ ] Latency P95 within 2x of source baseline
- [ ] Error rate < 0.1% in staging
- [ ] Monitoring dashboards and alerting active
- [ ] Rollback procedure documented and tested
- [ ] Cost estimates validated against staging usage

---

## Part 6: Success Criteria

| Category | Criteria            | Target                             |
| -------- | ------------------- | ---------------------------------- |
| Quality  | Response quality    | >= 90% of source baseline          |
| Quality  | Capability coverage | 100% of `ai-workload-profile.json` |
| Latency  | P50                 | Within 1.5x of source              |
| Latency  | P95                 | Within 2x of source                |
| Cost     | Monthly             | Within 20% of `estimation-ai.json` |
| Cost     | Per request         | Within 30% of source per-request   |

---

## Output

Write `generation-ai.json` to `$MIGRATION_DIR/`.

**Schema -- top-level fields:**

| Field                            | Type   | Description                                                                           |
| -------------------------------- | ------ | ------------------------------------------------------------------------------------- |
| `phase`                          | string | `"generate"`                                                                          |
| `generation_source`              | string | `"ai"`                                                                                |
| `timestamp`                      | string | ISO 8601                                                                              |
| `migration_plan`                 | object | `total_weeks`, `approach`, `phases[]` (name, week, activities), `models_to_migrate[]` |
| `step_by_step_guide`             | object | `languages[]`, `primary_pattern`, `files_to_modify[]`, `dependency_changes`           |
| `rollback_plan`                  | object | `mechanism`, `flag_name`, `default_value`, `rollback_time`, `triggers[]`              |
| `monitoring`                     | object | `dashboards[]`, `alerting_rules[]` (severity, condition, action)                      |
| `production_readiness_checklist` | array  | String checklist items (at least 5)                                                   |
| `success_criteria`               | object | `quality`, `latency`, `cost` sub-objects with targets                                 |
| `recommendation`                 | object | `approach`, `confidence`, `key_risks[]`, `estimated_total_effort_hours`               |

## Validation Checklist

- [ ] `migration_plan.models_to_migrate` covers all models from `gcp-design-ai.json`
- [ ] `step_by_step_guide.languages` matches `ai-workload-profile.json` languages
- [ ] `step_by_step_guide.files_to_modify` matches `gcp-design-ai.json` code_migration
- [ ] `rollback_plan.mechanism` is `"feature_flag"`
- [ ] `success_criteria` covers quality, latency, and cost

## Generate Phase Integration

The parent orchestrator (`generate.md`) uses `generation-ai.json` to:

1. Gate Stage 2 artifact generation -- `generate-artifacts-ai.md` requires this file
2. Provide AI migration context to `generate-artifacts-docs.md` for MIGRATION_GUIDE.md
3. Set phase completion status in `.phase-status.json`
