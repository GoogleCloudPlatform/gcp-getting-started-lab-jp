# Journey authoring conventions

A **journey** is a self-contained fictional cloud estate, named for its architecture pattern — AWS and Azure today — used to evaluate how well a coding agent (running the matching migration skill, or unaided) migrates a realistic workload to GCP. Agents under test run with the journey directory as cwd. This file is the contract every journey must satisfy. Where it describes a pattern rather than a rule, copy the exemplars: `user-journey-tests/aws/j2-three-tier-web` for the CloudFormation three-tier lift-and-shift shape, `user-journey-tests/aws/j5-eks-microservices` for the SDK funnel module and the IaC-invisible Kubernetes layer.

## Vendor namespace

Journeys are grouped by **source vendor** — the cloud or platform being migrated _from_. GCP is always the target and is never a vendor.

```
user-journey-tests/<vendor>/jN-<name>/
user-journey-tests/gcp-references/<vendor>/jN-<name>/
```

- `<vendor>` is lowercase, names the source platform, and is the same token in both trees: `aws`, `azure`. One vendor per migration skill.
- **Numbering restarts at `j1` inside each vendor.** `aws/j1-serverless-task-api` and `azure/j1-<name>` coexist, so `jN` alone is ambiguous — always cite a journey as `<vendor>/jN-<name>`.
- Difficulty ordering is per-vendor as well: `j1` is the easiest journey for that vendor, not the easiest in the harness.
- Each vendor has its own lab env file (`~/.aws/journeys.env`, `~/.azure/journeys.env`, …) and its own lab-constraints section below.
- Paths within a journey or a reference are relative to that package, so packages stay movable. Paths that reach _out_ of a package are depth-relative: journey packages sit three levels below the repo root (`../../../features/…`), while `gcp-references/` packages sit four (`../../../../user-journey-tests/<vendor>/…`) — count levels, don't copy.

## Directory contract

```
user-journey-tests/<vendor>/jN-<name>/
├── README.md            # harness-facing, English: what's in here, deploy/verify/teardown, how to run the skill
├── architecture.md      # customer-fidelity doc, English: mermaid diagram, service tables, ops details
├── app/                 # real, runnable application code (source-cloud SDK only — see answer-leak firewall)
├── <iac>/               # terraform/ | cloudformation/ | sam/ — the AUTHORITATIVE, deployable IaC
├── k8s/                 # (aws/j5, azure/j3 — workload layers deliberately invisible to IaC parsers)
├── discovery/           # optional, any journey: synthetic inventory exports — see "Fixture data"
├── costs/               # optional, any journey: synthetic cost exports — see "Fixture data"
├── scripts/
│   ├── deploy.sh        # idempotent, dependency-ordered; sources the vendor's lab env file
│   ├── seed.sh          # optional: test data
│   ├── smoke-test.sh    # REQUIRED: takes BASE_URL argument (or `<vendor>`|`gcp` provider arg for
│   │                    #   pipelines with no HTTP edge); same script verifies source AND GCP
│   └── teardown.sh      # reverse-order destroy; confirmation-gated (type "yes" or FORCE_TEARDOWN=1)
├── .gitignore           # MUST NOT ignore .migration/ or .iteration-log/ (agents read their own outputs)
└── .iteration-log/.gitkeep
```

`discovery/` and `costs/` are fixture-data directories and may appear on **any** journey, deployable or fixture-only — a deployable journey still ships them when the source estate's own tooling would have produced an assessment or a cost export worth discovering. `deploy.sh` and `teardown.sh` appear only on deployable journeys (a fixture-only journey is precisely one that has neither — see "Fixture data").

`app/` is required when the journey's archetype includes application code, which is most of them. An **infrastructure-lift** journey — a plain IaaS estate whose whole point is that nothing was ever modernized — may omit `app/`, on two conditions: its `README.md` names the HTTP edge and says where it comes from (for example an IIS status page written by a VM extension at provisioning time), and `smoke-test.sh` actually exercises that edge. The `/health` and `/admin/<vendor>-check` endpoint rule under "App conventions" applies only to journeys that ship app code.

Everything else in the tree above is required for every journey.

## The skill's discovery contract (what MUST be visible)

- Under `aws/`, IaC is detected as: Terraform `**/*.tf`, or CloudFormation/SAM files containing `AWSTemplateFormatVersion` or `AWS::` markers. ecspresso/k8s manifests/un-synthed CDK are **invisible** (recorded as context only).
- Generally: each vendor's paired migration skill defines its own IaC detection markers, and a journey's authoritative IaC must be inventoriable by that skill — every PRIMARY resource discoverable from it. Read the skill before authoring for a new vendor (Azure: Terraform `azurerm`, Bicep, ARM JSON).
- Source-cloud SDK call sites must be grep-able: funnel ALL SDK calls through one module per service (`app/.../aws_clients.py`, `awsClients.mjs`, `internal/awsclients/` …). A header comment states the intended GCP mapping per service — `user-journey-tests/aws/j5-eks-microservices/app/booking-api/awsClients.mjs` is the exemplar.
- HTTP routes are extracted for Rails/Express/Django/Flask/FastAPI/Sinatra/Go/Spring — declare routes idiomatically for the framework so extraction works.

