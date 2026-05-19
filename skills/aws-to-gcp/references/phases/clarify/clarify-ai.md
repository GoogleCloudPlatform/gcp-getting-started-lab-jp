# Category F — AI/Vertex AI (If `ai-workload-profile.json` Exists)

_Fire when:_ `ai-workload-profile.json` exists in `$MIGRATION_DIR/`.

---

## AI Context Summary

Before presenting questions, show:

> **AI Context Summary:**
> **AI source:** [from `summary.ai_source`: "Bedrock", "OpenAI", "Both", or "Other"]
> **Models detected:** [from `models[].model_id`]
> **Capabilities in use:** [from `integration.capabilities_summary` where true]
> **Integration pattern:** [from `integration.pattern`] via [from `integration.primary_sdk`]
> **Gateway/router:** [from `integration.gateway_type`, or "None (direct SDK)"]
> **Frameworks:** [from `integration.frameworks`, or "None"]

---

## Q14 — What AI framework or orchestration layer are you using? (select all that apply)

**Auto-detect signals** — scan IaC and application code before asking:

- No AI framework imports, raw HTTP calls to OpenAI/Bedrock endpoints -> A
- LiteLLM imports or config files -> B
- OpenRouter base URL in code/config -> B
- PortKey, Helicone, Martian SDK imports -> B
- Kong AI Gateway, Apigee AI config files -> B
- Custom proxy class wrapping the AI client -> B
- LangChain/LangGraph imports -> C
- LangChain/LlamaIndex with provider-agnostic model config -> C
- CrewAI imports, `Crew` and `Agent` class definitions -> D
- AutoGen imports, `ConversableAgent` patterns -> D
- Custom multi-agent loop with dispatcher logic -> D
- OpenAI Agents SDK / Swarm imports -> E
- Custom while-loop agent with tool-call parsing -> E
- `mcp.server` / `mcp.client` imports, MCP config JSON files -> F
- A2A protocol config or SDK imports -> F
- Vapi, Bland.ai, Retell SDK imports -> G
- Speech-to-Text or Text-to-Speech integration in code -> G

_Skip when:_ Auto-detection fully resolves the framework(s). Use detected value(s) with `chosen_by: "extracted"`.

> How your AI calls reach the model determines migration effort. Gateway users can often migrate by changing a single config line.
>
> A) No framework — direct API calls to OpenAI/Bedrock
> B) LLM router/gateway (LiteLLM, OpenRouter, PortKey, Kong, Apigee)
> C) LangChain / LangGraph
> D) Multi-agent framework (CrewAI, AutoGen, custom)
> E) OpenAI Agents SDK / custom agent loop
> F) MCP servers or A2A protocol
> G) Voice/conversational agent platform (Vapi, Retell, Bland.ai)
>
> _(Multiple selections allowed)_

| Answer                             | Recommendation Impact                                                                                        | Migration Effort  | Timeline                                           |
| ---------------------------------- | ------------------------------------------------------------------------------------------------------------ | ----------------- | -------------------------------------------------- |
| A) No framework — direct API calls | Swap SDK calls to Vertex AI SDK; evaluate Vertex AI Agent Builder if planning agentic                        | Low               | 1–3 weeks depending on call sites                  |
| B) LLM router/gateway              | Add Vertex AI as provider in gateway config; no app code changes; verify service account auth                | Minimal           | Hours to 1–3 days                                  |
| C) LangChain / LangGraph           | Provider swap via `ChatVertexAI`; chains/graphs/tools preserved; validate tool schemas                       | Low               | 1–3 days; 1 week if complex graphs                 |
| D) Multi-agent framework           | Path 1: Keep framework, swap LLM provider (lower effort). Path 2: Migrate to Vertex AI Agent Builder (deeper)| Medium            | Path 1: 3–5 days; Path 2: 2–4 weeks                |
| E) OpenAI Agents SDK               | Highest effort; tightly coupled to OpenAI API; recommend Vertex AI Agent Builder or LangGraph as portable step| High              | 2–4 weeks                                          |
| F) MCP / A2A                       | Vertex AI supports MCP tooling; A2A interop available; recommend Vertex AI Agent Builder as orchestration     | Low–Medium        | 3–5 days MCP; 1–2 weeks A2A                        |
| G) Voice platform                  | If platform supports Vertex AI natively -> config change; otherwise evaluate Chirp/Speech-to-Text            | Minimal to Medium | Hours if native; 2–3 weeks if speech migration     |

