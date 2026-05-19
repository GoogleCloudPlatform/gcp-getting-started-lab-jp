# Generate Phase: HTML Migration Report

> Loaded by generate.md AFTER generate-artifacts-docs.md completes.

**Execute ALL steps in order. Do not skip or optimize.**

## Overview

Generate a single self-contained HTML report (`migration-report.html`) combining an executive summary with detailed appendix. The HTML file uses inline CSS -- no external dependencies required. Users can open it in any browser and use "Print to PDF" if a PDF is needed.

**Output:**

- `migration-report.html` -- Self-contained HTML report with executive summary and detailed appendix

**Non-blocking:** If report generation fails for any reason, log a warning and continue. Do NOT fail the Generate phase. The markdown documentation (`MIGRATION_GUIDE.md`, `README.md`) is the primary output.

## Prerequisites

At least one of these must exist in `$MIGRATION_DIR/`:

- Design artifact: `gcp-design.json`, `gcp-design-ai.json`, or `gcp-design-billing.json`
- Estimation artifact: `estimation-infra.json`, `estimation-ai.json`, or `estimation-billing.json`
- Generation plan: `generation-infra.json`, `generation-ai.json`, or `generation-billing.json`

If **none** exist: skip report generation. Output: "Skipping HTML report -- no migration artifacts found."

## Data Sources

Gather data from all available artifacts. Each section below notes which artifact provides the data.

| Data Point                              | Primary Source                                               | Fallback                                         |
| --------------------------------------- | ------------------------------------------------------------ | ------------------------------------------------ |
| AWS services detected                   | `gcp-design.json` clusters[].resources[]                     | `gcp-design-billing.json` services[]             |
| GCP service mappings                    | `gcp-design.json` resources[].gcp_service                    | `gcp-design-billing.json` services[].gcp_service |
| Rationale per service                   | `gcp-design.json` resources[].rationale                      | `gcp-design-billing.json` services[].rationale   |
| Current AWS monthly cost                | `estimation-infra.json` current_costs.aws_monthly            | `estimation-billing.json`                        |
| Projected GCP monthly cost              | `estimation-infra.json` projected_costs.gcp_monthly_balanced | `estimation-billing.json`                        |
| Cost breakdown per service              | `estimation-infra.json` projected_costs.breakdown            | `estimation-billing.json`                        |
| Cost tiers (premium/balanced/optimized) | `estimation-infra.json` cost_comparison                      | --                                               |
| Optimization opportunities              | `estimation-infra.json` optimization_opportunities           | --                                               |
| Migration timeline                      | `generation-infra.json` migration_plan.total_weeks           | `generation-billing.json`                        |
| Top risks                               | `generation-infra.json` risk_assessment                      | `generation-billing.json`                        |
| Human expertise flags                   | Design artifact resources[].human_expertise_required         | --                                               |
| AI model mappings                       | `gcp-design-ai.json`                                         | --                                               |
| AI cost estimates                       | `estimation-ai.json`                                         | --                                               |

## Step 1: Build Executive Summary Section

The executive summary is the first thing visible when opening the report. Design it to fit approximately one printed page.

### Executive Summary Content

**Header:** "AWS to GCP Migration Assessment" with subtitle "Executive Summary" and generation date.

**Section 1 -- Current Stack Overview:**

- Count of AWS services detected
- List each AWS service with its type (e.g., "Fargate (compute)", "RDS PostgreSQL (database)")
- Source: design artifact

**Section 2 -- Recommended GCP Architecture:**

- Table with columns: AWS Service, GCP Service, **How we chose this**
- **How we chose this** values: use `design-refs/fast-path.md` -> **User-facing vocabulary** -- **Standard pairing** (`deterministic`), **Tailored to your setup** (`inferred`), **Estimated from billing only** (`billing_inferred`). Show the **bold phrase** in the table; JSON value optional in a tooltip or footnote for technical readers only.
- One row per mapped service
- If any service has `human_expertise_required: true`, mark it with a warning indicator and footnote: "Specialist guidance recommended -- contact your GCP account team"
- Source: design artifact

**Section 3 -- Cost Comparison:**

