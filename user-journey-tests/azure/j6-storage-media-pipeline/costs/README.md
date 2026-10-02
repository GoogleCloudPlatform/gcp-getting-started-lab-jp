# costs/ — synthetic Azure cost and usage export

**Everything in this directory is SYNTHETIC.** No figure here was measured, on Azure or anywhere else. No
real subscription, tenant, billing account, invoice or customer is represented. The subscription GUID,
the billing account number and the invoice id are all fabricated. It exists so that tooling reading this
directory meets a cost export shaped the way a real one is shaped.

## What it imitates

`smp-usage-focus.csv` imitates the CSV that **Microsoft Cost Management** writes for a
**FOCUS cost and usage export, dataset version 1.0r2**, as configured from Cost Management > Exports in
mid-2026. FOCUS is the FinOps Open Cost and Usage Specification; Microsoft publishes its column contract
at
<https://learn.microsoft.com/en-us/azure/cost-management-billing/dataset-schema/cost-usage-details-focus>.

Two version details are reproduced rather than glossed over, because both change how a parser behaves:

- **1.0r2 timestamps carry seconds** (`2026-06-01T00:00:00Z`). The original 1.0 release wrote
  `2026-06-01T00:00Z`. Anything string-slicing a date breaks across that boundary.
- **`ChargePeriodStart` is inclusive and `ChargePeriodEnd` is exclusive.** Daily rows must be bucketed on
  Start; bucketing on End shifts every row into the next day.

The Microsoft-specific `x_`-prefixed columns are present because they are what makes an Azure FOCUS
export usable as an inventory source: `x_ResourceGroupName`, `x_ResourceType`, `x_SkuMeterCategory`,
`x_SkuMeterSubcategory`, `x_SkuMeterName`, `x_SkuRegion`, `x_EffectiveCostInUsd` and friends. This is a
1.0r2 export, so the meter column is `x_SkuMeterName` — the rename to `SkuMeter` belongs to 1.2-preview
and is not present here.

**The meter names, units and list unit prices are real.** Every `x_SkuMeterName`, `ConsumedUnit` and
`ListUnitPrice` in this file was taken from the Azure Retail Prices API
(<https://prices.azure.com/api/retail/prices>) for `westus3`, and for Front Door for `Zone 1`, on
2026-08-06. The quantities are invented; the rate card they are multiplied by is not. Front Door rows
carry the billing **zone** in `RegionId`/`x_SkuRegion` rather than an Azure region, which is how Azure
bills a global service.

## What the file covers

| Property    | Value                                                                             |
| ----------- | --------------------------------------------------------------------------------- |
| Period      | 2026-04-01 to 2026-08-01 — four consecutive billing periods, half-open            |
| Granularity | Daily, plus one recurring monthly charge per period (the Front Door base fee)     |
| Rows        | 1740 data rows (~1.7 MB — a wide 52-column schema over four months of daily rows) |
| Currency    | USD, with `x_EffectiveCostInUsd` carrying the same number                         |
| Region      | `westus3`, and `Zone 1` on the Front Door rows                                    |
| Cost basis  | `EffectiveCost` (equal to `BilledCost` here — see below)                          |
| Pricing     | Pay-as-you-go throughout                                                          |

There are **no reservations, savings plans or Spot rows** anywhere in this export, and no
`UnusedReservation` charges. Every row is `ChargeCategory: Usage` at list price, which is why
`ListCost`, `ContractedCost`, `BilledCost` and `EffectiveCost` all carry the same number. The studio
has never bought a commitment; it is billed month to month on a Microsoft Customer Agreement.

Not every resource in the estate produces rows. A resource that consumed nothing in a billing period is
not billed and therefore does not appear — the Storage Sync Service is the case here, and it has no rows
in any of the four months.

Resource names carry the deploy-time uniqueness suffix from the studio's own subscription
(`smpmedia7f3c91ad`, `smpwip7f3c91ad`, `smpdelivery7f3c91ad`, `smp-adf-7f3c91ad`). A fresh deployment
computes a different suffix, so the names in this export will not match a newly stood up copy character
for character. Everything else — resource group, SKUs, redundancy, service set — does.

Region is the one column that has to be kept in step by hand. Nothing else in this journey names a
region: `arm/` takes it from the resource group, `terraform/` takes it from a variable and the scripts
take it from `AZURE_LOCATION`. A cost export has no such option, so `REGION_ID`, `REGION_NAME` and
`FD_ZONE` at the top of `make-usage-export.py` carry the region the estate is deployed into, and they
need editing together if it moves. The quantities are seeded per meter and independent of the region, so
nothing else in the file changes when it does.

## Regenerating

```bash
python3 make-usage-export.py               # rewrites smp-usage-focus.csv in place
python3 make-usage-export.py /tmp/a.csv    # or write a copy elsewhere
```

`make-usage-export.py` needs nothing outside the Python standard library. It is deterministic — fixed
period, fixed seed, one seeded generator per meter, and no clock reads anywhere — so regenerating
produces a **byte-identical** file, which is what lets a parity check hash it.
