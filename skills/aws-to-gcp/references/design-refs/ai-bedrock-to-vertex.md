# Bedrock to Vertex AI -- Model Selection Guide

**Applies to:** Amazon Bedrock (Claude, Nova, Llama, etc.) -> Google Cloud Vertex AI

This file is loaded by `design-ai.md` when `ai-workload-profile.json` has `summary.ai_source` = `"bedrock"` or `"both"`. It provides model mapping tables with pricing and honest competitive analysis for Bedrock -> Vertex AI migration decisions.

Many AWS-hosted applications use Bedrock's Converse API. This guide covers that migration path.

Verify all pricing via GCP Pricing Calculator or `references/shared/pricing-cache.md`.

---

## Competitive Reality (April 2026)

Vertex AI Model Garden provides access to Google's Gemini models alongside partner models including Claude (via Anthropic partner integration). Be honest with users:

- Gemini 3.1 Pro Preview is Google's current Pro-class preview model in Vertex AI pricing; verify current model lifecycle and pricing before final recommendations
- Gemini 3 Flash Preview is Google's current Flash-class preview model in Vertex AI pricing; use it for speed-sensitive workloads after verifying lifecycle and regional availability
- Gemini 2.5 Pro remains available as a strong mid-tier option at $1.25/$10.00 per 1M tokens
- Gemini 2.5 Flash provides excellent cost/performance ratio at $0.30/$2.50 per 1M tokens
- Gemini 2.0 Flash is deprecated -- do not use for new workloads
- Claude partner model availability varies by region and date; verify current Vertex AI partner model availability before recommending a zero-model-risk path
- This means Claude users can migrate to Vertex AI without switching model families (zero-model-risk path)

**Where Vertex AI wins:**

- Gemini 3.1 Pro Preview context window (1M tokens) is 5x larger than Claude (200K tokens)
- Native Grounding with Google Search -- no equivalent in Bedrock
- Vertex AI Agent Builder (Agentspace) integrates with Google Workspace, Search, and enterprise data
- Gemini 2.5 Flash at $0.30/$2.50 undercuts most Bedrock mid-tier models
- Google-native ecosystem: BigQuery ML, Cloud Run/Eventarc triggers, Dataflow integration
- Claude is also available on Vertex AI as a partner model -- zero-model-risk migration path from Bedrock

**Where Bedrock still wins:**

- Claude Sonnet/Opus 4.6 lead on real-world agentic tasks (GDPval evaluation)
- Claude prompt caching (90% savings on repeated content) is more mature than Gemini context caching
- AWS ecosystem integration (Bedrock Agents, Knowledge Bases, Guardrails) is more mature for AWS-native stacks
- Nova models provide very low-cost options for simple tasks

**Migration case by tier:**

- Claude on Bedrock -> Claude on Vertex AI: zero model risk, GCP infrastructure consolidation (same model, same API contract)
- Claude on Bedrock -> Gemini 3.1 Pro Preview: moderate risk, potential cost savings and larger context
- Nova Lite/Micro -> Gemini 2.5 Flash: evaluate quality/cost trade-off (Gemini Flash is more expensive than Nova Lite/Micro)
- Llama on Bedrock -> Llama on Vertex AI Model Garden: zero model risk, same open models

---

## Vertex AI Model Portfolio

| Model                | Best For                      | Complexity | Speed  | Context |
| -------------------- | ----------------------------- | ---------- | ------ | ------- |
| Gemini 3.1 Pro Preview       | Flagship reasoning, coding, multimodal | High | Medium | 1M     |
| Gemini 3.1 Pro Preview (thinking) | Complex reasoning, agentic tasks | High | Medium | 1M  |
| Gemini 3 Flash Preview | Latest fast model, broad multimodal workloads | Medium | High | 1M |
| Gemini 2.5 Pro       | Mid-tier reasoning, coding    | High       | Medium | 1M     |
| Gemini 2.5 Flash     | Fast, cost-effective          | Medium     | High   | 1M     |
| Claude Sonnet 4.6 (partner) | Agentic tasks, tool use | High    | High   | 200K   |
| Claude Opus 4.6 (partner) | Maximum reasoning        | High       | Medium | 200K   |
| Claude Haiku 4.5 (partner) | Simple + fast            | Medium     | High   | 200K   |
| Llama 4 Maverick (Model Garden) | Open source, strong quality | High | Medium | 1M |
| Llama 4 Scout (Model Garden) | Open source, cost-effective | Medium | High | 512K |
| Mistral Large 2      | EU/Multilingual               | High       | Medium | 128K   |
| Gemma 2 27B          | Small, self-hostable          | Medium     | High   | 8K     |

---

## Bedrock -> Vertex AI Model Mapping

### Claude Models (Partner Models on Both Platforms)

Claude is available on Vertex AI as a partner model -- this is the zero-model-risk migration path. Same models, same API contract, Google infrastructure.

