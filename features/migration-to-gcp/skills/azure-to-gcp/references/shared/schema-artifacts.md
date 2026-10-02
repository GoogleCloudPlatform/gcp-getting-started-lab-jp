# Run Artifact Schemas (azure-to-gcp)

**Loaded by:** every phase file. This is the single contract for every JSON artifact written under
`$MIGRATION_DIR`. A phase that writes a field not defined here, or omits a MANDATORY field, fails its
own pre-write self-check. All artifacts are valid JSON, UTF-8, no comments, no trailing commas.

Conventions used below: `""`/`0`/`[]`/`{}` are **shape placeholders**, never literal defaults.
`<...>` marks a value computed from the run. `null` is legal ONLY where a field is explicitly
described as nullable — everywhere else a missing value is a gate failure, not a `null`.

## 1. `azure-inventory.json` (Discover)

Always written, even on degraded runs (empty `resources[]` plus a `[PARTIAL_INVENTORY]` warning).

```json
{
  "subscriptions": [{ "subscription_id": "", "display_name": "", "source": "" }],
  "resources": [
    {
      "id": "<ARM resource ID when known, else synthetic 'iac:<file>#<symbolic_name>'>",
      "name": "",
      "azure_type": "Microsoft.Compute/virtualMachines",
      "resource_group": "",
      "location": "",
      "source": "terraform|bicep|arm|app-code|cost-export|migrate-export|resource-list",
      "source_ref": "<file>:<line> | <cost-export column/value> | <export sheet/row>",
      "sku": { "name": "", "tier": "" },
      "properties": {},
      "tags": {},
      "identity": { "type": "", "user_assigned": [] },
      "vm": {
        "os_type": "",
        "os_image": "",
        "vcpu": null,
        "memory_gib": null,
        "power_state": "",
        "os_disk": { "managed": true, "ephemeral": false, "size_gib": null, "encryption": "" },
        "data_disks": [{ "name": "", "managed": true, "size_gib": null, "encryption": "" }]
      },
      "warnings": []
    }
  ],
  "warnings": []
}
```

- `source` is REQUIRED and is the single most important provenance field: it tells Clarify and Design
  how much to trust the row. `vm{}` is present only on compute rows; omit it entirely otherwise
  (do not write a `vm` object full of nulls).
- `vcpu`/`memory_gib` are **nullable** — an Azure VM size string (`Standard_D4s_v5`) does not carry its
  own core/RAM counts in IaC, and this skill never expands a size string from recall. Resolve it live
  (Discover Step 5) or leave null with a warning.
- `id` for IaC-only rows uses the synthetic form because ARM IDs do not exist until deployment.
- A resource discovered from two sources gets ONE row with the higher-fidelity `source`, plus an
  `[IAC_DRIFT]` warning naming both, when the sources disagree on any field.

### Warnings taxonomy (MANDATORY floor — Discover emits these tags verbatim)

Format: `[TAG] <resource-name-or-scope>: <detail>`. Each tag maps to a Clarify card; never resolve one
inside Discover.

| Tag                         | Fires when                                                                       |
| --------------------------- | -------------------------------------------------------------------------------- |
| `[EOL_OS]`                  | Guest OS or App Service runtime past community end of support                    |
| `[CLIENT_OS]`               | Windows client SKU (10/11) rather than Windows Server                            |
| `[POWERED_OFF]`             | VM reported stopped/deallocated — no compute billing                             |
| `[STOPPED_NOT_DEALLOCATED]` | VM stopped but still allocated — STILL BILLING; only cost exports reveal it      |
| `[EPHEMERAL_OS_DISK]`       | `diffDiskSettings` / `diff_disk_settings` present — M2VM-ineligible              |
| `[UNMANAGED_DISK]`          | Page-blob VHD (`vhd { uri }` / `osDisk.vhd`) — M2VM-ineligible and Azure-retired |
| `[ADE_ENCRYPTED]`           | Azure Disk Encryption in use — high-friction, not an M2VM blocker                |
| `[IAC_DRIFT]`               | IaC disagrees with a cost export / resource list on existence or SKU             |
| `[PARTIAL_IAC]`             | IaC covers a minority of the billed estate                                       |
| `[PARTIAL_INVENTORY]`       | No per-resource source at all (cost-export-only or empty run)                    |
| `[LEGACY_SDK]`              | Retired/retiring Azure SDK package referenced in app code                        |
| `[TLS_LEGACY]`              | `minimumTlsVersion` absent or below `TLS1_2` on a storage account                |
| `[ORPHANED_DISK]`           | Managed disk with no owning VM                                                   |
| `[VMSS_ZERO]`               | Scale set at zero capacity — invisible in cost, real in IaC                      |
| `[AHB_SIGNAL]`              | Azure Hybrid Benefit / BYOL licence type on a VM or SQL resource                 |
| `[PRIVATE_ENDPOINT]`        | Private Endpoint / Private Link dependency on a migrating resource               |
| `[BASIC_SKU]`               | Basic public IP or Basic LB, retired 2025-09-30 — unsupported, must-replace      |
| `[UNRESOLVED_SOURCE_FIELD]` | A field no source could supply; value left `null`                                |
| `[NETWORK_CONTINUITY]`      | Project prose describes addressing/L3 constraints absent from IaC                |
| `[STALE_FACT]`              | A dated fact re-used without a same-run re-fetch (see `service-map.md`)          |

