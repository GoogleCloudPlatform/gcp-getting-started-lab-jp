# Estimate Phase: AI Workload Cost Analysis

> Loaded by estimate.md when gcp-design-ai.json exists.

**Execute ALL steps in order. Do not skip or optimize.**

## Pricing Mode

The parent `estimate.md` selects the pricing mode before loading this file.

**Price lookup order:**

1. **Google Developer Knowledge MCP (preferred when available)** -- Search official Google developer docs for current Vertex AI model pricing and lifecycle notes, then verify against the official Vertex AI pricing page. Set `pricing_source: "google_developer_knowledge"`.
2. **Official web search** -- Search `cloud.google.com/vertex-ai/generative-ai/pricing` for current Vertex AI model pricing. Set `pricing_source: "web_search"`.
3. **`shared/pricing-cache.md` (quick reference)** -- Look up Vertex AI model pricing and source provider pricing by table. Set `pricing_source: "cached"`.
4. **Cache after live lookup failure** -- If live lookup was attempted but failed, and the model IS in the cache, use the cached price. Set `pricing_source: "cached_fallback"`.
5. **Unavailable** -- If a model is NOT in the cache AND live lookup failed, set `pricing_source: "unavailable"` and warn the user.

For typical migrations (Gemini 3.1 Pro Preview, Gemini 3 Flash Preview, Gemini 2.5 Pro/Flash, Claude via Vertex, Llama via Model Garden, Bedrock source pricing), many prices are in `pricing-cache.md`. Verify current model availability and pricing with official provider pages before finalizing estimates. Note: Gemini 2.0 Flash is deprecated -- do not recommend it for new workloads.

## Prerequisites

Read from `$MIGRATION_DIR/`:

- **`ai-workload-profile.json`** -- `current_costs.monthly_ai_spend`, `current_costs.services_detected`, `models[]`
- **`preferences.json`** -- `ai_constraints.ai_token_volume.value`, `ai_constraints.ai_capabilities_required.value`
- **`gcp-design-ai.json`** -- `metadata.ai_source`, `ai_architecture.honest_assessment`, `ai_architecture.tiered_strategy`, `ai_architecture.vertex_models[]` (with `source_provider_price`, `vertex_price`, `honest_assessment`), `ai_architecture.capability_mapping`

---

## Part 1: Establish Current AWS AI Costs

Determine current Bedrock / SageMaker spending from the best available source:

1. **Billing data (preferred)** -- Use `current_costs.monthly_ai_spend` from `ai-workload-profile.json`
2. **Estimated from token volume** -- Use `ai_constraints.ai_token_volume.value` from `preferences.json` with Bedrock pricing from `pricing-cache.md` (under "Source Provider Pricing"). Apply 60/40 input/output ratio if actual ratio unknown.
3. **Neither available** -- Note in output and present model comparison at multiple volume tiers so user can find their range.

---

## Part 2: Build Model Comparison Table

Calculate the monthly Vertex AI cost for **every viable model** at the user's token volume.

**Token volume mapping** (from `ai_token_volume` in `preferences.json`):

| `ai_token_volume` | Input tokens/month | Output tokens/month | Ratio |
| ----------------- | ------------------ | ------------------- | ----- |
| `"low"`           | 6M                 | 4M                  | 60/40 |
| `"medium"`        | 60M                | 40M                 | 60/40 |
| `"high"`          | 600M               | 400M                | 60/40 |
| `"very_high"`     | 6B                 | 4B                  | 60/40 |

If design or discover phase has more specific token estimates, use those instead.

**Cost formula:** `Monthly = (input_tokens / 1M x input_rate) + (output_tokens / 1M x output_rate)`

**Long-context surcharge:** Gemini models generally do not charge extra for long context within their stated context window. However, if `ai_critical_feature = "ultra_long_context"` in `preferences.json`, note that partner models on Vertex AI (e.g., Claude) may charge 2x the standard input rate for tokens beyond 200K context. Apply the surcharge to the portion of input tokens that exceeds 200K per request. If per-request token counts are unknown, assume 50% of input tokens fall in the long-context tier as a conservative estimate.

**Comparison table columns:** Model, Vertex AI Monthly, vs Source Provider ($ and %), vs Current AWS, Quality, Capabilities Match (checked against `ai_capabilities_required`).

Include source provider pricing from `gcp-design-ai.json` -> `vertex_models[].source_provider_price`.

If Vertex AI is more expensive for the recommended model, flag prominently.

If embeddings are needed, add a separate line (additive to primary model cost).

---

## Part 3: Recommended Model Cost Breakdown

Using the model selected in the design phase, show:

- Input tokens x rate, output tokens x rate, embeddings x rate (if applicable)
- Total monthly cost
- Comparison to current AWS spend (monthly and annual difference)
- Backup model cost for comparison

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

Present the monthly and annual cost difference between current AWS AI spend and projected Vertex AI cost:

- **If Vertex AI is cheaper**: present monthly and annual savings clearly
- **If Vertex AI is more expensive**: state clearly, justify with non-cost benefits or note "not justified if cost is the only priority"

Reference `gcp-design-ai.json` -> `honest_assessment`. If `"recommend_stay"`, present prominently.

**Non-cost benefits to present:** Gemini Pro-class models (native Google models, large context windows), model flexibility (partner models via Model Garden when available), Vertex AI ecosystem (Vertex AI Search, Vertex AI Agent Builder, Vertex AI Pipelines), Google Cloud AI infrastructure (TPUs), vendor diversification, multi-model strategy.