| Bedrock Model       | Price (in/out per 1M) | Best Vertex AI Match            | Vertex AI Price | Winner                 |
| -------------------- | --------------------- | ------------------------------- | --------------- | ---------------------- |
| Claude Opus 4.6      | $5.00 / $25.00        | Gemini 3.1 Pro Preview                  | $2.00 / $12.00  | Vertex AI 53% cheaper  |
| Claude Opus 4.6      | $5.00 / $25.00        | Claude Opus 4.6 (partner)       | $5.00 / $25.00  | Same price (zero model risk) |
| Claude Sonnet 4.6    | $3.00 / $15.00        | Gemini 3.1 Pro Preview                  | $2.00 / $12.00  | Vertex AI 36% cheaper  |
| Claude Sonnet 4.6    | $3.00 / $15.00        | Gemini 2.5 Pro                  | $1.25 / $10.00  | Vertex AI 49% cheaper  |
| Claude Sonnet 4.6    | $3.00 / $15.00        | Claude Sonnet 4.6 (partner)     | $3.00 / $15.00  | Same price (zero model risk) |
| Claude Haiku 4.5     | $1.00 / $5.00         | Gemini 2.5 Flash                | $0.30 / $2.50   | Vertex AI 64% cheaper  |

### Amazon Nova Models

| Bedrock Model   | Price (in/out per 1M) | Best Vertex AI Match          | Vertex AI Price  | Winner                  |
| --------------- | --------------------- | ----------------------------- | ---------------- | ----------------------- |
| Nova 2 Pro      | PREVIEW (pricing TBD) | Gemini 3.1 Pro Preview                | $2.00 / $12.00   | Cannot compare -- Nova 2 Pro is PREVIEW only, no confirmed production pricing |
| Nova Pro        | $0.80 / $3.20         | Gemini 2.5 Flash              | $0.30 / $2.50    | Vertex AI 56% cheaper   |
| Nova Lite       | $0.06 / $0.24         | Gemini 2.5 Flash              | $0.30 / $2.50    | Bedrock 67% cheaper (but Gemini Flash is higher quality) |
| Nova Micro      | $0.035 / $0.14        | Gemini 2.5 Flash              | $0.30 / $2.50    | Bedrock 76% cheaper (but Gemini Flash is higher quality) |
| Nova Premier    | $2.50 / $12.50        | Gemini 3.1 Pro Preview                | $2.00 / $12.00   | Vertex AI 24% cheaper   |

### Llama Models (Available on Both Platforms)

Llama 4 models are available on Vertex AI Model Garden -- zero model risk migration path.

| Bedrock Model      | Price (in/out per 1M) | Best Vertex AI Match              | Vertex AI Price  | Winner                       |
| ------------------- | --------------------- | --------------------------------- | ---------------- | ---------------------------- |
| Llama 4 Maverick    | $0.15 / $0.60         | Llama 4 Maverick (Model Garden)   | Available        | Zero model risk, same model  |
| Llama 4 Scout       | $0.08 / $0.30         | Llama 4 Scout (Model Garden)      | Available        | Zero model risk, same model  |

### Other Models

| Bedrock Model      | Price (in/out per 1M) | Best Vertex AI Match    | Vertex AI Price | Winner                |
| ------------------- | --------------------- | ----------------------- | --------------- | --------------------- |
| DeepSeek-R1         | $1.35 / $5.40         | Gemini 3.1 Pro Preview          | $2.00 / $12.00  | Bedrock cheaper (but DeepSeek-R1 also available on Vertex AI) |
| DeepSeek-R1         | $1.35 / $5.40         | Gemini 2.5 Pro          | $1.25 / $10.00  | Mixed (input cheaper, output pricier) |
| Mistral Large 3     | $2.00 / $6.00         | Mistral Large 2 (Model Garden) | $2.00 / $6.00 | Same price           |

_Note: Mistral Large on Bedrock is $2.00/$6.00 (Bedrock pricing). The direct Mistral API price of $0.50/$1.50 does not apply on Bedrock._

_Percentages are blended savings using a 2:1 input-to-output token ratio. Actual savings depend on your input/output ratio._

---

## Decision Paths by Priority

### Quality-First

- If user needs **general reasoning/coding quality** -> current Gemini Pro-class model (verify lifecycle and pricing), native Google integration
- If user needs **agentic reliability** (real-world multi-step tasks) -> **Claude Sonnet 4.6 on Vertex AI** (same model, GCP infrastructure) or **Gemini 3.1 Pro Preview (thinking mode)**
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

- Claude on Bedrock -> **Claude on Vertex AI** (partner models, same API contract, same pricing)
- Llama on Bedrock -> **Llama on Vertex AI Model Garden** (same open models, Llama 4 Maverick and Scout available)
- DeepSeek-R1 on Bedrock -> **DeepSeek-R1 on Vertex AI** (also available)

---

## Volume-Based Recommendations

**Low (<1M tokens/day):** Use best model for quality. Cost difference minimal at this volume.

**Medium (1-10M tokens/day):** Present cost comparison at volume. At 5M input + 2.5M output/day:

| Model                  | Monthly Cost    |
| ---------------------- | --------------- |
| Claude Sonnet 4.6      | $1,575          |
| Gemini 3.1 Pro Preview         | $1,200 (-24%)   |
| Gemini 2.5 Pro         | $938 (-40%)     |
| Gemini 2.5 Flash       | $233 (-85%)     |
| Claude Haiku 4.5       | $525            |
| Gemini 2.5 Flash       | $233 (-56%)     |

