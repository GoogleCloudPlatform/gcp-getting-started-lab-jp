#!/usr/bin/env python3
"""Regenerate discovery/azure-migrate-assessment.xlsx — SYNTHETIC fixture data.

This produces a workbook shaped like the file Azure Migrate emits from
"Export assessment" on an Azure VM assessment: an assessment-properties sheet
plus a per-server sheet carrying readiness, recommended size, monthly cost
estimate and an issues column.

Nothing here was measured. Every number is invented. The sibling README.md
records what the file claims.

Deterministic by construction: no timestamps from the clock, no random values,
and the .xlsx container is rewritten with fixed zip entry metadata and pinned
docProps timestamps, so regenerating produces a byte-identical file and a parity
check can hash it. openpyxl restamps docProps/core.xml's dcterms:modified from
the wall clock at save time whatever wb.properties says, so that element is
rewritten after the save rather than set before it.

Usage:
    python3 discovery/make-assessment.py [output.xlsx]

Requires openpyxl. If it is unavailable, the CSV fallback described in
README.md is the supported alternative.
"""

from __future__ import annotations

import datetime as dt
import io
import pathlib
import re
import sys
import zipfile

from openpyxl import Workbook
from openpyxl.styles import Font

# Frozen so the workbook never picks up the wall clock.
FIXED_TIME = dt.datetime(2025, 11, 14, 9, 0, 0)
ZIP_TIME = (1980, 1, 1, 0, 0, 0)

CORE_XML = "docProps/core.xml"
CORE_STAMP = FIXED_TIME.strftime("%Y-%m-%dT%H:%M:%SZ").encode()
CORE_TIME_RE = re.compile(rb"(<dcterms:(?:created|modified)\b[^>]*>)[^<]*(</dcterms:(?:created|modified)>)")

ASSESSMENT_PROPERTIES = [
    ("Assessment name", "wil-consolidation-2025"),
    ("Assessment type", "Azure VM"),
    ("Project name", "wil-migrate-project"),
    ("Discovery source", "Imported (CSV)"),
    ("Sizing criterion", "As on-premises"),
    ("Performance history", "Not applicable"),
    ("Percentile utilization", "Not applicable"),
    ("Comfort factor", 1.0),
    ("Target location", "Japan East"),
    ("Currency", "JPY"),
    ("Offer", "Pay as you go"),
    ("Discount (%)", 0),
    ("VM uptime", "31 days per month, 24 hours per day"),
    ("Azure Hybrid Benefit (Windows Server)", "Yes"),
    ("Azure Hybrid Benefit (SQL Server)", "No"),
    ("Storage redundancy", "Locally redundant"),
    ("Reserved instances", "None"),
    ("Assessment created on", "2025-11-14"),
    ("Azure Migrate agent version", "Not applicable (imported)"),
]

ASSESSED_MACHINE_COLUMNS = [
    "Machine",
    "Operating system",
    "Boot type",
    "Cores",
    "Memory(MB)",
    "Storage(GB)",
    "Azure VM readiness",
    "Azure readiness issues",
    "Recommended size",
    "Compute monthly cost estimate JPY",
    "Storage monthly cost estimate JPY",
    "Estimated monthly cost JPY",
    "Confidence rating (# of stars)",
    "Data collection issues",
    "Group",
]

ASSESSED_MACHINES = [
    [
        "wil-app01",
        "Microsoft Windows Server 2019 Datacenter",
        "BIOS",
        2,
        8192,
        30,
        "Ready for Azure",
        "",
        "Standard_D2ds_v5",
        15840,
        340,
        16180,
        "Not applicable",
        "",
        "wil-lob-servers",
    ],
    [
        "wil-app02",
        "Microsoft Windows Server 2019 Datacenter",
        "BIOS",
        2,
        8192,
        30,
        "Ready for Azure",
        "",
        "Standard_B2ms",
        11960,
        340,
        12300,
        "Not applicable",
        "",
        "wil-lob-servers",
    ],
    [
        "wil-fs01",
        "Microsoft Windows Server 2012 R2 Standard",
        "BIOS",
        2,
        8192,
        500,
        "Ready with conditions",
        (
            "The guest operating system Windows Server 2012 R2 has reached end of "
            "extended support (2023-10-10). Azure supports the VM but Microsoft "
            "provides no security updates without Extended Security Updates. "
            "Marked for decommission - confirm before migrating."
        ),
        "Standard_B2ms",
        11960,
        3120,
        15080,
        "Not applicable",
        "",
        "wil-file-servers",
    ],
]


def build_workbook() -> Workbook:
    wb = Workbook()

    summary = wb.active
    summary.title = "Assessment_Summary"
    summary.append(["Property", "Value"])
    for row in ASSESSMENT_PROPERTIES:
        summary.append(list(row))
    summary.column_dimensions["A"].width = 42
    summary.column_dimensions["B"].width = 40

    machines = wb.create_sheet("All_Assessed_Machines")
    machines.append(ASSESSED_MACHINE_COLUMNS)
    for row in ASSESSED_MACHINES:
        machines.append(row)
    for column, width in zip("ABCDEFGHIJKLMNO", (14, 42, 10, 8, 12, 12, 22, 70, 20, 30, 30, 26, 28, 20, 20)):
        machines.column_dimensions[column].width = width

    for sheet in (summary, machines):
        for cell in sheet[1]:
            cell.font = Font(bold=True)
        sheet.freeze_panes = "A2"

    # Set here for correctness; dcterms:modified is re-pinned after the save,
    # because openpyxl overwrites it from the clock on the way out.
    wb.properties.created = FIXED_TIME
    wb.properties.modified = FIXED_TIME
    wb.properties.creator = "Azure Migrate"
    wb.properties.lastModifiedBy = "Azure Migrate"
    return wb


def pin_core_timestamps(core_xml: bytes) -> bytes:
    """Force dcterms:created / dcterms:modified in docProps/core.xml to FIXED_TIME."""
    pinned, count = CORE_TIME_RE.subn(rb"\g<1>" + CORE_STAMP + rb"\g<2>", core_xml)
    if count != 2:
        raise RuntimeError(
            f"expected 2 dcterms timestamps in {CORE_XML}, rewrote {count} — "
            "openpyxl changed its core.xml layout; update CORE_TIME_RE"
        )
    return pinned


def normalize_zip(raw: bytes) -> bytes:
    """Rewrite the xlsx container with fixed entry metadata and stable ordering."""
    out = io.BytesIO()
    with zipfile.ZipFile(io.BytesIO(raw)) as src:
        names = sorted(src.namelist())
        with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as dst:
            for name in names:
                payload = src.read(name)
                if name == CORE_XML:
                    payload = pin_core_timestamps(payload)
                info = zipfile.ZipInfo(name, date_time=ZIP_TIME)
                info.compress_type = zipfile.ZIP_DEFLATED
                info.external_attr = 0o600 << 16
                dst.writestr(info, payload)
    return out.getvalue()


def main() -> int:
    target = pathlib.Path(
        sys.argv[1]
        if len(sys.argv) > 1
        else pathlib.Path(__file__).with_name("azure-migrate-assessment.xlsx")
    )
    buffer = io.BytesIO()
    build_workbook().save(buffer)
    target.write_bytes(normalize_zip(buffer.getvalue()))
    print(f"wrote {target} ({target.stat().st_size} bytes)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
