# Phase 6: Feedback (Optional) + Post-Cutover Parity Verification

Builds an anonymized usage trace, runs user-journey parity tests against the deployed GCP stack (when applicable), and directs the user to the Pulse survey form.

**Execute ALL steps in order. Do not skip or deviate.**

## Prerequisites

Read `$MIGRATION_DIR/.phase-status.json`. Verify `phases.discover == "completed"`. If not: **STOP**. Output: "Feedback requires at least the Discover phase to be completed."

## Step -1: Run User-Journey Parity Tests (post-cutover verification)

This step runs the `user-journeys/*.sh` parity tests produced by `references/phases/generate/generate-artifacts-journeys.md` and records pass/fail in `$MIGRATION_DIR/parity-results.json`. It is the concrete realization of the "verify" intent in the user-facing checklist of `MIGRATION_GUIDE.md`.

**Gate:**

1. If `$MIGRATION_DIR/user-journeys/` directory does not exist (Generate ran with no app code, or the journey synthesis sub-file never ran): skip this step. Do NOT fail the feedback phase.
2. If `$MIGRATION_DIR/user-journeys/user-journeys.md` exists with the graceful-degradation sentinel ("No routes file found in inventory; user journeys could not be derived. Skipping."): write `$MIGRATION_DIR/parity-results.json` containing `{"status": "skipped", "reason": "no routes file in inventory; no journeys to verify", "scripts_run": []}` and proceed to Step 0.
3. If `$ALB_URL` and `$CLOUD_RUN_URL` are not set in the environment: write `parity-results.json` containing `{"status": "skipped", "reason": "ALB_URL and/or CLOUD_RUN_URL environment variables not set; cannot run parity tests", "scripts_run": []}` and proceed to Step 0. Ask the user to re-run the feedback phase after `export`ing both URLs.
4. Otherwise: enumerate every `$MIGRATION_DIR/user-journeys/*.sh` file. For each script, invoke it via Bash (the harness already exposes the Bash tool). Capture exit code, stdout, and stderr. Record one entry per script in `parity-results.json`:

```json
{
  "status": "completed",
  "ran_at": "<ISO 8601>",
  "alb_url": "<value of $ALB_URL at run time>",
  "cloud_run_url": "<value of $CLOUD_RUN_URL at run time>",
  "scripts_run": [
    {
      "script": "user-journeys/001-signup-journey.sh",
      "exit_code": 0,
      "pass": true,
      "stdout_tail": "PASS journey 001 signup-journey",
      "stderr_tail": ""
    },
    {
      "script": "user-journeys/002-file-upload-journey.sh",
      "exit_code": 1,
      "pass": false,
      "stdout_tail": "",
      "stderr_tail": "FAIL status: AWS=200 GCP=502"
    }
  ],
  "summary": {"total": 2, "passed": 1, "failed": 1}
}
```

`stdout_tail` / `stderr_tail` MUST be trimmed to the last 512 chars (or the entire output, whichever is shorter) to keep `parity-results.json` small. `pass` is `true` iff `exit_code == 0`.

If any script fails, surface a one-line warning in the feedback summary at Step 2 ("N of M parity tests failed — review parity-results.json before declaring cutover successful") but do NOT block feedback completion. Migration verification is the user's call to make, not the skill's.

## Step 0: Detect IDE Type and Plugin Version

Detect the IDE type and plugin version for the survey URL. These are passed as hidden fields -- the user never sees or enters them.

### IDE Detection

Determine which IDE is running:

- **Claude Code**: Check if the environment indicates Claude Code (e.g., the `CLAUDE_CODE` environment variable is set, or the skill was invoked via `/skill` or Claude Code CLI). Set `ide` to `claude-code`.
- **Gemini CLI**: Check if the environment indicates Gemini CLI (e.g., the `GEMINI_CLI` environment variable is set, or the editor context is Gemini CLI). Set `ide` to `gemini-cli`.
- **Cursor**: Check if the environment indicates Cursor (e.g., the `CURSOR_TRACE_ID` environment variable is set, or the editor context is Cursor). Set `ide` to `cursor`.
- **Fallback**: If detection fails, set `ide` to `unknown`.

### Plugin Version Detection

Read the plugin version from the plugin manifest:

- **Claude Code**: Read `.claude-plugin/plugin.json` -> `version` field (relative to the plugin install root).
- **Gemini CLI**: Read `.gemini-plugin/plugin.json` -> `version` field (relative to the plugin install root).
- **Cursor**: Read `.cursor-plugin/plugin.json` -> `version` field (relative to the plugin install root).
- **Fallback**: If the manifest cannot be read, set `version` to `0.0.0`.

### Sanitization

Values must use only Pulse-safe characters: letters, numbers, dots (`.`), tildes (`~`), hyphens (`-`), and underscores (`_`). Strip or replace any other characters.

Store the detected values as `$IDE_TYPE` and `$PLUGIN_VERSION` for use in Step 2.

## Step 1: Build Trace

Load `references/phases/feedback/feedback-trace.md` and execute it. This produces `$MIGRATION_DIR/trace.json`.

If trace building fails: log the error, set `trace_included` to `false`, and skip to Step 3.

## Step 2: Show Trace and Provide Instructions

Read `$MIGRATION_DIR/trace.json` and display it pretty-printed so the user can see exactly what data is included:

```
--- Anonymized Trace (what will be shared) ---

<pretty-printed trace.json>

--- End Trace ---

This trace contains only aggregate counts, enum values, and timing data.
No resource names, file paths, account IDs, or secrets are included.
```

Then output the single-line minified version for copy-paste:

```
--- Copy the line below and paste it into the "Migration trace (optional)" field ---

<trace.json as single-line minified JSON -- no newlines, no extra whitespace>

--- End ---
```

Then provide the survey link with IDE and version as hidden field query parameters:

```
Open the feedback form in your browser:
https://pulse.amazon/survey/MY0ZY7UA?ide=$IDE_TYPE&version=$PLUGIN_VERSION

Answer the 5 quick questions in the form, then paste the trace line above
into the "Migration trace (optional)" field and submit.
```

Replace `$IDE_TYPE` and `$PLUGIN_VERSION` with the actual values detected in Step 0. Example: `https://pulse.amazon/survey/MY0ZY7UA?ide=claude-code&version=1.0.0`

## Step 3: Write feedback.json

Write `$MIGRATION_DIR/feedback.json`:

```json
{
  "timestamp": "<ISO 8601>",
  "survey_url": "https://pulse.amazon/survey/MY0ZY7UA?ide=$IDE_TYPE&version=$PLUGIN_VERSION",
  "phases_completed_at_feedback": ["<list of completed phases>"],
  "trace_included": true
}
```

If trace building failed: set `"trace_included": false`.

## Step 4: Update Phase Status

Use the Phase Status Update Protocol (Write tool) to write `.phase-status.json` with `phases.feedback` set to `"completed"` -- **in the same turn** as the output message below.

Output to user: "Thank you for helping improve this tool."

After feedback completes, return control to the workflow execution in SKILL.md. The calling checkpoint determines whether to advance to the next phase or end the migration.
