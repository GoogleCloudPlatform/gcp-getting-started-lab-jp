# OpenAI to Vertex AI -- Model Selection Guide

**Applies to:** OpenAI SDK usage detected in AWS-hosted applications -> Google Cloud Vertex AI

This file is loaded by `design-ai.md` when `ai-workload-profile.json` has `summary.ai_source` = `"openai"` or `"both"`. It provides model mapping tables with pricing and honest competitive analysis for OpenAI -> Vertex AI migration decisions.

Many AWS-hosted applications use OpenAI's API rather than Bedrock. This guide covers that migration path.

Verify all pricing via GCP Pricing Calculator or `references/shared/pricing-cache.md`. Uses OpenAI Standard tier pricing.

---

## Pricing Guidance (verify at estimation time)

Model availability and prices change quickly. Before making a recommendation, verify current OpenAI API pricing and current Vertex AI model pricing from official pricing pages. Treat the tables below as examples and quick-start mappings, not as authoritative current pricing.

- **Often Vertex AI cheaper:** Gemini Pro-class models can be cheaper than premium OpenAI reasoning/pro tiers, but verify the current OpenAI model generation before claiming savings.
- **Often OpenAI cheaper:** Nano/mini tiers can be cheaper than Gemini Flash-class models for simple text workloads.
- **Context advantage:** Gemini 3.1 Pro Preview, Gemini 3 Flash Preview, and Gemini 2.5 Flash offer 1M token context vs 128-200K for most OpenAI models
- **GPT-4o note:** GPT-4o was retired from ChatGPT in February 2026, but OpenAI stated there were no API changes at that time. Verify API availability before treating GPT-4o as retired.

---

## Model Mapping Tables

### Flagship / GPT-5.x Series

Percentages below are blended savings using a 2:1 input-to-output token ratio.

| OpenAI Model         | Price (in/out per 1M) | Best Vertex AI Match             | Vertex AI Price  | Winner               |
| -------------------- | --------------------- | -------------------------------- | ---------------- | -------------------- |
| GPT-5.4 Standard     | $2.50 / $15.00        | Gemini 3.1 Pro Preview                   | $2.00 / $12.00   | Vertex AI 22% cheaper |
| GPT-5.2              | $1.75 / $14.00        | Gemini 3.1 Pro Preview                   | $2.00 / $12.00   | Mixed (Vertex AI cheaper output) |
| GPT-5 / GPT-5.1      | $1.25 / $10.00        | Gemini 2.5 Pro                   | $1.25 / $10.00   | Same price (cost parity) |
| GPT-5 Mini           | $0.25 / $2.00         | Gemini 2.5 Flash                 | $0.30 / $2.50    | OpenAI 20% cheaper    |
| GPT-5 Nano           | $0.05 / $0.40         | Gemini 2.5 Flash                 | $0.30 / $2.50    | OpenAI 78% cheaper    |

### Pro Models (Extended Reasoning)

| OpenAI Model    | Price (in/out per 1M) | Best Vertex AI Match              | Vertex AI Price  | Winner                |
| --------------- | --------------------- | --------------------------------- | ---------------- | --------------------- |
| GPT-5.4 Pro     | $30.00 / $180.00      | Gemini 3.1 Pro Preview (thinking)         | $2.00 / $12.00   | Vertex AI 95% cheaper |
| GPT-5.2 Pro     | $21.00 / $168.00      | Gemini 3.1 Pro Preview (thinking)         | $2.00 / $12.00   | Vertex AI 93% cheaper |
| GPT-5 Pro       | $15.00 / $120.00      | Gemini 3.1 Pro Preview (thinking)         | $2.00 / $12.00   | Vertex AI 90% cheaper |

### GPT-4.1 Series

| OpenAI Model | Price (in/out per 1M) | Best Vertex AI Match | Vertex AI Price | Winner                |
| ------------ | --------------------- | -------------------- | --------------- | --------------------- |
| GPT-4.1      | $2.00 / $8.00         | Gemini 3.1 Pro Preview       | $2.00 / $12.00  | OpenAI cheaper output |
| GPT-4.1      | $2.00 / $8.00         | Gemini 2.5 Pro       | $1.25 / $10.00  | Mixed (Vertex AI cheaper input, pricier output) |
| GPT-4.1 Mini | $0.40 / $1.60        | Gemini 2.5 Flash     | $0.30 / $2.50   | Vertex AI 19% cheaper |
| GPT-4.1 Nano | $0.10 / $0.40        | Gemini 2.5 Flash     | $0.30 / $2.50   | OpenAI 67% cheaper    |