**Note:** Human and professional-services one-time migration costs are out of scope for this advisor and are excluded from ROI calculations and user-facing summaries.

---

## Part 6: Cost Optimization Opportunities

Present applicable optimizations with estimated savings:

| Optimization               | Savings | Applies When                                        |
| -------------------------- | ------- | --------------------------------------------------- |
| Model downsizing / tiering | 60-87%  | High volume, premium model selected                 |
| Gemini 3 Flash Preview over Gemini 3.1 Pro Preview | ~75% | Tasks that don't require flagship-level reasoning (Flash Preview $0.50/$3.00 vs 3.1 Pro $2.00/$12.00) |
| Batch API                  | 50%     | Non-real-time workloads (`ai_latency = "flexible"`) |
| Context caching            | Varies  | Repeated system prompts (Gemini context caching)    |
| Input token reduction      | 10-30%  | Prompt optimization, shorter context                |
| Multi-model tiered routing | 60-87%  | High/very-high volume, `tiered_strategy` in design. Use: Tier 1 Gemini 3 Flash Preview (60%), Tier 2 Gemini 3.1 Pro Preview (30%), Tier 3 Gemini 3.1 Pro Preview thinking (10%) |

For each applicable optimization, calculate before/after monthly cost and show an `optimized_projection` (best-case monthly with all optimizations).

---

## Output

Write `estimation-ai.json` to `$MIGRATION_DIR/`.

**Schema -- top-level fields:**

| Field                           | Type   | Description                                                                                                         |
| ------------------------------- | ------ | ------------------------------------------------------------------------------------------------------------------- |
| `phase`                         | string | `"estimate"`                                                                                                        |
| `timestamp`                     | string | ISO 8601                                                                                                            |
| `pricing_source`                | string | `"google_developer_knowledge"`, `"web_search"`, `"cached"`, `"cached_fallback"`, or `"unavailable"`                 |
| `accuracy_confidence`           | string | `"+-5-10%"` or `"+-15-25%"`                                                                                         |
| `current_costs`                 | object | `source`, `aws_monthly_ai_spend`, `services[]`                                                                      |
| `token_volume`                  | object | `source`, `monthly_input_tokens`, `monthly_output_tokens`, ratio                                                    |
| `model_comparison`              | array  | All viable models: `model`, `monthly_cost`, `vs_current`, `quality`, `capabilities_match`, `missing_capabilities[]` |
| `recommended_model`             | object | `model`, `monthly_cost`, `breakdown` (input/output/embeddings), `rationale`                                         |
| `backup_model`                  | object | `model`, `monthly_cost`, `rationale`                                                                                |
| `embeddings`                    | object | `model`, `monthly_cost`, `monthly_tokens`, `note` (if applicable)                                                   |
| `cost_comparison`               | object | `current_aws_monthly`, `projected_vertex_monthly`, `monthly_difference`, `annual_difference`, `percent_change`      |
| `migration_cost_considerations` | object | `categories[]` (always `[]`), `complexity_factors[]` (technical integration only), `note` (must state human/pro costs excluded) |
| `roi_analysis`                  | object | `monthly_cost_delta`, `annual_cost_delta`, `justification`, `non_cost_benefits[]`                                   |
| `optimization_opportunities`    | array  | `opportunity`, `potential_savings_monthly`, `implementation_effort`, `description`                                  |
| `optimized_projection`          | object | `monthly_with_optimizations`, `vs_current`, `note`                                                                  |

All cost values are numbers, not strings. Output must be valid JSON.

## Validation Checklist

- [ ] `model_comparison` includes ALL viable Vertex AI models, not just recommended
- [ ] Every model has `capabilities_match` checked against `ai_capabilities_required`
- [ ] `recommended_model.rationale` references user's priority, preference, and volume
- [ ] `roi_analysis` is honest -- if migration increases cost, says so
- [ ] `optimization_opportunities` only includes strategies relevant to user's workload
- [ ] No compute, database, storage, or networking costs (those belong in `estimate-infra.md`)
- [ ] `migration_cost_considerations.categories` is `[]` -- no human one-time migration costs presented

## Present Summary

After writing `estimation-ai.json`, present under 25 lines:

1. **Pricing source and accuracy**: State whether prices came from Google Developer Knowledge MCP, official web search, cache, or fallback, and the accuracy range (+-15-25% for AI models from cache, +-5-10% from official live lookup). Example: "AI model estimates based on cached pricing (2026-04-12), accuracy +-15-25%."
2. Current AWS AI spend vs projected Vertex AI cost (recommended model)
3. Model comparison table: model name, monthly cost, vs source provider %, capabilities match
4. Recommended model with cost breakdown
5. If migration increases cost: flag honestly with non-cost justification
6. Top 2-3 optimization opportunities with potential savings
7. Optimized projection

## Generate Phase Integration

The Generate phase uses `estimation-ai.json`:

1. **`recommended_model`** -- Which Vertex AI model to provision and test
2. **`migration_cost_considerations`** -- `complexity_factors[]` only for integration risk context; **never** present human one-time migration **costs** to the user (`categories` stays `[]`)
3. **`optimization_opportunities`** -- Which optimizations to implement and when
4. **`cost_comparison`** -- Cost monitoring targets and alerts in production
5. **`model_comparison`** -- Fallback options if recommended model doesn't meet quality bar

## Scope Boundary

**This phase covers financial analysis ONLY for AI workloads.**

FORBIDDEN -- Do NOT include compute, database, storage, networking cost calculations, infrastructure provisioning, code migration examples, or detailed migration timelines.
