# Advanced Eval Commands

Opt-in commands from the Quality Flywheel. The core loop (`eval run`, and `eval generate` / `eval grade`) lives in SKILL.md.

## `eval analyze`

Runs LLM-based failure clustering and root-cause analysis over a `results_*.json` produced by an eval run. Use when you have 10+ failing cases and want categorized failure modes instead of reading the HTML case-by-case. Supported `--metric` values: `multi_turn_task_success`, `multi_turn_tool_use_quality`.

```bash
# Basic: analyze a results file with default settings
agents-cli eval analyze --eval-result artifacts/grade_results/results_<ts>.json

# Advanced: restrict to a specific metric and cap loss clusters
agents-cli eval analyze \
  --eval-result artifacts/grade_results/results_<ts>.json \
  --metric multi_turn_tool_use_quality \
  --top-k 5 \
  --output artifacts/analysis_<ts>.json
```

## `eval optimize`

Runs ADK GEPA prompt optimization against a target metric. Suitable after an eval run identifies prompt-only failures (wording, not tool/orchestration logic). `--dataset` and `--target-metric` override values in `--config` when both are passed. **Long-running and expensive, see Stage 4 of the Quality Flywheel for usage guidance.**

```bash
# Basic: optimize against a single metric on a dataset
agents-cli eval optimize --dataset tests/eval/datasets/basic-dataset.json --target-metric final_response_quality

# Advanced: drive multi-metric / multi-dataset optimization from a config file
agents-cli eval optimize --config tests/eval/optimization_config.json
```

## `eval submit` / `eval results` (cloud-side)

The managed, asynchronous counterpart to the local path, for large or CI-driven runs: `eval submit` hands the dataset and metrics to the Agent Platform Eval Service, and `eval results` polls and downloads the scores. Pass `--resource-name <agent>` to also run inference server-side (managed `generate` + `grade`); omit it to grade an existing trace (managed `grade`).

```bash
# Grade an existing trace server-side; returns a run resource name to poll
agents-cli eval submit --dataset tests/eval/datasets/basic-dataset.json --dest gs://my-bucket
# Add --resource-name projects/<p>/locations/<l>/reasoningEngines/<id> to run inference too

agents-cli eval results --run-id <run-resource-name>
```