### GPT-4o Series

GPT-4o was retired from ChatGPT in February 2026, but API availability can differ from ChatGPT availability. Verify current API status before migration planning.

| OpenAI Model | Price (in/out per 1M) | Best Vertex AI Match | Vertex AI Price | Notes                          |
| ------------ | --------------------- | -------------------- | --------------- | ------------------------------ |
| GPT-4o       | Verify live           | Gemini 3.1 Pro Preview         | $2.00 / $12.00  | API availability and price must be checked |
| GPT-4o Mini  | Verify live           | Gemini 2.5 Flash     | $0.30 / $2.50   | API availability and price must be checked |

### Reasoning Models (o-series)

| OpenAI Model                | Price (in/out per 1M) | Best Vertex AI Match          | Vertex AI Price | Winner                |
| --------------------------- | --------------------- | ----------------------------- | --------------- | --------------------- |
| o1-pro                      | $150.00 / $600.00     | Gemini 3.1 Pro Preview (thinking)     | $2.00 / $12.00  | Vertex AI 99% cheaper |
| o3-pro                      | $20.00 / $80.00       | Gemini 3.1 Pro Preview (thinking)     | $2.00 / $12.00  | Vertex AI 92% cheaper |
| o3                          | $2.00 / $8.00         | Gemini 3.1 Pro Preview                | $2.00 / $12.00  | Mixed (same input, Vertex AI pricier output) |
| o4-mini                     | $0.55 / $2.20         | Gemini 2.5 Flash              | $0.30 / $2.50   | Vertex AI 45% cheaper input, mixed output |
| o3-mini / o1-mini           | $1.10 / $4.40         | Gemini 2.5 Flash              | $0.30 / $2.50   | Vertex AI 63% cheaper |

### Legacy Models

| OpenAI Model  | Price (in/out per 1M) | Best Vertex AI Match | Vertex AI Price | Winner                                       |
| ------------- | --------------------- | -------------------- | --------------- | -------------------------------------------- |
| GPT-4 Turbo   | $10.00 / $30.00       | Gemini 3.1 Pro Preview       | $2.00 / $12.00  | Vertex AI 76% cheaper                        |
| GPT-4         | $30.00 / $60.00       | Gemini 3.1 Pro Preview       | $2.00 / $12.00  | Vertex AI 93% cheaper                        |
| GPT-3.5 Turbo | $0.50 / $1.50         | Gemini 2.5 Flash     | $0.30 / $2.50   | Vertex AI 24% cheaper + much better quality  |

_Percentages are blended savings using a 2:1 input-to-output token ratio. Actual savings depend on your input/output ratio._

---

## Migration Decision Framework

**Migrate to Vertex AI if:**

- Using Pro/expensive reasoning models -> compare against current Gemini Pro-class pricing; savings can be material, but verify live.
- Using GPT-5.x standard/flagship tiers -> compare against current Gemini Pro-class pricing; do not assume a fixed winner.
- Using mid-tier models (GPT-4.1) -> savings vary, evaluate per-model
- Using legacy GPT-4/3.5/4o -> verify API availability and pricing before claiming savings.
- Need Google Cloud infrastructure integration
- Need 1M token context window (Gemini 3.1 Pro Preview/2.5 Flash)
- Need native Grounding with Google Search
- Need Vertex AI Agent Builder / Agentspace integration
- Want Claude models on GCP -> Claude available as partner model on Vertex AI

**Consider staying on OpenAI if:**

- Using ultra-cheap models (GPT-5 Nano, GPT-4.1 Nano) -> OpenAI 67-78% cheaper than Gemini Flash
- Low volume (<$500/mo) where absolute savings are small
- Heavily integrated with OpenAI ecosystem (Assistants API, DALL-E, Whisper, Realtime)
- Need Realtime API (no Vertex AI equivalent)

**Analyze carefully:** Calculate actual token usage x model-specific pricing. Small % differences matter at scale.

