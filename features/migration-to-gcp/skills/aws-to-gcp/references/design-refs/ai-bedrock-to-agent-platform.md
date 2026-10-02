# Bedrock to Gemini Enterprise Agent Platform (formerly Vertex AI) -- Model Selection Guide

**Applies to:** Amazon Bedrock (Claude, Nova, Llama, etc.) -> the Gemini Enterprise Agent Platform (GEAP)

This file is loaded by `design-ai.md` when `ai-workload-profile.json` has `summary.ai_source` = `"bedrock"` or `"both"`. It provides model mapping tables with pricing and honest competitive analysis for Bedrock -> Agent Platform migration decisions.

Many AWS-hosted applications use Bedrock's Converse API. This guide covers that migration path.

> **BINDING — prices and model generations in this file are a SNAPSHOT and go stale within weeks** (a 2026-07 audit found several materially wrong after ~7 weeks: Llama 4 prices ~2× low, Mistral Large 3 Bedrock price 4× high, superseded flagship generations). NEVER quote a $ figure, "Winner" verdict, or "latest model" claim from this file to the user or into any estimate. The durable content here is the capability-CLASS mapping (which Bedrock tier maps to which Agent Platform tier). At design/estimate time, fetch: Agent Platform prices + model lifecycle via the `gcp-pricing` CLI / cloud.google.com/gemini-enterprise-agent-platform/generative-ai/pricing + the model lifecycle page; Bedrock prices via aws.amazon.com/bedrock/pricing.

---

## Competitive Reality (April 2026)

GEAP Model Garden provides access to Google's Gemini models alongside partner models including Claude (via Anthropic partner integration). Be honest with users:

- Enumerate the CURRENT Gemini models at design time — the lineup moves faster than this file (as of 2026-08-28, verified by live `generateContent` serving tests: **`gemini-3.7-flash` is the primary recommendation** — newest GA model, flagship-quality and stronger than the older-generation `gemini-3.1-pro-preview`, which remains the thinking-mode/extended-reasoning niche pick; the GA Flash line runs gemini-3.5/3.6/3.7-flash with agents-cli scaffolds defaulting to 3.6; **gemini-3.5-flash-lite** and gemini-3.1-flash-lite are the low-cost tier; no GA Pro successor serves yet)
- **Verify by SERVING, not metadata**: the publisher-models metadata GET can return 200/"GA" for catalog entries that do NOT serve (observed 2026-08-28 for a phantom `gemini-3.5-pro`). A model exists when `generateContent` answers, when it has Billing Catalog token SKUs, and when it has a docs page — require at least the first.
- Do NOT recommend a model with a published retirement date for new workloads (as of 2026-08: gemini-2.5-pro and gemini-2.5-flash retire 2026-10-16; gemini-2.0-flash is already retired; **gemini-embedding-001 and text-embedding-005 are no longer served** — publisher API 404, use `gemini-embedding-2`) — check the deprecations page every run
- Claude partner model availability varies by region and date; verify current Agent Platform partner model availability before recommending a zero-model-risk path
- This means Claude users can migrate to Agent Platform without switching model families (zero-model-risk path)

**Where Agent Platform wins:**

- Gemini 3.1 Pro Preview context window (1M tokens) is 5x larger than Claude (200K tokens)
- Native Grounding with Google Search -- no equivalent in Bedrock
- Google ADK agents on Agent Runtime + Gemini Enterprise integrate with Google Workspace, Search, and enterprise data
- Gemini 2.5 Flash at $0.30/$2.50 undercuts most Bedrock mid-tier models
- Google-native ecosystem: BigQuery ML, Cloud Run/Eventarc triggers, Dataflow integration
- Claude is also available on Agent Platform as a partner model -- zero-model-risk migration path from Bedrock

**Where Bedrock still wins:**

- The current Claude generation (verify the live lineup — newer Sonnet/Opus generations ship regularly; benchmark name-drops in a static file are always stale) is available on both Bedrock and Agent Platform
- Claude prompt caching (90% savings on repeated content) is more mature than Gemini context caching
- AWS ecosystem integration (Bedrock Agents, Knowledge Bases, Guardrails) is more mature for AWS-native stacks
- Nova models provide very low-cost options for simple tasks

**Migration case by tier:**

- Claude on Bedrock -> Claude on Agent Platform: zero model risk, GCP infrastructure consolidation (same model, same API contract)
- Claude on Bedrock -> Gemini 3.1 Pro Preview: moderate risk, potential cost savings and larger context
- Nova Lite/Micro -> Gemini 2.5 Flash: evaluate quality/cost trade-off (Gemini Flash is more expensive than Nova Lite/Micro)
- Llama on Bedrock -> Llama on GEAP Model Garden: zero model risk, same open models

