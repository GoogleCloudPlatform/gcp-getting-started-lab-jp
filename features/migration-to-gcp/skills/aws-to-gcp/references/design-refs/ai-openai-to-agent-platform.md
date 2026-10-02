# OpenAI to Gemini Enterprise Agent Platform (formerly Vertex AI) -- Model Selection Guide

**Applies to:** OpenAI SDK usage detected in AWS-hosted applications -> the Gemini Enterprise Agent Platform (GEAP)

This file is loaded by `design-ai.md` when `ai-workload-profile.json` has `summary.ai_source` = `"openai"` or `"both"`. It provides model mapping tables with pricing and honest competitive analysis for OpenAI -> Agent Platform migration decisions.

Many AWS-hosted applications use OpenAI's API rather than Bedrock. This guide covers that migration path.

> **BINDING — prices and model generations in this file are a SNAPSHOT and go stale within weeks** (a 2026-07 audit found the o4-mini row listed the 50%-off Flex rate as Standard — flipping the file's own comparison verdict — and the flagship table a full generation behind). NEVER quote a $ figure, "Winner" verdict, or "latest model" claim from this file; the durable content is the capability-CLASS mapping. Fetch OpenAI Standard-tier prices live from **https://developers.openai.com/api/pricing** (the docs pricing page — `openai.com/api/pricing` returns HTTP 403 to non-browser fetchers and MUST NOT be used as the WebFetch target) plus `platform.openai.com/docs/models` and `/docs/deprecations`; fetch Agent Platform prices via the `gcp-pricing` CLI / live pricing page.

---

## Pricing Guidance (verify at estimation time)

Model availability and prices change quickly. Before making a recommendation, verify current OpenAI API pricing and current Agent Platform model pricing from official pricing pages. Treat the tables below as examples and quick-start mappings, not as authoritative current pricing.

- **Often Agent Platform cheaper:** Gemini Pro-class models can be cheaper than premium OpenAI reasoning/pro tiers, but verify the current OpenAI model generation before claiming savings.
- **Often OpenAI cheaper:** Nano/mini tiers can be cheaper than Gemini Flash-class models for simple text workloads.
- **Context advantage:** Gemini 3.1 Pro Preview and the GA Flash line (gemini-3.5/3.6/3.7-flash, gemini-3.5-flash-lite) offer 1M token context vs 128-200K for most OpenAI models
- **Gemini lineup note (verified 2026-08-28 by live serving tests):** Pro-class flagship is `gemini-3.1-pro-preview` (no GA Pro successor serves yet — a phantom `gemini-3.5-pro` metadata entry exists but does NOT serve); GA Flash line is gemini-3.5/3.6/3.7-flash + 3.5-flash-lite; gemini-2.5-pro/flash retire 2026-10-16; embeddings = `gemini-embedding-2` (gemini-embedding-001 and text-embedding-005 no longer served)
- **Deprecation wave note:** check `platform.openai.com/docs/deprecations` EVERY run — OpenAI has announced API shutdowns (as of 2026-07: gpt-4, gpt-4-turbo, gpt-3.5-turbo, o1, o1-pro, o3-mini and gpt-4o-2024-05-13 all shut down 2026-10-23; o1-mini is already gone). A detected source model may be weeks from disappearing — that changes migration urgency and is worth surfacing to the user.

---

_"Agent Platform" below = Gemini Enterprise Agent Platform, formerly Vertex AI. Table headers use the short form._

## Model Mapping Tables

### Flagship / GPT-5.x Series

Percentages below are blended savings using a 2:1 input-to-output token ratio.

| OpenAI Model     | Price (in/out per 1M) | Best Agent Platform Match | Agent Platform Price                | Winner                                             |
| ---------------- | --------------------- | ------------------------- | ----------------------------------- | -------------------------------------------------- |
| GPT-5.4 Standard | $2.50 / $15.00        | Gemini 3.7 Flash          | $1.50 / $7.50 (verified 2026-08-28) | Agent Platform 48% cheaper                         |
| GPT-5.2          | $1.75 / $14.00        | Gemini 3.7 Flash          | $1.50 / $7.50 (verified 2026-08-28) | Agent Platform 40% cheaper                         |
| GPT-5 / GPT-5.1  | $1.25 / $10.00        | Gemini 3.5 Flash          | $1.50 / $9.00 (verified 2026-08-28) | ≈ cost parity (Agent Platform ~4% cheaper blended) |
| GPT-5 Mini       | $0.25 / $2.00         | Gemini 3.5 Flash-Lite     | $0.30 / $2.50 (verified 2026-08-28) | OpenAI 19% cheaper                                 |
| GPT-5 Nano       | $0.05 / $0.40         | Gemini 3.5 Flash-Lite     | $0.30 / $2.50 (verified 2026-08-28) | OpenAI 84% cheaper                                 |

### Pro Models (Extended Reasoning)

| OpenAI Model | Price (in/out per 1M) | Best Agent Platform Match         | Agent Platform Price | Winner                     |
| ------------ | --------------------- | --------------------------------- | -------------------- | -------------------------- |
| GPT-5.4 Pro  | $30.00 / $180.00      | Gemini 3.1 Pro Preview (thinking) | $2.00 / $12.00       | Agent Platform 95% cheaper |
| GPT-5.2 Pro  | $21.00 / $168.00      | Gemini 3.1 Pro Preview (thinking) | $2.00 / $12.00       | Agent Platform 93% cheaper |
| GPT-5 Pro    | $15.00 / $120.00      | Gemini 3.1 Pro Preview (thinking) | $2.00 / $12.00       | Agent Platform 90% cheaper |

### GPT-4.1 Series

| OpenAI Model | Price (in/out per 1M) | Best Agent Platform Match | Agent Platform Price                | Winner                               |
| ------------ | --------------------- | ------------------------- | ----------------------------------- | ------------------------------------ |
| GPT-4.1      | $2.00 / $8.00         | Gemini 3.7 Flash          | $1.50 / $7.50 (verified 2026-08-28) | Agent Platform 13% cheaper (blended) |
| GPT-4.1      | $2.00 / $8.00         | Gemini 3.5 Flash          | $1.50 / $9.00 (verified 2026-08-28) | ≈ cost parity (blended)              |
| GPT-4.1 Mini | $0.40 / $1.60         | Gemini 3.5 Flash-Lite     | $0.30 / $2.50                       | Agent Platform 19% cheaper           |
| GPT-4.1 Nano | $0.10 / $0.40         | Gemini 3.5 Flash-Lite     | $0.30 / $2.50                       | OpenAI 67% cheaper                   |

### GPT-4o Series

GPT-4o was retired from ChatGPT in February 2026, but API availability can differ from ChatGPT availability. Verify current API status before migration planning.

| OpenAI Model | Price (in/out per 1M) | Best Agent Platform Match | Agent Platform Price                | Notes                                      |
| ------------ | --------------------- | ------------------------- | ----------------------------------- | ------------------------------------------ |
| GPT-4o       | Verify live           | Gemini 3.7 Flash          | $1.50 / $7.50 (verified 2026-08-28) | API availability and price must be checked |
| GPT-4o Mini  | Verify live           | Gemini 3.5 Flash-Lite     | $0.30 / $2.50                       | API availability and price must be checked |

### Reasoning Models (o-series)

| OpenAI Model      | Price (in/out per 1M)                                                     | Best Agent Platform Match                | Agent Platform Price                | Winner                               |
| ----------------- | ------------------------------------------------------------------------- | ---------------------------------------- | ----------------------------------- | ------------------------------------ |
| o1-pro            | $150.00 / $600.00                                                         | Gemini 3.1 Pro Preview (thinking)        | $2.00 / $12.00                      | Agent Platform 99% cheaper           |
| o3-pro            | $20.00 / $80.00                                                           | Gemini 3.1 Pro Preview (thinking)        | $2.00 / $12.00                      | Agent Platform 92% cheaper           |
| o3                | $2.00 / $8.00                                                             | Gemini 3.7 Flash                         | $1.50 / $7.50 (verified 2026-08-28) | Agent Platform 13% cheaper (blended) |
| o4-mini           | $1.10 / $4.40 (Standard; $0.55/$2.20 is the Flex rate — do not mix tiers) | current Flash-class Gemini (verify live) | verify live                         | Compare live prices                  |
| o3-mini / o1-mini | $1.10 / $4.40                                                             | Gemini 2.5 Flash                         | $0.30 / $2.50                       | Agent Platform 63% cheaper           |

### Legacy Models

| OpenAI Model  | Price (in/out per 1M) | Best Agent Platform Match | Agent Platform Price | Winner                                           |
| ------------- | --------------------- | ------------------------- | -------------------- | ------------------------------------------------ |
| GPT-4 Turbo   | $10.00 / $30.00       | Gemini 3.1 Pro Preview    | $2.00 / $12.00       | Agent Platform 76% cheaper                       |
| GPT-4         | $30.00 / $60.00       | Gemini 3.1 Pro Preview    | $2.00 / $12.00       | Agent Platform 93% cheaper                       |
| GPT-3.5 Turbo | $0.50 / $1.50         | Gemini 3.5 Flash-Lite     | $0.30 / $2.50        | Agent Platform 24% cheaper + much better quality |

_Percentages are blended savings using a 2:1 input-to-output token ratio. Actual savings depend on your input/output ratio._

---

## Migration Decision Framework

**Migrate to Agent Platform if:**

- Using Pro/expensive reasoning models -> compare against current Gemini Pro-class pricing; savings can be material, but verify live.
- Using GPT-5.x standard/flagship tiers -> compare against current Gemini Pro-class pricing; do not assume a fixed winner.
- Using mid-tier models (GPT-4.1) -> savings vary, evaluate per-model
- Using legacy GPT-4/3.5/4o -> verify API availability and pricing before claiming savings.
- Need Google Cloud infrastructure integration
- Need 1M token context window (Gemini 3.1 Pro Preview/2.5 Flash)
- Need native Grounding with Google Search
- Need Google ADK + Agent Runtime (custom agents) or Gemini Enterprise (business agent hub) integration
- Want Claude models on GCP -> Claude available as partner model on Agent Platform

**Consider staying on OpenAI if:**

- Using ultra-cheap models (GPT-5 Nano, GPT-4.1 Nano) -> OpenAI 67-78% cheaper than Gemini Flash
- Low volume (<$500/mo) where absolute savings are small
- Heavily integrated with OpenAI ecosystem (Assistants API, DALL-E, Whisper, Realtime)
- Need Realtime API (no Agent Platform equivalent)

**Analyze carefully:** Calculate actual token usage x model-specific pricing. Small % differences matter at scale.

---

## Feature Migration

| OpenAI Feature                            | Agent Platform Equivalent                                                                                                                                                                                              | Notes                                              |
| ----------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------- |
| Function calling                          | Tool declarations (Gemini, excellent)                                                                                                                                                                                  | Similar format, minimal changes                    |
| Streaming                                 | stream_generate_content                                                                                                                                                                                                | Same SSE pattern                                   |
| Vision (GPT-4V)                           | Gemini multimodal (native, richer -- supports video/audio)                                                                                                                                                             | Better multimodal support                          |
| Embeddings (ada-002 / text-embedding-3-*) | Gemini Embedding (`gemini-embedding-2` — current model, text $0.10/1M batch verified 2026-08-28 via gcp-pricing, online rate + dims verify live; `gemini-embedding-001` and `text-embedding-005` are no longer served) | Must re-embed all docs                             |
| DALL-E                                    | Imagen 3 ($0.02-$0.06/img)                                                                                                                                                                                             | Competitive pricing                                |
| Whisper (STT)                             | Cloud Speech-to-Text ($0.016/min)                                                                                                                                                                                      | Cheaper than OpenAI Whisper                        |
| TTS                                       | Cloud Text-to-Speech                                                                                                                                                                                                   | Multiple voice options                             |
| Assistants API                            | Google ADK agents on Agent Runtime (rebuild)                                                                                                                                                                           | Google Workspace integration via Gemini Enterprise |
| JSON mode                                 | Controlled generation (response_mime_type, response_schema)                                                                                                                                                            | Native JSON schema enforcement on Gemini           |
| Realtime API                              | No equivalent                                                                                                                                                                                                          | Stay on OpenAI for this                            |
| Batch API                                 | GEAP Batch Inference                                                                                                                                                                                                   | Similar concept, different API                     |

---

## Common Migration Paths

### GPT-5.x Standard -> Gemini Pro-Class Model

Verify current OpenAI and Agent Platform prices before claiming savings. Gemini Pro-class models can be strong fits when Google Cloud integration and long context matter.

### GPT-5.x Pro -> Gemini Pro-Class Model (thinking)

95% savings. Massive cost reduction for extended reasoning workloads. Extremely strong migration case.

### GPT-5 -> Gemini 3.5 Flash

≈ cost parity blended ($1.25/$10.00 vs $1.50/$9.00, verified 2026-08-28), 1M context on Gemini (vs 128-200K). Low risk.

### o3 -> Gemini 3.7 Flash

13% cheaper blended (verified 2026-08-28), newest GA model, 1M context. Low risk.

### o4-mini -> Flash-class Gemini (verify current)

Compare the current Flash-class Gemini against o4-mini's STANDARD rate ($1.10/$4.40 as of 2026-07 — an earlier revision of this file mistakenly used the Flex rate and got the comparison backwards). Verify both live. Budget reasoning tier.

### GPT-4/4 Turbo -> Gemini 3.7 Flash

76-93% savings, much better quality, 1M context. Strong migration case for legacy workloads.

### GPT-4o API Availability Check

GPT-4o was retired from ChatGPT in February 2026, but API availability can differ. Verify current API status before recommending a migration solely because of retirement.

### GPT-3.5 Turbo -> Gemini 3.5 Flash-Lite

Comparable price (verify live), dramatically better quality, 1M context (vs 16K). The real driver: gpt-3.5-turbo shuts down 2026-10-23.

### Pro models -> Gemini 3.1 Pro Preview (thinking)

90-99% savings. Extremely strong migration case at any volume.

### High spend -> Multi-Model tiered strategy

Tier by complexity: simple -> Gemini 3.5 Flash-Lite (60%), moderate -> Gemini 3.7 Flash (30%), complex -> Gemini 3.1 Pro Preview thinking mode (10%). 70-90% savings.

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
