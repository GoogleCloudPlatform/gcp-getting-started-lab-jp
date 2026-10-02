# azure/j5-vmss-sql-iaas: VMSS + SQL Server IaaS migration test bed

Realistic test material for the `azure-to-gcp` skill in this repository. The precision-parts MES
operator (fictional) is a small manufacturer in Ōta-ku, Tokyo, whose manufacturing execution system was lifted from
the plant's own server room into Azure IaaS in 2022 and never modernized, described in
[`architecture.md`](./architecture.md).

Difficulty tier: **hard**. Nothing in this estate is a managed service. A scale set carries the web tier
behind a Standard load balancer, SQL Server runs inside a Windows VM, Azure Backup protects that VM, and
a Log Analytics workspace sits alongside them. The migration has to reason about Terraform `azurerm`,
about a Windows estate with no application source to port, and about an autoscale profile, a backup
policy and a retention setting that all need equivalents on the other side.

## What's in here

| Path              | Purpose                                                                                                                        | Used by                                         |
| ----------------- | ------------------------------------------------------------------------------------------------------------------------------ | ----------------------------------------------- |
| `terraform/`      | Authoritative, deployable IaC — Terraform `azurerm` ~> 5.0, one root module, no child modules                                  | Azure deploy AND the skill's Discover phase     |
| `discovery/`      | Synthetic Migration Center discovery-client export (`mcdc-export/`) plus its deterministic generator — see its own `README.md` | The skill's Discover phase                      |
| `costs/`          | Synthetic Enterprise Agreement actual-cost export (`.csv`) plus its deterministic generator — see its own `README.md`          | The skill's Discover and Estimate phases        |
| `scripts/`        | `deploy.sh`, `smoke-test.sh`, `teardown.sh` — all three source `~/.azure/journeys.env` and guard the subscription              | Operator                                        |
| `.migration/`     | Created by the skill at runtime — do not commit, do not gitignore                                                              | Phase outputs: inventory, design, generated IaC |
| `.iteration-log/` | One subdirectory per run                                                                                                       | Observation logs and transcripts                |

**There is no `app/` and no `seed.sh`.** The MES itself is a commercial ASP.NET application from a
third-party vendor, installed by hand on a maintenance window, and there is no source for it to ship. In
its place the scale set's `CustomScriptExtension` installs IIS and writes a static status page at
provisioning time, so the load balancer probe and `scripts/smoke-test.sh` have a real HTTP 200 to assert
against. That static page is the entire HTTP edge of this estate — exactly as
[`architecture.md`](./architecture.md) describes it, where it is the placeholder the contractor put in
front of IIS in 2022 and never removed.

Evaluation criteria and scoring live in the repo-root `CATALOG.md`.

## Deployment

```bash
# Pre-flight: ~/.azure/journeys.env must define EXPECTED_SUBSCRIPTION_ID,
# AUTOTEARDOWN_DATE and AZURE_LOCATION. Every script sources it and aborts on
# subscription mismatch; there is no region fallback.
az account show --query id -o tsv    # confirm the right subscription before any create

./scripts/deploy.sh                 # terraform apply into vsi-rg
                                    # prints BASE_URL, SCALE_SET, SQL_VM,
                                    # LOG_ANALYTICS_WORKSPACE, RECOVERY_VAULT
```

First deploy takes roughly 10-15 minutes. `terraform apply` converges, so the script is idempotent, with
one caveat: **the local Windows administrator password is regenerated on every run**, so a re-deploy
rotates it on both the scale set model and the database server. It is never written to this repository
and never printed.

Everything lands in the single resource group `vsi-rg`. One name is resolved at deploy time rather than
hard-coded — the Recovery Services vault (`vsi-rsv-<suffix>`), whose name must be unique across the
subscription.

Lab overrides, all prefixed `VSI_` because `~/.azure/journeys.env` is sourced by every test bed's
scripts: `VSI_WEB_VM_SIZE`, `VSI_SQL_VM_SIZE`, `VSI_WEB_INSTANCE_COUNT`, `VSI_WEB_IMAGE_SKU`,
`VSI_SQL_IMAGE_OFFER`, `VSI_SQL_IMAGE_SKU`.

Two cost notes for whoever is paying for the lab run:

- The Log Analytics workspace deploys with **730-day retention**, which is what the customer runs. That
  costs effectively nothing here, because retention is billed per GB retained and a freshly stood-up
  workspace with no agents attached ingests almost nothing. The customer's real bill for it is in
  `costs/`, not on your subscription.
- The estate runs **three Windows VMs' worth of compute** (two scale-set instances plus the database
  server) alongside a NAT gateway. It is the most expensive Azure test bed in this set per hour running.
  Tear it down when you are finished.

## Verification

```bash
./scripts/smoke-test.sh "$BASE_URL"
```

Eight checks: HTTP 200 on `/`, the status page identifying the MES operator and reporting `status: ok`, then
`az vmss show` reporting `Succeeded`, the scale set running at least two instances, `vsi-sql01` powered
on, the `vsi-law` workspace present, and `vsi-sql01` registered as a protected item in the vault.
Nonzero exit on any failure.

The three HTTP checks are provider-agnostic — the same invocation against a migrated GCP frontend is the
acceptance test for the migration. The five Azure control-plane checks skip themselves, rather than
failing, when `vsi-rg` is not present in the current subscription.

## Running the migration skill (Claude Code)

```bash
# Interactive run against this test bed
cd user-journey-tests/azure/j5-vmss-sql-iaas
claude --plugin-dir ../../../features/migration-to-gcp
# In the session: type "migrate from Azure to GCP"

# Headless run (time-boxed)
claude --plugin-dir ../../../features/migration-to-gcp -p "migrate from Azure to GCP" \
  --permission-mode acceptEdits
```

The skill's outputs land in `.migration/<MMDD-HHMM>/`.

## Resource tagging

Every taggable resource carries `Owner=migration-test`, `CostCenter=test-journeys`,
`AutoTeardown=<from env>`, `Journey=azure/j5-vmss-sql-iaas`. Find them later:

```bash
az resource list --tag Journey=azure/j5-vmss-sql-iaas -o table
```

Fifteen of the twenty-eight resources carry them. The other thirteen are not taggable resource types in
Azure at all, so their absence is expected rather than a gap: the two subnets, the four association
resources (NSG-to-subnet ×2, NAT-gateway-to-public-IP, NAT-gateway-to-subnet), the four load balancer
child resources (backend pool, probe, rule, outbound rule), the data-disk attachment, the backup policy
and the protected item.

## Teardown

```bash
./scripts/teardown.sh   # type "yes" at the prompt, or FORCE_TEARDOWN=1
```

**The order matters here in a way it does not in the other Azure test beds.** A Recovery Services vault
deletes cleanly with its resource group only while it is empty. Once `vsi-sql01` is a protected item the
vault holds backup data, and `az group delete` fails with _"Vault cannot be deleted as there are
existing resources within the vault"_, leaving the whole group — and three billing VMs — behind. So
`teardown.sh` disables protection on every protected item with `--delete-backup-data true`, waits until
nothing in the vault is actively protected any more, deletes the vault with `--force`, and only then
deletes the group and verifies it is gone. It asks for items of all three backup management types, not
just the `AzureIaasVM` one this template creates: the list call answers for one type at a time, and an
item left behind by a hand-run experiment blocks the group delete just as effectively.

Soft delete cannot be turned off to avoid this. The Terraform argument that used to do it was removed in
`azurerm` 5.0, and Azure no longer permits disabling it in the regions where secure-by-default is
generally available. Items deleted during teardown therefore sit in a soft-deleted state for 14 days,
which cannot be purged early — the vault name may keep appearing in a portal listing for a fortnight
after the group is gone. Nothing is billing during that time.

One more thing outlives the group, and it is the one a tag-scoped sweep will miss. Backing up a VM puts
its instant-restore snapshots in a restore point collection that the Backup service keeps in **its own
service-owned resource group** — `AzureBackupRG_<geo>_<n>`, outside `vsi-rg` — carrying none of this
test bed's tags. Deleting the VM does not delete them: they expire on the policy's snapshot retention,
two days by default, and the garbage collector clears them within about a day of that. So the check for
stragglers after teardown is subscription-wide, not tag-filtered, and anything it turns up in
`AzureBackupRG_*` should be left alone to age out rather than deleted by hand.

Deleting rather than deallocating matters: a deallocated VM stops compute billing but still consumes
regional vCPU quota.