## AWS lab constraints (hard — deploys FAIL otherwise)

- Account `382142169288` (Qwiklabs), region `ap-northeast-1`. Every script sources `~/.aws/journeys.env` and aborts if `aws sts get-caller-identity` ≠ `EXPECTED_ACCOUNT_ID`.
- **Never create or delete VPCs/subnets** (`ec2:DeleteVpc`/`DeleteSubnet` are denied). Use the **default VPC** via data sources (Terraform `data "aws_vpc" "default"`, `data "aws_subnets"`) or CFN parameters resolved by deploy.sh. Custom security groups are fine (prefix-scoped names).
- **No Spot anywhere** (`ec2:*Spot*` denied): on-demand node groups, plain FARGATE.
- **No AWS Marketplace** (`aws-marketplace:*ubscribe` denied): Bedrock = Amazon 1P models (Nova) only.
- Tags on every taggable resource: `Owner=migration-test`, `CostCenter=test-journeys`, `AutoTeardown=${AUTOTEARDOWN_DATE}`, `Journey=jN-<name>`.
- Cost ceiling: smallest instance classes (t3.micro/t3.medium, db.t3.micro), no NAT gateways, no provisioned capacity, log retention ≤ 30 days.

## Azure lab constraints (hard — deploys FAIL otherwise)

Measured against the lab subscription, 2026-08-06. The quota and SKU facts below are properties of _this_ subscription and were established by probing it; the platform-hazard bullets at the end are properties of Azure itself.

- **Argolis subscription** — the id lives in `~/.azure/journeys.env` as `EXPECTED_SUBSCRIPTION_ID` and is never committed. Guard exactly as the AWS scripts do: every script sources `~/.azure/journeys.env` and aborts unless `az account show --query id -o tsv` equals `EXPECTED_SUBSCRIPTION_ID`.
- **The lab identity is Contributor, not Owner**, so it cannot create role assignments. Any journey that needs a data-plane grant puts every such grant behind one journey-prefixed env flag — `PWA_DEPLOY_ROLE_ASSIGNMENTS`, `AKM_DEPLOY_ROLE_ASSIGNMENTS`, `CAR_DEPLOY_ROLE_ASSIGNMENTS`. The IaC parameter behind the flag defaults to `true`, because the estate a customer would recognise has its grants; `~/.azure/journeys.env` sets each flag to `false`, which is what makes the unelevated lab deploy succeed. A journey that ships such a flag **must** also give `smoke-test.sh` an XFAIL path for every check the missing grant breaks, naming the posture that excuses it — an unelevated run reports XFAIL, never FAIL.
- **Default location `westus3`**, pairing with `us-west2` on the GCP side. `japaneast` is SKU-gated for this subscription and must not be used. Location reaches scripts only through `AZURE_LOCATION` in `~/.azure/journeys.env`, hard-required (`"${AZURE_LOCATION:?…}"`) with **no fallback** — a silent fallback deploys into a region where the sizes are unavailable.
- **No x64 B-series in any region** on this subscription — the burstable cost-ceiling default is simply not offerable, so size on the smallest Standard alternative instead. `Standard_D2s_v5`, `Standard_D2ds_v5` and `Standard_D2ads_v5` are verified unrestricted and are the house sizes.
- **Regional vCPU quota is 350** in `westus3`, which no single journey comes near; the binding constraint is per-family availability, not the total. Check with `az vm list-usage --location westus3 -o table` rather than assuming.
- **One resource group per journey**, named `<prefix>-rg`, so teardown is a single `az group delete` and nothing survives it. Never scatter a journey across groups.
- Tags on every taggable resource: `Owner=migration-test`, `CostCenter=test-journeys`, `AutoTeardown=${AUTOTEARDOWN_DATE}`, `Journey=azure/jN-<name>`.
- Cost ceiling: the smallest Standard SKU that runs the workload — B-series is unavailable here, so the burstable tier is not an option — no provisioned throughput anywhere, log and Application Insights retention ≤ 30 days.
- **The spending limit is the biggest hazard.** Credit-based subscriptions (Azure free account, Visual Studio) enable it by default, set equal to the credit and not adjustable — it can only be removed. When it trips, Azure stops and deallocates VMs and drops storage to read-only, silently destroying a deployed journey mid-run. Either use a pay-as-you-go subscription or treat the credit as the true cost ceiling.
- **Free and Student subscriptions cannot request quota increases at all** — they must be upgraded to pay-as-you-go first. If any journey needs more than default quota, the lab cannot be a free account.
- vCPU quota is two-tier and per-region: a deployment must fit under _both_ the total regional vCPU quota and the per-VM-family quota. Defaults are conservative and vary by subscription type, so check rather than assume — `az vm list-usage --location westus3 -o table`.
- **Spot vCPUs draw on a separate quota** that is not granted by default. Assume Spot is unavailable and size for on-demand, mirroring the AWS no-Spot rule.
- Quota is not capacity: a size can be within quota and still fail to deploy when the region has none left. Prefer the verified D-series sizes above and be ready to fall back to another region.
- `teardown.sh` must **delete** resources, not deallocate them — a deallocated VM stops compute billing but still counts against quota. The single `az group delete` satisfies this.