---

_"Agent Platform" below = Gemini Enterprise Agent Platform, formerly Vertex AI. Table headers use the short form._

## Agent Platform Model Portfolio

| Model                             | Best For                                                       | Complexity | Speed  | Context |
| --------------------------------- | -------------------------------------------------------------- | ---------- | ------ | ------- |
| Gemini 3.7 Flash                  | **Primary recommendation** — newest GA, flagship-quality, fast | High       | High   | 1M      |
| Gemini 3.5 / 3.6 Flash            | GA Flash workhorses (3.6 = agents-cli scaffold default)        | Medium     | High   | 1M      |
| Gemini 3.5 Flash-Lite             | Cheapest tier, classification/routing                          | Low        | High   | 1M      |
| Gemini 3.1 Pro Preview (thinking) | Extended-reasoning niche (preview; 3.7 Flash beats it broadly) | High       | Medium | 1M      |
| Claude Sonnet 4.6 (partner)       | Agentic tasks, tool use                                        | High       | High   | 200K    |
| Claude Opus 4.6 (partner)         | Maximum reasoning                                              | High       | Medium | 200K    |
| Claude Haiku 4.5 (partner)        | Simple + fast                                                  | Medium     | High   | 200K    |
| Llama 4 Maverick (Model Garden)   | Open source, strong quality                                    | High       | Medium | 1M      |
| Llama 4 Scout (Model Garden)      | Open source, cost-effective                                    | Medium     | High   | 512K    |
| Mistral Large 2                   | EU/Multilingual                                                | High       | Medium | 128K    |
| Gemma 2 27B                       | Small, self-hostable                                           | Medium     | High   | 8K      |

---

## Bedrock -> Agent Platform Model Mapping

### Claude Models (Partner Models on Both Platforms)

Claude is available on Agent Platform as a partner model -- this is the zero-model-risk migration path. Same models, same API contract, Google infrastructure.

| Bedrock Model     | Price (in/out per 1M) | Best Agent Platform Match   | Agent Platform Price                | Winner                                   |
| ----------------- | --------------------- | --------------------------- | ----------------------------------- | ---------------------------------------- |
| Claude Opus 4.6   | $5.00 / $25.00        | Gemini 3.7 Flash            | $1.50 / $7.50 (verified 2026-08-28) | Agent Platform 70% cheaper               |
| Claude Opus 4.6   | $5.00 / $25.00        | Claude Opus 4.6 (partner)   | $5.00 / $25.00                      | Same price (zero model risk)             |
| Claude Sonnet 4.6 | $3.00 / $15.00        | Gemini 3.7 Flash            | $1.50 / $7.50 (verified 2026-08-28) | Agent Platform 50% cheaper               |
| Claude Sonnet 4.6 | $3.00 / $15.00        | Claude Sonnet 4.6 (partner) | $3.00 / $15.00                      | Same price (zero model risk)             |
| Claude Haiku 4.5  | $1.00 / $5.00         | Gemini 3.5 Flash-Lite       | $0.30 / $2.50 (verified 2026-08-28) | Agent Platform cheaper (70% in, 50% out) |

### Amazon Nova Models

| Bedrock Model | Price (in/out per 1M) | Best Agent Platform Match | Agent Platform Price                | Winner                                                                        |
| ------------- | --------------------- | ------------------------- | ----------------------------------- | ----------------------------------------------------------------------------- |
| Nova 2 Pro    | PREVIEW (pricing TBD) | Gemini 3.7 Flash          | $1.50 / $7.50 (verified 2026-08-28) | Cannot compare -- Nova 2 Pro is PREVIEW only, no confirmed production pricing |
| Nova Pro      | $0.80 / $3.20         | Gemini 3.5 Flash-Lite     | $0.30 / $2.50 (verified 2026-08-28) | Agent Platform cheaper (63% in, 22% out)                                      |
| Nova Lite     | $0.06 / $0.24         | Gemini 3.5 Flash-Lite     | $0.30 / $2.50 (verified 2026-08-28) | Bedrock far cheaper (but Flash-Lite is higher quality)                        |
| Nova Micro    | $0.035 / $0.14        | Gemini 3.5 Flash-Lite     | $0.30 / $2.50 (verified 2026-08-28) | Bedrock far cheaper (but Flash-Lite is higher quality)                        |
| Nova Premier  | $2.50 / $12.50        | Gemini 3.7 Flash          | $1.50 / $7.50 (verified 2026-08-28) | Agent Platform 40% cheaper                                                    |

### Llama Models (Available on Both Platforms)

Llama 4 models are available on GEAP Model Garden -- zero model risk migration path.

