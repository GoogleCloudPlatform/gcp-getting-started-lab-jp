# Azure Cost & Usage Exports — Detection, Parsing, Discount Normalization

**Loaded by:** `references/phases/discover.md` (builds `azure-cost-profile.json`) and
`references/phases/estimate.md` (builds `comparison_to_azure`). All facts verified 2026-08-06 against
learn.microsoft.com.

Cost data here means **source Azure cost/usage data**, never GCP billing. Nothing in this file produces
a GCP price — GCP rates come only from the pricing chain in `references/phases/estimate.md`.

## Step 1 — Identify the dataset before parsing a single row

Read only the header line first. The header decides everything downstream.

| Header contains                                                     | Dataset                          | `cost_basis` to record |
| ------------------------------------------------------------------- | -------------------------------- | ---------------------- |
| `BilledCost` **and** `EffectiveCost` **and** `ChargePeriodStart`    | FOCUS                            | `EffectiveCost`        |
| `PricingModel` **and** `ChargeType` **and** `CostInBillingCurrency` | actual or amortized cost details | `Cost`                 |
| `ResourceId` + meter columns, no `ChargeType`                       | usage-only                       | `Cost`                 |
| Neither                                                             | not a cost export — do not guess | n/a                    |

Then pin the FOCUS version, because the version changes the column set:

- **1.0 vs 1.0r2** — 1.0r2 is a **re-release of the same FOCUS 1.0 spec**; the only change is that all
  date columns now include seconds. Verbatim from the schema page: "a 1.0 export may use
  `2024-01-01T00:00Z` and a 1.0r2 export would use `2024-01-01T00:00:00Z`". **Anything doing strict
  ISO-8601 parsing or string-slicing on `ChargePeriodStart` breaks across that boundary.**
