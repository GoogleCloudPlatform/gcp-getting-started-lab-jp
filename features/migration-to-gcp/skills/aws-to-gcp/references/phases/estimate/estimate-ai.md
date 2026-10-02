# Estimate Phase: AI Workload Cost Analysis

> Loaded by estimate.md when gcp-design-ai.json exists.

**Execute ALL steps in order. Do not skip or optimize.**

## Pricing Mode

The parent `estimate.md` selects the pricing mode before loading this file. The hierarchy below mirrors `estimate-infra.md` and is binding for AI/model pricing too.

**Price lookup order (live-only — no cache, no recall from training):**

1. **`gcp-pricing` CLI (PRIMARY, Cloud Billing Catalog API)** -- For Vertex AI, `serviceId` is **`C7E2-9256-1C43`** (verified 2026-05-19 via live services listing). Other related IDs: `74B1-77CF-C302` (Vertex AI Search), `E5FE-878F-FECE` (Vertex AI Vision). Always verify the current ID with `gcp-pricing services --filter "Vertex AI"` rather than hard-coding from this doc:
   ```bash
   gcp-pricing skus --service C7E2-9256-1C43 --filter "Gemini .* (Input|Output) Tokens" --currency USD --limit 0
   ```
   Match SKUs by model name in the description (e.g. `Gemini 3.1 Pro Preview Input Tokens`, `Gemini 3 Flash Preview Output Tokens`); `tieredRates[].unitPrice` is a ready decimal string. Set `pricing.source = "gcp-pricing (Cloud Billing Catalog API)"`. If the `--filter "Vertex AI"` services lookup returns no rows at run time (the catalog display name may change after the Gemini Enterprise Agent Platform (GEAP; formerly Vertex AI) rebrand), retry `gcp-pricing services --filter "Gemini Enterprise|Agent Platform"` and use the returned ID before falling to source (2).
2. **`google-developer-knowledge` MCP (SECONDARY)** -- Only if the `gcp-pricing` lookup has no matching SKU or fails. Search official Agent Platform / model docs. Set `pricing.source = "google-developer-knowledge MCP"`.
3. **WebFetch (TERTIARY)** -- Only if both above fail. `https://cloud.google.com/gemini-enterprise-agent-platform/generative-ai/pricing` for Agent Platform models; provider docs (Anthropic, OpenAI) for source AWS pricing. Set `pricing.source = "WebFetch cloud.google.com"`.
4. **STOP if all three fail.** Do NOT recall model prices from training. Report the failure; let the user provide a manual rate (`pricing.source = "user_provided"`) with explicit justification in `evidence`.

For typical migrations (Gemini 3.1 Pro Preview, Gemini 3 Flash Preview, Gemini 2.5 Pro/Flash, Claude via Agent Platform, Llama via Model Garden, Bedrock source pricing), the Catalog API has all current SKUs. Note: Gemini 2.0 Flash is deprecated -- do not recommend it for new workloads.

The same `pricing.attempts[].evidence` and `pricing.attempts[].tool_call` requirements from `estimate-infra.md` apply here — every dollar must trace to a live tool call this run.

## Prerequisites

Read from `$MIGRATION_DIR/`:

- **`ai-workload-profile.json`** -- `current_costs.monthly_ai_spend`, `current_costs.services_detected`, `models[]`
- **`preferences.json`** -- `ai_constraints.ai_token_volume.value`, `ai_constraints.ai_capabilities_required.value`
- **`gcp-design-ai.json`** -- `metadata.ai_source`, `ai_architecture.honest_assessment`, `ai_architecture.tiered_strategy`, `ai_architecture.vertex_models[]` (with `source_provider_price`, `vertex_price`, `honest_assessment`), `ai_architecture.capability_mapping`

---

## Part 1: Establish Current AWS AI Costs

Determine current Bedrock / SageMaker spending from the best available source:

