# AI-Only Migration — Clarify Requirements

**Standalone flow** — Used when ONLY `ai-workload-profile.json` exists (no infrastructure or billing artifacts). Infrastructure stays on AWS; only AI/LLM calls move to GCP Vertex AI.

Produces the same `preferences.json` output but with `design_constraints` limited to region and `ai_constraints` fully populated.

---

## Step 1: Present AI Detection Summary

> **AI-Only Migration Detected**
> Your project has AI workloads but no infrastructure artifacts (Terraform, CloudFormation, billing). I'll focus on migrating your AI/LLM calls to GCP Vertex AI while your infrastructure stays on AWS.
>
> **AI source:** [from `summary.ai_source`]
> **Models detected:** [from `models[].model_id`]
> **Capabilities in use:** [from `integration.capabilities_summary` where true]
> **Integration pattern:** [from `integration.pattern`] via [from `integration.primary_sdk`]
> **Gateway/router:** [from `integration.gateway_type`, or "None (direct SDK)"]

---

## Step 2: Ask Questions (Q1–Q10)

Present all questions at once. User can answer each, skip individual ones (use defaults), or say "use all defaults."

## Q1 — AI framework or orchestration layer (select all that apply)

Same decision logic, auto-detect signals, and interpretation as Q14 in `clarify-ai.md`.

Auto-detect: No framework -> A, LiteLLM/OpenRouter/Kong/Apigee -> B, LangChain/LangGraph -> C, CrewAI/AutoGen -> D, OpenAI Agents SDK -> E, MCP/A2A -> F, Vapi/Bland.ai/Retell -> G.

> A) No framework — direct API calls | B) LLM router/gateway | C) LangChain / LangGraph | D) Multi-agent framework | E) OpenAI Agents SDK | F) MCP/A2A | G) Voice platform

Interpret -> `ai_framework` array. Default: auto-detect, fallback `["direct"]`.

## Q2 — What matters most for your AI application?

> A) Best quality/reasoning | B) Fastest speed | C) Lowest cost | D) Specialized capability (-> Q10) | E) Balanced | F) I don't know

| Answer   | Model Impact                                          |
| -------- | ----------------------------------------------------- |
| Quality  | Gemini 3.1 Pro Preview primary                         |
| Speed    | Gemini 3 Flash Preview; Gemini 2.5 Flash if GA-only is required |
| Cost     | Gemini 3 Flash Preview; Gemini 2.5 Flash if GA-only / lower cached rate is required |
| Special  | Deferred to Q10                                       |
| Balanced | Gemini 3.1 Pro Preview                                        |

Interpret -> `ai_priority`. Default: E -> `"balanced"`.

## Q3 — Monthly AI spend on Bedrock or OpenAI?

> A) < $500 | B) $500–$2K | C) $2K–$10K | D) > $10K | E) Don't know

Interpret -> `ai_monthly_spend`. Default: B -> `"$500-$2K"`.

## Q4 — Cross-cloud API call concerns

Unique to AI-only: infrastructure stays on AWS while AI calls route to GCP.

> A) Latency critical — AI in hot path | B) Latency acceptable — async/users can wait | C) Concerned about egress costs | D) Want to test first — parallel running

| Answer           | Impact                                         |
| ---------------- | ---------------------------------------------- |
| Latency critical | Private Service Connect; closest region to AWS deployment |
| Acceptable       | Standard endpoint; region by cost              |
| Egress concerned | Private Service Connect; egress cost analysis  |
| Test first       | Phased migration; parallel running guidance    |

Interpret -> `cross_cloud`. Default: B -> `"latency-acceptable"`.

## Q5 — Current model in use?

Establishes baseline Vertex AI recommendation. Override hierarchy: Q10 special features > Q2 priority > Q7/Q8 volume/latency > Q5 baseline.

> A) Claude Haiku | B) Claude Sonnet | C) Claude Opus | D) GPT-3.5 Turbo | E) GPT-4/4 Turbo | F) GPT-4o | G) GPT-5/5.x | H) o-series | I) Amazon Nova | J) Other/Multiple | K) Don't know

| Source         | Baseline Recommendation              | Pricing Context                    |
| -------------- | ------------------------------------ | ---------------------------------- |
| Claude Haiku   | Gemini 3 Flash Preview               | Competitive pricing                |
| Claude Sonnet  | Gemini 3.1 Pro Preview                       | Comparable tier                    |
| Claude Opus    | Gemini 3.1 Pro Preview or Ultra              | Comparable tier                    |
| GPT-3.5 Turbo  | Gemini 3 Flash Preview               | Faster Flash-class replacement     |
| GPT-4/4 Turbo  | Gemini 3.1 Pro Preview                       | Competitive pricing                |
| GPT-4o         | Gemini 3.1 Pro Preview                       | Comparable pricing                 |
| GPT-5/5.x      | Gemini 3.1 Pro Preview                       | Savings story is quality, not cost |
| GPT-5 flagship | Gemini 3.1 Pro Preview               | Competitive pricing                |
| o-series       | Gemini 3.1 Pro Preview with thinking mode    | Competitive savings                |
| Amazon Nova    | Gemini 3 Flash Preview (Micro/Lite) or 3.1 Pro Preview | Direct tier mapping                |

Override examples: Claude Sonnet + Q2=cost -> Flash; Haiku + Q10=extended thinking -> Gemini 3.1 Pro Preview; GPT-4o + Q10=speech -> Chirp; Nova + Q9=complex -> Gemini 3.1 Pro Preview.