**High (10-100M tokens/day):** Cost optimization critical. Recommend multi-model tiered approach.

**Very high (>100M tokens/day):** Mandatory multi-model tiered strategy:

- Tier 1 -- Simple tasks (60% of traffic) -> Gemini 2.5 Flash ($0.30/$2.50) -- classification, extraction, routing
- Tier 2 -- Moderate tasks (30% of traffic) -> Gemini 3.1 Pro Preview ($2.00/$12.00) -- summarization, generation, Q&A
- Tier 3 -- Complex tasks (10% of traffic) -> Gemini 3.1 Pro Preview (thinking mode) -- reasoning, agentic tasks

---

## Cost Comparison Table (150M input + 75M output per month)

| Bedrock Model                       | Monthly  | Best Vertex AI Match                 | Monthly  | Difference |
| ----------------------------------- | -------- | ------------------------------------ | -------- | ---------- |
| Claude Opus 4.6 ($5/$25)            | $2,625   | Gemini 3.1 Pro Preview ($2.00/$12.00)        | $1,200   | -54%       |
| Claude Sonnet 4.6 ($3/$15)          | $1,575   | Gemini 3.1 Pro Preview ($2.00/$12.00)        | $1,200   | -24%       |
| Claude Sonnet 4.6 ($3/$15)          | $1,575   | Gemini 2.5 Pro ($1.25/$10.00)        | $938     | -40%       |
| Claude Haiku 4.5 ($1/$5)            | $525     | Gemini 2.5 Flash ($0.30/$2.50)       | $233     | -56%       |
| Nova 2 Pro (PREVIEW)                | TBD      | Gemini 3.1 Pro Preview ($2.00/$12.00)        | $1,200   | Cannot compare (PREVIEW) |
| Nova Pro ($0.80/$3.20)              | $360     | Gemini 2.5 Flash ($0.30/$2.50)       | $233     | -35%       |
| Nova Lite ($0.06/$0.24)             | $27      | Gemini 2.5 Flash ($0.30/$2.50)       | $233     | +763%      |
| Nova Micro ($0.035/$0.14)           | $16      | Gemini 2.5 Flash ($0.30/$2.50)       | $233     | +1356%     |
| Llama 4 Maverick ($0.15/$0.60)      | $68      | Llama 4 Maverick (Model Garden)      | Available | Zero model risk |
| Llama 4 Scout ($0.08/$0.30)         | $35      | Llama 4 Scout (Model Garden)         | Available | Zero model risk |
| DeepSeek-R1 ($1.35/$5.40)           | $608     | DeepSeek-R1 (Vertex AI)              | Available | Also available on Vertex AI |
| Mistral Large 3 ($2.00/$6.00)       | $750     | Mistral Large 2 (Model Garden)       | $750     | Same price  |

_Difference column shows blended savings at a 2:1 input/output token ratio. Positive = Vertex AI costs more (Bedrock cheaper), negative = Vertex AI cheaper._

**Key takeaway:** Vertex AI is cheaper for Claude-equivalent and premium workloads (Gemini 3.1 Pro Preview and 2.5 Flash undercut Claude/Nova premium tiers). For ultra-cheap workloads (Nova Lite/Micro), Bedrock remains far cheaper -- evaluate whether the quality improvement of Gemini Flash justifies the cost increase. For Claude users who want zero model risk, Claude is available as a partner model on Vertex AI at the same pricing.

---

## Context Caching (Gemini)

Cache frequently-used context for cost reduction on cached portions. Gemini 2.5 Pro and Flash support context caching with reduced per-token pricing for cached content. Similar to Claude's prompt caching but with different pricing mechanics.

Available on Gemini models only. This is a significant advantage for applications with heavy system prompt or document repetition.

---

## Feature Migration Notes

| Bedrock Feature                 | Vertex AI Equivalent                                      | Notes                              |
| ------------------------------- | --------------------------------------------------------- | ---------------------------------- |
| Converse API                    | GenerativeModel API                                       | Similar structure, different SDK    |
| Function calling (tools)        | Tool declarations (excellent)                             | Minimal changes                    |
| Structured output/JSON          | Controlled generation (response_mime_type, response_schema)| Native JSON mode on Gemini        |
| Streaming                       | stream_generate_content                                   | Same SSE pattern                   |
| Multimodal (Claude vision)      | Gemini multimodal (native, richer)                        | Gemini supports video/audio too    |
| Prompt caching (Claude)         | Context caching (Gemini)                                  | Different pricing, similar concept |
| Bedrock Knowledge Bases          | Vertex AI Search & Grounding                             | Grounding with Google Search       |
| Bedrock Agents                   | Vertex AI Agent Builder (Agentspace)                     | Google Workspace integration       |
| Bedrock Guardrails              | Vertex AI Safety Filters                                  | Built-in content filtering         |
| Titan Embeddings ($0.02/1M)     | Text Embedding API ($0.025/1M, 768 dims)                 | Must re-embed all docs             |