- Side-by-side display: Current AWS Monthly vs Projected GCP Monthly (**Balanced** tier -- the default scenario for comparing to AWS)
- Percent change (savings or increase)
- **How to read cost tiers (callout box -- required when infra estimation with three tiers exists):** The three GCP monthly figures are **pricing scenarios** for the **same** mapped architecture (same services in `gcp-design.json`), not three different generated Terraform stacks. **Order = highest -> middle -> lowest** monthly estimate in this model. Use **Balanced** as the **primary** row vs AWS; **Premium** and **Optimized** are **bounds** (higher HA / newer skew vs cost-optimization skew). When `terraform/` is present, it implements **one** infrastructure baseline aligned with the **Balanced** cost scenario (see `terraform/README.md` and `migration_summary` output).
- If 3 tiers available: show **Premium**, **Balanced**, and **Optimized** with **short subtitles** (second line or subtext under each label):
  - **Premium** -- *Highest resilience / highest monthly estimate in this model*
  - **Balanced** -- *Default scenario; compare AWS to this row first*
  - **Optimized** -- *Lower monthly estimate; committed use, preemptible, or storage trade-offs assumed*
- **Footnote (required):** *Only one Terraform configuration is generated (Balanced-aligned baseline). Premium and Optimized are what-if cost models in `estimation-infra.json` -- adjust IaC yourself if you want those postures in production.*
- **Only include "AWS data transfer egress (est.)" when the infra estimation artifact has `migration_cost_considerations.billing_data_available === true`.** Never present human one-time migration costs. If `false` or only non-infra estimates exist, footnote: "AWS data transfer egress estimates require billing data and the infra estimate path."
- Source: estimation artifact

**Section 4 -- Timeline:**

- Total migration weeks
- Migration approach (phased/fast-track/conservative)
- Source: generation plan

**Section 5 -- Top Risks:**

- Up to 3 highest-severity risks
- Each with: risk name, severity, one-line mitigation
- Source: generation plan risk_assessment

## Step 2: Build Detailed Appendix

The appendix follows the executive summary, clearly separated with an "Appendix: Detailed Migration Analysis" header.

### Appendix Section A -- Service Recommendations

For each mapped service, include:

- AWS service name and type
- GCP service recommendation
- **How the mapping was chosen** -- use **Standard pairing**, **Tailored to your setup**, or **Estimated from billing only** (`design-refs/fast-path.md` -> User-facing vocabulary); JSON `confidence` may appear in parentheses for support
- Full rationale text from design artifact
- If the mapping was **Tailored to your setup** (`inferred`) and `rubric_applied` is present: list the 6 criteria evaluations (appendix detail -- optional in executive summary)
- If `human_expertise_required: true`: include the specialist guidance callout

Source: design artifact (gcp-design.json or gcp-design-billing.json)

### Appendix Section B -- Cost Estimates

**Per-service cost breakdown table** with columns: Service Category, GCP Service, Monthly Cost (Balanced), Alternative, Alternative Cost, Potential Savings.

Source: estimation artifact projected_costs.breakdown

**Three-tier comparison table** with columns: **Tier** (name + subtitle as in Section 3), Monthly Cost, vs AWS Monthly, Annual Difference.

Repeat the **How to read cost tiers** callout from Section 3 here or include a one-line pointer: *See executive summary -- three tiers are scenario $ only; generated Terraform matches **Balanced** baseline.*

Source: estimation artifact cost_comparison

**Optimization opportunities table** with columns: Optimization, Target Services, Monthly Savings, Commitment, Effort.

Source: estimation artifact optimization_opportunities

### Appendix Section C -- Migration Steps

Numbered migration phases from the generation plan, each with:

- Phase name and description
- Services included
- Estimated duration
- Dependencies and prerequisites

Source: generation plan

**Rollback procedure** -- triggers, steps, and RTO from generation plan.

### Appendix Section D -- AI Migration (conditional)

**Only include if `gcp-design-ai.json` or `estimation-ai.json` exists.**

- Model mappings (AWS model to GCP Vertex AI model)
- AI cost estimates
- Migration approach (adapter pattern, A/B testing)

### Appendix Section E -- Generated Artifacts Catalog

List all files and directories generated during the Generate phase:

- `terraform/` -- list .tf files and **`README.md`**
- `scripts/` -- list migration scripts
- `ai-migration/` -- list adapter files (if applicable)
- `MIGRATION_GUIDE.md`, `README.md`

Check for actual file/directory existence before listing.

## Step 3: Generate HTML

Write the complete HTML to `$MIGRATION_DIR/migration-report.html`.

### HTML Structure

```html
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>AWS to GCP Migration Assessment</title>
  <style>
    /* All CSS inline -- see CSS specification below */
  </style>
</head>
<body>
  <div class="report">
    <div class="executive-summary">
      <!-- Executive summary content from Step 1 -->
    </div>
    <div class="appendix">
      <!-- Appendix content from Step 2 -->
    </div>
    <footer>
      Generated by AWS to GCP Migration Advisor
    </footer>
  </div>
</body>
</html>
```

