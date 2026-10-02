# costs/ — synthetic Azure cost and usage exports

**Everything in this directory is SYNTHETIC.** No figure here was measured, on Azure or anywhere else.
No real subscription, tenant, enrolment, billing account, invoice or customer is represented. The
subscription GUID, the enrolment number, the invoice id, the reservation order id and the savings plan
id are all fabricated. These files exist so that tooling reading this directory meets cost exports
shaped the way real ones are shaped.

## What these imitate

All four artifacts are what **Microsoft Cost Management** writes from Cost Management > Exports,
configured in mid-2026 against an Enterprise Agreement enrolment. Each schema page below is the source
for that file's column names and their order.

| Path                        | Dataset                                  | Version     | Schema                                                                                                                              |
| --------------------------- | ---------------------------------------- | ----------- | ----------------------------------------------------------------------------------------------------------------------------------- |
| `focus/`                    | FOCUS cost and usage details             | 1.2-preview | [cost-usage-details-focus](https://learn.microsoft.com/en-us/azure/cost-management-billing/dataset-schema/cost-usage-details-focus) |
| `cpi-actual-cost.csv`       | Cost and usage details, actual metric    | 2024-08-01  | [cost-usage-details-ea](https://learn.microsoft.com/en-us/azure/cost-management-billing/dataset-schema/cost-usage-details-ea)       |
| `cpi-amortized-cost.csv`    | Cost and usage details, amortized metric | 2024-08-01  | as above                                                                                                                            |
| `cpi-reservation-usage.csv` | Reservation details                      | 2023-03-01  | [reservation-details-ea](https://learn.microsoft.com/en-us/azure/cost-management-billing/dataset-schema/reservation-details-ea)     |

Four version details are reproduced rather than glossed over, because each one changes how a parser
behaves:

- **1.2-preview renames three columns.** `x_InvoiceId` became `InvoiceId` and `x_PricingCurrency`
  became `PricingCurrency`; `x_SkuMeterName` became `SkuMeter` and is still carried alongside it,
  marked deprecated. A mapping layer keyed on the 1.0 spellings silently drops the first two.
- **1.2-preview timestamps carry seconds** (`2026-07-01T00:00:00Z`), and `ChargePeriodStart` is
  inclusive while `ChargePeriodEnd` is exclusive. Daily rows must be bucketed on Start; bucketing on
  End shifts every row into the next day.
- **The actual and amortized metrics are the same charges on two different bases**, so the two files
  do not add up to the same number and are not meant to. FOCUS carries both bases in one row set:
  `BilledCost` reconciles to the actual export and `EffectiveCost` to the amortized one.
- **Reservation details is CSV only.** The format matrix that offers Parquet and gzip for cost and
  usage datasets does not apply to it, which is why that one file sits here uncompressed while the
  FOCUS partitions are gzipped. Its file name is the export name, which whoever configures the export
  chooses; the dataset is identified by its columns, not by its name.

## The FOCUS export is partitioned

Partitioning is always on in the current exports experience and cannot be switched off. A run writes
one `_manifest.json` plus one file per partition, and the manifest is the only supported way to
enumerate them — partition names are not a contract, so read `blobs[].blobName` rather than globbing.
A run lands under `<container>/<root folder>/<export name>/<date range>/<run id>/`; here `focus/`
stands in for the container, so those blob names resolve underneath it and the manifest sits in the
run folder with its partitions, as it does in a real run.

## What the files cover

| Property    | Value                                                                             |
| ----------- | --------------------------------------------------------------------------------- |
| Period      | 2026-07-01 to 2026-08-01 (one full billing month, half-open)                      |
| Granularity | Daily, plus one recurring monthly charge                                          |
| Rows        | 776 in FOCUS across two partitions; 745 actual; 775 amortized; 62 reservation     |
| Currency    | JPY, with `x_*InUsd` columns alongside at a flat 150 JPY/USD                      |
| Region      | `westus3`                                                                         |
| Cost basis  | `EffectiveCost` for FOCUS; `CostInBillingCurrency` for the other two              |
| Pricing     | Mostly on demand, with one reserved-instance order and one savings plan in effect |

Resource names in the templated part of the estate carry the deploy-time uniqueness suffix from one
concrete deployment (`cpi-portal-w4n7q2xkm5cdb`, `cpi-sql-w4n7q2xkm5cdb`, `cpiportalw4n7q2xkm5cdb`). A
fresh `bicep/main.bicep` deployment computes a different suffix, so those names will not match a newly
stood up copy character for character. Everything else — resource group, SKUs, sizes, service set —
does, and `check-consistency.py` fails if it stops matching.

Region is the one thing that has to be kept in step by hand. Nothing else in this journey names a
region: `bicep/` takes it from the resource group and the scripts take it from `AZURE_LOCATION`. A cost
export has no such option, so `REGION_ID`, `REGION_NAME` and `REGION_NORMALIZED` at the top of
`estate.py` carry the region the estate is deployed into, and all three need editing together if it
moves. Every other appearance of the region — including the region each meter's product name ends
with — is composed from those three, and `check-consistency.py` fails if one of them drifts.

## Which parts are documented and which are not

Microsoft documents the **column set and the column order** of all four datasets, on the pages linked
above, and publishes a complete `_manifest.json` sample in the
[exports tutorial](https://learn.microsoft.com/en-us/azure/cost-management-billing/costs/tutorial-improved-exports).
Those are what the headers and the manifest here follow.

What is **not** documented, and is therefore shaped to look plausible rather than to match a
specification: the naming of the partition blobs, the export name, the run id, and the `apiVersion`
recorded in `exportConfig`. Nothing should depend on those character for character; re-check them
against a live export first.

One column carries a value the two Microsoft pages disagree about. `cost-usage-details-ea` gives
`PricingModel`'s on-demand value as `On Demand`, while
[understand-usage-details-fields](https://learn.microsoft.com/en-us/azure/cost-management-billing/automate/understand-usage-details-fields)
gives it as `OnDemand`. These files use `OnDemand`; a parser should match case-insensitively and
tolerate the space.

## Regenerating

```bash
python3 make-cost-exports.py           # rewrite every artifact in this directory
python3 make-cost-exports.py /tmp/out  # or write a full copy elsewhere
python3 check-consistency.py           # verify the results against discovery/ and bicep/
```

`estate.py` holds the description of the subscription that both this generator and
`../discovery/make-resource-list.py` read, which is what keeps the artifacts agreeing.
`check-consistency.py` re-derives that agreement from the written files rather than from `estate.py`,
so a generator that stops doing what it says still fails the check.

`fixtures.sha256` records the hash of every written artifact, and the check verifies them, so an edit
to the data — by hand or through a changed generator — cannot pass quietly. After an intended change,
re-record from the journey directory:

```bash
sha256sum $(cut -c 67- costs/fixtures.sha256) > costs/fixtures.sha256
```

Neither generator needs anything outside the Python standard library. Both are deterministic — fixed
period, fixed seed, one seeded generator per meter, no clock reads, and gzip members written with a
zeroed timestamp and no stored filename — so regenerating produces **byte-identical** files, which is
what lets a parity check hash them.
