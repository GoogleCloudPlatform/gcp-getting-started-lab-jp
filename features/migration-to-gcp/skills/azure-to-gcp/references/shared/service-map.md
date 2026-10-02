# Azure -> Google Cloud Target Map

**Loaded by:** `references/phases/clarify.md` (fires the trade-off cards) and
`references/phases/design.md` (routes each mapping). This file is the canonical rubric. It fixes
**which targets are candidates** and **which decisions are cards**; it does NOT fix the answer. Every
card's content is populated by live research in the run that presents it — see the
**FACTS THAT GO STALE** table at the end.

Google's own canonical cross-cloud table is **[cmp]** (fetched 2026-08-06):
https://docs.cloud.google.com/docs/get-started/aws-azure-gcp-service-comparison. The per-workload Azure
migration guides moved off `cloud.google.com`: only the series index remains at
https://docs.cloud.google.com/architecture/migration-from-azure-get-started, while every guide now lives
on Google's `googlecloudplatform.github.io/cloud-solutions/` Pages site (**[series]**; noted 2026-08-06).

## Mapping classes

- **deterministic** — one documented target, no viable alternative. Design maps it directly and stamps
  `design_choice_ref: "deterministic"`.
- **card** — 2+ viable targets. Clarify MUST present a trade-off card and record the pick in
  `preferences.json.design_choices[]`. A card mapping without a recorded choice is a Design STOP.
- **deferred** — a specialist gate owns it. Carried verbatim: no `gcp_config`, no dollars, no Terraform.

## Master table