### Combination Logic

| Combination                          | Approach                                                                                               |
| ------------------------------------ | ------------------------------------------------------------------------------------------------------ |
| A only                               | Simplest path — direct SDK migration                                                                   |
| B only                               | Quick win — gateway config change, skip SDK migration steps                                            |
| B + any other                        | Gateway swap is the quick win; assess framework migration as separate workstream                       |
| C + A                                | Two workstreams: LangChain provider swap (fast) + direct call migration (slower)                       |
| D + F                                | Complex — multi-agent with MCP tooling; recommend Vertex AI Agent Builder to unify orchestration + tools|
| E + anything                         | E is the long pole; plan timeline around Agents SDK migration; other layers may be quick wins          |
| Multiple frameworks (C+D, C+E, etc.) | Assess independently; prioritize by traffic volume or business criticality; consolidate post-migration |

If answer includes B and no other selections, skip or abbreviate SDK migration steps. If answer is A only, proceed with standard model migration flow.

Interpret -> `ai_framework` array (multiple selections -> array of all selected values). Default: auto-detect from code, fallback `["direct"]`.

---

## Q15 — Approximately how much are you spending on Bedrock or OpenAI per month?

> A) < $500/month
> B) $500–$2,000/month
> C) $2,000–$10,000/month
> D) > $10,000/month
> E) I don't know

| Answer               | Recommendation Impact                                                                             |
| -------------------- | ------------------------------------------------------------------------------------------------- |
| < $500/month         | GCP free tier or low-tier credits; Vertex AI cost comparison shows modest savings                 |
| $500–$2,000/month    | Committed use discounts analysis; Vertex AI cost comparison highlighted                           |
| $2,000–$10,000/month | Significant committed use discounts; Vertex AI cost savings prominently featured; provisioned throughput analysis |
| > $10,000/month      | Enterprise agreement eligibility; dedicated AI migration support; Vertex AI provisioned throughput analysis   |

Interpret -> `ai_monthly_spend`. Default: B -> `"$500-$2K"`.

---

## Q16 — What matters most for your AI workloads?

Present with concrete anchors: Quality = legal analysis/code gen; Speed = autocomplete/live chat; Cost = classification/tagging at scale; Specialized = specific feature (-> Q17); Balanced = all-rounder.

> A) Best quality/reasoning — accuracy matters most, willing to pay more
> B) Fastest speed — response time is the primary constraint
> C) Lowest cost — high volume, budget tight, good-enough quality at scale
> D) Specialized capability — rely on a specific feature (covered in Q17)
> E) Balanced — no single dimension dominates
> F) I don't know

| Answer                 | Recommendation Impact                                                                                                        |
| ---------------------- | ---------------------------------------------------------------------------------------------------------------------------- |
| Best quality/reasoning | Gemini 3.1 Pro Preview (latest Pro-class preview, highest reasoning)                                                        |
| Fastest speed          | Gemini 3 Flash Preview — latest Flash-class preview; use Gemini 2.5 Flash if GA-only is required                            |
| Lowest cost            | Gemini 3 Flash Preview for latest Flash-class workloads; use Gemini 2.5 Flash if GA-only / lower cached rate is required     |
| Specialized capability | Deferred to Q17 to determine which model                                                                                     |
| Balanced               | Gemini 3.1 Pro Preview as default balanced recommendation                                                                            |

Interpret -> `ai_priority`. Default: E -> `"balanced"`.

---

## Q17 — What is your MOST CRITICAL specialized AI feature?

