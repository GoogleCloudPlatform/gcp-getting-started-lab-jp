# azure/j1-windows-iaas-lift: clinic group (fictional) migration test bed

Realistic test material for the `azure-to-gcp` skill in this repository. The clinic group here is a
fictional four-site private clinic chain in Setagaya, Tokyo, whose Windows line-of-business estate was
lifted into Azure IaaS in 2021 and never modernized, described in [`architecture.md`](./architecture.md).

Difficulty tier: **easy** — the first Azure test bed. It is a small, entirely conventional IaaS estate:
hub-and-spoke VNets, two Windows Server 2019 VMs behind a Standard load balancer, Azure SQL, a storage
account, and a Recovery Services vault. The migration has to reason about a portal-exported ARM template
— one flat `resources[]` array wired together by expressions and a copy loop — and about a Windows estate
with no containers and no application code to port.

## What's in here

| Path              | Purpose                                                                                                           | Used by                                         |
| ----------------- | ----------------------------------------------------------------------------------------------------------------- | ----------------------------------------------- |
| `arm/`            | Authoritative, deployable IaC — one portal-flavored ARM template plus its parameters file                         | Azure deploy AND the skill's Discover phase     |
| `discovery/`      | Synthetic Azure Migrate assessment export (`.xlsx`) plus its deterministic generator — see its own `README.md`    | The skill's Discover phase                      |
| `scripts/`        | `deploy.sh`, `smoke-test.sh`, `teardown.sh` — all three source `~/.azure/journeys.env` and guard the subscription | Operator                                        |
| `.migration/`     | Created by the skill at runtime — do not commit, do not gitignore                                                 | Phase outputs: inventory, design, generated IaC |
| `.iteration-log/` | One subdirectory per run                                                                                          | Observation logs and transcripts                |

**There is no `app/` and no `seed.sh`.** The clinic's ASP.NET portal predates the Azure move and is out
of scope; in its place the CustomScriptExtension installs IIS and writes a static status page at
provisioning time, so the load balancer probe and `scripts/smoke-test.sh` have a real HTTP 200 to assert
against. That static page is the entire HTTP edge of this estate.

Evaluation criteria and scoring live in the repo-root `CATALOG.md`.

## Deployment

```bash
# Pre-flight: ~/.azure/journeys.env must define EXPECTED_SUBSCRIPTION_ID and
# AUTOTEARDOWN_DATE. Every script sources it and aborts on subscription mismatch.
az account show --query id -o tsv    # confirm the right subscription before any create

./scripts/deploy.sh                 # az group create wil-rg + one az deployment group create
                                    # prints BASE_URL, SQL_FQDN, STORAGE_ACCOUNT
```

First deploy takes roughly 10-15 minutes; the two Windows VMs and their IIS install dominate. The script
is idempotent — `az group create` and Incremental-mode deployments are both create-or-update — with one
caveat: **both securestring passwords are regenerated on every run**, so a re-deploy resets the Windows
local administrator password and the Azure SQL administrator password. Neither is ever written to this
repository or printed to the terminal.

Everything lands in the single resource group `wil-rg`, so nothing survives teardown.

Two names are resolved at deploy time rather than hard-coded, because both are globally unique across all
of Azure: the storage account (`wilscans<uniqueString>`) and the Azure SQL logical server
(`wil-sql-<uniqueString>`, since the name becomes a `database.windows.net` DNS label).

## Verification

```bash
./scripts/smoke-test.sh "$BASE_URL"
```

Eight checks: HTTP 200 on `/`, the status page identifying the clinic and reporting `status: ok`, then
`az sql db show` on `wil-clinicdb`, the storage account's existence and its `TLS1_2` floor, and the
presence of the `scans` file share and `backups` container. Nonzero exit on any failure.

The HTTP checks are provider-agnostic — the same invocation against a migrated GCP frontend is
the acceptance test for the migration. The Azure control-plane checks skip themselves, rather than
failing, when `wil-rg` is not present in the current subscription.

## Running the migration skill (Claude Code)

```bash
# Interactive run against this test bed
cd user-journey-tests/azure/j1-windows-iaas-lift
claude --plugin-dir ../../../features/migration-to-gcp
# In the session: type "migrate from Azure to GCP"

# Headless run (time-boxed)
claude --plugin-dir ../../../features/migration-to-gcp -p "migrate from Azure to GCP" \
  --permission-mode acceptEdits
```

The skill's outputs land in `.migration/<MMDD-HHMM>/`.

## Resource tagging

Every taggable resource carries `Owner=migration-test`, `CostCenter=test-journeys`,
`AutoTeardown=<from env>`, `Journey=azure/j1-windows-iaas-lift`. Find them later:

```bash
az resource list --tag Journey=azure/j1-windows-iaas-lift -o table
```

## Teardown

```bash
./scripts/teardown.sh   # type "yes" at the prompt, or FORCE_TEARDOWN=1
```

Lists what is about to go, then runs a single `az group delete --yes` and verifies the group is gone.
Deleting rather than deallocating matters: a deallocated VM stops compute billing but still consumes
regional vCPU quota.