| Azure source                                                                                | GCP target(s)                                                    | Class                                     | Migration method                                                        | Source                                                                                                                     |
| ------------------------------------------------------------------------------------------- | ---------------------------------------------------------------- | ----------------------------------------- | ----------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------- |
| Virtual Machines (+ Managed Disks)                                                          | Compute Engine (+ Hyperdisk)                                     | deterministic                             | Migrate to Virtual Machines (M2VM), Azure source; disks carried by M2VM | [cmp]; [series] VM guide                                                                                                   |
| VM Scale Sets (Uniform/Flexible)                                                            | Managed instance group + Compute Engine Autoscaler               | card (`Q_MAP.vmss`)                       | rebuild MIG; per-VM M2VM only for pets                                  | [cmp] "Azure Autoscale, Azure Virtual Machine Scale Sets -> Compute Engine Autoscaler"                                     |
| Container Apps / Container Instances                                                        | Cloud Run                                                        | deterministic                             | rebuild image, redeploy                                                 | [cmp] "Azure Container Apps, Azure Container Instances -> Cloud Run"                                                       |
| App Service (web apps)                                                                      | App Engine **or** Cloud Run                                      | card (`Q_MAP.appservice`)                 | containerize + redeploy                                                 | [cmp] maps App Service -> App Engine; Cloud Run is the container-native alternative                                        |
| Functions                                                                                   | Cloud Run functions                                              | deterministic (plan-aware)                | redeploy per trigger                                                    | [cmp]; plan facts below                                                                                                    |
| Azure SQL Database / SQL Managed Instance                                                   | Cloud SQL for SQL Server                                         | deterministic                             | BACPAC via SqlPackage; MI link + DMS for MI                             | [series] SQL MI and SQL DB guides                                                                                          |
| Azure Database for PostgreSQL Flexible Server                                               | Cloud SQL for PostgreSQL **or** AlloyDB                          | card (`Q_MAP.postgres`)                   | engine backups; DMS + pglogical for CDC                                 | [series] PostgreSQL guide; DMS list                                                                                        |
| Azure Database for MySQL Flexible Server                                                    | Cloud SQL for MySQL                                              | deterministic                             | engine backups; DMS for CDC                                             | [series] MySQL guide; DMS list                                                                                             |
| Cosmos DB                                                                                   | Firestore / Spanner / Bigtable / AlloyDB, by API                 | **card (MANDATORY)** (`Q_MAP.cosmos`)     | export + rewrite; no lift tool                                          | [cmp] lists Firestore, Datastore, Bigtable, Spanner, AlloyDB                                                               |
| Blob Storage                                                                                | Cloud Storage                                                    | deterministic                             | Storage Transfer Service                                                | [cmp]; [series] Blob guide; STS Azure source                                                                               |
| Azure Files                                                                                 | Filestore (NFS) **or** NetApp Volumes (SMB)                      | **card (protocol-gated)** (`Q_MAP.files`) | STS/copy tooling per protocol                                           | Filestore protocols; NetApp Volumes features                                                                               |
| Azure NetApp Files                                                                          | Google Cloud NetApp Volumes                                      | deterministic                             | vendor replication                                                      | [cmp]                                                                                                                      |
| Service Bus / Storage Queues                                                                | Pub/Sub **or** Cloud Tasks                                       | **card** (`Q_MAP.messaging`)              | rewrite call sites                                                      | [cmp] lists BOTH targets; Storage Queues -> Cloud Tasks                                                                    |
| Event Hubs / Event Grid                                                                     | Pub/Sub / Eventarc                                               | deterministic                             | rewrite call sites / re-declare subscriptions                           | [cmp]                                                                                                                      |
| Container Registry                                                                          | Artifact Registry                                                | deterministic                             | image copy                                                              | [cmp]                                                                                                                      |
| Key Vault                                                                                   | Secret Manager (secrets) / Cloud KMS + Cloud HSM (keys)          | card (`Q_MAP.keyvault`)                   | re-create material; never copy secrets through the run                  | [cmp] lists both                                                                                                           |
| Application Insights / Azure Monitor                                                        | Cloud Trace + Cloud Monitoring + Cloud Logging (OpenTelemetry)   | card (`Q_MAP.observability`)              | re-instrument                                                           | [cmp]: Monitor -> Cloud Monitoring, Monitor Logs -> Cloud Logging, App Insights -> Cloud Trace, Profiler -> Cloud Profiler |
| Front Door                                                                                  | Cloud CDN + Cloud Load Balancing (Media CDN for media)           | **card (rules gap)** (`Q_MAP.edge`)       | rebuild rules                                                           | [cmp] Front Door -> Cloud CDN, Front Door -> Media CDN                                                                     |
| Azure Cache (Redis)                                                                         | Memorystore                                                      | deterministic                             | re-provision, warm cache                                                | [cmp]                                                                                                                      |
| API Management                                                                              | API Gateway **or** Apigee                                        | card (`Q_MAP.apim`)                       | re-import API definitions                                               | [cmp] lists both                                                                                                           |
| Logic Apps                                                                                  | Workflows / Cloud Scheduler / Application Integration            | card (`Q_MAP.logicapps`)                  | rebuild                                                                 | [cmp] lists three                                                                                                          |
| Azure OpenAI / Azure AI services                                                            | Vertex AI                                                        | **card** (`Q_MAP.ai`)                     | SDK-shape rewrite, below                                                | [cmp] "Azure AI Platform -> Vertex AI"; Chat Completions sample                                                            |
| Azure AI Search                                                                             | Agent Search **or** a self-managed vector store                  | **card** (`Q_MAP.search`)                 | reindex from the source of truth; no index transfer                     | [cmp] pairs "Azure AI Search" with Agent Search (and Agent Search for retail)                                              |
| Virtual Network / Load Balancer / DNS / NAT / WAF                                           | VPC / Cloud Load Balancing / Cloud DNS / Cloud NAT / Cloud Armor | deterministic                             | rebuild                                                                 | [cmp]                                                                                                                      |
| Private Link / Private Endpoint / ExpressRoute                                              | Private Service Connect / Cloud Interconnect (+ Cloud Router)    | deterministic                             | rebuild; a new circuit has lead time                                    | [cmp]                                                                                                                      |
| Entra ID (Azure AD)                                                                         | Cloud Identity (federated)                                       | gate (`Q_IDENTITY`)                       | federate, do not migrate the IdP                                        | [cmp]; federation guide                                                                                                    |
| Entra Workload Identity Federation / managed identities (system/user-assigned)              | Workload Identity Federation for GKE / service accounts + ADC    | deterministic                             | re-bind pods; rewrite credential bootstrap                              | [cmp] "Azure Identity Management -> IAM"; GKE WIF; Entra WIF; ADC per the Vertex sample                                    |
| Synapse / Fabric / Databricks / HDInsight / Stream Analytics / Data Factory / Data Explorer | see the analytics gate                                           | **deferred**                              | none — specialist engagement                                            | `Q_ANALYTICS` gate in `references/phases/clarify.md`                                                                       |
| Azure VMware Solution                                                                       | (out of scope)                                                   | refuse                                    | none                                                                    | Google's Azure series has no AVS journey; [cmp] does list AVS -> Google Cloud VMware Engine as a product pairing           |