## App conventions

- Endpoints every web-facing app must expose: `GET /health` (JSON, checks each hard dependency, never raises) and `GET /admin/<vendor>-check` — `/admin/aws-check`, `/admin/azure-check`, … (the parity dashboard: pings every SDK-touched service — S3 list, DynamoDB describe, secret describe, model list, … — returns per-service ok/fail JSON). Post-migration, the same page becomes the GCP parity check. An estate with no compute tier has nowhere to serve those routes from, and may carry the same two checks as CLI subcommands of its own tool instead, emitting the identical JSON (`azure/j6-storage-media-pipeline`'s `smp-upload health` and `smp-upload azure-check` are the precedent).
- All config via env vars (12-factor). No secrets in code, IaC, or docs — Secrets Manager or generated-at-deploy only. Fixture domains use the `.example` TLD and the journey's resource prefix (`vsi.example`, `cpi.example`) — no invented brand names.
- Containerized apps: one multi-stage Dockerfile per service, non-root runtime user, `EXPOSE`d port from `$PORT`.
- Keep apps small but real: actual business logic, actual persistence, deterministic seed data (parity can hash results).

## Fixture data (non-deployed)

Some source platforms cannot be stood up in a lab at all — licensing gates, minimum cluster sizes, or a cost that dwarfs the rest of the harness. Those journeys ship **fixture data** in place of a live source deployment: synthetic exports shaped exactly like what the customer's own tooling would emit.

Deployable journeys ship the same directories whenever the customer's own tooling would plausibly have produced such an export — a live source estate is no reason for an assessment workbook or a cost export not to exist. The rules below apply identically in both cases.

```
discovery/    # assessment/inventory exports the migration tooling reads (RVTools workbook, mcdc output, resource dumps)
costs/        # billing/cost exports the estimation phase consumes
```

- **Each fixture directory carries its own `README.md` declaring the data synthetic**, and naming the tool and version whose output format it imitates. Never present fixture data as a lab-derived measurement — not in the fixture, not in `architecture.md`, not in anything that cites it.
- **Agreement with `architecture.md` and the IaC is the contract.** Every host, VM, disk, database, and instance size in `discovery/` and `costs/` must match both — same names, same counts, same sizes. An agent reading the fixture must reach the same inventory a human reading the doc would. A contradiction between artifacts is a bug, never a trap.
- A fact that surfaces in only one artifact is fine, and is a legitimate carrier for an **assigned** trap: a VM stopped but never deallocated shows up only in the cost export, and that is exactly where such a trap belongs. The rule above bans disagreement between artifacts, not asymmetry between them.
- Synthetic but faithfully shaped: same columns, sheet names, and value formats the real tool emits, so a parser written against the real export works unmodified.
- No real customer data and no real tenancy, subscription, or account identifiers; `.example` domains throughout.
- Deterministic: regenerating a fixture produces byte-identical output (seed any generator), so parity checks can hash it.
- A fixture-only journey has no `deploy.sh` and no `teardown.sh`. Its `smoke-test.sh` verifies the GCP side only, and its README states plainly that the source side is fixture data.

## Deliberate traps (assigned per journey — do NOT add extras)

Each journey embeds its assigned discovery-phase ambiguities (see the journey spec). Everything else must be clean and deployable: exactly the assigned traps, no accidental ones. A trap must never break the source deploy itself.

## GCP reference contract (`user-journey-tests/gcp-references/<vendor>/jN-<name>/`)

The known-good migration target. **Never referenced from inside the journey dir** (answer-leak firewall — agents under test must not find it from cwd).

```
user-journey-tests/gcp-references/<vendor>/jN-<name>/
├── README.md            # mapping table source→GCP, deploy order, parity instructions
├── deploy/00-vars.sh … NN-*.sh   # numbered idempotent gcloud/terraform steps; 99-teardown.sh
├── app-overlay/         # ONLY the files that change vs user-journey-tests/<vendor>/jN-<name>/app/ (GCP SDK ports)
└── build.sh             # copies journey app + applies overlay → builds/pushes image or function source
```

- Project `aws-migration-501814`, region `asia-northeast1` — **every** gcloud/terraform invocation passes the project explicitly (the box's default project is different).
- The journey's own `scripts/smoke-test.sh <gcp-url>` must pass unmodified against the reference deployment.
- Every vendor's references share this one GCP project, which is why resource prefixes must be unique across vendors.

## Naming

Resource prefixes are **globally unique across every vendor**, not merely within one. `aws/j1-serverless-task-api` owns `sta-`, so no `azure/` journey may reuse it. Two reasons: every reference deployment lands in the same GCP project, and journeys are routinely deployed side by side, so a collision is an outage rather than a naming nit. Journey `<name>` slugs are globally unique for the same reason.

The `Journey=` tag carries the vendor namespace for every new vendor (`Journey=azure/jN-<name>`); `aws/` journeys use the legacy unprefixed `Journey=jN-<name>`. **Legacy live estates:** the aws j1–j5 stacks and their GCP references were deployed before the 2026-08-28 neutral-naming restructure and still run under the retired prefixes, tags, and slugs — retagging or renaming them means redeploying, so they keep the old names until teardown (state files moved with the tree; `terraform destroy` still works). The repo's IaC, scripts, and docs use only the current names.

CFN stack names / TF state keys are prefix-scoped (`ttw-data-stack` …). One journey never references another's resources.

**Where the hyphen does not fit.** Some resource types reject the `xxx-` form, and the prefix becomes a bare token plus a uniqueness suffix:

- Azure **storage accounts** take 3–24 characters, lowercase letters and digits only — no hyphens — and are globally unique across all of Azure, because the name is a public DNS label. `sta-assets` is invalid; use `staassets<suffix>` and confirm with `az storage account check-name --name <n>` before deploying.
- Azure **SQL logical servers** are a global DNS namespace too — the name becomes `<name>.database.windows.net` — so a bare `wil-sql` is unsafe. Suffix them exactly as storage accounts are suffixed: `[concat('wil-sql-', uniqueString(resourceGroup().id))]`. Hyphens are legal here; only the uniqueness constraint bites.
- Azure **Key Vaults** take 3–24 characters of alphanumerics and hyphens, must start with a letter, and are likewise globally unique across all of Azure.
- GCS buckets are globally unique too; existing journeys already suffix with the project (`ttw-assets-<project>`), and Azure equivalents should suffix the same way.

The tables below are the registry: claim a prefix by adding its row in the same commit that creates the journey.

### AWS (`user-journey-tests/aws/`)

| Journey                | Workload persona (all fictional)                | Resource prefix | GCP name prefix |
| ---------------------- | ----------------------------------------------- | --------------- | --------------- |
| j1-serverless-task-api | Internal task/reminder API                      | `sta-`          | `sta-`          |
| j2-three-tier-web      | Online shop, classic three tier                 | `ttw-`          | `ttw-`          |
| j3-event-driven-fanout | Event-driven photo pipeline                     | `edf-`          | `edf-`          |
| j4-fargate-ai-chatbot  | AI support-desk chatbot                         | `fac-`          | `fac-`          |
| j5-eks-microservices   | Two-service marketplace on Kubernetes           | `ems-`          | `ems-`          |
| j6-fargate-agentic-rag | Policy copilot, agentic RAG (logistics company) | `arc-`          | `arc-`          |

### Azure (`user-journey-tests/azure/`)

| Journey                       | Workload persona (all fictional)              | Resource prefix | GCP name prefix |
| ----------------------------- | --------------------------------------------- | --------------- | --------------- |
| j1-windows-iaas-lift          | Windows LOB estate on IaaS                    | `wil-`          | `wil-`          |
| j2-paas-web-app               | Online stationery shop on PaaS                | `pwa-`          | `pwa-`          |
| j3-aks-microservices          | Parcel tracking on AKS                        | `akm-`          | `akm-`          |
| j4-durable-functions-pipeline | Event-driven claims intake                    | `dfp-`          | `dfp-`          |
| j5-vmss-sql-iaas              | Precision-parts MES on VMSS + SQL-on-VM       | `vsi-`          | `vsi-`          |
| j6-storage-media-pipeline     | Photo/video licensing storage estate          | `smp-`          | `smp-`          |
| j7-container-apps-rag         | RAG portfolio explainer on Container Apps     | `car-`          | `car-`          |
| j8-clickops-partial-iac       | ClickOps university estate, one templated app | `cpi-`          | `cpi-`          |
