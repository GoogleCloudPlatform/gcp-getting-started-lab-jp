# AGENTS.md — conventions for AI agents working in this repository

This repo is a Claude Code plugin (`features/migration-to-gcp/`, skills `aws-to-gcp` + `azure-to-gcp`)
plus the user-journey test harness that evaluates it (`user-journey-tests/`, `CATALOG.md`, `tools/`).
Human-facing overview: [`README.md`](README.md). Fixture authoring rules:
[`user-journey-tests/CONVENTIONS.md`](user-journey-tests/CONVENTIONS.md).

## Binding rules

- **Live research over recall.** Prices come from the `gcp-pricing` CLI (Cloud Billing Catalog API)
  with provenance (`retrieved_at`, `source_url`); service capabilities from the bundled MCP servers
  or official docs fetched at decision time. Never write a rate or capability claim from memory.
  Note: `gcp-pricing skus --service aiplatform` fuzzy-matches the wrong service — use
  `--service "Vertex AI"`; Gemini embedding SKUs live under the separate `"Gemini API"` service.
- **A model exists only when it SERVES.** Verify Gemini/partner model IDs with a live
  `generateContent` call — the publisher-models metadata GET returns 200/"GA" for catalog entries
  that do not serve. Never cite a model that has not answered a request.
- **Naming:** GCP display names use **Gemini Enterprise Agent Platform** (GEAP; formerly Vertex AI)
  with a per-file "(formerly Vertex AI)" first mention. Machine identifiers stay frozen:
  `aiplatform.googleapis.com`, `google-cloud-aiplatform`, LiteLLM `vertex_ai/` routes,
  `google_vertex_ai_*` Terraform types, JSON contract keys (`vertex_models`, `vertex_price`, …).
- **Agent workloads** (ADK / LangGraph / CrewAI / Bedrock Agents) default to **Agent Runtime**;
  the only eliminator is a K8s mandate → GKE. See
  `features/migration-to-gcp/skills/aws-to-gcp/references/design-refs/agent-runtime.md` (placement)
  and `agent-governance.md` (Registry / Gateway / Identity / Model Armor mapping). The vendored
  `.agents/skills/google-agents-cli-*` suite is the canonical GCP-side guidance; keep
  `skills-lock.json` in sync if you update it.
- **Journey fixtures are deterministic test beds.** Never add meta/tooling files inside a
  `user-journey-tests/<vendor>/jN-*/` directory — the Discover phase greps the journey cwd, so any
  extra file pollutes evaluation. Answer keys live in `CATALOG.md` and
  `user-journey-tests/gcp-references/` only. Azure cost/discovery fixtures are generated: edit the
  generator, regenerate deterministically (`gzip -n`), recompute `fixtures.sha256`, re-run the
  journey's `check-consistency.py`.
- **`user-journey-tests/git-exclude/` is permanently local-only** (gitignored). Never track it,
  reference it from published docs, or "fix" the ignore rule.
- **Eval scenarios** (`features/…/skills/*/evals/evals.json`) are append-only; update an existing
  scenario's expectations only when the behavior it asserts was itself corrected.
- **CHANGELOG discipline:** every substantive change lands a bullet in the top `Unreleased` block
  of `CHANGELOG.md`; released history below is never rewritten.

## Verification gates (run what your change touches before committing)

```bash
npx -y dprint@0.51 check                          # formatting — pinned version, no mise required
npx -y markdownlint-cli2@0.17                     # markdown lint (pre-existing baseline findings exist)
node tools/validate-manifests.mjs
node tools/validate-cross-refs.mjs
python3 tools/verify-catalog-refs.py              # MUST print "8 journey blocks" and a nonzero ref
                                                  #   total — exit 0 with 0 blocks means the heading
                                                  #   regex broke and the checker is silently green
claude plugin validate features/migration-to-gcp  # "version unset" warning is intentional (SHA-versioned)
terraform fmt -check && terraform validate        # in any journey terraform/ dir you touched
```

## Git conventions

- **No AI attribution in commits** — no `Co-Authored-By: Claude …`, no "Generated with" lines.
- Small, single-purpose commits; commit messages explain the why, not the file list.
- Never commit credentials or account IDs of live environments; the repo runs gitleaks
  (`.gitleaks.toml`). Lab/deploy credentials live outside the repo (`~/.aws`, `~/.azure`, ADC).