Interpret -> `ai_model_baseline`. Default: auto-detect, fallback Q2 priority-based.

## Q6 — What input types must the model accept: text only, images (vision), or audio/video?

> A) Text only | B) Vision required | C) Audio/Video inputs

| Answer      | Impact                                                                                   |
| ----------- | ---------------------------------------------------------------------------------------- |
| Text only   | Full model catalog                                                                       |
| Vision      | Gemini 3.1 Pro Preview or Flash (both support multimodal vision); Nano excluded (text-only)      |
| Audio/Video | Gemini 3.1 Pro Preview (multimodal) or Chirp 3/Video Intelligence API                            |

Interpret -> `ai_vision`. Default: A -> no constraint.

## Q7 — Monthly AI usage volume

> A) < 1M tokens | B) 1–10M | C) 10–100M | D) > 100M | E) Don't know

| Answer    | Impact                                             |
| --------- | -------------------------------------------------- |
| Low       | On-demand; no provisioned throughput               |
| Medium    | On-demand with context caching analysis            |
| High      | Provisioned throughput analysis; context caching   |
| Very high | Provisioned throughput required; capacity planning |

Interpret -> `ai_token_volume`: A -> `"low"`, B -> `"medium"`, C -> `"high"`, D -> `"very_high"`. Default: B -> `"medium"`.

## Q8 — Response speed importance

Present with concrete anchors: Critical = autocomplete/live chat; Important = chat assistant; Flexible = reports/batch.

> A) Critical (< 500ms) | B) Important (< 2s) | C) Flexible (2–10s)

| Answer    | Impact                                                       |
| --------- | ------------------------------------------------------------ |
| Critical  | Gemini 3 Flash Preview; streaming required; provisioned throughput        |
| Important | Gemini 3.1 Pro Preview with streaming; standard on-demand            |
| Flexible  | Any model; batch prediction for cost savings                 |

Interpret -> `ai_latency`. Default: B -> `"important"`.

## Q9 — AI task complexity

Present with concrete examples: Simple = classify/extract/summarize; Moderate = analyze+JSON/few-shot; Complex = multi-turn reasoning/tool use/agentic.

> A) Simple | B) Moderate | C) Complex

| Answer   | Impact                                                              |
| -------- | ------------------------------------------------------------------- |
| Simple   | Gemini 3 Flash Preview sufficient; significant cost savings                     |
| Moderate | Gemini 3.1 Pro Preview recommended; Flash may suffice with prompt engineering|
| Complex  | Gemini 3.1 Pro Preview required; thinking mode considered; Ultra for hardest|

Interpret -> `ai_complexity`. Default: B -> `"moderate"`.

## Q10 — Specialized features needed

Same decision logic as Q17 in `clarify-ai.md`.

> A) Function calling | B) Ultra-long context (> 1M) | C) Extended thinking | D) Context caching | E) RAG optimization | F) Agentic workflows | G) Real-time speed | H) Image generation | I) Conversational speech | J) None

Interpret -> `ai_critical_feature`. Default: J -> no override.

---

## Step 3: Write preferences.json

Write `$MIGRATION_DIR/preferences.json`:

**Schema — AI-only structure:**

| Field                      | Path                                      | Notes                                       |
| -------------------------- | ----------------------------------------- | ------------------------------------------- |
| `migration_type`           | `metadata.migration_type`                 | `"ai-only"` — downstream skips infra phases |
| `discovery_artifacts`      | `metadata.discovery_artifacts`            | `["ai-workload-profile.json"]`              |
| `questions_asked`          | `metadata.questions_asked`                | Array of Q1-Q10 asked                       |
| `questions_defaulted`      | `metadata.questions_defaulted`            | Array of Q IDs where defaults used          |
| `target_region`            | `design_constraints.target_region`        | Derived from AWS region or cross-cloud pref |
| `ai_framework`             | `ai_constraints.ai_framework`             | From Q1                                     |
| `ai_priority`              | `ai_constraints.ai_priority`              | From Q2                                     |
| `ai_monthly_spend`         | `ai_constraints.ai_monthly_spend`         | From Q3                                     |
| `cross_cloud`              | `ai_constraints.cross_cloud`              | From Q4 (unique to AI-only)                 |
| `ai_model_baseline`        | `ai_constraints.ai_model_baseline`        | From Q5                                     |
| `ai_vision`                | `ai_constraints.ai_vision`                | From Q6                                     |
| `ai_token_volume`          | `ai_constraints.ai_token_volume`          | From Q7                                     |
| `ai_latency`               | `ai_constraints.ai_latency`               | From Q8                                     |
| `ai_complexity`            | `ai_constraints.ai_complexity`            | From Q9                                     |
| `ai_critical_feature`      | `ai_constraints.ai_critical_feature`      | From Q10                                    |
| `ai_capabilities_required` | `ai_constraints.ai_capabilities_required` | Derived from `capabilities_summary`         |

Each `ai_constraints` field uses `{ "value": ..., "chosen_by": "user"|"extracted"|"derived" }` format. No nulls. All schema rules from `clarify.md` apply.

---

## Step 4: Update Phase Status

Use the Phase Status Update Protocol to write `.phase-status.json` with `phases.clarify` set to `"completed"` -- in the same turn as the output message.

Output: "Clarification complete. Proceeding to Phase 3: Design AI Migration Architecture."