---

## Feature Migration

| OpenAI Feature       | Vertex AI Equivalent                                        | Notes                                    |
| -------------------- | ----------------------------------------------------------- | ---------------------------------------- |
| Function calling     | Tool declarations (Gemini, excellent)                       | Similar format, minimal changes          |
| Streaming            | stream_generate_content                                     | Same SSE pattern                         |
| Vision (GPT-4V)      | Gemini multimodal (native, richer -- supports video/audio) | Better multimodal support                |
| Embeddings (ada-002) | Text Embedding API ($0.025/1M, 768 dims)                   | Must re-embed all docs                   |
| DALL-E               | Imagen 3 ($0.02-$0.06/img)                                 | Competitive pricing                      |
| Whisper (STT)        | Cloud Speech-to-Text ($0.016/min)                          | Cheaper than OpenAI Whisper              |
| TTS                  | Cloud Text-to-Speech                                       | Multiple voice options                   |
| Assistants API       | Vertex AI Agent Builder (Agentspace)                       | Google Workspace integration             |
| JSON mode            | Controlled generation (response_mime_type, response_schema) | Native JSON schema enforcement on Gemini |
| Realtime API         | No equivalent                                               | Stay on OpenAI for this                  |
| Batch API            | Batch Prediction                                            | Similar concept, different API           |

---

## Common Migration Paths

### GPT-5.x Standard -> Gemini Pro-Class Model

Verify current OpenAI and Vertex AI prices before claiming savings. Gemini Pro-class models can be strong fits when Google Cloud integration and long context matter.

### GPT-5.x Pro -> Gemini Pro-Class Model (thinking)

95% savings. Massive cost reduction for extended reasoning workloads. Extremely strong migration case.

### GPT-5 -> Gemini 2.5 Pro

Cost parity ($1.25/$10.00 each), 1M context on Gemini (vs 128-200K). Low risk.

### o3 -> Gemini 3.1 Pro Preview

Same input price ($2.00), Gemini pricier output but stronger Google integration. Evaluate per use case.

### o4-mini -> Gemini 2.5 Flash

Gemini 2.5 Flash at $0.30/$2.50 vs o4-mini at $0.55/$2.20. Cheaper input, slightly pricier output. Budget reasoning tier.

### GPT-4/4 Turbo -> Gemini 3.1 Pro Preview

76-93% savings, much better quality, 1M context. Strong migration case for legacy workloads.

### GPT-4o API Availability Check

GPT-4o was retired from ChatGPT in February 2026, but API availability can differ. Verify current API status before recommending a migration solely because of retirement.

### GPT-3.5 Turbo -> Gemini 2.5 Flash

24% savings, dramatically better quality, 1M context (vs 16K). Strong migration case.

### Pro models -> Gemini 3.1 Pro Preview (thinking)

90-99% savings. Extremely strong migration case at any volume.

### High spend -> Multi-Model tiered strategy

Tier by complexity: simple -> Gemini 2.5 Flash (60%), moderate -> Gemini 3.1 Pro Preview (30%), complex -> Gemini 3.1 Pro Preview thinking mode (10%). 70-90% savings.

---

## Volume-Based Recommendations

**Low (<1M tokens/day):** Use best model for quality. Cost difference minimal.

**Medium (1-10M tokens/day):** Present cost comparison at volume. At 5M input + 2.5M output/day, evaluate per-model economics carefully.

**High (10-100M tokens/day):** Multi-model tiered approach recommended. Route by task complexity.

**Very high (>100M tokens/day):** Mandatory tiering:

- Tier 1 -- Simple tasks (60%) -> Gemini 2.5 Flash ($0.30/$2.50) -- classification, extraction, routing
- Tier 2 -- Moderate tasks (30%) -> Gemini 3.1 Pro Preview ($2.00/$12.00) -- summarization, generation, Q&A
- Tier 3 -- Complex tasks (10%) -> Gemini 3.1 Pro Preview (thinking mode) -- reasoning, agentic tasks

---

## OpenAI Pricing Tiers

OpenAI offers 4 tiers: Batch (50% off, 24hr), Flex (30-50% off, higher latency), Standard (baseline), Priority (2x, lowest latency). This guide uses Standard tier for comparison.