1. **Billing data (preferred)** -- Use `current_costs.monthly_ai_spend` from `ai-workload-profile.json`
2. **Estimated from token volume** -- Use `ai_constraints.ai_token_volume.value` from `preferences.json` with current Bedrock/source-provider pricing fetched live via WebFetch of the official provider pricing page: `claude.com/pricing` (anthropic.com/pricing 301-redirects there), the OpenAI developer-docs pricing page at `developers.openai.com` (do NOT WebFetch `openai.com/api/pricing` — it returns HTTP 403 to non-browser fetchers), and `aws.amazon.com/bedrock/pricing`. Record the fetch in `pricing.attempts[]` with `evidence`. Apply 60/40 input/output ratio if actual ratio unknown.
3. **Neither available** -- Note in output and present model comparison at multiple volume tiers so user can find their range.

---

## Part 2: Build Model Comparison Table

Calculate the monthly Agent Platform cost for **every viable model** at the user's token volume.

**Token volume mapping** (from `ai_token_volume` in `preferences.json`):

| `ai_token_volume` | Input tokens/month | Output tokens/month | Ratio |
| ----------------- | ------------------ | ------------------- | ----- |
| `"low"`           | 6M                 | 4M                  | 60/40 |
| `"medium"`        | 60M                | 40M                 | 60/40 |
| `"high"`          | 600M               | 400M                | 60/40 |
| `"very_high"`     | 6B                 | 4B                  | 60/40 |

If design or discover phase has more specific token estimates, use those instead.

**Cost formula:** `Monthly = (input_tokens / 1M x input_rate) + (output_tokens / 1M x output_rate)`

**Long-context surcharge:** Gemini Pro-class models DO charge long-context rates — when the prompt exceeds 200K tokens, ALL tokens (input and output) bill at the higher tier (e.g., as of 2026-07: Gemini 3.1 Pro Preview $4 input/$18 output above 200K vs $2/$12 below; fetch current tier boundaries and rates from the live pricing page — they appear as separate columns per model). Partner models on Agent Platform (e.g., Claude) likewise publish a `>200K input tokens` rate column. Whenever `ai_critical_feature = "ultra_long_context"`, apply the correct >200K tier to the long-context share of traffic; if per-request token counts are unknown, assume 50% of input tokens fall in the long-context tier as a conservative estimate and label it `derived`.

**Comparison table columns:** Model, Agent Platform Monthly, vs Source Provider ($ and %), vs Current AWS, Quality, Capabilities Match (checked against `ai_capabilities_required`).

Include source provider pricing from `gcp-design-ai.json` -> `vertex_models[].source_provider_price`.

If Agent Platform is more expensive for the recommended model, flag prominently.

If embeddings are needed, add a separate line (additive to primary model cost).

---

## Part 3: Recommended Model Cost Breakdown

Using the model selected in the design phase, show:

- Input tokens x rate, output tokens x rate, embeddings x rate (if applicable)
- Total monthly cost
- Comparison to current AWS spend (monthly and annual difference)
- Backup model cost for comparison

---

## Part 3B: Agent Runtime Compute Pricing

**Gate: run only when `gcp-design-ai.json` -> `ai_architecture.agent_placement[]` is non-empty.**

> **BINDING — SNAPSHOT, verify live:** SKU descriptions for the managed agent runtime have carried several names across the rebrand ("ReasoningEngine", "Agent Engine", "Agent Runtime"). Search broadly and record what the catalog actually returned this run.

1. **Double-count guard:** if the agent's host resource is already priced in `estimation-infra.json` (the IaC path ran and priced the placement), do NOT price it again. Write `agent_runtime_costs: {"skipped": true, "reason": "priced in estimation-infra.json"}` and stop this part.
2. **Lookup:** `gcp-pricing skus --service C7E2-9256-1C43 --filter "(Agent|Reasoning)" --currency USD --limit 0`. Select the vCPU-hour and GiB-hour SKUs for the managed agent runtime. Same fallback chain as the Pricing Mode section (MCP -> WebFetch -> STOP); same `pricing.attempts[]` evidence and tool-call provenance requirements.
3. **Formula:** `monthly = min_instances x cpu x 730 x vcpu_hr_rate + min_instances x memory_GiB x 730 x gib_hr_rate`, with sizing from `agent_placement[].sizing`. Add the note `TODO: burst above min_instances not modeled — not billed when idle above the floor`.
4. **Output:** populate the `agent_runtime_costs` field (schema below) with `sku_evidence[]`, `monthly_cost`, `assumptions` (`cpu`, `memory_GiB`, `min_instances`, `hours`), and `pricing`.

