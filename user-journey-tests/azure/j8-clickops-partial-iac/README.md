# azure/j8-clickops-partial-iac: university estate migration test bed

Realistic test material for the `azure-to-gcp` skill in this repository. The university estate (fictional) is a
private university's Azure footprint that grew out of a server-room evacuation in 2018 and has
been extended by hand ever since; its student portal is the one part of it anybody ever templated,
described in [`architecture.md`](./architecture.md).

Difficulty tier: **hard** — not because the portal is complicated. It is the simplest application in
the set: one Flask site, one small database, one blob container, no identity, no network. The
difficulty is that `bicep/` is **not a description of the subscription**. It is a description of the
student portal. `architecture.md` says so plainly, and says what else is out there; nothing in the
template will confirm any of it. A migration sized from the template alone is a migration of the
portal, and the portal is not what the university is paying for.

## What's in here

| Path              | Purpose                                                                                                                                                                                                          | Used by                                           |
| ----------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------- |
| `bicep/`          | Authoritative, deployable IaC for the student portal — `main.bicep` plus three modules under `modules/`, and a parameters file                                                                                   | Azure deploy AND the skill's Discover phase       |
| `app/`            | The Flask portal, its notice seed data and the two documents the registrar publishes                                                                                                                             | App Service deploy AND the skill's Discover phase |
| `costs/`          | Synthetic FOCUS 1.2-preview cost export, actual and amortized cost details, reservation details, and the generator behind them                                                                                   | The skill's Discover and Estimate phases          |
| `discovery/`      | Synthetic `az resource list` output for the resource groups the IT office keeps                                                                                                                                  | The skill's Discover phase                        |
| `scripts/`        | `deploy.sh`, `seed.sh`, `smoke-test.sh`, `teardown.sh` — all four source `~/.azure/journeys.env` and guard the subscription; `app-self-test.sh` and `package-app.py` need neither a subscription nor credentials | Operator                                          |
| `.migration/`     | Created by the skill at runtime — do not commit, do not gitignore                                                                                                                                                | Phase outputs: inventory, design, generated IaC   |
| `.iteration-log/` | One subdirectory per run                                                                                                                                                                                         | Observation logs and transcripts                  |

Evaluation criteria and scoring live in the repo-root `CATALOG.md`.

**What `bicep/` does not cover.** Everything the template creates lands in `cpi-rg`, and everything in
`cpi-rg` is created by the template — the two match exactly, which is what makes teardown a single
`az group delete`. What does not match is the template against the estate. The administrative machines,
the staff file shares and the data office's analytics project described in `architecture.md` were
clicked together in the portal over eight years, were never templated, and are not created, changed or
removed by anything in here. That is the estate as it really is, not an omission in this test bed. What
the university can show for the rest of it is what any such office can show: a bill and a resource
listing, which is what `costs/` and `discovery/` hold. Neither directory is deployed by `deploy.sh` —
only `cpi-rg` is ever created — and each carries its own README stating where its data came from.

**Deployment style: plain zip deploy, not a container.** `deploy.sh` packages `app/` and pushes it with
`az webapp deploy --type zip`; App Service builds the Python environment from `requirements.txt` with
Oryx, which the `SCM_DO_BUILD_DURING_DEPLOYMENT` application setting turns on. There is no Dockerfile —
the university has never containerised anything, and a container would misrepresent the estate.

**No role assignments.** The site has no managed identity and reaches both dependencies with
credentials carried in its own configuration, so nothing in `bicep/` writes a role assignment and the
template itself needs no more than Contributor on the resource group. `deploy.sh` reaches above that
only to create the group and to register resource providers, both of which are subscription-scope
operations.

## Deployment

```bash
# Pre-flight: ~/.azure/journeys.env must define EXPECTED_SUBSCRIPTION_ID,
# AUTOTEARDOWN_DATE and AZURE_LOCATION. Every script sources it and aborts on
# subscription mismatch. seed.sh additionally needs SEED_CLIENT_IP — this
# machine's public IPv4 — for the temporary database firewall rule.
az account show --query id -o tsv    # confirm the right subscription before any create

./scripts/app-self-test.sh           # no subscription, no credentials; ~2 minutes
./scripts/deploy.sh                  # ~5-8 minutes; the SQL logical server dominates
./scripts/seed.sh                    # five notices, two published documents
./scripts/smoke-test.sh "$BASE_URL"  # BASE_URL is echoed by deploy.sh
```

