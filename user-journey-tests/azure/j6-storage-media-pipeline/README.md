# azure/j6-storage-media-pipeline: Blob Storage media-pipeline migration test bed

Realistic test material for the `azure-to-gcp` skill in this repository. The media-licensing operator (fictional) is an
eleven-person photo and video licensing agency in Kanazawa whose 340,000-frame library lives on Azure
Blob Storage behind a Front Door edge, described in [`architecture.md`](./architecture.md).

Difficulty tier: **hard** — not because the estate is large, but because it is described in **two IaC
dialects at once**. The library is a portal-exported ARM JSON template under `arm/`; the delivery edge is
a Terraform tree under `terraform/`. Both trees name the same delivery storage account, and a parser that
reads only one of them sees a different estate from one that reads both. On top of that the workload is
storage-shaped rather than compute-shaped: there is no VM, no container and no managed compute anywhere,
so the migration has to reason about access tiers, lifecycle policies, redundancy choices, a write-once
retention policy, a file-sync service and an event fan-out, with a four-month cost export as the main
evidence of what any of it actually costs.

## What's in here

| Path              | Purpose                                                                                                             | Used by                                         |
| ----------------- | ------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------- |
| `arm/`            | Authoritative, deployable IaC for the library — one portal-flavored ARM template plus its parameters file           | Azure deploy AND the skill's Discover phase     |
| `terraform/`      | Authoritative, deployable IaC for the delivery edge — `azurerm` 5.x, the delivery origin and the Front Door profile | Azure deploy AND the skill's Discover phase     |
| `app/uploader/`   | The Node CLI the photographers run to push a shoot into `intake`; all SDK calls funnel through `azureClients.mjs`   | Operator; the skill's app-code scan             |
| `costs/`          | Synthetic FOCUS 1.0r2 cost and usage export plus its deterministic generator — see its own `README.md`              | The skill's Discover and Estimate phases        |
| `scripts/`        | `deploy.sh`, `smoke-test.sh`, `teardown.sh` — all three source `~/.azure/journeys.env` and guard the subscription   | Operator                                        |
| `.migration/`     | Created by the skill at runtime — do not commit, do not gitignore                                                   | Phase outputs: inventory, design, generated IaC |
| `.iteration-log/` | One subdirectory per run                                                                                            | Observation logs and transcripts                |

**Two IaC directories, one estate.** `arm/` and `terraform/` are both authoritative and both deployable —
neither is a leftover. `scripts/deploy.sh` applies them in a fixed order (Terraform first, ARM second) and
documents why in its header. There is no `discovery/` directory: this estate has no VMs, so an Azure
Migrate assessment was never run against it.

**The app is a command-line tool, not a service.** `app/uploader/` runs on the ingest workstation in the
studio's own office; there is no compute tier in Azure for it to be deployed to. It therefore has no
`GET /health` or `GET /admin/azure-check` endpoint. It has the same two checks as `health` and
`azure-check` subcommands, emitting the same JSON those endpoints would, so the parity contract survives
the shape change:

```bash
cd app/uploader && npm install
node uploader.mjs health         # hard dependencies, never raises
node uploader.mjs azure-check    # per-service ok/fail across every Azure service it touches
```

The HTTP edge `scripts/smoke-test.sh` exercises is the Front Door endpoint, which serves the watermarked
previews out of the delivery origin. `deploy.sh` seeds the placeholder objects that edge answers with.

Evaluation criteria and scoring live in the repo-root `CATALOG.md`.

## Deployment

```bash
# Pre-flight: ~/.azure/journeys.env must define EXPECTED_SUBSCRIPTION_ID,
# AUTOTEARDOWN_DATE and AZURE_LOCATION. Every script sources it and aborts on
# subscription mismatch. AZURE_LOCATION is hard-required — there is no fallback.
az account show --query id -o tsv    # confirm the right subscription before any create

./scripts/deploy.sh                 # az group create smp-rg, terraform apply, then
                                    # az deployment group create; prints BASE_URL and
                                    # the four resolved resource names
```

Needs `terraform` on `PATH` in addition to `az`. First deploy takes roughly 10-15 minutes, most of it
Front Door provisioning and the wait for the new endpoint to start answering on its generated hostname.
Set `SMP_SKIP_EDGE_WAIT=1` to skip that final poll.

The script is idempotent: `az group create` is create-or-update, `terraform apply` converges, and the ARM
deployment runs in Incremental mode. There are no passwords anywhere in this estate, so a re-deploy
rotates no credentials. The delivery account key is read once, in memory, to upload the two placeholder
objects, and is not written anywhere.

**One suffix, both trees.** Three storage accounts and the data factory are global DNS names, so each
carries an 8-character suffix. `deploy.sh` derives it once from the subscription id and the resource group
name and passes the same value to the ARM template (`nameSuffix`) and to Terraform (`name_suffix`) — which
is what makes both trees name the same delivery account. Override it with `SMP_NAME_SUFFIX`.

Everything lands in the single resource group `smp-rg`.

