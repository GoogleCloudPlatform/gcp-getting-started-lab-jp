# costs/ — synthetic Azure cost and usage export

**Everything in this directory is SYNTHETIC.** No figure here was measured, on Azure or anywhere else. No
real subscription, tenant, billing account, invoice, reservation or customer is represented. The
subscription GUID, the billing account number, the invoice id and the reservation order id are all
fabricated. It exists so that tooling reading this directory meets a cost export shaped the way a real
one is shaped.

## What it imitates

`car-usage-focus.csv` imitates the CSV that **Microsoft Cost Management** writes for a
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
| Rows        | 511 data rows                                                    |
| Currency    | JPY, with `x_EffectiveCostInUsd` alongside at a flat 150 JPY/USD |
| Region      | `westus3`                                                        |
| Cost basis  | `EffectiveCost` (equal to `BilledCost` on every row)             |

Every row but one is `ChargeCategory: Usage` at list price, so `ListCost`, `ContractedCost`,
`BilledCost` and `EffectiveCost` carry the same number.

**The exception is the one row the operator's finance lead cannot explain.** A single
`ChargeCategory: Purchase` row carries a month-to-month reservation for 15 provisioned throughput units
against the model account, with `PricingCategory: Committed`, `CommitmentDiscountType: Reservation` and
`CommitmentDiscountName: car-openai-ptu-monthly`. Fifteen units is the smallest global provisioned
deployment Azure sells for this model. It is the largest single line in the month by a wide margin, and
it is billed by the hour whether or not a request is made — which is a different metering shape from
every other row in the file, and from anything the per-token meters record.

There are no savings plans and no Spot rows anywhere in this export, and no `UnusedReservation` rows: the
reservation was bought against an account whose deployments are all pay-per-token, so nothing draws down
against it and nothing reports back as unused either.

Resource names carry the deploy-time uniqueness suffix from the operator's own subscription
(`car-openai-q7mp4kx2wnb3f`, `car-search-q7mp4kx2wnb3f`, `car-cosmos-q7mp4kx2wnb3f`,
`cardocsq7mp4kx2wnb3f`, `caracrq7mp4kx2wnb3f`). A fresh deployment of `bicep/main.bicep` computes a
different suffix, so the names in this export will not match a newly stood up copy character for
character. Everything else — resource group, SKUs, tiers, service set — does.

Region is the one column that has to be kept in step by hand. Nothing else in this estate names a
region: `bicep/` takes it from the resource group and the scripts take it from `AZURE_LOCATION`. A cost
export has no such option, so `REGION_ID` and `REGION_NAME` at the top of `make-usage-export.py` carry
the region the estate is deployed into, and both need editing together if it moves.
`OPENAI_REGION_ID` and `OPENAI_REGION_NAME` are separate because `bicep/main.bicep` gives the model
account its own region parameter; on the deployment this export describes they resolved to the same
place. The quantities are seeded per meter and independent of the region, so nothing else in the file
changes when it moves.

## Regenerating

```bash
python3 make-usage-export.py               # rewrites car-usage-focus.csv in place
python3 make-usage-export.py /tmp/a.csv    # or write a copy elsewhere
```

`make-usage-export.py` needs nothing outside the Python standard library. It is deterministic — fixed
period, fixed seed, one seeded generator per meter, and no clock reads anywhere — so regenerating
produces a **byte-identical** file, which is what lets a parity check hash it.