`app-self-test.sh` runs first because it is cheap and it fails in the two minutes a laptop takes rather
than the ten a platform start timeout takes. It packages the portal with the same packager `deploy.sh`
pushes, unpacks that archive, and starts it with the command line read out of `bicep/modules/webapp.bicep`
— so a renamed entry point, a `requirements.txt` that has moved out of the archive root, or a pin that
no longer resolves all fail here instead of arriving as a worker that never started.

**Expect failed container starts in the log, and do not read them as a failed deployment.** The site
is created with a startup command before it has any code, so until the zip lands every container start
finds no built environment, cannot import the portal, and exits 3. A first deployment leaves two or
three of those. `deploy.sh` therefore decides whether the portal is up by asking the site for `/health`
for up to five minutes, rather than by trusting the CLI's own startup tracking, which polls for ten
minutes and can report a deployment as failed on the strength of a container that was never carrying
this code. If the CLI does report a failure, the wait still runs; a site that answers is reported as
serving, with the deployment record written out so the build summary can be checked. `CPI_SITE_READY_TIMEOUT`
moves the five minutes if a region is slower than that.

`deploy.sh` generates the SQL administrator password, passes it to ARM as a `securestring` through a
0600 temp file, and never prints or stores it. A re-deploy rotates it. The only place it survives is
the site's `PortalDb` connection string, which is where `seed.sh` reads it from.

Both SKUs are parameters, and both can be moved per run without editing a template when a
subscription's catalogue does not carry the default:

| Variable                | Overrides             | Default | Note                                                           |
| ----------------------- | --------------------- | ------- | -------------------------------------------------------------- |
| `CPI_APP_PLAN_SKU_NAME` | App Service plan SKU  | `B1`    | Free and Shared cannot keep the site warm; S1 is the next step |
| `CPI_APP_PLAN_SKU_TIER` | matching tier         | `Basic` | Moves with the SKU name                                        |
| `CPI_SQL_DB_SKU_NAME`   | SQL service objective | `Basic` | S0 is the next objective up                                    |
| `CPI_SQL_DB_SKU_TIER`   | matching tier         | `Basic` | Moves with the objective                                       |
| `CPI_PYTHON_VERSION`    | site runtime          | `3.12`  |                                                                |

`seed.sh` reads `SEED_CLIENT_IP` — a property of the machine you are running from, shared with the
other test beds — and `CPI_SEED_CLIENT_IP` overrides it for this one.

## Verification

```bash
./scripts/smoke-test.sh "$BASE_URL"
```

Eighteen checks — thirteen provider-agnostic, five against the Azure control plane. The
provider-agnostic ones: `/health` returns 200 with `status: ok` and both dependencies healthy,
`/admin/azure-check` reports `all_ok` across both services, the notice board renders and lists the
seeded notices, a notice page renders, the document library lists what the registrar published, and a
document comes back from object storage. The Azure control-plane ones: the web app is Running, the
App Service plan matches `CPI_EXPECTED_APP_PLAN_SKU` (`B1` unless overridden), the `cpiportal` database
matches `CPI_EXPECTED_SQL_SKU` (`Basic` unless overridden), and the storage account has a `TLS1_2` floor
and a `documents` container.

The HTTP checks are provider-agnostic — the same invocation against a migrated GCP frontend is the
acceptance test for the migration. The Azure control-plane checks skip themselves, rather than failing,
when `cpi-rg` is not present in the current subscription.

## Running the migration skill (Claude Code)

```bash
# Interactive run against this test bed
cd user-journey-tests/azure/j8-clickops-partial-iac
claude --plugin-dir ../../../features/migration-to-gcp
# In the session: type "migrate from Azure to GCP"

# Headless run (time-boxed)
claude --plugin-dir ../../../features/migration-to-gcp -p "migrate from Azure to GCP" \
  --permission-mode acceptEdits
```

The skill's outputs land in `.migration/<MMDD-HHMM>/`.

## Resource tagging

Every taggable resource carries `Owner=migration-test`, `CostCenter=test-journeys`,
`AutoTeardown=<from env>`, `Journey=azure/j8-clickops-partial-iac`. Find them later:

```bash
az resource list --tag Journey=azure/j8-clickops-partial-iac -o table
```

## Teardown

```bash
./scripts/teardown.sh   # type "yes" at the prompt, or FORCE_TEARDOWN=1
```

Lists what is about to go, runs a single `az group delete --yes`, and verifies the group is gone.
There is no purge step: neither the SQL logical server nor the storage account has a soft-delete state
that outlives the resource group, so a rebuild computing the same names is not blocked by anything this
script leaves behind.