## 2. `azure-cost-profile.json` (Discover)

```json
{
  "dataset": {
    "kind": "focus|actual|amortized|usage|unknown",
    "version": "1.0|1.0r2|1.2-preview|n-a",
    "scope": "",
    "currency": "",
    "period": { "start": "", "end": "", "days": 0, "extrapolated_to_30d": false }
  },
  "summary": { "total_monthly_cost": 0.0, "cost_basis": "EffectiveCost|BilledCost|Cost" },
  "services": [{ "service": "", "monthly_cost": 0.0, "top_items": [], "resource_ids": [] }],
  "discount_normalization": {
    "pricing_models_seen": [],
    "commitment_ids": { "reservation_ids": [], "benefit_ids": [], "product_order_ids": [] },
    "amortization_class_available": false,
    "unused_reservation_cost": null,
    "on_demand_equivalent_available": false,
    "note": ""
  },
  "warnings": []
}
```

- `summary.cost_basis` MUST be recorded: `EffectiveCost` for FOCUS TCO baselining, `Cost` for the
  actual/amortized datasets. `BilledCost` front-loads an upfront commitment purchase into its purchase
  month while the usage rows it covers carry 0 — a timing distortion, not a double count. See
  `references/shared/billing-exports.md`.
- `discount_normalization` is what makes the later `comparison_to_azure` honest. `unused_reservation_cost`
  is `null` (not `0`) whenever the dataset cannot express it.

## 3. `adjacent-services.json` (Discover)

```json
{
  "items": [
    {
      "azure_service": "",
      "evidence": ["<verbatim string + where it came from>"],
      "gate": "analytics|identity|licensing|datastore|none",
      "candidate_strategies": []
    }
  ]
}
```

`candidate_strategies` arrives EMPTY from Discover — Clarify populates it from live research. Discover
names no GCP services anywhere in this file.

## 4. `preferences.json` (Clarify)

```json
{
  "identity_strategy": "",
  "license_strategy": "",
  "analytics_strategy": "",
  "sizing_mode": "as-provisioned|rightsize",
  "sizing_source": "az-monitor|observability-tool|verbal|conservative-defaults",
  "network_mode": "re-ip|preserve-cidr",
  "region": "",
  "intent": "cutover|pilot",
  "design_choices": [
    {
      "id": "<Q_ID or Q_ID.<scope>>",
      "value": "",
      "chosen_by": "user|derived|default|headless-default|user-requested-default",
      "resources": [],
      "card_citations": ["<url> (fetched <YYYY-MM-DD>)"],
      "specialist_review_required": false,
      "note": ""
    }
  ],
  "sizing_data": {},
  "headless_defaults_applied": [],
  "warnings": []
}
```

- `chosen_by` lives on `design_choices[]` entries ONLY. `headless_defaults_applied[]` is a flat array of
  plain strings (`"Q_SIZING=conservative-defaults"`), never objects.
- `identity_strategy`, `license_strategy` and `analytics_strategy` are free-text but MUST be one of the
  card values in `references/phases/clarify.md` — Design copies them VERBATIM and never paraphrases.
- `sizing_data` is keyed by Azure resource id; each entry carries `source`, `window`, `fetched_at`,
  `metrics`, and `evidence` (the literal command or paste). Empty `{}` for conservative defaults.
- A decision absent from `design_choices[]` may not shape `gcp-design.json`. That is a Design gate.

## 5. `gcp-design.json` (Design)

```json
{
  "region": "",
  "groups": [
    {
      "id": "<resource group | app tier | 'ungrouped'>",
      "resources": [
        {
          "source_id": "",
          "source_type": "",
          "disposition": "mapped|deferred|needs-decision",
          "gcp_service": "",
          "gcp_config": {},
          "sizing_mode": "",
          "migration_method": "",
          "rationale": "<why, with >=1 cited URL>",
          "design_choice_ref": "<design_choices[].id backing this mapping, or 'deterministic'>",
          "human_expertise_required": false,
          "warnings": []
        }
      ]
    }
  ],
  "network": { "vpc": "", "subnets": [], "connectivity": {}, "dns": {}, "rationale": "" },
  "identity": {
    "strategy": "<verbatim from preferences>",
    "workload_identity": {},
    "rationale": ""
  },
  "deferred": [{ "source_id": "", "reason": "", "gate": "" }],
  "warnings": []
}
```

