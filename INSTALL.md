# Installing the `migration-to-gcp` plugin

A Claude Code plugin that bundles the AWS-to-GCP migration skill, two official knowledge MCP servers (AWS Knowledge, Google Developer Knowledge), and the live `gcp-pricing` CLI.

> 日本語版: [`INSTALL.ja.md`](INSTALL.ja.md)

## Prerequisites

| Requirement     | Version / setup                                                               |
| --------------- | ----------------------------------------------------------------------------- |
| **Claude Code** | ≥ 2.1.119 (`claude --version`)                                                |
| **Node.js**     | ≥ 18 (runs the bundled pricing CLI and MCP proxy)                             |
| **gcloud CLI**  | Installed and on PATH ([install guide](https://cloud.google.com/sdk/install)) |
| **AWS CLI**     | Configured with read access to the source AWS account (for discovery)         |

## 1. Install the plugin

### Option A — from the marketplace (recommended)

Inside a Claude Code session:

```text
/plugin marketplace add cloud-gtm/migration-skills
/plugin install migration-to-gcp@migration-skills
```

Or from the terminal:

```bash
claude plugin marketplace add cloud-gtm/migration-skills
claude plugin install migration-to-gcp@migration-skills          # user scope (all your projects)
claude plugin install migration-to-gcp@migration-skills --scope project   # shared via .claude/settings.json
```

The plugin is versioned by commit SHA — `/plugin update migration-to-gcp` picks up every new commit.

### Option B — local checkout (development, session-only)

```bash
git clone git@github.com:cloud-gtm/migration-skills.git
claude --plugin-dir migration-skills/features/migration-to-gcp
```

## 2. Set up Google authentication (ADC first)

The Developer Knowledge MCP server and the `gcp-pricing` CLI authenticate with this priority: **gcloud ADC → gcloud user credentials → API key failover**.

```bash
gcloud auth application-default login
gcloud config set project PROJECT_ID
gcloud services enable cloudbilling.googleapis.com developerknowledge.googleapis.com
```

**Optional API-key failover** (for machines without gcloud ADC):

```bash
gcloud services api-keys create --display-name="migration-to-gcp" \
  --api-target=service=developerknowledge.googleapis.com \
  --api-target=service=cloudbilling.googleapis.com
```

Store the key in the plugin config — run `/plugin configure migration-to-gcp@migration-skills` in Claude Code (field `google_dev_knowledge_api_key`, kept in secure storage), or pass `--config google_dev_knowledge_api_key=KEY` at install time. For the pricing CLI alone you can instead export `GCP_PRICING_API_KEY`.

## 3. Verify the installation

```bash
claude plugin details migration-to-gcp   # expect: Skills (1) aws-to-gcp, MCP servers (2)
claude mcp list                          # expect both plugin servers "✔ Connected"
```

Then, inside a Claude Code session in your project:

```text
> migrate from AWS to GCP
```

The `aws-to-gcp` skill activates and starts the 5-phase workflow (Discover → Clarify → Design → Estimate → Generate). To spot-check the pricing tool, ask Claude to run `gcp-pricing services --filter "Cloud Run"` — output is JSON with `auth_mode` and `retrieved_at` provenance.

## 4. Update / uninstall

```bash
claude plugin update migration-to-gcp
claude plugin uninstall migration-to-gcp
claude plugin marketplace remove migration-skills
```

## Troubleshooting

- **`google-developer-knowledge` shows "failed to connect"** — the proxy's stderr (visible via `claude --debug` or `/mcp`) prints exact setup steps. Usual causes: no ADC (`gcloud auth application-default login`), the Developer Knowledge API not enabled on the quota project, or no failover API key set.
- **`gcp-pricing` exits with HTTP 403 `SERVICE_DISABLED`** — the error body includes the exact `gcloud services enable ...` activation URL for your project; enable the Cloud Billing API and retry.
- **`gcp-pricing: command not found` in Claude's Bash** — plugin `bin/` executables require Claude Code ≥ 2.1.91; upgrade and restart the session.
- **Ambiguous service name** — `gcp-pricing skus --service "Cloud SQL"` style lookups list candidate serviceIds when more than one matches; re-run with the exact ID.
