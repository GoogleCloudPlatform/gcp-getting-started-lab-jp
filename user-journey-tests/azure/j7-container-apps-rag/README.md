# azure/j7-container-apps-rag: robo-advisory RAG migration test bed

The robo-advisory operator (fictional) is a startup whose product is a retrieval-augmented
"portfolio explainer": a chat service that answers "why do I own this?" from a small corpus of fund
documentation. The estate is a container app on Azure Container Apps talking to Azure OpenAI and Azure
AI Search — both of which have public network access switched off and are reachable only over private
endpoints — plus blob storage for the corpus, a serverless Cosmos DB account for conversation history,
and Application Insights. [`architecture.md`](architecture.md) is the customer-fidelity description.

**Difficulty tier:** hard. The estate is small but its failure surface is not: the container apps
environment only reaches the model and the search service because it is integrated into a virtual
network whose private DNS zones resolve their public hostnames to private addresses, and every one of
those pieces has to be right before anything answers.

## What's in here

| Path                                  | Purpose                                                                       | Used by                                   |
| ------------------------------------- | ----------------------------------------------------------------------------- | ----------------------------------------- |
| `architecture.md`                     | Customer-fidelity description: backstory, diagram, service tables, operations | A human reading in; the agent under test  |
| `bicep/registry.bicep`                | Container registry. Deployed **first**, on its own                            | `scripts/deploy.sh` step 1                |
| `bicep/main.bicep` + `bicep/modules/` | Everything else. The authoritative, deployable definition of the estate       | `scripts/deploy.sh` step 3                |
| `bicep/main.parameters.json`          | Tier, model and mode defaults, with the rationale inline as JSONC comments    | `scripts/deploy.sh`                       |
| `app/advisor/`                        | The runnable FastAPI service, its Dockerfile and its pinned dependencies      | `az acr build` in `scripts/deploy.sh`     |
| `app/advisor/azure_clients.py`        | The single funnel every Azure SDK call goes through                           | Anything grepping for SDK call sites      |
| `app/seed-data/docs/`                 | Six markdown fund notes — the retrieval corpus                                | `scripts/seed.sh`                         |
| `costs/car-usage-focus.csv`           | Synthetic FOCUS 1.0r2 cost export for June 2026                               | Cost estimation                           |
| `costs/make-usage-export.py`          | Deterministic generator for that export                                       | Regenerating it                           |
| `costs/README.md`                     | What the export imitates and how it is regenerated                            | A human reading in                        |
| `scripts/`                            | `deploy.sh`, `seed.sh`, `smoke-test.sh`, `teardown.sh`                        | Standing the estate up and taking it down |

There is no `discovery/` directory. The robo-advisory operator (fictional) has never run an assessment tool against this estate — it is
one resource group, deployed from a template that one person owns and can hold in their head, and nobody
has ever needed an inventory export to understand it.

## Deployment

Prerequisites: the Azure CLI signed in to the lab subscription, and `~/.azure/journeys.env` carrying
`EXPECTED_SUBSCRIPTION_ID`, `AUTOTEARDOWN_DATE` and `AZURE_LOCATION`. No region is hard-coded in `bicep/`,
`app/` or `scripts/`; `AZURE_LOCATION` is required and there is no fallback. The one exception is `costs/`,
where a cost export cannot leave the region column empty — `costs/README.md` names the constants that
carry it.

```bash
./scripts/deploy.sh          # ~15-20 minutes on a cold subscription
./scripts/seed.sh            # upload the corpus and build the index
./scripts/smoke-test.sh <BASE_URL>
```

`deploy.sh` runs three steps in a fixed order, and the order is not cosmetic:

1. `bicep/registry.bicep` creates the container registry.
2. `az acr build` builds and pushes the explainer image into it.
3. `bicep/main.bicep` deploys everything else, including the container app that pulls that image.

Step 3 cannot precede step 2. A container app whose image cannot be pulled provisions as `Failed` and
fails the whole deployment, which is why the registry is a separate template rather than another module.

**The app ships in `stub` mode.** Retrieval, citations, persistence and history are all live; only the
final paragraph of each explanation is composed locally instead of by the model. This is what lets the
estate stand up and pass its acceptance test on a subscription whose Azure OpenAI quota is unknown. To
run the model for real, confirm there is quota and redeploy:

```bash
az cognitiveservices usage list --location "$AZURE_LOCATION" -o table
CAR_LLM_MODE=live ./scripts/deploy.sh
```

Per-run overrides, for a subscription that argues with the defaults — all of them read by `deploy.sh`
and settable in `~/.azure/journeys.env`:

| Variable                                             | Effect                                                                                                                                                 |
| ---------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `CAR_OPENAI_LOCATION`                                | Region for the model account alone. Set it when `AZURE_LOCATION` does not offer the model at the chosen deployment type. Defaults to `AZURE_LOCATION`. |
| `CAR_OPENAI_MODEL_NAME` / `CAR_OPENAI_MODEL_VERSION` | The model to deploy. See the note below.                                                                                                               |
| `CAR_OPENAI_DEPLOYMENT_SKU`                          | `GlobalStandard` (default), `Standard` or `DataZoneStandard`.                                                                                          |
| `CAR_OPENAI_DEPLOYMENT_CAPACITY`                     | Thousands of tokens per minute. Defaults to 1, the floor.                                                                                              |
| `CAR_SEARCH_SKU`                                     | `basic` (default), `standard`, `standard2`. The Free tier is not an option: it is one per subscription and cannot take a private endpoint.             |
| `CAR_LLM_MODE`                                       | `stub` (default) or `live`.                                                                                                                            |
| `CAR_DEPLOY_ROLE_ASSIGNMENTS`                        | `false` where the container app identity's **Azure** role assignments are applied by the subscription administrator instead.                           |
| `CAR_DEPLOY_COSMOS_DATA_PLANE_ROLE`                  | `false` where the **Cosmos DB** data-plane assignment is managed outside the template. A separate switch, because Contributor can make this one.       |
| `CAR_IMAGE_TAG`                                      | Image tag to build and deploy. Defaults to `v1`.                                                                                                       |

**Two subscription-shaped things that will bite before anything else:**

- _The model._ The template defaults to `gpt-4o-mini` version `2024-07-18`, which is what the service was
  written against. Azure lists that model as deprecated rather than retired: a subscription that has
  already deployed it can keep doing so, but one that never has cannot start. On a fresh subscription,
  set `CAR_OPENAI_MODEL_NAME=gpt-5-mini` and `CAR_OPENAI_MODEL_VERSION=2025-08-07`. Nothing else changes
  — the SDK call shape and the prompt are identical.
- _Role assignments._ Writing an Azure role assignment needs more than Contributor on the scope. The four
  the container app's identity needs — one on the model account, two on the search service and one on the
  documentation storage — sit behind the `deployRoleAssignments` parameter, on by default. With it off
  the estate still deploys, but `/admin/azure-check` reports those services as unavailable, `seed.sh`
  cannot build the index, and every explanation comes back uncited. The **Cosmos DB** grant is a
  different mechanism (a `Microsoft.DocumentDB` write, which Contributor can make) and so has its own
  switch, `deployCosmosDataPlaneRole`: turning the first one off does not cost you conversation history.
  Separately, `seed.sh` needs Storage Blob Data Contributor for the **operator** running it, tries to
  self-grant it on a best-effort basis, and retries the upload for four minutes before failing with the
  role name — on a Contributor-only principal that grant must come from a subscription administrator
  first, or seeding cannot work at all.

## Verification

```bash
./scripts/smoke-test.sh https://car-advisor.<env-suffix>.<region>.azurecontainerapps.io
```

The same script is the acceptance test for a migrated GCP deployment of this workload. Its HTTP checks
are provider-agnostic; the Azure control-plane checks are skipped, not failed, when `car-rg` is not in
the current subscription. It covers `/health` and its three dependency substatuses, all six services on
`/admin/azure-check`, a `POST /explain` that must come back with citations naming the bond ladder fund, a
`/history` round trip on the session it just wrote, 400 on an empty question, 404 on an unknown session,
and — on the Azure side — scale-to-zero, single-revision mode, the environment's network integration,
public network access disabled on the model account, the search tier, both private endpoints, all four
private DNS zones, and the storage TLS floor.

