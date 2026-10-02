# Phase 2: Clarify Requirements (Azure -> GCP)

**Phase 2 of 5** — turn Discover's inventory into explicit, user-owned decisions. Every mapping with 2+
viable options is asked HERE and recorded in `preferences.json`; a decision not recorded there may not
shape `gcp-design.json`. **Execute ALL steps in order.**

> **HARD GATE — Clarify before Design (no exceptions):** do not load `references/phases/design.md` or any
> later phase until this phase finishes AND `.phase-status.json` records `phases.clarify` as
> `"completed"`. Writing `preferences.json` without updating phase status is a protocol violation.
>
> **Clarify completes either way:** interactive (present cards, STOP, wait) or headless (apply the
> dispositions in the `SKILL.md` table — never stall). If the user says "skip the questions" / "use all
> defaults", apply the same dispositions with `chosen_by: "user-requested-default"` and still complete
> the phase. There is no path that skips Clarify.

## Step 0: Prior Run Check

If `$MIGRATION_DIR/preferences.json` already exists, ask: **A)** reuse it, **B)** re-answer. On A: run the
Validation Checklist below against it — if it passes, emit the Step 12 summary rebuilt from the reused
file (including the MANDATORY "Headless assumptions" block whenever `headless_defaults_applied[]` is
non-empty), then jump to Step 13; if any check fails, say which and continue at Step 1. Headless: reuse only if it passes, else regenerate.

## Step 1: Read Discovery Artifacts

1. Read `$MIGRATION_DIR/azure-inventory.json` (required) plus `azure-cost-profile.json` and
   `adjacent-services.json` (optional but expected).
2. **STOP** if `azure-inventory.json` is missing or `.phase-status.json` lacks
   `phases.discover: "completed"` — output "Run Discover first." and end the turn. Never fabricate an
   inventory. **A partial inventory is NOT a STOP:** empty `resources: []` with a `[PARTIAL_INVENTORY]`
   warning is accepted — proceed, but `Q_SIZING` escalates to the user and the summary must state that
   per-resource design is unavailable until inventory data is provided.
3. Bucket Discover's `warnings[]` by tag — the tags decide which cards fire — then present a short
   discovery summary: resource counts by type, monthly Azure spend and its `cost_basis`, warning counts
   per tag, and each `adjacent-services.json` item with the gate it arms.
4. **Scope re-check (GATE 7):** confirm every discovered source is in scope against `SKILL.md`'s "Do not use for" list; refuse any that is not, by name, with its correct destination skill. This is the gate's firing point and produces the `clarify/scope-gate` ledger entry — record `in-scope` when nothing is refused.

## Step 2: Live Research Pass (populates every card)

Card content MUST be researched at run time — **never copied from these files**. These files fix each
card's REQUIRED fields and its dated floor facts, nothing more. Per fact, try in order: Google-side
(1) `google-developer-knowledge` MCP -> (2) WebSearch -> (3) WebFetch of
`docs.cloud.google.com`/`cloud.google.com`; Azure-side (1) `microsoft-learn` MCP -> (2) WebFetch of
`learn.microsoft.com`/`azure.microsoft.com`. Cite the fetched URL + date inline in the card. If all tiers
fail for a fact, use the floor fact labelled `UNREFRESHED (floor fact, verified 2026-08-06)`, record the
failure per the visible-degradation protocol, and never invent a figure or silently continue.

## Step 3: Q_IDENTITY — Identity adjacency (GATE 1; fires on any `identity` item or Entra/AD signal)

```text
Q_IDENTITY: How should Azure identity be handled?
  [A] Federate Entra ID with Cloud Identity (DEFAULT) — Entra ID stays the IdP; users and optionally
      groups are auto-provisioned to Cloud Identity/Workspace with SAML SSO. Migrating the IdP itself
      is a separate project and is NOT in this migration's scope.
  [B] Add Managed Service for Microsoft AD — required when AD-joined VMs, Kerberos/LDAP apps, or an
      SMB file share with AD authentication must keep working.
  [C] Re-platform identity — replace AD/Entra dependencies with Google-native IAM. Specialist scope.
  [D] Defer — record "Deferred — specialist engagement".
```