**Running cost, roughly.** With an empty estate the recurring floor is the Front Door Standard base fee
(USD 35/month per profile), the premium file share's provisioned 100 GiB (USD 16/month), and pennies of
storage. The cost export under `costs/` describes a full library and is not what a lab deployment bills.

Optional environment overrides, all journey-prefixed because `~/.azure/journeys.env` is sourced by every
journey's scripts:

| Variable              | Effect                                                                     |
| --------------------- | -------------------------------------------------------------------------- |
| `SMP_NAME_SUFFIX`     | Override the derived 8-character global-name suffix (6-12 lowercase alnum) |
| `SMP_FRONTDOOR_SKU`   | Front Door tier; default `Standard_AzureFrontDoor`                         |
| `SMP_SKIP_EDGE_WAIT`  | `1` skips the post-deploy poll of the Front Door endpoint                  |
| `SMP_WARMUP_ATTEMPTS` | Smoke-test edge warm-up attempts before the HTTP checks; default `20`      |
| `SMP_WARMUP_INTERVAL` | Seconds between those attempts; default `30` (ten minutes in total)        |

## Verification

```bash
./scripts/smoke-test.sh "$BASE_URL"
```

The Azure control-plane checks run first: the three storage accounts, the library's `Standard_RAGRS`
redundancy and `TLS1_2` floor, the `masters`/`proxies`/`intake` containers, the lifecycle policy's rule
count, the state of the retention policy on `masters`, the `wip-edit` premium share, the storage sync
service, the Event Grid system topic and its subscription, the data factory, the edge profile, and then
the edge binding — the endpoint's state and hostname, and the route's state, its link to the default
domain, its `/*` pattern and its `/public/` origin path, plus the origin's host header. Then four HTTP
checks against the edge: 200 on `/index.html`, the page identifying the media-licensing operator and reporting
`status: ok`, and 200 on `/health.txt`, which is also the origin health-probe target. Nonzero exit on any
failure.

The HTTP checks are provider-agnostic — the same invocation against a migrated GCP edge is the acceptance
test for the migration. The Azure control-plane checks skip themselves, rather than failing, when `smp-rg`
is not present in the current subscription.

Before the HTTP checks the script waits for `/index.html` to answer 200, up to ten minutes by default. A
Front Door endpoint minutes old is not a broken endpoint: the profile's configuration has to reach the
POPs, and the origin has to pass three good health probes at the 100-second interval this estate
configures — about five minutes on its own, counted from the moment `deploy.sh` seeds the two objects.
That is why a smoke run straight after a deploy can fail every HTTP check while every control-plane check
passes. Every HTTP failure line names the URL, the status and the first line of the body, which is what
separates a Front Door 404 from an origin `BlobNotFound`.

The order matters, and so does reading the binding rather than inferring it. A Front Door route matches on
protocol × domain × path, so a route linked to no domain matches nothing: every request returns Front
Door's own 404 forever, while every resource in the profile still exists and still reports healthy. That
404 cannot be recognised from the client side — it is byte for byte the ~266 KB "Page not found" page that
`*.azurefd.net` serves for a hostname that was never created, sent with `x-cache: CONFIG_NOCACHE`, and
because that namespace is wildcard DNS onto the Front Door anycast, even the hostname resolving proves
nothing. Waiting cannot distinguish the two, so the control plane is asked directly, and the warm-up is
skipped outright when the answer is already no. `deploy.sh` records the same fact as
`ROUTE_LINKED_TO_DEFAULT_DOMAIN=` in its closing banner, because `az group delete` destroys the only place
that answer was ever written down.

## Running the migration skill (Claude Code)

```bash
# Interactive run against this test bed
cd user-journey-tests/azure/j6-storage-media-pipeline
claude --plugin-dir ../../../features/migration-to-gcp
# In the session: type "migrate from Azure to GCP"

# Headless run (time-boxed)
claude --plugin-dir ../../../features/migration-to-gcp -p "migrate from Azure to GCP" \
  --permission-mode acceptEdits
```

The skill's outputs land in `.migration/<MMDD-HHMM>/`.

## Resource tagging

Every taggable resource carries `Owner=migration-test`, `CostCenter=test-journeys`,
`AutoTeardown=<from env>`, `Journey=azure/j6-storage-media-pipeline`. Find them later:

```bash
az resource list --tag Journey=azure/j6-storage-media-pipeline -o table
```

## Teardown

```bash
./scripts/teardown.sh   # type "yes" at the prompt, or FORCE_TEARDOWN=1
```

Lists what is about to go, then does two things before the single `az group delete --yes`:

1. **Clears the time-based retention policy on `masters`.** It is in the Unlocked state, so it can simply
   be removed with its current etag. A locked policy could not be removed at all, and its container could
   only be deleted once empty and past retention.
2. **Deletes the Storage Sync Service.** A sync service with registered servers refuses to delete and
   takes the group delete down with it. This one has none, but removing it first means teardown does not
   become a manual job the first time somebody registers one.

It then verifies the group is gone and clears the local Terraform state, which would otherwise describe
resources that no longer exist. Deleting rather than emptying matters: the premium share bills on its
provisioned size whether or not anything is written to it.