Cited URLs, in full, for the rows above:

- [series] VM: https://googlecloudplatform.github.io/cloud-solutions/migrate-from-azure-to-google-cloud/migrate-from-azure-vms-to-compute-engine
- [series] AKS: https://googlecloudplatform.github.io/cloud-solutions/migrate-from-azure-to-google-cloud/migrate-from-aks-to-gke
- [series] Blob: https://googlecloudplatform.github.io/cloud-solutions/migrate-from-azure-to-google-cloud/migrate-from-azure-blob-storage-to-cloud-storage
- [series] SQL MI: https://googlecloudplatform.github.io/cloud-solutions/migrate-from-azure-to-google-cloud/migrate-azure-sql-managed-instance-to-cloud-sql-sql-server
- [series] SQL DB: https://googlecloudplatform.github.io/cloud-solutions/migrate-from-azure-to-google-cloud/migrate-azure-sql-database-to-cloud-sql-sql-server
- [series] MySQL: https://googlecloudplatform.github.io/cloud-solutions/migrate-from-azure-to-google-cloud/migrate-azure-database-mysql-to-cloud-sql-mysql
- [series] PostgreSQL: https://googlecloudplatform.github.io/cloud-solutions/migrate-from-azure-to-google-cloud/migrate-azure-database-postgresql-to-cloud-sql-and-alloydb-postgresql
- STS Azure source: https://docs.cloud.google.com/storage-transfer/docs/source-microsoft-azure
- DMS supported databases: https://docs.cloud.google.com/database-migration/docs/supported-databases
- Filestore protocols: https://docs.cloud.google.com/filestore/docs/about-supported-protocols
- NetApp Volumes features: https://docs.cloud.google.com/netapp/volumes/docs/discover/features
- GKE Workload Identity Federation: https://docs.cloud.google.com/kubernetes-engine/docs/concepts/workload-identity
- Entra Workload Identity Federation: https://learn.microsoft.com/en-us/entra/workload-id/workload-identity-federation

## Compute path: M2VM, and what it will not take

The documented Azure path is Migrate to Virtual Machines with an **Azure source**
(https://docs.cloud.google.com/migrate/virtual-machines/docs/5.0/migrate/create-an-azure-source,
fetched 2026-08-06). Facts that shape both Design and the runbook:

- **Azure-side setup is four steps:** register an app in the Azure portal App Registration page, add a
  client secret (**copy the value at creation — it cannot be retrieved later** from the Azure portal or
  the Google Cloud console), create a custom role, and assign that role to the registered app.
- **Immutable at creation:** Google Cloud region, Azure location, Name, Subscription ID and Tenant ID.
  A typo in the region means the source never becomes Active and must be recreated.
- **Two unsupported disk attributes, quoted from the page's own list:** _ephemeral OS disks_ and
  _non-managed disks_. A VM with either fails migration — it is excluded from the automated wave and
  becomes a `needs-decision` row (`Q_M2VM`). Temporary-disk data is not guaranteed to survive clone or
  cutover.
- **There is no VM utilization report for Azure sources** — that feature is VMware/vCenter-only. Azure
  sizing evidence therefore comes from Migration Center (`mcdc`), Azure Monitor, or the user. Never from
  M2VM, and never from recall.
- **Scale caps** (from [series] VM guide): a maximum of 15 cloud sources (AWS + Azure combined) per host
  project; the VM Migration API must be enabled on the host project; a new source can take up to
  15 minutes to become Active.