| Bedrock Model    | Price (in/out per 1M)                             | Best Agent Platform Match       | Agent Platform Price | Winner                      |
| ---------------- | ------------------------------------------------- | ------------------------------- | -------------------- | --------------------------- |
| Llama 4 Maverick | ~$0.24 / $0.97 (us-east-1, 2026-07 — verify live) | Llama 4 Maverick (Model Garden) | Available            | Zero model risk, same model |
| Llama 4 Scout    | ~$0.17 / $0.66 (us-east-1, 2026-07 — verify live) | Llama 4 Scout (Model Garden)    | Available            | Zero model risk, same model |

### Other Models

| Bedrock Model   | Price (in/out per 1M)                                        | Best Agent Platform Match                             | Agent Platform Price                | Winner                                                             |
| --------------- | ------------------------------------------------------------ | ----------------------------------------------------- | ----------------------------------- | ------------------------------------------------------------------ |
| DeepSeek-R1     | $1.35 / $5.40                                                | Gemini 3.7 Flash                                      | $1.50 / $7.50 (verified 2026-08-28) | Bedrock cheaper (but DeepSeek-R1 also available on Agent Platform) |
| Mistral Large 3 | ~$0.50 / $1.50 (Bedrock US on-demand, 2026-07 — verify live) | Mistral Large (Model Garden — verify current version) | verify live                         | Compare live prices                                                |

_Note: verify Bedrock's Mistral pricing live — as of 2026-07 Bedrock's standard on-demand Mistral Large 3 price ($0.50/$1.50 per 1M, US regions) MATCHES the direct Mistral API; older revisions of this file claimed a 4× premium that no longer exists._

_Percentages are blended savings using a 2:1 input-to-output token ratio. Actual savings depend on your input/output ratio._

---

## Decision Paths by Priority

### Quality-First

- If user needs **general reasoning/coding quality** -> current Gemini Pro-class model (verify lifecycle and pricing), native Google integration
- If user needs **agentic reliability** (real-world multi-step tasks) -> **Claude Sonnet 4.6 on Agent Platform** (same model, GCP infrastructure) or **Gemini 3.1 Pro Preview (thinking mode)**
- If user needs **maximum reasoning** -> Gemini 3.1 Pro Preview (thinking mode) or Claude Opus 4.6 (partner)

### Speed-First

- Claude Haiku -> **Gemini 2.5 Flash** ($0.30/$2.50, sub-200ms, 1M context)
- Nova Micro/Lite -> **Gemini 2.5 Flash** (higher quality at moderate cost increase)

### Cost-First

- Claude Opus -> **Gemini 3.1 Pro Preview** (53% cheaper)
- Claude Sonnet -> **Gemini 2.5 Pro** (49% cheaper) or **Gemini 3.1 Pro Preview** (36% cheaper)
- Claude Haiku -> **Gemini 2.5 Flash** (64% cheaper)
- Nova Premier -> **Gemini 3.1 Pro Preview** (24% cheaper)
- Nova Lite/Micro -> These are the cheapest options. Gemini Flash is more expensive but higher quality. Evaluate quality/cost trade-off.

### Zero Model Risk

- Claude on Bedrock -> **Claude on Agent Platform** (partner models, same API contract, same pricing)
- Llama on Bedrock -> **Llama on GEAP Model Garden** (same open models, Llama 4 Maverick and Scout available)
- DeepSeek-R1 on Bedrock -> **DeepSeek-R1 on Agent Platform** (also available)

---

## Volume-Based Recommendations

**Low (<1M tokens/day):** Use best model for quality. Cost difference minimal at this volume.

**Medium (1-10M tokens/day):** Present cost comparison at volume. At 5M input + 2.5M output/day:

| Model                  | Monthly Cost  |
| ---------------------- | ------------- |
| Claude Sonnet 4.6      | $1,575        |
| Gemini 3.1 Pro Preview | $1,200 (-24%) |
| Gemini 2.5 Pro         | $938 (-40%)   |
| Gemini 2.5 Flash       | $233 (-85%)   |
| Claude Haiku 4.5       | $525          |
| Gemini 2.5 Flash       | $233 (-56%)   |

**High (10-100M tokens/day):** Cost optimization critical. Recommend multi-model tiered approach.

**Very high (>100M tokens/day):** Mandatory multi-model tiered strategy:

- Tier 1 -- Simple tasks (60% of traffic) -> Gemini 2.5 Flash ($0.30/$2.50) -- classification, extraction, routing
- Tier 2 -- Moderate tasks (30% of traffic) -> Gemini 3.1 Pro Preview ($2.00/$12.00) -- summarization, generation, Q&A
- Tier 3 -- Complex tasks (10% of traffic) -> Gemini 3.1 Pro Preview (thinking mode) -- reasoning, agentic tasks

---

