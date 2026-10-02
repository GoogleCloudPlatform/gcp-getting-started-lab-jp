# costs/ — synthetic Azure cost and usage export

**Everything in this directory is SYNTHETIC.** No figure here was measured, on Azure or anywhere else. No
real subscription, tenant, billing account, invoice or customer is represented. The subscription GUID,
the billing account number and the invoice id are all fabricated. It exists so that tooling reading this
directory meets a cost export shaped the way a real one is shaped.

## What it imitates

`pwa-usage-focus.csv` imitates the CSV that **Microsoft Cost Management** writes for a
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

## What the file covers

| Property    | Value                                                            |
| ----------- | ---------------------------------------------------------------- |
| Period      | 2026-06-01 to 2026-07-01 (one full billing month, half-open)     |
| Granularity | Daily, plus one recurring monthly charge                         |
| Rows        | 301 data rows                                                    |
| Currency    | JPY, with `x_EffectiveCostInUsd` alongside at a flat 150 JPY/USD |
| Region      | `westus3`                                                        |
| Cost basis  | `EffectiveCost` (equal to `BilledCost` here — see below)         |
| Pricing     | Pay-as-you-go throughout                                         |

There are **no reservations, savings plans or Spot rows** anywhere in this export, and no
`UnusedReservation` charges. Every row is `ChargeCategory: Usage` at list price, which is why
`ListCost`, `ContractedCost`, `BilledCost` and `EffectiveCost` all carry the same number. The shop
has never bought a commitment; it is billed month to month on a Microsoft Customer
Agreement.

Resource names carry the deploy-time uniqueness suffix from the shop's own subscription
(`pwa-pg-k4xq7m2vb9zdc`, `pwamediak4xq7m2vb9zdc`, `pwa-kv-k4xq7m2vb9zdc`). A fresh deployment of
`bicep/main.bicep` computes a different suffix, so the names in this export will not match a newly stood
up copy character for character. Everything else — resource group, SKUs, sizes, service set — does.

Region is the one column that has to be kept in step by hand. Nothing else in this journey names a
region: `bicep/` takes it from the resource group and the scripts take it from `AZURE_LOCATION`. A cost
export has no such option, so `REGION_ID` and `REGION_NAME` at the top of `make-usage-export.py` carry
the region the estate is deployed into, and both need editing together if it moves. The quantities are
seeded per meter and independent of the region, so nothing else in the file changes when it does.

## Regenerating

```bash
python3 make-usage-export.py               # rewrites pwa-usage-focus.csv in place
python3 make-usage-export.py /tmp/a.csv    # or write a copy elsewhere
```

`make-usage-export.py` needs nothing outside the Python standard library. It is deterministic — fixed
period, fixed seed, one seeded generator per meter, and no clock reads anywhere — so regenerating
produces a **byte-identical** file, which is what lets a parity check hash it.
