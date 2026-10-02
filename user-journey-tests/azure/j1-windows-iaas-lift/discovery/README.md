# discovery/ — synthetic Azure Migrate assessment export

**Everything in this directory is SYNTHETIC.** No number here was measured, on Azure or anywhere else.
No real tenant, subscription, customer or host is represented. It exists so that tooling reading this
directory meets an assessment artifact shaped the way a real one is shaped.

## What it imitates

`azure-migrate-assessment.xlsx` imitates the Excel workbook **Azure Migrate** produces from
**Export assessment** on an Azure VM assessment — the per-server, row-level export as the portal emitted
it in late 2025, not the newer read-only Reports summary. The real export carries per-VM Azure readiness,
a recommended size, monthly compute and storage cost estimates, and an issues column, which is exactly
the column set reproduced here. The assessment is import-based, so there is no appliance agent version to
imitate; the summary sheet records that as `Not applicable (imported)`.

Neither Microsoft nor Google publishes a literal column contract for that workbook — the docs describe
its content, never its headers. So these headers are a faithful imitation, not a specification, and any
parser reading them should match tolerantly and case-insensitively rather than requiring exact strings.

| Sheet                   | Contents                                                                                           |
| ----------------------- | -------------------------------------------------------------------------------------------------- |
| `Assessment_Summary`    | Assessment properties: sizing criterion, target location, currency, offer, Azure Hybrid Benefit    |
| `All_Assessed_Machines` | One row per assessed server: OS, cores, memory, storage, readiness, recommended size, cost, issues |

## The story behind the file

The fictional clinic group's IT contractor ran an **import-based (CSV) assessment** in November 2025 to price
a consolidation. Import-based means the server inventory was typed in from a spreadsheet rather than
collected by an appliance, which has two consequences visible in the file and worth honoring in any
parse:

- **Sizing criterion is "As on-premises"**, not performance-based.
- **Confidence rating is "Not applicable"** on every row. Azure Migrate does not assign a performance
  coverage rating to CSV-imported servers or to as-is sizing. That absence means "no performance data
  was collected", not "the performance data was poor".

Three servers are in scope, and the cost columns are worth two notes:

- They are **Azure-target estimates in JPY** — what Azure Migrate thought running these servers as Azure
  VMs would cost. They are not a measurement of anything the clinic actually paid.
- The summary sheet records **Azure Hybrid Benefit (Windows Server): Yes**. That was the contractor's
  assumption when pricing.

## Regenerating

```bash
python3 make-assessment.py            # rewrites azure-migrate-assessment.xlsx in place
python3 make-assessment.py /tmp/a.xlsx  # or write a copy elsewhere
```

`make-assessment.py` needs `openpyxl`. It is deterministic — no clock reads, no random values, and the
`.xlsx` zip container and its `docProps` timestamps are rewritten with fixed metadata — so regenerating
produces a **byte-identical** file, which is what lets a parity check hash it.

If `openpyxl` is unavailable in your environment, export the `All_Assessed_Machines` sheet to
`azure-migrate-assessment.csv` and keep the same headers; the real tool emits `.xlsx`, so the workbook is
the higher-fidelity form and is what ships here.