> A) Function calling / Tool use
> B) Ultra-long context (> 1M tokens)
> C) Extended thinking / Chain-of-thought
> D) Prompt caching (context caching)
> E) RAG optimization
> F) Agentic workflows
> G) Real-time speed (< 500ms)
> H) Multimodal with image generation
> I) Real-time conversational speech
> J) None — standard features are sufficient

| Answer                               | Recommendation Impact                                                                                                                                                        |
| ------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Function calling / Tool use          | Gemini 3.1 Pro Preview — best-in-class tool use on Vertex AI via structured JSON function declarations; supports parallel function calls and multi-turn tool use                      |
| Ultra-long context (> 1M tokens)     | Gemini 3.1 Pro Preview/Flash with 1M token context window; Gemini 3.1 Pro Preview supports up to 1M tokens natively                                                                         |
| Extended thinking / Chain-of-thought | Gemini 3.1 Pro Preview with thinking mode                                                                                                   |
| Prompt caching (context caching)     | Gemini 3.1 Pro Preview/Flash with context caching enabled; cost savings analysis included                                                                                            |
| RAG optimization                     | Vertex AI Search recommended alongside model; Vertex AI Embeddings for vector store                                                                                          |
| Agentic workflows                    | Gemini 3.1 Pro Preview with Vertex AI Agent Builder; multi-agent orchestration guidance included                                                                                     |
| Real-time speed (< 500ms)            | Gemini 3 Flash Preview; streaming response guidance included. Use Gemini 2.5 Flash if GA-only is required                                         |
| Multimodal with image generation     | Gemini 3.1 Pro Preview (vision) + Imagen 3 for generation                                                                                                                           |
| Real-time conversational speech      | Chirp 3 / Cloud Speech-to-Text recommended for speech-to-speech; latency guidance included                                                                                   |
| None                                 | Default recommendation from Q16 priority stands                                                                                                                              |

Interpret -> `ai_critical_feature`. Default: J -> no override.

---

## Q18 — What's your AI usage volume and cost tolerance?

> A) Low volume + quality priority — small-scale, quality matters most
> B) Medium volume + balanced — moderate production use, balanced approach
> C) High volume + cost critical — high scale, budget is tight, need cost control

| Answer                        | Recommendation Impact                                                                                         |
| ----------------------------- | ------------------------------------------------------------------------------------------------------------- |
| Low volume + quality priority | On-demand Gemini 3.1 Pro Preview; no provisioned throughput needed                                                    |
| Medium volume + balanced      | On-demand Gemini 3.1 Pro Preview or Flash depending on Q16; committed use analysis                                    |
| High volume + cost critical   | **Provisioned throughput strongly recommended**; Gemini 3 Flash Preview; context caching analysis included |

Interpret -> `ai_token_volume`: A -> `"low"`, B -> `"medium"`, C -> `"high"`. Default: A -> `"low"`.

---

## Q19 — Which Bedrock or OpenAI model are you currently using?

Establishes baseline Vertex AI recommendation. **Override hierarchy:** Q17 special features (hard override) > Q16 priority > Q18/Q21 volume and latency > Q19 source model (baseline only).

> A) Claude Haiku (3.5/4.5)
> B) Claude Sonnet (3.5/4.6)
> C) Claude Opus (3/4.6)
> D) GPT-3.5 Turbo
> E) GPT-4 / GPT-4 Turbo
> F) GPT-4o
> G) GPT-5 / GPT-5.x
> H) o-series (o1, o3)
> I) Amazon Nova (Micro/Lite/Pro)
> J) Other / Multiple models
> K) I don't know