- **Guest OS support** is per-source, with a separate "migration support only" bucket for guests that are
  EOL or not officially supported on Google Cloud — they migrate, but not all Compute Engine features
  work (https://docs.cloud.google.com/migrate/virtual-machines/docs/5.0/discover/supported-os-versions).
- **Azure Disk Encryption is NOT an M2VM blocker** — it is a high-friction card. ADE retires 2028-09-15
  and ADE-to-encryption-at-host migration is **not in place** (disabling ADE is unsupported on Linux OS
  disks, so they cannot be decrypted in-place; clean migration requires new disks via the Upload
  method), so an ADE estate should resolve encryption strategy before or during the move
  (https://learn.microsoft.com/en-us/azure/virtual-machines/disk-encryption-migrate).
- **Migrate to Containers does not accept Azure sources** — it takes VMs running on VMware or Compute
  Engine only, so containerization is a post-landing step after M2VM
  (https://docs.cloud.google.com/migrate/containers/docs/getting-started).

Discovery tooling on the Azure side: the Migration Center discovery client (`mcdc`) supports Azure VM
inventory discovery, still labelled **(Preview)** on the CLI overview page; it runs either from Azure
Cloud Shell with existing credentials (`--tenant`, `--host-credentials`) or from any machine using a
registered Azure app (`--client`/`--secret`). **Azure PowerShell is unsupported — Azure CLI only.**
Pair inventory discovery with guest discovery for a full assessment
(https://docs.cloud.google.com/migration-center/docs/discover-azure-vms,
https://docs.cloud.google.com/migration-center/docs/discovery-client-cli-overview,
https://docs.cloud.google.com/migration-center/docs/run-guest-discovery).

## Trade-off cards (definitions — the run fills the content)

Every card below is presented by `references/phases/clarify.md`. Each MUST carry, per option: the target
label, a URL fetched THIS run with its fetch date, cost shape, operational impact, rewrite/downtime
cost, and dealbreakers. **Do not copy option text out of this file into the card.**

- **`Q_MAP.appservice` — App Service.** Options: App Engine (Google's own comparison-table pairing) vs
  Cloud Run (container-native; same target the table gives Container Apps). Decide on: containerization
  effort, request/instance cost shape, VPC and scaling needs, and whether other tiers already land on
  Cloud Run. Fires once per distinct App Service plan, not per app. **Why Cloud Run is the unattended
  default:** it needs only the app to build into an image, whereas App Engine standard needs a supported
  runtime for that language and version — unverifiable in a headless run. It is the conservative pick, not
  the better one; App Engine is the recorded alternative an interactive user may well prefer.
- **`Q_MAP.aks` — AKS.** Options: GKE Autopilot vs GKE Standard. The [series] AKS guide describes both
  and mandates neither; it recommends the Kubernetes Cluster Discovery Tool (refined with Azure Resource
  Manager / Azure Resource Inventory) for discovery. Decide on: node-level control, DaemonSets and
  privileged workloads, GPU/Infiniband needs, and cost shape.
- **`Q_MAP.vmss` — VM Scale Sets.** Options: rebuild as a MIG with an instance template (default for
  cattle) vs per-VM M2VM (only for scale sets holding stateful pets). Note the source constraint: the
  orchestration mode "is defined when you create the scale set and cannot be changed or updated later"
  (https://learn.microsoft.com/en-us/azure/virtual-machine-scale-sets/virtual-machine-scale-sets-orchestration-modes),
  and Microsoft's availability-set-to-Flexible migration tooling is **not** a Uniform-to-Flexible
  converter — so the source's mode tells you nothing about the target shape.
- **`Q_MAP.postgres` — Azure Database for PostgreSQL Flexible Server.** Options: Cloud SQL for
  PostgreSQL vs AlloyDB for PostgreSQL. The [series] PostgreSQL guide targets both. Note the DMS
  scoping trap: Azure PostgreSQL Flexible Server 11+ is listed as a homogeneous DMS source **into
  Cloud SQL for PostgreSQL only** — it does not appear under the AlloyDB section.
- **`Q_MAP.cosmos` — Cosmos DB (MANDATORY card, one per account).** Candidate targets by API flavor:
  Firestore or Datastore (document), Bigtable (wide-column / Cassandra-shaped), Spanner (relational,
  global consistency), AlloyDB (Cosmos DB for PostgreSQL). **Gremlin and Table APIs have no candidate on
  the comparison table — record them as `Deferred — specialist engagement`.** Every option costs an
  application rewrite; there is no lift tool. The card must state the source API flavor, the consistency
  level in use, and the partition-key design, or say plainly that they are unknown.
- **`Q_MAP.files` — Azure Files (protocol-gated).** **Do not take the comparison table's
  Azure Files -> Filestore row at face value.** Filestore's supported-protocols page enumerates exactly
  NFSv3 and NFSv4.1 — phrase this as "Filestore supports only NFSv3 and NFSv4.1", which is an
  enumeration, not an explicit Google statement that SMB is unsupported. Google Cloud NetApp Volumes
  serves both NFS and SMB and is the SMB answer. NetApp Volumes SMB **requires Active Directory and does
  not support workgroup mode**, so an AD-authenticated SMB share pulls in Managed Service for Microsoft
  AD (or a trust) as a prerequisite — which couples this card to `Q_IDENTITY`
  (https://docs.cloud.google.com/netapp/volumes/docs/configure-and-use/active-directory/about-ad).
- **`Q_MAP.messaging` — Service Bus / Storage Queues.** Options: Pub/Sub (the comparison table's
  Service Bus **Messaging** pairing) vs Cloud Tasks (its Service Bus / Queue Storage pairing). The card
  MUST name the source features in use and verify each target's handling of them live: **sessions**
  (FIFO per session), **dead-letter queues**, scheduled/deferred delivery, duplicate detection, and
  transactions. These semantics are the whole decision — a queue using sessions and a queue used as a
  fan-out topic do not land in the same place.
- **`Q_MAP.keyvault` — Key Vault.** Split by content type: secrets/connection strings -> Secret Manager;
  keys and HSM-backed material -> Cloud KMS / Cloud HSM. Fires as a card when one vault holds both, or
  when the content type is unknown. **Secret values are never read, copied, or written into any run
  artifact** — the design records where a secret must be re-created, not the secret.
- **`Q_MAP.observability` — Application Insights / Azure Monitor.** The target is a set, not a product:
  Cloud Monitoring (metrics), Cloud Logging (logs), Cloud Trace (distributed traces), Cloud Profiler.
  The card decides the instrumentation route — OpenTelemetry SDK/agent vs re-instrumentation per
  language — and which alert rules and dashboards are in scope. Instrumentation is app-code work, so it
  is a `Q_SDK` dependency.
- **`Q_MAP.edge` — Front Door / CDN (rules gap).** Options: Cloud CDN behind an external Application
  Load Balancer, or Media CDN. The card MUST enumerate the source's rules engine, WAF policies, routing
  rules, and custom domains, and state plainly that **rules do not port** — each is rebuilt as a URL map,
  backend service, or Cloud Armor policy. Anything not enumerable from the source is a `# TODO(verify):`
  in Generate, never an invented rule.
- **`Q_MAP.apim` — API Management.** Options: API Gateway (lightweight, OpenAPI-driven) vs Apigee (full
  lifecycle, monetization, portals). Both appear on the comparison table.
- **`Q_MAP.logicapps` — Logic Apps.** Options: Workflows, Cloud Scheduler, or Application Integration and
  Integration Connectors. Connector coverage is the deciding factor and must be checked live per
  connector in use.
- **`Q_MAP.ai` — Azure OpenAI / Azure AI services.** Target is Vertex AI. Two sub-decisions: (1) the
  **compatibility route** — Vertex AI exposes an OpenAI-compatible Chat Completions endpoint, so an
  existing OpenAI-SDK call site can point at
  `https://{location}-aiplatform.googleapis.com/v1/projects/{project}/locations/{location}/endpoints/openapi`
  with `api_key` set to an **ADC-derived OAuth token, not a static key** — versus a native Vertex SDK
  rewrite; and (2) **model selection**, which is a live-research question every time. Note the
  comparison table pairs "Azure OpenAI Service" with Imagen, Veo and Lyria (generative media) and pairs
  the general platform as "Azure AI Platform -> Vertex AI" — do not read the media rows as the chat
  mapping. Sample source:
  https://docs.cloud.google.com/vertex-ai/generative-ai/docs/samples/generativeaionvertexai-gemini-chat-completions-non-streaming
- **`Q_MAP.search` — Azure AI Search.** Options: Agent Search, the comparison table's pairing, mid-rename
  from Vertex AI Search so verify the live name (https://docs.cloud.google.com/generative-ai-app-builder/docs),
  vs a self-managed vector store — Vector Search, or AlloyDB's `vector` and `alloydb_scann` extensions —
  when the index is only an embeddings store. **Nothing lifts:** there is no index transfer, so every
  option reindexes from the source of truth, and the ingestion model sets the rewrite scope — push apps
  re-point their upload calls, indexer pipelines are re-architected, since AI enrichment and integrated
  vectorization require the pull model and skillsets "are attached to indexers and don't run independently" (https://learn.microsoft.com/en-us/azure/search/search-what-is-data-import).

## Azure Functions: plan awareness (source-side, changes the target shape)

The hosting plan on the source decides how much of the function survives the move
(https://learn.microsoft.com/en-us/azure/azure-functions/functions-scale, fetched 2026-08-06):

- **Consumption (Y1) on Linux is retired-and-frozen** — retiring 2028-09-30, receiving no new features
  and no new language versions; the table shows Linux as Retired and Windows as GA (legacy). Migration
  to Flex Consumption is **not an in-place plan change** — Microsoft's own migration guide states "You
  must create a new app", with every route (CLI, portal, IaC) building a Flex Consumption app alongside
  the original and cutting over
  (https://learn.microsoft.com/en-us/azure/azure-functions/migration/migrate-plan-consumption-to-flex).
  A source still on Y1 Linux is a modernization case, not a lift: say so in the design rationale.
- **Flex Consumption is the current serverless plan** — Linux-only, scales to 1,000 instances, VNet
  integration, always-ready instances, 512/2048/4096 MB instance sizes.
- Other GA plans: Premium (Elastic Premium), Dedicated (App Service plan), and Container Apps.
- Nearer-term trap than the plan retirement: function apps on the **end-of-life v3 runtime on Linux in a
  Consumption plan stop running after 2026-09-30**.

## Microsoft licensing on Google Cloud (advisory facts for `Q_LICENSE`)

Loaded by `references/phases/clarify.md` Step 4. These are the rules, not a ruling: the skill states them,
names the evidence found in the estate, and routes the decision. **It never counts licences and never
asserts what a specific customer is entitled to.** Every fact below is re-verified in the run that
presents it.

1. **Google is a Listed Provider.** Microsoft's hosted-cloud licensing changes "exclude what we term
   Listed Providers: Alibaba, Amazon, Google, and Microsoft", and the stated remedy is that customers
   wanting a Listed Provider "can acquire licenses directly from the Listed Provider"
   (https://www.microsoft.com/en-us/licensing/news/options-for-hosted-cloud). The roster drifts, so cite
   **aka.ms/listedproviders** — or the Product Terms Glossary, which also defines Listed Providers —
   rather than hardcoding the four names.
2. **Flexible Virtualization Benefit does not reach Google Cloud shared infrastructure.** FVB permits
   shared servers only under an **Authorized Outsourcer**'s day-to-day management and control, and
   eligibility is gated on subscription licences or licences with active Software Assurance, including
   CALs (https://www.microsoft.com/licensing/terms/product/ForallSoftware/all — section "Outsourcing
   Software Management", subsection "Flexible Virtualization Benefit"). **Cite the conjunctive Authorized
   Outsourcer test from the Product Terms Glossary, NOT the FVB guidance page**: the Glossary defines an
   Authorized Outsourcer as a third-party provider "that is not a Listed Provider and is not using Listed
   Provider as a Data Center Provider as part of the outsourcing service"
   (https://www.microsoft.com/licensing/terms/product/Glossary/MOSA), whereas the FVB guidance page states
   the test with an "or" and therefore does not produce it.
3. **License Mobility through Software Assurance covers SQL Server, not Windows Server (the April 2026
   CSP carve-out below narrows this) — and it does NOT by itself require a sole-tenant node.** The
   eligible-product list leads with SQL Server, Exchange and SharePoint
   (https://www.microsoft.com/licensing/guidance/LicenseMobility), and Google states flatly that "Windows
   server is not covered under License Mobility because License Mobility only applies to server
   applications". On a Listed Provider, License Mobility rights "also apply to Listed Providers' Servers
   that are dedicated to Customer's use"
   (https://www.microsoft.com/licensing/terms/product/SoftwareAssuranceBenefits/all) — but **"dedicated"
   is not a synonym for sole-tenant node.** Google's FAQ: "Workloads covered by License Mobility don't
   necessarily need to be placed on sole-tenant nodes", provided "The instance is solely dedicated to
   your use" AND "The underlying operating system does not require a sole-tenant node"
   (https://docs.cloud.google.com/compute/docs/instances/windows/ms-licensing-faq). Its worked example
   settles it: BYOL SQL Server on a Google license-included Windows Server image needs **no**
   sole-tenancy; the same SQL Server on a **BYOL** Windows Server image does — the OS licence drags in
   sole-tenancy, not the SQL Server one. Eligibility is a **per-licence designation**, not a
   product-family assumption.
4. **Azure Hybrid Benefit cannot follow the workload.** AHB "is an Azure offer"
   (https://azure.microsoft.com/en-us/pricing/hybrid-benefit/), and the entitlement is bounded by the
   Software Assurance or subscription term, so a lapse mid-migration removes it on the Azure side too
   (https://learn.microsoft.com/en-us/azure/virtual-machines/windows/hybrid-use-benefit-licensing).
5. **What Google Cloud actually offers.** Compute Engine license-included (premium) Windows Server images
   bundle the Microsoft licence into the hourly compute rate, and Google's own docs state that Windows
   Server BYOL requires sole-tenant nodes because "Microsoft doesn't allow the use of Outsourcing Software
   Management right in a multi-tenant environment"
   (https://docs.cloud.google.com/compute/docs/instances/windows/ms-licensing). **State the vintage gate
   from that same page alongside the sole-tenant requirement:** OSM Rights apply to legacy licences only —
   "The license covers a Microsoft product version released before October 1, 2019" AND was acquired
   "under an enrollment effective before October 1, 2019". The page states the consequence outright, so
   assert it rather than inferring it: **"Windows Server 2022 is not eligible."** Sole-tenant nodes are
   Google's dedicated-hardware construct (https://docs.cloud.google.com/compute/docs/nodes/bringing-your-own-licenses).
   Prebuilt SQL Server images have Google manage and bill both the Windows Server and SQL Server licences
   (https://docs.cloud.google.com/compute/docs/instances/sql-server/creating-sql-server-instances), and
   Cloud SQL for SQL Server charges a core licence per vCPU with a **four-core minimum per instance**, so
   small instances pay a disproportionate licence fee (https://docs.cloud.google.com/sql/docs/sqlserver/faq).
6. **A BYOL licence is pinned to its region for 90 days.** Google: "After deploying a license within a
   region, you cannot move that license to another region for 90 days"
   (https://docs.cloud.google.com/compute/docs/instances/windows/ms-licensing). The restriction comes from
   Microsoft's License Mobility reassignment terms — re-verify it in the Product Terms in the run that
   quotes it. **A wave-planning constraint, not a footnote:** a BYOL row landed in the wrong region cannot
   be re-homed for a quarter, so `Q_REGION` and `Q_LICENSE` must be answered together.

**April 2026 CSP change — surface it when CSP purchasing is in evidence.** Effective 2026-04-01, Windows
Server **and** SQL Server **subscriptions** under the Microsoft Customer Agreement bought through CSP
gain License Mobility rights "equivalent to Software Assurance in legacy Volume Licensing", automatically
and with no partner or customer action — while "CSP perpetual licenses remain unchanged and don't gain
License Mobility" (https://learn.microsoft.com/en-us/partner-center/announcements/2026-april). State both
halves of the tension and resolve neither. The announcement **names Windows Server**, so the skill must
not call Windows Server License-Mobility-ineligible as a product; but the grant is scoped to "eligible
server application workloads in shared environments and with authorized outsourcing partners", and
Google separately states Windows Server is not covered because License Mobility "only applies to server
applications". Whether a Windows Server OS licence practically benefits is exactly the specialist
question this skill does not answer. Unchanged: the Listed Provider roster, and the Product Terms'
dedicated-server condition on License Mobility at a Listed Provider. Route it to `Q_LICENSE`.

**Two claims this skill must never make.** That Cloud SQL for SQL Server has no BYOL option — **UNVERIFIED**,
no official sentence states it, and the pricing pages could not be rendered to confirm. And that any
specific licence the customer holds is or is not portable — that is a licensing specialist's call.

## FACTS THAT GO STALE (re-verify live in every run that relies on them)

Each row was true at its `fetched_at` and WILL drift. Quoting a row without a same-run live fetch is a
degradation recorded through the existing mechanism: append a `corrected` entry (the fact was re-used
unverified) or `skipped` entry (the lookup was attempted and failed) to `validation-ledger.json` for the
phase that quoted it, and add a `[STALE_FACT]` warning naming the row to the artifact that used it.

| Claim (snapshot)                                                                                            | Re-verify at                                                                                                                                            | fetched_at   |
| ----------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------ |
| The whole Azure -> GCP service pairing table                                                                | https://docs.cloud.google.com/docs/get-started/aws-azure-gcp-service-comparison                                                                         | 2026-08-06   |
| Per-workload guides live on googlecloudplatform.github.io, not cloud.google.com; index page remains         | https://docs.cloud.google.com/architecture/migration-from-azure-get-started                                                                             | 2026-08-06   |
| M2VM Azure source: unsupported disk attributes, immutable fields, no utilization report                     | https://docs.cloud.google.com/migrate/virtual-machines/docs/5.0/migrate/create-an-azure-source                                                          | 2026-08-06   |
| M2VM guest-OS buckets incl. "migration support only"                                                        | https://docs.cloud.google.com/migrate/virtual-machines/docs/5.0/discover/supported-os-versions                                                          | 2026-08-06   |
| DMS Azure source lists; the SQL Server homogeneous table has no Azure source                                | https://docs.cloud.google.com/database-migration/docs/supported-databases                                                                               | 2026-08-06   |
| Azure discovery in mcdc is Preview; Azure CLI only                                                          | https://docs.cloud.google.com/migration-center/docs/discover-azure-vms                                                                                  | 2026-08-06   |
| Filestore protocol list (NFSv3, NFSv4.1)                                                                    | https://docs.cloud.google.com/filestore/docs/about-supported-protocols                                                                                  | 2026-08-06   |
| NetApp Volumes SMB requires AD, no workgroup mode                                                           | https://docs.cloud.google.com/netapp/volumes/docs/configure-and-use/active-directory/about-ad                                                           | 2026-08-06   |
| Vertex OpenAI-compatible endpoint shape and auth                                                            | https://docs.cloud.google.com/vertex-ai/generative-ai/docs/samples/generativeaionvertexai-gemini-chat-completions-non-streaming                         | 2026-08-06   |
| Functions plan status (Y1 Linux retiring 2028-09-30; v3 Linux Consumption stops 2026-09-30)                 | https://learn.microsoft.com/en-us/azure/azure-functions/functions-scale                                                                                 | 2026-08-06   |
| AI Search ingestion: push vs indexer, and skillsets running only under the pull model                       | https://learn.microsoft.com/en-us/azure/search/search-what-is-data-import                                                                               | 2026-08-06   |
| Azure Disk Encryption retirement 2028-09-15 and the not-in-place migration                                  | https://learn.microsoft.com/en-us/azure/virtual-machines/disk-encryption-migrate                                                                        | 2026-08-06   |
| Migrate to Containers source list (VMware / Compute Engine only)                                            | https://docs.cloud.google.com/migrate/containers/docs/getting-started                                                                                   | 2026-08-06   |
| Microsoft Product Terms: Listed Providers, FVB, License Mobility, the April 2026 CSP change                 | https://www.microsoft.com/licensing/terms/product/Glossary/MOSA plus every URL in the licensing section above                                           | 2026-08-06   |
| Windows/SQL on Google Cloud: license-included images, sole-tenant BYOL, the pre-2019 vintage gate           | https://docs.cloud.google.com/compute/docs/instances/windows/ms-licensing                                                                               | 2026-08-06   |
| License Mobility vs sole-tenancy (the conditional test and its worked example), the 90-day region lock      | https://docs.cloud.google.com/compute/docs/instances/windows/ms-licensing-faq                                                                           | 2026-08-06   |
| FOCUS column semantics: 1.2-preview renames, the "Currently null/empty" commitment columns, half-open dates | https://learn.microsoft.com/en-us/azure/cost-management-billing/dataset-schema/cost-usage-details-focus — `ms.date` 2025-06-26, `updated_at` 2025-10-09 | 2026-08-06   |
| Any GCP price or SKU                                                                                        | the pricing chain in `references/phases/estimate.md`                                                                                                    | never cached |

**Naming drift to expect:** `cloud.google.com/*` now 301-redirects to `docs.cloud.google.com/*`; the Vertex
AI generative-AI docs are being renamed to "Gemini Enterprise Agent Platform" under a
`docs.cloud.google.com/gemini-enterprise-agent-platform/...` prefix while the old URLs still resolve;
"Vertex AI Search is being renamed to Agent Search" (console: AI Applications); GKE "Workload Identity" is
now "Workload Identity Federation for GKE". Prefer the new names, accept the old URLs, and re-verify.
