# azure/j2-paas-web-app: PaaS web app migration test bed

Realistic test material for the `azure-to-gcp` skill in this repository. The estate belongs to a fictional
stationery shop whose Django storefront runs on Azure App Service, described in
[`architecture.md`](./architecture.md).

Difficulty tier: **medium** — a small but fully modern PaaS estate rather than an IaaS lift. There are no
virtual machines and nothing to image-migrate. Instead the migration has to reason about a Bicep tree
split across modules, an App Service deployment slot with its own configuration, a Key Vault reference
resolved into an application setting, a system-assigned managed identity with data-plane role
assignments, and a Front Door rules engine — none of which map one-to-one onto anything on the other
side.

## What's in here

| Path                       | Purpose                                                                                                                     | Used by                                           |
| -------------------------- | --------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------- |
| `bicep/`                   | Authoritative, deployable IaC — `main.bicep` plus seven modules under `modules/`, and a parameters file                     | Azure deploy AND the skill's Discover phase       |
| `app/`                     | The Django 5.2 storefront, its catalogue seed data and its product images                                                   | App Service deploy AND the skill's Discover phase |
| `costs/`                   | Synthetic FOCUS 1.0r2 cost export plus its deterministic generator — see its own `README.md`                                | The skill's Discover and Estimate phases          |
| `scripts/`                 | `deploy.sh`, `seed.sh`, `smoke-test.sh`, `teardown.sh` — all four source `~/.azure/journeys.env` and guard the subscription | Operator                                          |
| `scripts/app-self-test.sh` | Runs the storefront on this machine with its dependencies taken away, one at a time. No Azure, no credentials               | Operator, before spending a deploy                |
| `.migration/`              | Created by the skill at runtime — do not commit, do not gitignore                                                           | Phase outputs: inventory, design, generated IaC   |
| `.iteration-log/`          | One subdirectory per run                                                                                                    | Observation logs and transcripts                  |

Evaluation criteria and scoring live in the repo-root `CATALOG.md`.

**Deployment style: plain zip deploy, not a container.** `deploy.sh` packages `app/` and pushes it with
`az webapp deploy --type zip`; App Service builds the Python environment from `requirements.txt` with
Oryx, which the `SCM_DO_BUILD_DURING_DEPLOYMENT` application setting turns on. There is no Dockerfile —
the shop has never containerised anything, and a container would misrepresent the estate.

## Deployment

```bash
# Pre-flight: ~/.azure/journeys.env must define EXPECTED_SUBSCRIPTION_ID,
# AUTOTEARDOWN_DATE and AZURE_LOCATION. Every script sources it and aborts on
# subscription mismatch. seed.sh additionally needs SEED_CLIENT_IP — this
# machine's public IPv4 — for the temporary database firewall rule.
az account show --query id -o tsv    # confirm the right subscription before any create

./scripts/deploy.sh                 # az group create pwa-rg + one az deployment group create,
                                    # then a zip deploy of app/
                                    # prints BASE_URL, ORIGIN_URL, STAGING_URL and the resource names

./scripts/seed.sh                   # migrations + catalogue + product images
```

First deploy takes roughly 10-15 minutes; the PostgreSQL flexible server and the Front Door endpoint
dominate, and the Oryx build adds a few minutes on top. The script is idempotent — `az group create` and
Incremental-mode deployments are both create-or-update — with one caveat: **the PostgreSQL administrator
password and the Django `SECRET_KEY` are regenerated on every run**, so a re-deploy rotates both. Neither
is ever written to this repository or printed to the terminal.

Everything lands in the single resource group `pwa-rg`.

**No region is written down anywhere in this journey except the cost export.** `AZURE_LOCATION` places
the resource group, every resource takes its region from the resource group, and `teardown.sh` reads the
region back off the vault it is about to purge. The one exception is `costs/` — a cost export has to name
a region in its own column, and `costs/README.md` says which and how to move it.

Both compute SKUs are template parameters with defaults (`S1` for the App Service plan, `Standard_B1ms`
for the flexible server), because a subscription's catalogue is not the same everywhere. Override either
without editing a file:

```bash
PWA_POSTGRES_SKU_NAME=Standard_D2s_v5 PWA_POSTGRES_SKU_TIER=GeneralPurpose ./scripts/deploy.sh
PWA_EXPECTED_PG_SKU=Standard_D2s_v5 ./scripts/smoke-test.sh "$BASE_URL"   # keeps the check honest
```

`az postgres flexible-server list-skus --location "$AZURE_LOCATION" -o table` is what to check
before picking one — the catalogue differs by region and by subscription.

`PWA_APP_PLAN_SKU_NAME` and `PWA_APP_PLAN_SKU_TIER` do the same for the App Service plan, which has one
hard constraint: the staging slot needs Standard or better, so a burstable plan will not deploy.

The web app identity's two role assignments are written by `bicep/modules/rbac.bicep`, which
`main.bicep` includes behind a `deployRoleAssignments` parameter. Writing a role assignment needs more on
the scope than Contributor carries; in environments where identity grants are applied by the subscription
administrator instead, deploy with `PWA_DEPLOY_ROLE_ASSIGNMENTS=false` and have them applied separately.
The estate is incomplete until they exist: the storefront reads blobs and the checkout key through that
identity, so `/admin/azure-check` reports both services as unavailable and product images do not render
until the grants land.