---

## Part 4: Human One-Time Migration Costs (Out of Scope)

**Do not** present human labor, contractors, professional services, or engineering effort as one-time migration **costs** or budget line items (no dollar figures, no "budget for people work" lists, no "one-time migration cost" categories for implementation).

Populate `migration_cost_considerations.categories` as an **empty array** `[]`. Use `migration_cost_considerations.note` to state that human and professional-services one-time migration costs are intentionally excluded from this advisor.

**Technical integration complexity** (for internal JSON and risk context only -- not framed as money):

From `ai-workload-profile.json`, record non-monetary factors in `migration_cost_considerations.complexity_factors[]` as short strings, for example:

- `integration.pattern = "framework"` -> lower integration touch surface
- `integration.pattern = "direct_sdk"` -> moderate SDK and API pattern changes
- `integration.pattern = "rest_api"` -> higher endpoint, auth, and parsing changes
- `summary.total_models_detected` > 3 -> multi-model coordination

Do **not** repeat these as "costs" in the user-facing summary.

---

## Part 5: ROI Analysis

Present the monthly and annual cost difference between current AWS AI spend and projected Agent Platform cost:

- **If Agent Platform is cheaper**: present monthly and annual savings clearly
- **If Agent Platform is more expensive**: state clearly, justify with non-cost benefits or note "not justified if cost is the only priority"

Reference `gcp-design-ai.json` -> `honest_assessment`. If `"recommend_stay"`, present prominently.

**Non-cost benefits to present:** Gemini Pro-class models (native Google models, large context windows), model flexibility (partner models via Model Garden when available), Agent Platform ecosystem (Agent Search, Google ADK + Agent Runtime, GEAP Pipelines), Google Cloud AI infrastructure (TPUs), vendor diversification, multi-model strategy.

**Note:** Human and professional-services one-time migration costs are out of scope for this advisor and are excluded from ROI calculations and user-facing summaries.

---

## Part 6: Cost Optimization Opportunities

Present applicable optimizations with estimated savings:

| Optimization                                       | Savings | Applies When                                                                                                                                                                    |
| -------------------------------------------------- | ------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Model downsizing / tiering                         | 60-87%  | High volume, premium model selected                                                                                                                                             |
| Gemini 3 Flash Preview over Gemini 3.1 Pro Preview | ~75%    | Tasks that don't require flagship-level reasoning (Flash Preview $0.50/$3.00 vs 3.1 Pro $2.00/$12.00)                                                                           |
| Batch API                                          | 50%     | Non-real-time workloads (`ai_latency = "flexible"`)                                                                                                                             |
| Context caching                                    | Varies  | Repeated system prompts (Gemini context caching)                                                                                                                                |
| Input token reduction                              | 10-30%  | Prompt optimization, shorter context                                                                                                                                            |
| Multi-model tiered routing                         | 60-87%  | High/very-high volume, `tiered_strategy` in design. Use: Tier 1 Gemini 3 Flash Preview (60%), Tier 2 Gemini 3.1 Pro Preview (30%), Tier 3 Gemini 3.1 Pro Preview thinking (10%) |

For each applicable optimization, calculate before/after monthly cost and show an `optimized_projection` (best-case monthly with all optimizations).

---

## Output

Write `estimation-ai.json` to `$MIGRATION_DIR/`.

**Schema -- top-level fields:**