- `disposition` is REQUIRED on every row: `mapped` rows carry `gcp_config` and are the only rows Estimate
  prices and Generate emits Terraform for. `deferred` rows have `gcp_service` exactly
  `"Deferred — specialist engagement"`, **no `gcp_config` key at all** (not an empty object), and
  `human_expertise_required: true`; `needs-decision` rows likewise carry no `gcp_config` and no dollars.
  Both are still REAL ROWS in this file, never omissions — that is what balances Design's Step 8a count
  and stops Estimate stalling on a resource it cannot find.
- `migration_method` names the tool actually documented for that hop (for example
  `"Migrate to Virtual Machines"`, `"Storage Transfer Service"`, `"Database Migration Service"`,
  `"BACPAC export"`, `"rebuild-and-redeploy"`), never an invented product.
- `design_choice_ref` is what the preferences-fidelity gate walks. `"deterministic"` is legal only for
  1:1 mappings marked deterministic in `references/shared/service-map.md`.

## 6. `estimation.json` (Estimate)

```json
{
  "resources": [
    {
      "source_id": "<or 'component' for shared items>",
      "gcp_service": "",
      "sizing_mode": "",
      "monthly_cost": 0.0,
      "pricing": {
        "attempts": [
          { "source": "", "tool_call": "", "result": "", "evidence": "", "fetched_at": "" }
        ],
        "source": "",
        "fetched_url": "",
        "fetched_at": "",
        "sku_rate": "",
        "assumed_quantity": "",
        "calculation": ""
      }
    }
  ],
  "external_costs": [{ "item": "", "note": "<no dollar figures, ever>" }],
  "totals": {
    "gcp_monthly_total": 0.0,
    "by_service": {},
    "excluded_deferred": [{ "item": "", "reason": "" }],
    "note": ""
  },
  "comparison_to_azure": {
    "available": true,
    "label": "source-billing-derived actuals",
    "azure_monthly_total": 0.0,
    "azure_cost_basis": "",
    "gcp_monthly_total": 0.0,
    "delta_monthly": 0.0,
    "discount_normalization": {
      "azure_baseline_is_discounted": false,
      "pricing_models_seen": [],
      "gcp_side_basis": "list-price, license-included",
      "comparable": false,
      "caveats": []
    }
  },
  "warnings": []
}
```

- `pricing.attempts[].source` enum: `"gcp-pricing (Cloud Billing Catalog API)"`,
  `"google-developer-knowledge MCP"`, `"WebFetch cloud.google.com"`, `"user_provided"`. There is no
  cached tier — a `"cached"` value means stale instructions.
- `pricing.attempts[].result` enum: `"ok"`, `"MCP_AUTH_FAILED"`, `"MCP_NO_RESULT"`, `"MCP_UNAVAILABLE"`,
  `"BillingAPI_NO_SKU_MATCH"`, `"BillingAPI_AUTH_FAILED"`, `"BillingAPI_REGION_NOT_COVERED"`,
  `"WebFetch_404"`, `"WebFetch_parse_failed"`, `"WebFetch_unavailable"`.
- `comparison_to_azure.discount_normalization.comparable` is `false` whenever the Azure baseline carries
  Reservation, SavingsPlan, Spot or Azure Hybrid Benefit pricing and no on-demand equivalent was
  recovered. **A discounted Azure baseline versus GCP list-price, license-included rates is not a
  like-for-like comparison** and the summary must say so in those words.

## 7. `.phase-status.json` (all phases)

```json
{
  "migration_id": "<MMDD-HHMM>",
  "last_updated": "<ISO 8601 UTC>",
  "phases": {
    "discover": "completed",
    "clarify": "pending",
    "design": "pending",
    "estimate": "pending",
    "generate": "pending"
  }
}
```

Status values: `"pending"` -> `"in_progress"` -> `"completed"`; a phase may end at `"failed"` (a
MANDATORY output missing). `"failed"` -> `"in_progress"` on re-entry is the only backward transition.

## 8. `validation-ledger.json` (all phases)

```json
[{ "phase": "", "gate": "", "result": "pass|fail|corrected|skipped", "evidence": "", "at": "" }]
```

One entry per BLOCKING gate a phase runs, plus one `skipped`/`corrected` entry per degradation.
`evidence` carries real numbers or real names, never "ok". **Ledger resume rule:** on session resume,
Read this file ONCE before the session's first append — earlier phases' entries are not re-derivable and
a blind Write clobbers them. The no-prior-Read protocol applies to `.phase-status.json` only.

## 9. `generation-validation.json` (Generate)

```json
{
  "artifacts": [
    {
      "artifact": "",
      "mandatory": true,
      "present": false,
      "non_empty": false,
      "references_design": false
    }
  ],
  "budget_skipped": [{ "artifact": "", "reason": "" }],
  "warnings": []
}
```

`artifact` is the path relative to `$MIGRATION_DIR`. Rewrite the COMPLETE file after each artifact,
replacing any prior entry for the same path and never losing the others — this per-file audit is what
makes a `"failed"` Generate resumable.