Five names are resolved at deploy time rather than hard-coded, because all five are global DNS labels:
the web app (`pwa-web-<uniqueString>`), the PostgreSQL flexible server (`pwa-pg-<uniqueString>`, which
becomes a `postgres.database.azure.com` label), the storage account (`pwamedia<uniqueString>`), the key
vault (`pwa-kv-<uniqueString>`) and the Front Door endpoint (`pwa-shop-<uniqueString>`).

`seed.sh` needs two grants that the template does not make, because they are about the operator rather
than the application: a PostgreSQL firewall rule for `SEED_CLIENT_IP`, which it removes again on exit,
and Storage Blob Data Contributor on the media container for the signed-in principal, because the storage
account has shared-key access switched off and there is no account key to fall back on. The client
address is supplied rather than looked up — Azure publishes no first-party address-echo endpoint, and
these scripts call no third-party service.

The blob grant is itself privileged: creating a role assignment needs Owner or User Access
Administrator, so on a Contributor-only subscription it is refused, and there is no way around it from
inside the script — with shared-key access off there is no account key, and a user-delegation SAS would
need the same blob permission that is missing. `seed.sh` says so plainly, loads the catalogue anyway,
and exits nonzero with the media container left empty, so a partial seed cannot be read as a whole one.
The shop still serves and every page renders; product images 404 until someone with the right role
grants it and the script is re-run.

Front Door takes a few minutes to propagate after the first deploy. Until it does, `ORIGIN_URL` answers
immediately and `smoke-test.sh` works against it.

## Verification

```bash
./scripts/smoke-test.sh "$BASE_URL"
```

Twenty-three checks — seventeen provider-agnostic, six against the Azure control plane. The
provider-agnostic ones: `/health` returns 200 with `status: ok` and all three
dependencies healthy, `/admin/azure-check` reports `all_ok` across all five services, the catalogue page
renders six seeded products, a product page renders with its tax-inclusive price, and a product image
comes back from object storage. The Azure control-plane ones: the web app is Running, the `staging` slot
exists, the flexible server matches `PWA_EXPECTED_PG_SKU` (`Standard_B1ms` unless overridden), the storage
account has a `TLS1_2` floor and a `media` container, and the Front Door profile exists.

The HTTP checks are provider-agnostic — the same invocation against a migrated GCP frontend is the
acceptance test for the migration. The Azure control-plane checks skip themselves, rather than failing,
when `pwa-rg` is not present in the current subscription.

The script waits for the site before judging it: up to ten attempts fifteen seconds apart, which
`PWA_WARMUP_ATTEMPTS` and `PWA_WARMUP_INTERVAL` override. A shop that was deployed a minute ago is still
starting, and App Service builds the Python environment on the first request after a zip deploy.

Where `PWA_DEPLOY_ROLE_ASSIGNMENTS` is anything but `true`, seven of the checks cannot pass — the two
`/health` dependencies that read the vault and the blob account, the `status: ok` that depends on them,
`all_ok` and its two matching services on `/admin/azure-check`, and the product image. Those report
`XFAIL` and do not fail the run; everything else still has to pass. The shop itself is expected to work:
the catalogue and product pages render, and `/health` answers 200 with `status: degraded`.

### Before spending a deploy

```bash
./scripts/app-self-test.sh
```

Runs the storefront on this machine in three postures — nothing configured, a vault and blob account
configured but unreachable, and that same posture with a real PostgreSQL behind it — and asserts it
serves in all three. It talks to no subscription and needs no credentials; it runs under a scratch `HOME`
precisely so the credential chain cannot reach a signed-in `az` session and flatter the result. The
PostgreSQL posture needs docker and skips without it.

## Running the migration skill (Claude Code)

```bash
# Interactive run against this test bed
cd user-journey-tests/azure/j2-paas-web-app
claude --plugin-dir ../../../features/migration-to-gcp
# In the session: type "migrate from Azure to GCP"

# Headless run (time-boxed)
claude --plugin-dir ../../../features/migration-to-gcp -p "migrate from Azure to GCP" \
  --permission-mode acceptEdits
```

The skill's outputs land in `.migration/<MMDD-HHMM>/`.

## Resource tagging

Every taggable resource carries `Owner=migration-test`, `CostCenter=test-journeys`,
`AutoTeardown=<from env>`, `Journey=azure/j2-paas-web-app`. Find them later:

```bash
az resource list --tag Journey=azure/j2-paas-web-app -o table
```

## Teardown

```bash
./scripts/teardown.sh   # type "yes" at the prompt, or FORCE_TEARDOWN=1
```

Lists what is about to go, runs a single `az group delete --yes`, verifies the group is gone, and then
purges the soft-deleted key vault. That last step matters: Key Vault soft delete cannot be turned off, the
vault name is derived from the resource group id and is therefore stable across a rebuild, and a
soft-deleted vault of the same name blocks the next deploy until it is purged.