| Source Model              | Baseline Vertex AI Recommendation                                    | Pricing Context                                                  |
| ------------------------- | --------------------------------------------------------------------- | ---------------------------------------------------------------- |
| Claude Haiku variants     | Gemini 3 Flash Preview — latest Flash-class speed/cost tier; Gemini 2.5 Flash if GA-only is required | Competitive pricing vs Haiku                                     |
| Claude Sonnet variants    | Gemini 3.1 Pro Preview — quality match                                        | Comparable pricing tier                                          |
| Claude Opus variants      | Gemini 3.1 Pro Preview — flagship-to-flagship                 | Comparable pricing tier                                          |
| GPT-3.5 Turbo             | Gemini 3 Flash Preview — latest Flash-class replacement; Gemini 2.5 Flash if GA-only is required | Flash-class models are faster and cheaper                                      |
| GPT-4 / GPT-4 Turbo       | Gemini 3.1 Pro Preview — quality equivalent                                   | Competitive pricing                                              |
| GPT-4o                    | Gemini 3.1 Pro Preview — performance equivalent                               | Comparable pricing                                               |
| GPT-5 / GPT-5.x           | Gemini 3.1 Pro Preview — performance equivalent                               | Competitive pricing                                              |
| o-series (o1, o3)         | Gemini 3.1 Pro Preview with thinking mode    | Competitive savings with Gemini 3.1 Pro Preview                          |
| Amazon Nova variants      | Gemini 3 Flash Preview (Micro/Lite equivalent) or Gemini 3.1 Pro Preview (Pro equivalent) | Direct tier mapping                                         |

**Override examples:** Claude Sonnet + Q16=cost -> Flash; Haiku + Q17=extended thinking -> Gemini 3.1 Pro Preview; GPT-4o + Q17=speech -> Chirp; Nova + Q22=complex -> Gemini 3.1 Pro Preview; GPT-5 + Q16=balanced -> Gemini 3.1 Pro Preview.

Interpret -> `ai_model_baseline`. Default: auto-detect from code, fallback Q16 priority-based.

---

## Q20 — What input types must the model accept: text only, images (vision), or audio/video?

> A) Text only
> B) Vision required — model must process images
> C) Audio/Video inputs needed

| Answer             | Recommendation Impact                                                                    |
| ------------------ | ---------------------------------------------------------------------------------------- |
| Text only          | Full model catalog available; cheapest/fastest text model per Q16 priority               |
| Vision required    | Gemini 3.1 Pro Preview or Flash (both support multimodal vision); Nano excluded (text-only)      |
| Audio/Video inputs | Gemini 3.1 Pro Preview (multimodal) or Chirp 3 for audio; Video Intelligence API for video       |

Interpret -> `ai_vision`. Default: A -> no constraint.

---

## Q21 — How important is AI response speed?

Present with concrete anchors: Critical = autocomplete/live chat/real-time transcription; Important = chat assistant/search augmentation; Flexible = report generation/batch analysis.

> A) Critical (< 500ms) — users staring at a loading spinner
> B) Important (< 2s) — quick response expected, brief pause acceptable
> C) Flexible (2–10s) — users can wait, background/async acceptable

| Answer             | Recommendation Impact                                                                             |
| ------------------ | ------------------------------------------------------------------------------------------------- |
| Critical (< 500ms) | Gemini 3 Flash Preview; streaming required; provisioned throughput for consistent latency |
| Important (< 2s)   | Gemini 3.1 Pro Preview with streaming; standard on-demand acceptable                                      |
| Flexible (2–10s)   | Any model; batch prediction considered for cost savings at high volume                            |

Interpret -> `ai_latency`. Default: B -> `"important"`.

---

## Q22 — How complex are your AI tasks?

Present with concrete examples: Simple = classify/extract/summarize; Moderate = analyze+JSON/few-shot; Complex = multi-turn reasoning/tool use/agentic.

> A) Simple (classification, short summaries, extraction)
> B) Moderate (analysis, structured content, few-shot)
> C) Complex (multi-step reasoning, tool use, agentic workflows)

| Answer   | Recommendation Impact                                                                       |
| -------- | ------------------------------------------------------------------------------------------- |
| Simple   | Gemini 3 Flash Preview sufficient; significant cost savings vs larger models       |
| Moderate | Gemini 3.1 Pro Preview recommended; Flash may suffice with prompt engineering                       |
| Complex  | Gemini 3.1 Pro Preview required; thinking mode considered           |

Interpret -> `ai_complexity`. Default: B -> `"moderate"`.