- **1.2-preview** is the latest version Microsoft publishes, for EA and MCA contracts; the schema page
  documents 1.2-preview, 1.0 and 1.0-preview(v1) side by side
  (https://learn.microsoft.com/en-us/azure/cost-management-billing/dataset-schema/schema-index).
  Because it is preview, a production export **must pin an explicit dataset version at creation** rather
  than tracking latest — an unpinned export silently changes column names underneath a parser.

**Every FOCUS column fact in this file is a FACTS-THAT-GO-STALE row** — that table, and the rule for
recording a stale quote, live in `references/shared/service-map.md`. The schema page carried `ms.date` 2025-06-26 and `updated_at`
2025-10-09 when these rules were written on 2026-08-06 — measure staleness from `updated_at`, the later
of the two, and state which anchor you used. 1.2-preview may well have advanced since. Any run
that turns on a column name, a rename, or a "Currently null/empty" caveat re-fetches the schema page
first; if that re-fetch is skipped or fails, append a `corrected`/`skipped` entry to
`validation-ledger.json` and add a `[STALE_FACT]` warning to `azure-cost-profile.json` — never quote the
column silently.

Record `dataset.kind` and `dataset.version` in `azure-cost-profile.json`. Unknown version -> `"unknown"`
plus a warning; never assume 1.0 column names.

Schema source for this whole section:
https://learn.microsoft.com/en-us/azure/cost-management-billing/dataset-schema/cost-usage-details-focus

## Step 2 — Column semantics that change the number

### EffectiveCost vs BilledCost (the TCO decision)

`EffectiveCost` is the **amortized** cost: "the amortized cost of the charge after applying all reduced
rates, discounts, and the applicable portion of relevant, prepaid purchases (one-time or recurring) that
covered the charge." `BilledCost` is the invoice-basis charge — it includes reduced rates and discounts
but **excludes amortization of upfront charges**. Both definitions are character-identical in FOCUS 1.0
and 1.2-preview — but **not** in 1.0-preview(v1), where `EffectiveCost` is defined far more loosely as
"The cost inclusive of amortized upfront fees". A parser handling a v1 export must not assume the
columns mean the same thing.

**For migration TCO baselining, sum `EffectiveCost`.** `BilledCost` **front-loads; it does not
duplicate.** An upfront reservation purchase lands in full in its purchase month and the usage rows it
covers carry `BilledCost` 0, so a `BilledCost` baseline is inflated in the purchase month and near-free
in every month it covers — a month-to-month timing distortion, not a double count. Do not describe it as
double-counting anything. If a run uses `BilledCost` for any reason, that reason goes in
`azure-cost-profile.json.warnings[]` and in the Estimate summary.

### Half-open charge periods

`ChargePeriodStart` is **inclusive**, `ChargePeriodEnd` is **exclusive**. Bucket daily-grain rows on
**Start**, never End — bucketing on End shifts every row into the following day and silently misaligns
month boundaries. The guarantee does not reach backwards: the 1.0-preview(v1) table says only "Beginning
date and time" and "End date and time", with no inclusive/exclusive wording to rely on.

### `ResourceId` and the inventory join

The schema defines `ResourceId` as exactly "Unique identifier assigned to a resource by the provider".
That one sentence is the whole documented contract, and it is the whole contract a parser may rely on.
Azure rows do carry the ARM resource id in practice, but the page never says so — treat the ARM shape as
an observation to confirm per export, never as a guarantee to parse against.

**Never key `ResourceId is null` to mean "this row is a purchase."** The schema page makes no such
statement, and the columns that genuinely are empty are explicitly annotated "Currently null/empty" while
`ResourceId` is not — so the page cuts against that reading rather than merely omitting it. Identify
purchase rows on `ChargeCategory`, on `x_AmortizationClass` (1.2-preview), or on `ChargeType` in the
actual-cost dataset. A join to `azure-inventory.json` must still tolerate rows matching no inventory
resource: keep them in the cost total, report them as unattributed, and never silently drop them or
reclassify them as purchases. `ServiceName` is defined as an offering purchasable from a provider.

Microsoft's `x_`-prefixed additions are what make a cost export usable as an inventory source:

- `x_ResourceGroupName`, `x_ResourceType` (the ARM resource type) — the join keys to `azure-inventory.json`
- `x_SkuMeterName` / `x_SkuMeterCategory` / `x_SkuMeterSubcategory` — meter identity
- `x_SkuRegion`, `x_SkuOfferId`, `x_CostCenter`, `x_PricingSubcategory`
- `x_BilledCostInUsd` / `x_EffectiveCostInUsd` / `x_ListCostInUsd` / `x_ContractedCostInUsd` — USD
  normalization for multi-currency estates
- **1.2-preview only:** `x_AmortizationClass`, distinguishing `Principal` (commitment purchase/refund
  rows) from `Amortized Charge` (usage rows). This is the cleanest way to avoid summing a commitment
  purchase together with the amortized rows that already spread it, and it is also a reliable purchase-row
  discriminator where `ChargeCategory` is not available. Also 1.2-preview only: `x_ServiceModel`
  (IaaS/PaaS/SaaS), genuinely useful as a mapping heuristic. **`ChargeClass` is NOT 1.2-only** — the
  correction-to-prior-period flag appears in the 1.0 table as well, with a character-identical
  description, so version-gating it silently drops corrections from a 1.0 export.

### 1.2-preview column renames (a mapping layer keyed on 1.0 names silently drops these)

| 1.0 name            | 1.2-preview name                                                                          |
| ------------------- | ----------------------------------------------------------------------------------------- |
| `x_InvoiceId`       | `InvoiceId`                                                                               |
| `x_PricingCurrency` | `PricingCurrency`                                                                         |
| `x_SkuMeterName`    | `SkuMeter` (`x_SkuMeterName` still present but marked "Deprecated, replaced by SkuMeter") |

Also: `x_SkuTerm` ("Number of months a purchase covers") is in the 1.0 table but **not** in the
1.2-preview table. Resolve every column name through a version-aware alias map; matching case-insensitively
on both spellings is the cheap, safe implementation.

### 1.2-preview declared-but-empty columns — the commitment-waste trap

In 1.2-preview these are documented as **"Currently null/empty"**: `CommitmentDiscountStatus`,
`CommitmentDiscountQuantity`, `CommitmentDiscountUnit`, `CapacityReservationId`,
`CapacityReservationStatus`, `SkuPriceDetails`. The FOCUS 1.0 schema carries no such caveat on
`CommitmentDiscountStatus`.

**Therefore: commitment-waste detection MUST NOT be built on 1.2-preview FOCUS alone.** Use the
AMORTIZED dataset's `ChargeType = UnusedReservation` rows instead — Microsoft: unused reservation
costs "can be seen only when viewing amortized cost" (learn.microsoft.com/en-us/azure/cost-management-billing/reservations/charge-back-usage);
the actual-cost view shows the purchase, never the waste. If only 1.2-preview FOCUS is
available, record `discount_normalization.unused_reservation_cost: null` with a warning saying why —
do not report zero waste, which reads as "no waste found" when it means "not measurable here".

The full commitment family, for reference: `CommitmentDiscountId`, `CommitmentDiscountName`,
`CommitmentDiscountCategory` (usage-quantity vs cost/spend based), `CommitmentDiscountType`.

## Step 3 — Discount normalization (actual/amortized datasets)

This is what makes `comparison_to_azure` defensible. Source:
https://learn.microsoft.com/en-us/azure/cost-management-billing/automate/understand-usage-details-fields

**`PricingModel` is the primary discriminator** and carries exactly four values: `OnDemand`,
`Reservation`, `Spot`, `SavingsPlan`. It applies to all account types (EA, MCA, MPA, pay-as-you-go).
Pair it with `ChargeType` (`Usage`, `Purchase`, `Refund`). EA quirk: where `PricingModel` is `Spot`, the
**pricing currency is USD regardless of the billing currency**.

**Commitment identifiers** — `BenefitId`/`BenefitName` for savings plans, `ReservationId`/
`ReservationName` for reservations; all four are EA and MCA only. Join logic:

- A **purchase** row is `PricingModel = Reservation` with `ChargeType = Purchase`, and stamps the
  purchase order id into **both** `ReservationId` and `ProductOrderId`.
- A **usage** row is `PricingModel = Reservation` with `ChargeType = Usage` or `UnusedReservation`, where
  `ReservationId` is attributed to the benefiting resource and **can differ** from the purchase — split,
  merge and exchange create new reservations. **`ProductOrderId` is the stable key** for joining
  purchases to usage.
- `UnusedReservation` rows are how wasted commitment is found — they exist ONLY in the amortized dataset.
- Azure Savings Plan and prepurchased reservation rows have **no `PartNumber`**.
- Doc bug to ignore: `BenefitName`'s description on that page is copy-pasted from `BenefitId`. Do not
  treat that description as authoritative for the column's contents.

**What Discover records** in `azure-cost-profile.json.discount_normalization`:

1. `pricing_models_seen[]` — the distinct `PricingModel` values present.
2. `commitment_ids{}` — distinct `reservation_ids`, `benefit_ids`, `product_order_ids`.
3. `amortization_class_available` — true only when 1.2-preview `x_AmortizationClass` is populated.
4. `unused_reservation_cost` — from `ChargeType = UnusedReservation`, or `null` with the reason.
5. `on_demand_equivalent_available` — **almost always false.** The export shows what was paid under the
   commitment, not what the same usage would have cost on demand. Reconstructing an on-demand baseline
   needs the price sheet, which this skill does not assume exists.

**The binding consequence, carried into Estimate and stated to the user:** an Azure baseline containing
Reservation, SavingsPlan, Spot or Azure Hybrid Benefit pricing is **not comparable** to a GCP
list-price, license-included estimate. Set
`comparison_to_azure.discount_normalization.comparable = false`, list the models seen, and say plainly
that the Azure side is discounted and the GCP side is not. Committed-use discounts and sustained-use
behaviour on the GCP side are not modelled by this skill.

## Step 4 — Scope exclusions that explain a suspiciously small export

Two hard exclusions for FOCUS exports: **Azure MOSP (pay-as-you-go) billing scopes and subscriptions do
not support FOCUS datasets at all**, and **the management group scope is not supported for FOCUS**.

The management group scope is broadly degraded in the new exports experience: only the cost and usage
details (Usage) dataset is available there, CSV with no compression, usage charges only (no purchases,
reservations or savings plans), no amortized reports, no multiple currencies, EA only, and a cap of
3,000 subscriptions per management group. FOCUS supported agreements are EA, MCA bought via the Azure
website, MCA enterprise, and MCA via a Microsoft partner — notably the Azure internal agreement type
listed for actual and amortized exports is **absent** from the FOCUS row
(https://learn.microsoft.com/en-us/azure/cost-management-billing/costs/tutorial-improved-exports).

When the export covers fewer subscriptions than the inventory, say which exclusion likely explains it
rather than reporting a smaller estate.

## Step 5 — File mechanics

**Formats:** FOCUS cost and usage exports support **CSV with None or Gzip**, and **Parquet with None or
Snappy**; the same matrix applies to actual, amortized, usage-only and the price sheet. Reservation
details, recommendations and transactions are **CSV-only, no compression**. In a multi-dataset export
job, Parquet and compression options appear only if every selected dataset supports them.

- **CSV / CSV.gz** — parseable by this skill (see the helper rule below).
- **Parquet** — this skill does not parse Parquet. STOP for that file and ask for a CSV export, or
  proceed with whatever other sources exist plus a `[PARTIAL_INVENTORY]` warning. Do not write a Parquet
  reader.

**Partitioning is always on and cannot be disabled.** Files split by **size** (each uncompressed file
kept under 1 GB), never by row count, and every run emits a `_manifest.json` listing every partition.
**Never hardcode partition names — read `_manifest.json`.** Output lands at
`StorageContainer/StorageDirectory/ExportName/[YYYYMMDD-YYYYMMDD]/[RunID]/`; with overwrite on (the
default) there is one RunID folder per month, without it one per run. Data is typically available within
4 hours of a run starting, and a daily cost export runs **twice a day for the first five days of a
month** — the second, invisible run rewrites the prior month to capture up to 72 hours of latent
charges. A month-boundary export read too early is therefore incomplete by design; note the read date.

**Backfill differs by channel:** the Azure portal retrieves up to 13 months, one month at a time, via
"Export selected dates" on an existing export; the Exports - Execute REST API reaches up to 7 years for
cost and usage datasets. Reservation recommendations are current-snapshot only.

**Operational prerequisites that bite in labs** (useful when a user says the export is empty): new
subscriptions may need up to 48 hours before Cost Management features work; an export run can take up to
24 hours to first produce data; storage accounts need "Permitted scope for copy operations" set to "From
any storage account"; firewalled storage requires API version 2023-08-01 or later plus Owner or
`roleAssignments/write`; firewalled storage is not supported for cross-tenant exports.

## Step 6 — The single sanctioned helper script

Cost exports are routinely tens of MB. Reading one into context wastes the run and often fails.

- **<= 200 data rows AND <= 1 MB** -> Read in context and aggregate directly. No script.
- **> 200 rows OR > 1 MB** -> the ONE permitted helper:
  1. Read only the first line (headers) via Bash.
  2. Write the helper to exactly `$MIGRATION_DIR/_extract_cost.py` (or `.js`/`.sh` if no Python runtime).
     This is the only helper script this skill may ever write, and it exists solely to keep multi-MB cost
     files out of context. It must: read the CSV (decompressing `.csv.gz` internally), match headers
     case-insensitively **against both the 1.0 and 1.2-preview spellings**, group by `ServiceName` (FOCUS)
     or `MeterCategory` (actual/amortized), sum the `cost_basis` column, take the top 3 items per service
     by cost, capture the currency and the min/max of `ChargePeriodStart`/`ChargePeriodEnd`, collect the
     distinct `PricingModel` values and commitment ids, sum `ChargeType = UnusedReservation` (amortized dataset only), and print
     JSON to stdout. It must not write files, make network calls, or read anything outside the export.
  3. Run once: try `python3`, then `python`; if neither exists, DELETE the script, fall back to a chunked
     in-context Read, and record a `corrected` ledger entry.
  4. Write the output to `$MIGRATION_DIR/azure-cost-profile.json`, then **DELETE `_extract_cost.*`**. One
     run, then gone — the post-phase write audit fails if it survives.

`summary.total_monthly_cost` is the sum of the recorded `cost_basis` over the report interval. If the
interval is not approximately 30 days, extrapolate to 30 days and add a warning stating the observed
interval and the extrapolation. Never present an extrapolated figure without that warning.
