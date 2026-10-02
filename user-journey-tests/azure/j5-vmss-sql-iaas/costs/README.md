# costs/ — synthetic Azure cost and usage export

**Everything in this directory is SYNTHETIC.** No figure here was measured, on Azure or anywhere else.
No real billing account, enrolment, subscription, invoice or customer is represented; the billing
account number, the subscription GUID, the meter ids and the part numbers are all fabricated. It exists
so that tooling reading this directory meets a cost export shaped the way a real one is shaped.

## What it imitates

`vsi-actual-cost.csv` imitates the CSV that **Microsoft Cost Management** writes for a
**Cost and usage details (actual)** export on an **Enterprise Agreement** billing account, as configured
from Cost Management > Exports in mid-2026. Microsoft publishes the column contract at
<https://learn.microsoft.com/en-us/azure/cost-management-billing/automate/understand-usage-details-fields>.

This is **not** a FOCUS export, and the difference is the first thing a parser has to notice. The
discriminating columns here are `PricingModel`, `ChargeType` and `CostInBillingCurrency`; there is no
`BilledCost`, no `EffectiveCost` and no `ChargePeriodStart`. Anything keyed on FOCUS column names reads
this file as empty.

Three details are reproduced rather than glossed over:

- **`PricingModel` is the discount discriminator**, and it carries `OnDemand` on every row here. The
  commitment columns (`ReservationId`, `ReservationName`, `ProductOrderId`, `benefitId`, `benefitName`,
  `Term`) are present but empty, which is what an estate that has never bought a reservation or a
  savings plan looks like. There are no `Purchase` and no `UnusedReservation` rows anywhere.
- **Rows are daily**, one per resource per meter per day, which is the only granularity Cost Management
  emits regardless of how often the export is scheduled.
- **`Tags` is a JSON object with its enclosing braces.** The legacy Enterprise Agreement portal download
  omitted them; the modern export does not, and this file imitates the modern export.

## What the file covers

| Property    | Value                                                       |
| ----------- | ----------------------------------------------------------- |
| Period      | 2026-06-01 to 2026-06-30 inclusive (one full billing month) |
| Granularity | Daily                                                       |
| Rows        | 540 data rows across 18 resource-and-meter combinations     |
| Currency    | JPY                                                         |
| Region      | `westus3`                                                   |
| Cost basis  | `CostInBillingCurrency`                                     |
| Pricing     | Pay-as-you-go list price throughout                         |
| Total       | ~279,900 JPY for the month                                  |

`EffectivePrice`, `UnitPrice` and `PayGPrice` all carry the same number on every row, because there is
no discount of any kind on this account.

The export is dated a month before the discovery export in `../discovery/`. That is the normal shape:
you pull last month's closed bill while you are looking at this month's inventory.

## Two things to know before reconciling this against anything else

**Names carry a deploy-time suffix.** The Recovery Services vault appears as `vsi-rsv-4c9a7e13`, whose
suffix is computed at deployment from the subscription and the resource group name. A fresh deployment
of `terraform/` computes a different suffix, so that one name will not match character for character.
Everything else — resource group, machine names, disk names, sizes, meters — does.

**Region is kept in step by hand.** Nothing else in this package names a region: the Terraform takes it
from a variable and the scripts take it from `AZURE_LOCATION`. A cost export has no such option, so
`REGION_ID` and `REGION_NAME` at the top of `make-actual-cost.py` carry the region the estate is
deployed into, and both need editing together if it moves. The quantities are seeded per meter and
independent of the region, so nothing else in the file changes when it does.

## Regenerating

```bash
python3 make-actual-cost.py               # rewrites vsi-actual-cost.csv in place
python3 make-actual-cost.py /tmp/a.csv    # or write a copy elsewhere
```

`make-actual-cost.py` needs nothing outside the Python standard library. It is deterministic — a fixed
period, one seeded generator per meter, and no clock reads anywhere — so regenerating produces a
**byte-identical** file, which is what lets a parity check hash it.