## Cost Comparison Table (150M input + 75M output per month)

| Bedrock Model                  | Monthly | Best Agent Platform Match             | Monthly   | Difference                       |
| ------------------------------ | ------- | ------------------------------------- | --------- | -------------------------------- |
| Claude Opus 4.6 ($5/$25)       | $2,625  | Gemini 3.1 Pro Preview ($2.00/$12.00) | $1,200    | -54%                             |
| Claude Sonnet 4.6 ($3/$15)     | $1,575  | Gemini 3.1 Pro Preview ($2.00/$12.00) | $1,200    | -24%                             |
| Claude Sonnet 4.6 ($3/$15)     | $1,575  | Gemini 2.5 Pro ($1.25/$10.00)         | $938      | -40%                             |
| Claude Haiku 4.5 ($1/$5)       | $525    | Gemini 2.5 Flash ($0.30/$2.50)        | $233      | -56%                             |
| Nova 2 Pro (PREVIEW)           | TBD     | Gemini 3.1 Pro Preview ($2.00/$12.00) | $1,200    | Cannot compare (PREVIEW)         |
| Nova Pro ($0.80/$3.20)         | $360    | Gemini 2.5 Flash ($0.30/$2.50)        | $233      | -35%                             |
| Nova Lite ($0.06/$0.24)        | $27     | Gemini 2.5 Flash ($0.30/$2.50)        | $233      | +763%                            |
| Nova Micro ($0.035/$0.14)      | $16     | Gemini 2.5 Flash ($0.30/$2.50)        | $233      | +1356%                           |
| Llama 4 Maverick ($0.15/$0.60) | $68     | Llama 4 Maverick (Model Garden)       | Available | Zero model risk                  |
| Llama 4 Scout ($0.08/$0.30)    | $35     | Llama 4 Scout (Model Garden)          | Available | Zero model risk                  |
| DeepSeek-R1 ($1.35/$5.40)      | $608    | DeepSeek-R1 (Agent Platform)          | Available | Also available on Agent Platform |
| Mistral Large 3 ($2.00/$6.00)  | $750    | Mistral Large 2 (Model Garden)        | $750      | Same price                       |

_Difference column shows blended savings at a 2:1 input/output token ratio. Positive = Agent Platform costs more (Bedrock cheaper), negative = Agent Platform cheaper._

**Key takeaway:** Agent Platform is cheaper for Claude-equivalent and premium workloads (Gemini 3.1 Pro Preview and 2.5 Flash undercut Claude/Nova premium tiers). For ultra-cheap workloads (Nova Lite/Micro), Bedrock remains far cheaper -- evaluate whether the quality improvement of Gemini Flash justifies the cost increase. For Claude users who want zero model risk, Claude is available as a partner model on Agent Platform at the same pricing.

---

## Context Caching (Gemini)

Cache frequently-used context for cost reduction on cached portions. Gemini 2.5 Pro and Flash support context caching with reduced per-token pricing for cached content. Similar to Claude's prompt caching but with different pricing mechanics.

Available on Gemini models only. This is a significant advantage for applications with heavy system prompt or document repetition.

---

## Feature Migration Notes

| Bedrock Feature                | Agent Platform Equivalent                                                                                                                                                                                              | Notes                                              |
| ------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------- |
| Converse API                   | GenerativeModel API                                                                                                                                                                                                    | Similar structure, different SDK                   |
| Function calling (tools)       | Tool declarations (excellent)                                                                                                                                                                                          | Minimal changes                                    |
| Structured output/JSON         | Controlled generation (response_mime_type, response_schema)                                                                                                                                                            | Native JSON mode on Gemini                         |
| Streaming                      | stream_generate_content                                                                                                                                                                                                | Same SSE pattern                                   |
| Multimodal (Claude vision)     | Gemini multimodal (native, richer)                                                                                                                                                                                     | Gemini supports video/audio too                    |
| Prompt caching (Claude)        | Context caching (Gemini)                                                                                                                                                                                               | Different pricing, similar concept                 |
| Bedrock Knowledge Bases        | Agent Search & Grounding                                                                                                                                                                                               | Grounding with Google Search                       |
| Bedrock Agents                 | Google ADK agents on Agent Runtime (rebuild)                                                                                                                                                                           | Google Workspace integration via Gemini Enterprise |
| Bedrock Guardrails             | Agent Platform safety filters                                                                                                                                                                                          | Built-in content filtering                         |
| Titan Embeddings (verify live) | Gemini Embedding (`gemini-embedding-2` — current model, text $0.10/1M batch verified 2026-08-28 via gcp-pricing, online rate + dims verify live; `gemini-embedding-001` and `text-embedding-005` are no longer served) | Must re-embed all docs                             |