The explainer scales to zero, so when the script starts there is usually no replica at all and the first
request pays an image pull and a Python start-up. The script polls `/health/live` until the app answers
before it judges anything, and says how many attempts that took. `CAR_WARMUP_ATTEMPTS` and
`CAR_WARMUP_INTERVAL` (12 and 10 seconds by default) set how long it is willing to wait. If that poll
runs out, every check after it is meaningless and the script says so, with the two `az` commands that
show whether the revision ever started.

Where `CAR_DEPLOY_ROLE_ASSIGNMENTS` is anything but `true`, nine of the checks cannot pass — the two
`/health` dependencies that read the search service and the documentation storage, the `status: ok` that
depends on them, `all_ok` and its three matching services on `/admin/azure-check`, and the citation and
fund-name assertions on `POST /explain`, because the index was never built. Those report `XFAIL` and do
not fail the run; everything else still has to pass. The explainer itself is expected to answer:
`/health` returns 200 with `status: degraded`, an explanation comes back uncited, and it is still written
to the conversation store, whose grant is a separate switch.

## Running the migration skill (Claude Code)

From this directory:

```
/migration-to-gcp:azure-to-gcp
```

The agent runs with this directory as its working directory and reads the Bicep, the application code
and the cost export the same way it would read a customer's own repository.

```bash
# Interactive run against this test bed
cd user-journey-tests/azure/j7-container-apps-rag
claude --plugin-dir ../../../features/migration-to-gcp
# In the session: type "migrate from Azure to GCP"

# Headless run (time-boxed)
claude --plugin-dir ../../../features/migration-to-gcp -p "migrate from Azure to GCP" \
  --permission-mode acceptEdits
```

The skill's outputs land in `.migration/<MMDD-HHMM>/`.

## Resource tagging

Every taggable resource carries `Owner=migration-test`, `CostCenter=test-journeys`,
`AutoTeardown=<AUTOTEARDOWN_DATE>` and `Journey=azure/j7-container-apps-rag`. The container apps environment
replicates its tags onto the managed resource group the platform creates alongside it, so those
resources are tagged too.

```bash
az resource list --tag Journey=azure/j7-container-apps-rag -o table
```

## Teardown

```bash
./scripts/teardown.sh                 # prompts for confirmation
FORCE_TEARDOWN=1 ./scripts/teardown.sh
```

Everything is in one resource group, so teardown is essentially one `az group delete`. Three things need
more than that and the script handles all three:

- **The private endpoints and the environment come out first.** Resource Manager works out its own
  delete order and retries for fifteen minutes, and Microsoft states that deleting the group also removes
  the managed resource group the Container Apps platform created alongside the environment. Two things
  make it worth not relying on: there is a whole class of resource whose private endpoint blocks the
  delete of its target — a Recovery Services vault is the documented case — and the environment holds a
  service association link on the delegated `apps` subnet that has to come off before the subnet and the
  network can go. Both pre-deletes are non-fatal: if either fails, the group delete runs regardless.
- **The Log Analytics workspace outlives the resource group.** Deleting the group soft-deletes `car-logs`
  for 14 days and reserves the name, and the name carries no uniqueness suffix — so a re-deploy either
  silently recovers the old workspace with its old data still in it, or fails outright if the region
  moved. `teardown.sh` deletes it permanently with `--force` before the group goes.
- **The model account outlives the resource group.** Azure soft-deletes a Cognitive Services account and
  holds its name, and its custom subdomain, for 48 hours. The account name is derived from the resource
  group id, so a re-deploy into the same group computes the same name and fails against the soft-deleted
  record. `teardown.sh` purges it. That purge needs
  `Microsoft.CognitiveServices/locations/resourceGroups/deletedAccounts/delete`, which Contributor
  carries only at subscription scope; the script says so plainly when it cannot.

The search service, the registry and the Cosmos DB account have no soft delete and no purge — their
names are free the moment they are gone.

```bash
az resource list --tag Journey=azure/j7-container-apps-rag -o table
az cognitiveservices account list-deleted -o table
az monitor log-analytics workspace list-deleted-workspaces -o table
```
