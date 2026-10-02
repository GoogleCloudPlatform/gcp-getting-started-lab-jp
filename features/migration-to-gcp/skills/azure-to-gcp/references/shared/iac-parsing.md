# Azure Source Parsing Rules (ARM, Bicep, Terraform azurerm, exports)

**Loaded by:** `references/phases/discover.md`. Everything here is read with the Read, Grep and Glob
tools in context. **Helper parser scripts are BANNED** (see the banned-stem list in `SKILL.md`); the one
sanctioned exception is the cost-extraction helper described in
`references/shared/billing-exports.md`.

Facts below were verified 2026-08-06 against learn.microsoft.com and, for the Terraform provider,
against the Terraform Registry's own JSON docs API pinned to **hashicorp/azurerm 5.0.1** (published
2026-07-30). Registry HTML pages are client-side rendered and return no usable body to a fetch, so
`registry.terraform.io/v2/provider-docs/<id>` is the citable surface; the human-readable page URL is
given for each resource.

## Dialect 1 — ARM templates (JSON)

**Two shapes for `resources`, and a parser must handle both.** By default `resources` is a JSON array of
resource objects. When `languageVersion` is `2.0` or newer, `resources` becomes an **object keyed by
Bicep-style symbolic name**
(https://learn.microsoft.com/en-us/azure/azure-resource-manager/templates/syntax). Detect
`languageVersion` first; branch on it before iterating.

**Copy loops.** A `copy` element inside a resource carries `name`, `count`, and optional `mode`
(`serial` or `parallel`, default parallel) and `batchSize`. `copyIndex()` is zero-based and can be
offset as `copyIndex(n)`. Count cannot exceed 800. `copy` also applies to properties, variables and
outputs (https://learn.microsoft.com/en-us/azure/azure-resource-manager/templates/copy-resources).

- Record a looped resource as **one inventory row per iteration when `count` resolves statically**, else
  ONE row with `"count": "<unresolved expression>"` and a `[PARTIAL_IAC]` warning. Never silently emit a
  single row for a loop of unknown size.
- **Copy cannot be applied to a nested child resource.** To create multiple child instances the child is
  hoisted to a top-level resource with a fully qualified type
  (`namespace/parent-type/child-type`) and a name of the form `parent-name/child-name` (same URL). So a
  slash in `type` or `name` is the signal that you are looking at a hoisted child, not a top-level
  resource — attribute it to its parent.

**Expression opacity — the single biggest source of false confidence.** `parameters('x')` and
`variables('y')` dereference declared sections; `reference(...)` resolves only at deploy time and its
return shape "highly relies on how each resource provider implements its PUT and GET responses"
(https://learn.microsoft.com/en-us/azure/azure-resource-manager/templates/template-functions-resource,
https://learn.microsoft.com/en-us/azure/azure-resource-manager/templates/template-functions-deployment).
Rules:

1. Resolve `parameters()` from the template's `parameters` section `defaultValue`, or from a supplied
   parameters file. No default and no file -> the field is `null` plus
   `[UNRESOLVED_SOURCE_FIELD] <resource>: <expression>`.
2. Resolve `variables()` transitively, giving up (with the same warning) on any expression that touches
   `reference()`, `listKeys()`, `newGuid()`, `utcNow()` or a resource id you have not parsed.
3. **Never evaluate a `reference()` expression.** Its value does not exist in the template text.
   `languageVersion 2.0` additionally adds `references()`, returning an array for a copy-loop collection.

**Nested vs linked templates.** Both are a `Microsoft.Resources/deployments` resource: a **nested**
template embeds the child under `properties.template`; a **linked** template points outward via
`properties.templateLink.uri` or `templateLink.relativePath`
(https://learn.microsoft.com/en-us/azure/azure-resource-manager/templates/linked-templates).

- Nested: recurse into `properties.template` and inventory its resources too.
- Linked with `relativePath`: resolve against the parent's directory and parse if the file is in the
  project. Linked with an absolute `uri`: **do not fetch it** — record
  `[PARTIAL_IAC] linked template not in project: <uri>`.
- Nested templates carry `expressionEvaluationOptions.scope` of `inner` or `outer`, which changes how
  parameters and variables resolve. Default is `outer`; under `languageVersion 2.0` the default flips to
  `inner` and `outer` is blocked. With `inner` scope, the parent's variables are NOT visible to the
  nested template — resolving them anyway produces wrong values, so scope must be checked before any
  cross-boundary resolution.

## Dialect 2 — Bicep

**Resource declarations:** `resource SYMBOLIC-NAME 'TYPE@API-VERSION' = { ... }`. **The symbolic name is
not the resource name.** It is the cross-reference handle; the deployed name is the `name` property.
Symbolic names are case-sensitive, allow letters/digits/underscores, and cannot start with a digit
(https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/resource-declaration). Writing the
symbolic name into `azure-inventory.json.name` is a parsing bug; put it in `source_ref`.

**`existing` marks a lookup, not a deployment:**
`resource stg 'Microsoft.Storage/storageAccounts@2025-06-01' existing = { name: 'examplestorage' }`
supplies only `name` plus an optional `scope`
(https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/existing-resource).
**Exclude `existing` declarations from the created-resource inventory.** They are still useful: record
them separately as dependency evidence (something outside this template is being consumed), which often
reveals estate the IaC does not create — a `[PARTIAL_IAC]` signal.

**Modules:** `module SYMBOLIC-NAME 'PATH' = { name: ..., params: {...} }`, where `PATH` may be a local
`.bicep` file, a local ARM JSON template, a **registry reference** (`br/public:` or
`br:REGISTRY.azurecr.io/...`), or a template spec (`ts:`). Modules compile to ARM nested templates and an
optional `scope` retargets the deployment
(https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/modules).

- Local path -> recurse and parse.
- **Registry or template-spec reference -> do NOT resolve.** Record
  `[PARTIAL_IAC] module contents not in project: <ref>` and capture the `params` block verbatim as
  evidence of what the module is being asked to create. A registry module frequently hides the majority
  of an estate; understating this is worse than admitting it.

**Loops — five syntactic forms**, all in square brackets after `=`
(https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/loops):
`for i in range(start, count)`, `for item in collection`, `for item in items(object)`,
`for (item, index) in collection`, and the loop-plus-condition form
`for item in collection` with a trailing `if(condition)`. Iterations cap at 800; the `batchSize`
decorator forces serial deployment. Same counting rule as ARM copy loops.

**Conditions:** an `if` expression sits between `=` and the body, e.g.
`resource dnsZone 'Microsoft.Network/dnsZones@2023-07-01-preview' = if (deployZone) { ... }`, and works
identically on modules. **The condition does not cascade to child resources** — each child repeats it
(https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/conditional-resource-deployment).
A conditional resource whose condition cannot be resolved statically is inventoried with
`"conditional": "<expression>"` and a `[PARTIAL_IAC]` warning — never dropped, never assumed deployed.

## Dialect 3 — Terraform `azurerm` (5.0.1 current names, plus legacy names still found in source)

**Current resources to expect** (all documented in 5.0.1):

| Area            | Current resource names                                                                                                                                                                                          |
| --------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| VMs             | `azurerm_linux_virtual_machine`, `azurerm_windows_virtual_machine`                                                                                                                                              |
| Scale sets      | `azurerm_orchestrated_virtual_machine_scale_set` (**Flexible**), `azurerm_linux_virtual_machine_scale_set` / `azurerm_windows_virtual_machine_scale_set` (**Uniform only**)                                     |
| Web / functions | `azurerm_service_plan` + `azurerm_linux_web_app` / `azurerm_windows_web_app`; `azurerm_linux_function_app` / `azurerm_windows_function_app`                                                                     |
| Containers      | `azurerm_kubernetes_cluster`, `azurerm_container_app` (needs `container_app_environment_id` and a `template` block)                                                                                             |
| Data            | `azurerm_mssql_server` + `azurerm_mssql_database`, `azurerm_postgresql_flexible_server`, `azurerm_mysql_flexible_server`, `azurerm_storage_account`, `azurerm_cosmosdb_account`, `azurerm_servicebus_namespace` |
| AI              | `azurerm_cognitive_account` (Azure OpenAI is `kind = "OpenAI"`), `azurerm_cognitive_deployment`, `azurerm_search_service` (AI Search)                                                                           |

**Orchestration mode is encoded in the resource name, not an argument.** The split took effect in
provider v2.86.0: `azurerm_linux_virtual_machine_scale_set` and `azurerm_windows_virtual_machine_scale_set`
create **Uniform** scale sets only; **Flexible** requires
`azurerm_orchestrated_virtual_machine_scale_set`
(https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/linux_virtual_machine_scale_set).
Record the mode on the inventory row — it is not recoverable later.

**Legacy names: still parsed as SOURCE, never emitted as TARGET.**

| Legacy name                                         | Status in 5.0.1                                                   | Parse it because                                                                                                                                                                                                                                                                |
| --------------------------------------------------- | ----------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `azurerm_virtual_machine`                           | **Still documented**, superseded and feature-frozen — not removed | Only resource supporting unmanaged disks and attaching a pre-existing OS disk, so it is exactly where `[UNMANAGED_DISK]` lives. **A parse-side fact only** — the platform retired unmanaged disks 2026-03-31 (cannot start), so Design/Generate must never emit or preserve one |
| `azurerm_virtual_machine_scale_set`                 | Present but **explicitly deprecated with removal announced**      | Older scale-set configs                                                                                                                                                                                                                                                         |
| `azurerm_app_service`, `azurerm_app_service_plan`   | **Absent from 5.0.1 docs**                                        | Older web-app configs                                                                                                                                                                                                                                                           |
| `azurerm_function_app`                              | **Absent from 5.0.1 docs**                                        | Older function configs                                                                                                                                                                                                                                                          |
| `azurerm_sql_server`, `azurerm_sql_database`        | **Absent from 5.0.1 docs**                                        | Older SQL configs                                                                                                                                                                                                                                                               |
| `azurerm_postgresql_server`, `azurerm_mysql_server` | **Absent from 5.0.1 docs**                                        | Single Server-era configs                                                                                                                                                                                                                                                       |

Source for the feature-frozen wording:
https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/virtual_machine —
"The existing `azurerm_virtual_machine` resource will continue to be available however is in a
feature-frozen state to maintain compatibility." Absence was **tested, not inferred**: for
`azurerm_app_service`, `azurerm_app_service_plan` and `azurerm_function_app` the identical registry query
returns 1 doc each against azurerm 4.81.0 and 0 against 5.0.1, which distinguishes genuine removal from a
mistyped slug. The remaining legacy names come from the 5.0.1 docs index without that control — treat
them as absent but re-check before asserting it to a user.

**Binding rule:** Discover MUST recognise every legacy name above. **Generate MUST NEVER emit one** —
this skill generates Google Cloud Terraform, and any Azure-side snippet it writes for reference uses
current names only.

**Cross-fact collision guard — two true facts about different layers.** `azurerm_virtual_machine` still
**models** unmanaged disks in 5.0.1 (a Terraform provider fact; its replacement states "This resource
does not support Unmanaged Disks. If you need to use Unmanaged Disks you can continue to use the
`azurerm_virtual_machine` resource instead"), while the Azure platform **retired** unmanaged disks on
2026-03-31 (a platform fact — see the detection rule below). Both hold at once: the resource exists, but
what it provisions can no longer start. So parse such a config as **legacy inventory and flag it**, and
**never read provider support as licence to design, generate or fixture an unmanaged-disk VM.**

**Two more `azurerm` facts worth not getting wrong:** `azurerm_ai_foundry` and
`azurerm_ai_foundry_project` exist but are the **legacy hub-based Foundry** under the Machine Learning
subcategory, explicitly called legacy by HashiCorp and **not** the Azure OpenAI resource; there is no
`azurerm_ai_services` resource. Current Foundry and Azure OpenAI are both provisioned via
`azurerm_cognitive_account`
(https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/ai_foundry).

## Cross-dialect detection rules

### Ephemeral OS disk (M2VM-ineligible — `[EPHEMERAL_OS_DISK]`)

One property, three spellings. ARM JSON and Bicep share the rule; `azurerm` differs only in casing.

| Dialect   | Where to look                                                                                             | Shape                                                                                                                                                       |
| --------- | --------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------- |
| ARM JSON  | `properties.storageProfile.osDisk.diffDiskSettings` (VMSS: `virtualMachineProfile.storageProfile.osDisk`) | `option: "Local"`, `placement: "ResourceDisk" \| "CacheDisk"`; sibling `caching` must be `ReadOnly`                                                         |
| Bicep     | same property path and names as ARM                                                                       | `diffDiskSettings` with `enableFullCaching` (**public preview**, needs api-version 2025-04-01+), `option`, `placement`; `placement` also allows `NvmeDisk`  |
| Terraform | `diff_disk_settings` block nested inside the `os_disk` block                                              | `option` accepts only `Local`; `placement` accepts `CacheDisk`, `ResourceDisk`, `NvmeDisk` (default `CacheDisk`); settable only when `caching = "ReadOnly"` |

Sources: https://learn.microsoft.com/en-us/azure/virtual-machines/ephemeral-os-disks-deploy,
https://learn.microsoft.com/en-us/azure/templates/microsoft.compute/virtualmachines?pivots=deployment-language-bicep,
https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/linux_virtual_machine.
Grep both `diffDiskSettings` and `diff_disk_settings` on every run; a hit is an automatic
`needs-decision` row via `Q_M2VM`.

Two `azurerm` constraints that make a config invalid rather than merely unusual, worth naming when one
appears: `NvmeDisk` placement is documented for **v6 VM sizes only, in combination with a supported
`source_image_reference`**, and `diff_disk_settings` **cannot be set when the VM is built from an
existing managed disk** via `os_managed_disk_id`. Also: Microsoft's own full-caching sample on the
ephemeral-OS-disks page has a doc bug — it nests `hardwareProfile` inside `storageProfile`. Never copy
that sample verbatim into a fixture or a snippet shown to a user.

### Unmanaged disk (`[UNMANAGED_DISK]`)

Signals: `azurerm_virtual_machine` with a `storage_os_disk`/`storage_data_disk` block carrying `vhd_uri`;
ARM/Bicep `osDisk.vhd.uri` or `dataDisks[].vhd.uri`. Unmanaged disks were **fully retired 2026-03-31**
(extended from 2025-09-30): after that date IaaS VMs using them **cannot be started**, and running or
allocated ones are **stopped and deallocated**
(https://learn.microsoft.com/en-us/azure/virtual-machines/unmanaged-disks-deprecation).

**Word the rule as "workloads must not rely on unmanaged disks (cannot start since 2026-03-31)", never
as "the API rejects creation".** The documented prohibition is on starting and on continuing to run; the
page nowhere says creation is blocked, and it points readers to support for "help with adding
subscriptions to the allow list", so a support-mediated allow list exists. Page blobs used directly over
the REST APIs are explicitly unaffected — do not flag those. Two consequences to state: the VM is
M2VM-ineligible, **and** the source-side estate has a live problem independent of the migration.

### Storage TLS (`[TLS_LEGACY]`)

Flag a storage account when `minimumTlsVersion` / `min_tls_version` is **absent** or below `TLS1_2`.
Absence matters: the portal sets 1.2 at creation, but PowerShell, Azure CLI and ARM templates leave
`MinimumTlsVersion` unset by default, and "The storage account will permit requests sent with TLS version
1.0 or greater if the property is not set"
(https://learn.microsoft.com/en-us/azure/storage/common/transport-layer-security-configure-minimum-version).
So an IaC file that simply omits the property is not automatically compliant. Azure
Storage stopped supporting TLS 1.0/1.1 on **2026-02-03**, enforced at the storage-account level and
therefore covering Files, Queue and Table too
(https://learn.microsoft.com/en-us/azure/storage/common/transport-layer-security-configure-migrate-to-tls2).

### Scale-set validity trap

"Overprovisioning is supported for Uniform Orchestration mode only; it is not supported for Flexible
Orchestration mode"
(https://learn.microsoft.com/en-us/azure/virtual-machine-scale-sets/virtual-machine-scale-sets-design-overview).
The **Unsupported parameters** list that also rules out image-based automatic OS upgrades, unmanaged
disks, Basic Load Balancer, Standard Load Balancer NAT pools and system-assigned managed identity lives
on the orchestration-modes page, not on design-overview
(https://learn.microsoft.com/en-us/azure/virtual-machine-scale-sets/virtual-machine-scale-sets-orchestration-modes).
A template setting overprovision on a Flexible scale set is invalid — record it as an inventory warning,
not as a fact about the running estate.

## Non-IaC sources

### App code / SDK scan

Glob the project for source files, then Grep for the detection patterns in
`references/shared/sdk-map.md`. Record one entry per (file, pattern) hit with the file path and line.
App-code hits create inventory rows with `source: "app-code"` **only for services with no IaC or export
evidence** — otherwise they enrich the existing row. A dependency manifest (`requirements.txt`,
`package.json`, `*.csproj`, `pom.xml`, `go.mod`) counts as a hit, and is often the only signal that a
service exists at all.

### Cost / usage export

Detection and parsing live in `references/shared/billing-exports.md`.

### Azure Migrate assessment export

An Azure VM assessment is exported from the assessment view as an **Excel file** via **Export
assessment**; it carries per-VM Azure readiness, monthly compute/storage cost estimation, and per-VM
compute/storage/network settings plus an `Issues` column
(https://learn.microsoft.com/en-us/azure/migrate/tutorial-assess-vmware-azure-vm?view=migrate).
Rules that keep this parse honest:

- **Google publishes no column contract, and neither does Microsoft.** The docs describe the workbook's
  _content_ but never list literal column headers or sheet names. Match headers **tolerantly and
  case-insensitively**; when an expected column is absent, warn naming the column and file, set `null`,
  and continue. **NEVER tell the user a column is "required".**
- **Readiness strings vary between official pages** — the VMware assessment tutorial says
  "Ready with conditions" while the assessment-report concept page says "Conditionally ready for Azure".
  Match on a normalized lowercased prefix (`ready for`, `ready with` / `conditionally ready`,
  `not ready`, `readiness unknown`), never on an exact string.
- **Blank size/cost cells are expected, not corrupt.** Calculation runs strictly readiness -> sizing ->
  cost, and a server failing readiness is marked unsuitable and receives no sizing or cost values.
- Cost estimates cover running on-premises VMs as Azure VMs and exclude PaaS/SaaS costs — they are
  Azure-target estimates, so they are **never** a GCP cost input. They are useful only as sizing evidence
  and as a readiness signal.
- The newer Azure Migrate **Reports** experience is a different artifact — exportable read-only
  PowerPoint/Excel summaries, not the per-VM row-level workbook. If per-VM rows are needed, ask for
  **Export assessment** on an assessment.
- Performance-based sizing carries a performance coverage rating that is **not assigned** for
  CSV-imported servers or as-is sizing; treat its absence as "no perf data", not "poor perf data".

### `az resource list` JSON

The ARM `Resources - List` operation returns a `value` array plus `nextLink`, with each entry exposing
`id`, `name`, `type`, `location`, `tags`, `kind`, `sku`, `identity`, `plan`, `properties`, `managedBy`
and `extendedLocation`. **`createdTime`, `changedTime` and `provisioningState` are not returned by
default** — they require `$expand`. Nested shapes: `sku` has `capacity`/`family`/`model`/`name`/`size`/
`tier`; `identity` has `principalId`/`tenantId`/`type`/`userAssignedIdentities`
(https://learn.microsoft.com/en-us/rest/api/resources/resources/list).

> **UNVERIFIED INFERENCE — carry this caveat.** That the `az resource list` CLI returns _exactly_ the
> `GenericResourceExpanded` shape is an inference from the CLI wrapping the REST API; the CLI reference
> page was not fetched. Parse tolerantly and confirm against
> https://learn.microsoft.com/en-us/cli/azure/resource before relying on any field being present.

Two collection caveats worth passing to the user: filtering by tag name and value causes the original
tags **not** to be returned, and Azure Resource Graph (`Resources` is the default table) adds
`subscriptionId`, `resourceGroup` and `tenantId` columns the plain ARM list API does not project, with
limits of 3 `join` and 3 `mv-expand` per query and 10,000 subscriptions per management-group scope
(https://learn.microsoft.com/en-us/azure/governance/resource-graph/concepts/query-language).
