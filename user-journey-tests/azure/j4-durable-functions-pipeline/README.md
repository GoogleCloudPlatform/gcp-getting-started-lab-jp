# azure/j4-durable-functions-pipeline: claims-intake operator (fictional) migration test bed

Realistic test material for the `azure-to-gcp` skill in this repository. The claims-intake operator is a fictional
forty-one-person claims-handling agency in central Tokyo, whose claims intake runs as a serverless
event-driven pipeline built in 2023 — Event Grid to a storage queue, Azure Functions, Service Bus, Table
Storage — described in [`architecture.md`](./architecture.md).

Difficulty tier: **medium**. The estate is small and every resource is serverless or Standard tier, but
nothing about it is a lift-and-shift. There are no VMs and no disks, so none of the compute-migration
machinery applies. What there is instead is a Bicep template split across four modules, an event path
that crosses three services before it reaches code, and a Node function app carrying its own state
machine.

## What's in here

| Path              | Purpose                                                                                                                     | Used by                                         |
| ----------------- | --------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------- |
| `infra/`          | Authoritative, deployable IaC — `main.bicep` plus four modules and a parameters file                                        | Azure deploy AND the skill's Discover phase     |
| `app/`            | The claims pipeline: Node 22 on the Functions v4 programming model, with every Azure SDK call funnelled through one module  | Azure deploy AND the skill's Discover phase     |
| `scripts/`        | `deploy.sh`, `seed.sh`, `smoke-test.sh`, `teardown.sh` — all four source `~/.azure/journeys.env` and guard the subscription | Operator                                        |
| `.migration/`     | Created by the skill at runtime — do not commit, do not gitignore                                                           | Phase outputs: inventory, design, generated IaC |
| `.iteration-log/` | One subdirectory per run                                                                                                    | Observation logs and transcripts                |

**There is no `discovery/` and no `costs/`.** The claims-intake operator has no VMs, so nobody has run an assessment
against this estate, and the agency reads its Azure spend off the invoice PDF the reseller emails rather
than exporting it. Everything the migration needs is in the Bicep, the app code and `architecture.md`.

**There is no `BASE_URL`.** This pipeline has no HTTP edge — work reaches it when a claim document lands
in the `intake` blob container, and leaves it as a row in the `claimstate` table. `scripts/smoke-test.sh`
therefore takes a provider argument rather than a URL.

Evaluation criteria and scoring live in the repo-root `CATALOG.md`.

## Deployment

```bash
# Pre-flight: ~/.azure/journeys.env must define EXPECTED_SUBSCRIPTION_ID and
# AUTOTEARDOWN_DATE. Every script sources it and aborts on subscription mismatch.
az account show --query id -o tsv    # confirm the right subscription before any create

./scripts/deploy.sh                 # az group create dfp-rg, one az deployment group create,
                                    # then npm install + zip push of the function app
./scripts/seed.sh                   # optional: a working day's claims through the pipeline
```

`az`, `npm` and `python3` all have to be on `PATH`. A Windows plan does not build on the server, so
`deploy.sh` installs the app's runtime dependencies locally and ships them inside the package; `python3`
builds the archive so `zip` is not a dependency.

First deploy takes roughly 4-6 minutes, most of it the Service Bus namespace. The script is idempotent —
`az group create` and Incremental-mode deployments are both create-or-update, and a zip deploy replaces
the whole package — so re-running converges.

Everything lands in the single resource group `dfp-rg`, so nothing survives teardown.

Four names are resolved at deploy time rather than hard-coded, because all four are globally unique
across Azure: the two storage accounts (`dfpclaims<uniqueString>` and `dfpfn<uniqueString>`), the Service
Bus namespace (`dfp-sb-<uniqueString>`, a `servicebus.windows.net` DNS label) and the function app
(`dfp-fn-<uniqueString>`, an `azurewebsites.net` DNS label).

This estate holds no passwords, so there are no securestring parameters. The connection strings on the
function app are built inside the template from `listKeys()` at deployment time; none is written to this
repository, passed on a command line or printed.

## Verification

```bash
./scripts/smoke-test.sh azure       # or: ./scripts/smoke-test.sh gcp
```

Five checks against Azure: the claims storage account exists and its TLS floor is `TLS1_2`, a claim
document can be written to the `intake` container, a matching claim state row reaches `with-adjuster`
within the polling window, and the review queue's dead-letter store is empty.

The three pipeline assertions are provider-agnostic in intent — a document reaches intake storage, a
claim state row appears for it, the dead-letter store is empty — and the `gcp` branch runs the same
three with `gcloud`, reading the target's shape from the environment so the script does not have to know
how the migration named things or which services it picked: `GCP_PROJECT`, `GCP_INTAKE_BUCKET`,
`GCP_REVIEW_DLQ_SUBSCRIPTION`, and — because claim state lives in Table Storage here, and what carries it
afterwards is the migration's own decision — `GCP_CLAIM_STATE_BACKEND` together with the naming variables
that backend needs. Passing it against a migrated GCP deployment is the acceptance test for the
migration. The Azure branch skips itself, rather than failing, when `dfp-rg` is not present in the
current subscription.

## Running the migration skill (Claude Code)

```bash
# Interactive run against this test bed
cd user-journey-tests/azure/j4-durable-functions-pipeline
claude --plugin-dir ../../../features/migration-to-gcp
# In the session: type "migrate from Azure to GCP"

# Headless run (time-boxed)
claude --plugin-dir ../../../features/migration-to-gcp -p "migrate from Azure to GCP" \
  --permission-mode acceptEdits
```

The skill's outputs land in `.migration/<MMDD-HHMM>/`.

## Resource tagging

Every taggable resource carries `Owner=migration-test`, `CostCenter=test-journeys`,
`AutoTeardown=<from env>`, `Journey=azure/j4-durable-functions-pipeline`. Find them later:

```bash
az resource list --tag Journey=azure/j4-durable-functions-pipeline -o table
```

## Teardown

```bash
./scripts/teardown.sh   # type "yes" at the prompt, or FORCE_TEARDOWN=1
```

Lists what is about to go, removes the Event Grid system topic first — ARM does not guarantee it is
deleted before the storage account it is sourced from — then runs a single `az group delete --yes` and
verifies the group is gone. Blob soft delete does not hold anything open: it defers the blobs' own
removal and goes with the account.