Floor facts (refresh them, cite what you fetched):

- Google publishes an official Entra ID -> Cloud Identity/Workspace provisioning + SAML SSO guide, and
  notes that with the **free** Cloud Identity edition setting up federation with Entra ID does not use
  billable components (https://docs.cloud.google.com/architecture/identity/federating-gcp-with-azure-ad-configuring-provisioning-and-single-sign-on;
  editions at https://docs.cloud.google.com/identity/docs/editions).
- The alternative, **Workforce Identity Federation**, federates Entra ID directly over OIDC or SAML with
  no Cloud Identity accounts provisioned; the standard guide maps up to 100 Entra groups
  (https://docs.cloud.google.com/iam/docs/workforce-sign-in-microsoft-entra-id).
- **Managed Service for Microsoft AD runs actual Microsoft AD domain controllers** on Windows VMs
  operated by Google — not an emulation — and supports a forest-level trust to existing on-premises AD
  (https://docs.cloud.google.com/managed-microsoft-ad/docs/overview).
- **Workload identity is a separate axis from user identity.** Entra Workload Identity Federation
  explicitly supports GKE, so an AKS pod's federated-credential pattern survives the move and can still
  reach Entra-protected resources (https://learn.microsoft.com/en-us/entra/workload-id/workload-identity-federation).
  Say this out loud — teams routinely assume moving off AKS breaks their Entra-protected calls.

Interpret -> `identity_strategy`. **[B] is additive, not exclusive** — record it alongside [A] when both
apply, and note the coupling to `Q_MAP.files` when an SMB share needs AD.
**Headless:** `"Federate Entra ID with Cloud Identity — IdP migration deferred"`.

## Step 4: Q_LICENSE — Microsoft licensing (GATE 2; ADVISORY ONLY; fires on any `licensing` item)

This card **never** asserts what the customer is entitled to and **never** counts licences. It states the
rules, names the evidence found, and routes the decision.

**Load the "Microsoft licensing on Google Cloud" section of `references/shared/service-map.md` NOW** and
present all six of its facts, each re-verified this run with its citation: (1) Google is a Listed
Provider; (2) FVB does not reach Google Cloud shared infrastructure — cite the **Product Terms Glossary**
for the conjunctive Authorized Outsourcer test; (3) License Mobility covers SQL Server but not Windows
Server and does **not** by itself force sole-tenancy — Google's FAQ says such workloads "don't
necessarily need to be placed on sole-tenant nodes"; (4) Azure Hybrid Benefit is Azure-only and cannot
follow the workload; (5) license-included images, the pre-2019-vintage sole-tenant gate that **Windows
Server** BYOL triggers (not SQL Server BYOL), and Cloud SQL for SQL Server's four-core minimum; (6) the
90-day region lock on a deployed BYOL licence. Surface the April 2026 CSP change when CSP is in evidence.

Two things this card must NOT say: that Cloud SQL for SQL Server has no BYOL option (**unverified** — no
official sentence states it), and that any specific licence the customer holds is or is not portable.

```text
Q_LICENSE: How should Windows/SQL licensing be handled on Google Cloud?
  [A] License-included Google-provided images (DEFAULT) — simplest, compliant, no entitlement analysis.
  [B] BYOL where eligible — SQL Server via License Mobility needs an instance dedicated to you but NOT
      necessarily a sole-tenant node (a BYOL Windows Server image under it does force one); Windows
      Server only via OSM Rights, sole-tenant, pre-2019-vintage licences only. Specialist confirms first.
  [C] Mixed — license-included for Windows, BYOL for SQL (or vice versa). Same specialist requirement.
  [D] Defer — "Deferred — specialist engagement".
```

**HARD RULE recorded on every pick:** the Azure baseline in `azure-cost-profile.json` may include AHB,
Reservation, SavingsPlan or Spot pricing, and **a discounted Azure baseline is not comparable to GCP
license-included list pricing.** Set `specialist_review_required: true` on [B] and [C]. **Headless:**
`"license-included (Google-provided images); BYOL eligibility Deferred to licensing specialist"`.

## Step 5: Q_ANALYTICS — Analytics / data platform (GATE 3; fires on any `analytics` item)

A specialist advisory, not a mapping decision. Name the evidence rows, then present the candidate targets
**for the specialist conversation only**, each with a same-run citation — Synapse and Microsoft Fabric
pair with BigQuery, Databricks/HDInsight with Managed Service for Apache Spark, Stream Analytics with
Dataflow, Data Factory with Cloud Data Fusion / Datastream / BigQuery Data Transfer Service, per
https://docs.cloud.google.com/docs/get-started/aws-azure-gcp-service-comparison. **Azure Data Explorer
has no pairing on that table** — say so rather than inventing one.

```text
Q_ANALYTICS: <n> analytics/data-platform services detected (<names>). How should they be handled?
  [1] Defer — "Deferred — specialist engagement" (RECOMMENDED without specialist input).
  [2] Keep on Azure for now and design cross-cloud connectivity only.
  [3] In scope — requires a data-platform specialist engagement BEFORE any design or estimate.
```

Every pick records `specialist_review_required: true`. Deferred rows carry through Design, Estimate and
Generate **verbatim: no `gcp_config`, no dollars, no Terraform**, and the user is directed to their
Google Cloud account team. **Headless:** `"Deferred — specialist engagement"`.

## Step 6: Q_M2VM — Per-VM migration eligibility (GATE 4; fires on `[EPHEMERAL_OS_DISK]`, `[UNMANAGED_DISK]` or `[ADE_ENCRYPTED]`)

List affected VMs BY NAME under each class. The eligibility facts are in
`references/shared/service-map.md` and must be re-verified this run.

- **`[EPHEMERAL_OS_DISK]` / `[UNMANAGED_DISK]` — hard M2VM blockers.** Those are the two attributes the
  Azure-source page documents as unsupported. Dispositions: `[1]` remediate on Azure first (convert to a
  managed, non-ephemeral OS disk), `[2]` rebuild on GCP from image rather than migrate, `[3]` exclude,
  `[4]` needs-decision. **There is no "migrate anyway" option** — it fails with an error.
- **`[ADE_ENCRYPTED]` — friction, not a blocker.** ADE retires 2028-09-15 and ADE-to-encryption-at-host
  migration is not in place (disabling ADE is unsupported on Linux OS disks — no in-place decrypt)
  (https://learn.microsoft.com/en-us/azure/virtual-machines/disk-encryption-migrate). Dispositions:
  `[1]` migrate and resolve encryption on the GCP side, `[2]` remediate on Azure first, `[4]` needs-decision.

Interpret -> one `design_choices[]` entry per class, with the VM names in `resources[]`.
**Headless:** blocker classes -> `needs-decision`, EXCLUDED from the automated wave, named in a banner;
ADE -> migrate with the friction warning attached to each row.

## Step 7: Q_MAP.cosmos — Cosmos DB (GATE 5; MANDATORY, one card per account)

Never resolved by default. Per account, state the API flavor, the consistency level and the partition-key
design — or say plainly that they are unknown. Candidate targets and the Gremlin/Table exclusion are in
`references/shared/service-map.md`; refresh each option's cost shape, consistency model and rewrite cost
this run. Every option costs an application rewrite; there is no lift tool.
**Headless:** `needs-decision` per account; Gremlin/Table -> `Deferred — specialist engagement`.

## Step 8: Q_SIZING — Sizing evidence (GATE 6; fires always)

Two decisions in one card: **where the numbers come from** and **which mode Design applies**.
Remember: **M2VM has no utilization report for Azure sources**, so there is no free path here.

```text
Q_SIZING: How should I learn how your workload is actually used, so I can size GCP correctly?
  [A] Query Azure Monitor directly — I shell out to the `az` CLI with your current credentials and read
      metrics for each resource. Requires `az` on PATH, an active login, and Monitoring Reader on the
      subscription. I will print the exact commands and the subscription and ask you to confirm first.
  [B] Another observability tool — Datadog, Grafana/Prometheus, Dynatrace, New Relic, etc. You export or
      paste; I tell you which metrics matter per resource type.
  [C] Describe the workload in text — peak/average load, request duration, peak concurrency, working set.
  [D] Conservative defaults — size from provisioned Azure specs, no measurement. Generated Terraform
      carries `# TODO: tune based on actual traffic` markers.
Then: sizing mode — [as-provisioned] map configured specs 1:1 (safe upper bound), or [rightsize] size
from measured use (selectable ONLY with data from A, B or C).
```

### Path A — live Azure read (CONSENT-GATED, never headless)

**Step A.1 — pre-flight. Print this and STOP for an explicit yes:**

```text
About to read Azure Monitor metrics using your current az credentials:
  Subscription: <id and name from `az account show`>   Tenant: <tenant id>
  Resources:    <N total, listed by resource id>
  Window:       last 7 days, 1-hour interval   Permission: Monitoring Reader on the subscription
  Commands:     az monitor metrics list-definitions --resource <id>
                az monitor metrics list --resource <id> --metric <name> ...
Nothing is written to Azure. Confirm to proceed [y/N]:
```

If the user declines, OFFER paths B, C or D — do **not** silently degrade to defaults.

**Step A.2 — resolve metric names from the resource itself, not from memory.** Run
`az monitor metrics list-definitions --resource <id>` first and pick metric names from its output. That
is a runtime enumeration, so it cannot be stale. Only if it fails, look the metric up via
`microsoft-learn` MCP or the supported-metrics index on learn.microsoft.com, and cite what you fetched.
Confirm the exact flag set for your `az` version against
https://learn.microsoft.com/en-us/cli/azure/monitor/metrics before running — never invent a flag.

**Step A.3 — record.** Per resource, write `preferences.json.sizing_data[<azure resource id>]` with
`source: "az-monitor"`, `window`, `fetched_at`, `metrics` (name -> `{max, avg, p95}` where available),
and `evidence` containing the literal command plus the first line of its response. A `sizing_data` entry
whose `evidence` lacks the literal `az monitor metrics` substring is not evidence.

**Step A.4 — on failure, offer a fallback, never a silent default.** `az` not on PATH, no active login,
`AuthorizationFailed` on Monitoring Reader, or an empty datapoint set for a specific resource each get a
named remediation plus the B/C/D offer. An empty set usually means the resource is new or idle — say that.

Paths B, C and D mirror the sibling skill's contract: B records `source: "observability-tool"` with the
tool name and the user's paste verbatim as evidence; C records `source: "verbal"` per workload group; D
records `source: "conservative-defaults"` with `sizing_data: {}`. Interpret -> `sizing_source` +
`sizing_mode`; `rightsize` requires non-empty `sizing_data` for the sized resources. **Headless:**
`sizing_source: "conservative-defaults"`, `sizing_mode: "as-provisioned"`, plus the banner:
`WARNING — HEADLESS DEFAULT: sizing_mode=as-provisioned from provisioned Azure specs, with no measured
utilization. Estimates are an upper bound, not a forecast.` **Path A is NEVER selected headlessly.**

## Step 9: Mapping cards (`Q_MAP.*`) — fire per detected service

For each card in `references/shared/service-map.md` whose source service appears in the inventory,
present the trade-off card with options populated by the Step 2 research chain. The mapping file owns
which cards exist and what each MUST cover; this step owns firing them and recording the answer. The card
set is `Q_MAP.appservice`, `Q_MAP.aks`, `Q_MAP.vmss`, `Q_MAP.postgres`, `Q_MAP.files`, `Q_MAP.messaging`,
`Q_MAP.keyvault`, `Q_MAP.observability`, `Q_MAP.edge`, `Q_MAP.apim`, `Q_MAP.logicapps`, `Q_MAP.ai`, `Q_MAP.search`.

Two couplings to state when they apply: `Q_MAP.files` SMB pulls in Managed Service for Microsoft AD from
`Q_IDENTITY`; `Q_MAP.observability` and `Q_MAP.ai` both create app-code work owned by `Q_SDK`.
Interpret -> one `design_choices[]` entry per fired card, with `card_citations[]`.
**Headless:** the per-card disposition in the `SKILL.md` table.

## Step 10: Q_SDK, Q_OS, Q_ZOMBIE — resource dispositions

- **`Q_SDK`** (fires on any app-code hit): confirm which call sites are in scope for rewrite guidance.
  Name every `[LEGACY_SDK]` hit explicitly — the legacy Service Bus libraries retire **2026-09-30** along
  with the SBMP protocol (https://learn.microsoft.com/en-us/azure/service-bus-messaging/service-bus-faq),
  a source-side deadline that does not go away by staying on Azure. Dispositions: `[1]` in scope,
  `[2]` note only, `[3]` out of scope.
  **Headless:** notes only, `manual_review: true` on every row. **No code is ever emitted.**
- **`Q_OS`** (fires on `[EOL_OS]` / `[CLIENT_OS]`): list guests by name per class. EOL and Windows client
  guests fall in M2VM's "migration support only" bucket — they migrate, but not all Compute Engine
  features work, and the EOL problem is not solved by moving it
  (https://docs.cloud.google.com/migrate/virtual-machines/docs/5.0/discover/supported-os-versions);
  Windows client SKUs also inherit the licensing constraints from `Q_LICENSE`. Dispositions:
  `[1]` migrate-as-is-where-supported, `[2]` upgrade-first (out of wave 1), `[3]` exclude,
  `[4]` needs-decision. **Headless:** every `[EOL_OS]` and `[CLIENT_OS]` guest -> `needs-decision`,
  excluded from auto-design, named in a banner.
- **`Q_ZOMBIE`** (fires on `[POWERED_OFF]`, `[STOPPED_NOT_DEALLOCATED]`, `[ORPHANED_DISK]`, `[VMSS_ZERO]`,
  `[BASIC_SKU]`): list each by name; `[STOPPED_NOT_DEALLOCATED]` still bills today (usually news) and
  `[BASIC_SKU]` is retired and unsupported, so replacing it is unavoidable either way — never propose
  creating another. Dispositions: `[1]` migrate, `[2]` defer, `[3]` retire (the user's decision — this
  skill never retires anything unilaterally). **Headless:** `defer`, each item individually listed.

## Step 11: Q_NET, Q_REGION, Q_INTENT, Q_ADJ — always-on cards

- **`Q_NET`**: `[A] re-ip` (new addressing in VPC subnets; needs a DNS/config sweep and breaks hard-coded
  addresses) vs `[B] preserve-cidr` (mirror source CIDRs where they do not collide with the target VPC or
  each other). Name every `[NETWORK_CONTINUITY]` and `[PRIVATE_ENDPOINT]` finding in the card — Private
  Endpoints become Private Service Connect endpoints and are a real rebuild, not a rename.
  Interpret -> `network_mode`. **Headless:** `re-ip`, recorded as an assumption.
- **`Q_REGION`**: propose a Google Cloud region by **geographic proximity** to the dominant Azure location
  in the inventory, and say that it is a proximity proposal rather than a documented pairing — no
  vendor-published Azure-to-Google region map is cited here because none was verified. Confirm via the
  Step 2 chain that the proposed region offers every service in the design (regions differ in service
  availability), and confirm data-residency constraints with the user. Interpret -> `region`.
  **Headless:** the derived proximity region, else `us-central1`, `chosen_by: "headless-default"`, with
  the derivation in the entry's `note`.
- **`Q_INTENT`**: `[A] cutover` (production migration: waves, cutover and rollback runbooks, DNS plan) vs
  `[B] pilot` (validation-only landing zone, no production traffic). **Headless:** `cutover`.
- **`Q_ADJ`**: for every `adjacent-services.json` item with `gate: "none"` and no decision yet, populate
  `candidate_strategies[]` via the Step 2 chain (2-4 options with a citation each; always include
  `defer`), then present a one-line lettered pick. Record `{"id":"Q_ADJ.<service>","value":"<strategy>"}`.
  **Headless:** `defer`, each listed.

## Step 12: Present All Cards, Then Write `preferences.json`

Present every firing card in ONE message, in Step 3 -> Step 11 order, numbered "Question N of M", with the
discovery summary on top. Offer: answer each / skip individual ones (that card's documented disposition
applies) / "use all defaults" (all dispositions apply — which still cannot assert a licensing entitlement
or pick a Cosmos DB target). **Interactive runs: STOP here and wait — do not proceed without a response.**
Headless runs apply the dispositions and continue. **Headless detection:** the run is HEADLESS when the
driving context establishes no interactive human, OR when the driver continues the run after this turn
ends with no human answer. A missing reply mid-turn is NEVER headless evidence.

Write `$MIGRATION_DIR/preferences.json` per `references/shared/schema-artifacts.md` §4. Rules: **(1)**
every firing question yields >=1 `design_choices[]` entry with `id`, `value`, `chosen_by`; gate cards and
`Q_MAP.*` entries also carry `card_citations[]`. **(2)** `headless_defaults_applied[]` is `[]` on fully
interactive runs, else one plain string per defaulted answer. **(3)** `chosen_by` never appears on a
`headless_defaults_applied[]` string. **(4)** no nulls; valid JSON.

Then output the phase summary: questions asked vs defaulted, each gate's outcome, and — **MANDATORY
whenever `headless_defaults_applied[]` is non-empty — a "Headless assumptions" block** listing every
applied default verbatim, including the sizing banner, the excluded `[EOL_OS]`/`[CLIENT_OS]` guests by
name, the M2VM-ineligible VMs by name, deferred zombies by name, the identity/licensing/analytics
dispositions, the re-ip assumption and the cutover assumption. Fully interactive runs print
`Headless assumptions: none`.

## Validation Checklist (run before Step 13)

- [ ] `identity_strategy`, `license_strategy` and `analytics_strategy` are each present and are one of
      this file's card values (or the documented "not fired" value) — never invented
- [ ] `license_strategy` of BYOL or mixed carries `specialist_review_required: true`
- [ ] Every `analytics` item is Deferred, kept-on-Azure, or explicitly specialist-scoped — none mapped;
      every Cosmos DB account has a `Q_MAP.cosmos` entry, and Gremlin/Table accounts are Deferred
- [ ] Every `[EPHEMERAL_OS_DISK]` and `[UNMANAGED_DISK]` VM has a disposition, and none of them is "migrate"
- [ ] `sizing_mode` present; `rightsize` only with non-empty `sizing_data` for the sized resources
- [ ] `sizing_source: "az-monitor"` only with an explicit consent quote AND `evidence` containing the literal `az monitor metrics` substring — never headless
- [ ] Every fired `Q_MAP.*` card has a `design_choices[]` entry with `card_citations[]`
- [ ] EVERY `[EOL_OS]`, `[CLIENT_OS]`, `[POWERED_OFF]`, `[STOPPED_NOT_DEALLOCATED]`, `[ORPHANED_DISK]`,
      `[VMSS_ZERO]` warning has a matching disposition — no warning silently dropped
- [ ] `network_mode`, `region` and `intent` populated; `preserve-cidr` records CIDRs checked for collision
- [ ] `headless_defaults_applied[]` agrees with every `chosen_by`; the assumptions block printed when non-empty
- [ ] Valid JSON; all writes under `$MIGRATION_DIR`; no secret value written anywhere

## Step 13: Ledger, Phase Status, Write Audit (same turn as the summary)

1. Append one entry per gate outcome to `validation-ledger.json`: `clarify/identity-gate`,
   `clarify/licensing-gate`, `clarify/analytics-gate`, `clarify/m2vm-eligibility-gate`,
   `clarify/cosmos-gate`, `clarify/sizing-consent-gate` (consented / declined / not-applicable — headless
   is always "not-applicable, conservative defaults"), `clarify/scope-gate`, plus
   `clarify/headless-defaults` (the list or empty) and one degradation entry per failed Step 2 lookup.
2. **Phase Status Update Protocol** (Write, no prior Read): set `phases.clarify: "completed"`, then run
   the post-phase write audit per the `SKILL.md` protocol.
3. Output: "Clarification complete. Proceeding to Phase 3: Design."

## Scope Boundary

**This phase gathers decisions ONLY.** FORBIDDEN: GCP architecture or service configs, machine-type
picks, Terraform, cost calculations or dollar figures (cost _shape_ language only), migration timelines.
**Your ONLY job: turn ambiguity into recorded, user-owned choices. Nothing else.**