| Field                           | Type   | Description                                                                                                                                                       |
| ------------------------------- | ------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `phase`                         | string | `"estimate"`                                                                                                                                                      |
| `timestamp`                     | string | ISO 8601                                                                                                                                                          |
| `pricing_source`                | string | `"gcp_pricing_catalog_api"`, `"google_developer_knowledge"`, `"web_fetch"`, `"user_provided"`, or `"unavailable"`                                                 |
| `accuracy_confidence`           | string | `"+-2-5%"` (Catalog API), `"+-5-10%"` (MCP/WebFetch), `"+-10-20%"` (user_provided)                                                                                |
| `current_costs`                 | object | `source`, `aws_monthly_ai_spend`, `services[]`                                                                                                                    |
| `token_volume`                  | object | `source`, `monthly_input_tokens`, `monthly_output_tokens`, ratio                                                                                                  |
| `model_comparison`              | array  | All viable models: `model`, `monthly_cost`, `vs_current`, `quality`, `capabilities_match`, `missing_capabilities[]`                                               |
| `recommended_model`             | object | `model`, `monthly_cost`, `breakdown` (input/output/embeddings), `rationale`                                                                                       |
| `backup_model`                  | object | `model`, `monthly_cost`, `rationale`                                                                                                                              |
| `embeddings`                    | object | `model`, `monthly_cost`, `monthly_tokens`, `note` (if applicable)                                                                                                 |
| `cost_comparison`               | object | `current_aws_monthly`, `projected_vertex_monthly`, `monthly_difference`, `annual_difference`, `percent_change`                                                    |
| `migration_cost_considerations` | object | `categories[]` (always `[]`), `complexity_factors[]` (technical integration only), `note` (must state human/pro costs excluded)                                   |
| `roi_analysis`                  | object | `monthly_cost_delta`, `annual_cost_delta`, `justification`, `non_cost_benefits[]`                                                                                 |
| `optimization_opportunities`    | array  | `opportunity`, `potential_savings_monthly`, `implementation_effort`, `description`                                                                                |
| `optimized_projection`          | object | `monthly_with_optimizations`, `vs_current`, `note`                                                                                                                |
| `agent_runtime_costs`           | object | Optional — present iff `agent_placement` non-empty: `sku_evidence[]`, `monthly_cost`, `assumptions`, `pricing`; or `{skipped, reason}` per the double-count guard |

All cost values are numbers, not strings. Output must be valid JSON.

## Validation Checklist

- [ ] `model_comparison` includes ALL viable Agent Platform models, not just recommended
- [ ] Every model has `capabilities_match` checked against `ai_capabilities_required`
- [ ] `recommended_model.rationale` references user's priority, preference, and volume
- [ ] `roi_analysis` is honest -- if migration increases cost, says so
- [ ] `optimization_opportunities` only includes strategies relevant to user's workload
- [ ] No compute, database, storage, or networking costs (those belong in `estimate-infra.md`; sole exception: `agent_runtime_costs` per Part 3B when the IaC path did not price the placement)
- [ ] `agent_runtime_costs` present iff `agent_placement` non-empty; either priced with live SKU evidence or `skipped` with the infra-estimate guard reason
- [ ] `migration_cost_considerations.categories` is `[]` -- no human one-time migration costs presented

## Present Summary

After writing `estimation-ai.json`, present under 25 lines:

1. **Pricing source and accuracy**: State the proportion of models priced from each live source (e.g. "All 4 Vertex models priced via Cloud Billing Catalog API; Bedrock baseline via WebFetch claude.com/pricing"). Catalog API accuracy is +/-2-5%; WebFetch +/-5-10%. If any model lacks a live price, list it.
2. Current AWS AI spend vs projected Agent Platform cost (recommended model)
3. Model comparison table: model name, monthly cost, vs source provider %, capabilities match
4. Recommended model with cost breakdown
5. If migration increases cost: flag honestly with non-cost justification
6. Top 2-3 optimization opportunities with potential savings
7. Optimized projection

## Generate Phase Integration

The Generate phase uses `estimation-ai.json`:

1. **`recommended_model`** -- Which Agent Platform model to provision and test
2. **`migration_cost_considerations`** -- `complexity_factors[]` only for integration risk context; **never** present human one-time migration **costs** to the user (`categories` stays `[]`)
3. **`optimization_opportunities`** -- Which optimizations to implement and when
4. **`cost_comparison`** -- Cost monitoring targets and alerts in production
5. **`model_comparison`** -- Fallback options if recommended model doesn't meet quality bar

## Scope Boundary

**This phase covers financial analysis ONLY for AI workloads.**

FORBIDDEN -- Do NOT include compute, database, storage, networking cost calculations, infrastructure provisioning, code migration examples, or detailed migration timelines.