### CSS Specification

The inline CSS must include:

**Layout:**

- `body`: font-family system-ui, -apple-system, sans-serif; max-width 900px; margin 0 auto; padding 40px 20px; color #1a1a2e; background #ffffff; line-height 1.6
- `.report`: single container

**Typography:**

- `h1`: font-size 1.8rem; color #1a1a2e; border-bottom 3px solid #4285f4; padding-bottom 8px
- `h2`: font-size 1.4rem; color #202124; margin-top 2rem
- `h3`: font-size 1.1rem; color #5f6368

**Tables:**

- `table`: width 100%; border-collapse collapse; margin 1rem 0
- `th`: background #202124; color white; padding 10px 12px; text-align left; font-size 0.85rem
- `td`: padding 8px 12px; border-bottom 1px solid #e8e8e8; font-size 0.85rem
- `tr:hover`: background #f5f5f5

**Cards (for executive summary metrics):**

- `.metric-card`: display inline-block; background #f8f9fa; border 1px solid #e8e8e8; border-radius 8px; padding 16px 24px; margin 8px; text-align center; min-width 160px
- `.metric-value`: font-size 1.6rem; font-weight bold; color #202124
- `.metric-label`: font-size 0.8rem; color #5f6368; text-transform uppercase

**Cost comparison highlight:**

- `.cost-savings`: color #137333 (green for savings)
- `.cost-increase`: color #c5221f (red for increase)

**Warning callout (for human_expertise_required):**

- `.callout-warning`: background #fef7e0; border-left 4px solid #f9ab00; padding 12px 16px; margin 1rem 0; border-radius 0 4px 4px 0

**Confidence badges (visible text = user-facing vocabulary, not JSON):**

- `.badge`: display inline-block; padding 2px 8px; border-radius 12px; font-size 0.75rem; font-weight 600
- `.badge-deterministic`: background #e6f4ea; color #137333 -- label **Standard pairing**
- `.badge-inferred`: background #fef7e0; color #b05a00 -- label **Tailored to your setup**
- `.badge-billing`: background #fce8e6; color #c5221f -- label **Estimated from billing only**

**Print styles:**

- `@media print`: hide nothing, adjust margins, ensure page breaks before `.appendix`

**Footer:**

- `footer`: margin-top 3rem; padding-top 1rem; border-top 1px solid #e8e8e8; text-align center; color #5f6368; font-size 0.8rem

### Content Rules

1. **All data must come from artifacts** -- do not invent numbers or services. If an artifact field is missing, omit that section.
2. **Currency formatting**: All cost values displayed as `$X,XXX.XX` with dollar sign and commas.
3. **Percentage formatting**: Include `+` or `-` prefix. Use green styling for savings, red for increases.
4. **No external resources**: No CDN links, no external fonts, no images. Everything inline.
5. **Valid HTML5**: Output must be valid, well-formed HTML5.

## Step 4: Self-Check

After generating the HTML file, verify:

1. **Data accuracy**: Cost figures in HTML match the estimation artifact values exactly
2. **Conditional sections**: AI appendix only present if AI artifacts exist; billing caveats shown when billing_data_available is false
3. **Human expertise flags**: Warning callouts appear for all services with `human_expertise_required: true`
4. **Valid HTML**: Opening and closing tags match, no broken table structures
5. **No placeholders**: No `[placeholder]` or `TODO` text in the report output

## Step 5: Open Report in Browser

After writing the HTML file, open it in the user's default browser so they can view it immediately.

Run: `open "$MIGRATION_DIR/migration-report.html"` (macOS) or `xdg-open "$MIGRATION_DIR/migration-report.html"` (Linux).

If the open command fails, fall back to presenting the full file path to the user:

```
Migration report ready -- open in your browser:
file://$MIGRATION_DIR/migration-report.html
```

## Completion

Report to the parent orchestrator. **Do NOT update `.phase-status.json`** -- the parent `generate.md` handles phase completion.

Output:

```
Migration report saved to $MIGRATION_DIR/migration-report.html

Report sections:
- Executive Summary: [services count] services, [cost comparison], [timeline]
- Appendix A: Service Recommendations
- Appendix B: Cost Estimates
- Appendix C: Migration Steps
- [Appendix D: AI Migration -- if applicable]
- Appendix E: Artifacts Catalog
```
