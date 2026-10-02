#!/usr/bin/env python3
"""Check that the cost exports, the resource listing and bicep/ still agree.

Run after regenerating anything under costs/ or discovery/:

    python3 costs/check-consistency.py

It re-derives every claim from the written files rather than from estate.py, so
a generator that stops doing what it says still fails here. Exits non-zero on
the first section that reports a failure, and prints every check either way.

What it verifies:

  goldens       the artifacts are byte-for-byte the ones recorded in
                fixtures.sha256, so no edit passes unnoticed
  manifest      the run manifest describes the partitions actually on disk
  schema        the FOCUS partitions carry the 1.2-preview column contract
  portal        the templated resources carry one set of names and sizes
                everywhere they appear, including in bicep/
  inventory     every listed resource that Azure meters has charges, and every
                charge inside a listed resource group has a listed resource
  commitments   reservation identifiers join across the cost and reservation files
  totals        the three cost datasets add up to the same money
  region        one region throughout
"""

from __future__ import annotations

import csv
import gzip
import hashlib
import io
import json
import pathlib
import re
import sys
from collections import defaultdict

HERE = pathlib.Path(__file__).resolve().parent
JOURNEY = HERE.parent
# focus/ stands in for the storage container the export is written to, so the
# manifest's blob names resolve underneath it.
FOCUS_CONTAINER = HERE / "focus"
DISCOVERY = JOURNEY / "discovery" / "az-resource-list.json"
BICEP_MAIN = JOURNEY / "bicep" / "main.bicep"
GOLDENS = HERE / "fixtures.sha256"

EPSILON = 0.05  # JPY, for comparing independently rounded sums

# Columns the FOCUS 1.2-preview schema renamed, with the 1.0 spelling they
# replaced. The old spelling of the meter column is still carried alongside.
RENAMED_COLUMNS = {
    "InvoiceId": "x_InvoiceId",
    "PricingCurrency": "x_PricingCurrency",
    "SkuMeter": "x_SkuMeterName",
}
RETAINED_OLD_SPELLINGS = {"x_SkuMeterName", "x_PricingCurrency"}
# Columns the 1.2-preview schema documents as "Currently null/empty".
DOCUMENTED_EMPTY_COLUMNS = [
    "CapacityReservationId",
    "CapacityReservationStatus",
    "CommitmentDiscountQuantity",
    "CommitmentDiscountStatus",
    "CommitmentDiscountUnit",
    "SkuPriceDetails",
]
# A 1.0 column that 1.2-preview does not carry.
ABSENT_IN_12_PREVIEW = ["x_SkuTerm"]

# Azure bills nothing against these resource types; the charges belong to a
# parent, a child or nothing at all.
UNMETERED_TYPES = {
    "Microsoft.Compute/virtualMachines/extensions",
    "Microsoft.Network/networkInterfaces",
    "Microsoft.Network/networkSecurityGroups",
    "Microsoft.Network/virtualNetworks",
    "Microsoft.Sql/servers",
}

FAILURES: list[str] = []
SECTION = ""


def section(name: str) -> None:
    global SECTION
    SECTION = name
    print(f"\n[{name}]")


def check(ok: bool, description: str, detail: str = "") -> None:
    if ok:
        print(f"  PASS  {description}")
    else:
        suffix = f" — {detail}" if detail else ""
        print(f"  FAIL  {description}{suffix}")
        FAILURES.append(f"{SECTION}: {description}{suffix}")


# --- loading -----------------------------------------------------------------


def read_csv(path: pathlib.Path) -> tuple[list[str], list[dict]]:
    with path.open(newline="", encoding="utf-8") as handle:
        reader = csv.DictReader(handle)
        return list(reader.fieldnames or []), list(reader)


def read_gzip_csv(path: pathlib.Path) -> tuple[list[str], list[dict]]:
    with gzip.open(path, "rb") as handle:
        text = handle.read().decode("utf-8")
    reader = csv.DictReader(io.StringIO(text))
    return list(reader.fieldnames or []), list(reader)


def money(rows: list[dict], column: str) -> float:
    return sum(float(row[column] or 0) for row in rows)


def main() -> int:
    manifest_paths = sorted(FOCUS_CONTAINER.rglob("_manifest.json"))
    if len(manifest_paths) != 1:
        print(f"FAILED — expected one manifest under {FOCUS_CONTAINER}, found {len(manifest_paths)}")
        return 1
    manifest = json.loads(manifest_paths[0].read_text(encoding="utf-8"))
    inventory = json.loads(DISCOVERY.read_text(encoding="utf-8"))
    actual_columns, actual = read_csv(HERE / "cpi-actual-cost.csv")
    amortized_columns, amortized = read_csv(HERE / "cpi-amortized-cost.csv")
    _, reservations = read_csv(HERE / "cpi-reservation-usage.csv")
    bicep = BICEP_MAIN.read_text(encoding="utf-8")

    # ---- recorded hashes -----------------------------------------------------
    # Any edit to a written artifact — by hand or by a changed generator —
    # shows up here rather than passing quietly. Re-record with:
    #   cd .. && sha256sum $(cut -c 67- costs/fixtures.sha256) > costs/fixtures.sha256
    section("goldens")
    recorded = 0
    for line in GOLDENS.read_text(encoding="utf-8").splitlines():
        if not line.strip():
            continue
        digest, name = line.split(maxsplit=1)
        target = JOURNEY / name.strip().lstrip("*")
        if not target.exists():
            check(False, f"{name.strip()} exists")
            continue
        actual_digest = hashlib.sha256(target.read_bytes()).hexdigest()
        check(actual_digest == digest, f"{name.strip()} matches its recorded hash", actual_digest)
        recorded += 1
    check(recorded >= 7, f"{recorded} artifacts are covered by a recorded hash")

    # ---- manifest ------------------------------------------------------------
    section("manifest")
    blobs = manifest["blobs"]
    on_disk = sorted(
        str(p.relative_to(FOCUS_CONTAINER)) for p in FOCUS_CONTAINER.rglob("*.csv.gz")
    )
    named = sorted(b["blobName"] for b in blobs)
    check(named == on_disk, "manifest blob names resolve to the partitions on disk",
          f"{named} vs {on_disk}")
    check(
        manifest_paths[0].parent == (FOCUS_CONTAINER / blobs[0]["blobName"]).parent,
        "the manifest sits in the run folder alongside its partitions",
    )
    check(
        manifest["blobCount"] == len(blobs) == len(on_disk),
        f"blobCount is {manifest['blobCount']} and that many partitions exist",
    )

    focus_columns: list[str] = []
    focus: list[dict] = []
    for blob in blobs:
        name = pathlib.PurePosixPath(blob["blobName"]).name
        path = FOCUS_CONTAINER / blob["blobName"]
        columns, rows = read_gzip_csv(path)
        focus_columns = focus_columns or columns
        focus.extend(rows)
        check(
            path.stat().st_size == blob["byteCount"],
            f"{name} is {blob['byteCount']} bytes as the manifest says",
            f"on disk {path.stat().st_size}",
        )
        check(
            len(rows) == blob["dataRowCount"],
            f"{name} holds {blob['dataRowCount']} data rows as the manifest says",
            f"counted {len(rows)}",
        )
        check(columns == focus_columns, f"{name} repeats the header of the first partition")
    check(
        manifest["dataRowCount"] == len(focus),
        f"dataRowCount {manifest['dataRowCount']} matches the partitions ({len(focus)})",
    )
    check(
        manifest["byteCount"] == sum(b["byteCount"] for b in blobs),
        "byteCount is the sum of the partitions",
    )
    check(
        manifest["exportConfig"]["dataVersion"] == "1.2-preview",
        "manifest declares dataset version 1.2-preview",
        manifest["exportConfig"]["dataVersion"],
    )

    # ---- FOCUS column contract ----------------------------------------------
    section("schema")
    for new, old in RENAMED_COLUMNS.items():
        check(new in focus_columns, f"{new} is present under its 1.2-preview name")
        if old in RETAINED_OLD_SPELLINGS:
            check(old in focus_columns, f"{old} is still carried alongside {new}")
        else:
            check(old not in focus_columns, f"{old} is not carried, {new} replaced it")
    for column in ABSENT_IN_12_PREVIEW:
        check(column not in focus_columns, f"{column} is absent, as 1.2-preview has no such column")
    for column in DOCUMENTED_EMPTY_COLUMNS:
        present = column in focus_columns
        check(present, f"{column} is declared")
        if present:
            populated = [row for row in focus if (row[column] or "").strip()]
            check(
                not populated,
                f"{column} is empty in every row, as the schema documents",
                f"{len(populated)} populated",
            )
    check(
        len(focus_columns) == len(set(focus_columns)),
        "no column name appears twice in the FOCUS header",
    )
    for name, columns in (("actual", actual_columns), ("amortized", amortized_columns)):
        for required in ("PricingModel", "ChargeType", "CostInBillingCurrency"):
            check(required in columns, f"{name} export carries {required}")
    check(
        actual_columns == amortized_columns,
        "the two cost-details exports share one column set",
    )

    # ---- the templated resources --------------------------------------------
    section("portal")
    by_id = {item["id"]: item for item in inventory}
    inventory_names = {item["name"]: item for item in inventory}

    suffixes = set()
    for stem, bicep_expression in (
        ("cpi-portal-", "'cpi-portal-${uniqueSuffix}'"),
        ("cpi-sql-", "'cpi-sql-${uniqueSuffix}'"),
        ("cpiportal", "'cpiportal${uniqueSuffix}'"),
    ):
        check(bicep_expression in bicep, f"bicep/main.bicep composes {bicep_expression}")
        matches = [n for n in inventory_names if n.startswith(stem) and n != stem and "/" not in n]
        check(len(matches) == 1, f"exactly one listed resource is named {stem}<suffix>", str(matches))
        if matches:
            suffixes.add(matches[0][len(stem) :])
    check(
        len(suffixes) == 1 and all(re.fullmatch(r"[a-z0-9]{13}", s) for s in suffixes),
        "the templated names share one 13-character suffix",
        str(sorted(suffixes)),
    )

    check("'cpi-plan'" in bicep, "bicep/main.bicep names the plan cpi-plan")
    check("cpi-plan" in inventory_names, "cpi-plan is in the resource listing")
    plan = inventory_names.get("cpi-plan")
    if plan:
        check(plan["sku"]["name"] == "B1", "cpi-plan is listed as B1", str(plan["sku"]))
        check(
            "param appServicePlanSkuName string = 'B1'" in bicep,
            "bicep/main.bicep defaults the plan to B1",
        )
    database = next(
        (i for i in inventory if i["type"] == "Microsoft.Sql/servers/databases"), None
    )
    check(database is not None, "the portal database is in the resource listing")
    if database:
        check(
            database["name"].endswith("/cpiportal"),
            "the database is named cpiportal under its server",
            database["name"],
        )
        check(database["sku"]["name"] == "Basic", "the database is listed as Basic")
        check(
            "param sqlDatabaseSkuName string = 'Basic'" in bicep,
            "bicep/main.bicep defaults the database to Basic",
        )

    focus_meters = defaultdict(set)
    for row in focus:
        focus_meters[row["ResourceName"]].add(row["SkuMeter"])
    check("B1 App" in focus_meters.get("cpi-plan", set()), "cpi-plan is billed on the B1 App meter")
    check(
        "B DTUs" in focus_meters.get("cpiportal", set()),
        "the database is billed on a Basic-tier DTU meter",
    )
    portal_storage = next(
        (
            i
            for i in inventory
            if i["type"] == "Microsoft.Storage/storageAccounts" and i["name"].startswith("cpiportal")
        ),
        None,
    )
    check(portal_storage is not None, "the portal storage account is in the resource listing")
    if portal_storage:
        check(
            portal_storage["sku"]["name"] == "Standard_LRS",
            "the portal storage account is listed as Standard_LRS",
        )
        check(
            portal_storage["name"] in focus_meters,
            "the portal storage account has charges",
        )

    for name in ("cpi-plan", "cpiportal"):
        for label, rows in (("actual", actual), ("amortized", amortized)):
            check(
                any(row["ResourceName"] == name for row in rows),
                f"{name} appears in the {label} export",
            )

    # ---- inventory against the charges --------------------------------------
    section("inventory")
    listed_groups = {item["resourceGroup"] for item in inventory}
    charged_ids = {row["ResourceId"] for row in focus if row["ResourceId"]}
    charged_ids_lower = {i.lower() for i in charged_ids}

    missing_charges = [
        item["id"]
        for item in inventory
        if item["type"] not in UNMETERED_TYPES and item["id"].lower() not in charged_ids_lower
    ]
    check(
        not missing_charges,
        "every listed resource Azure meters has charges",
        f"{len(missing_charges)}: {missing_charges[:3]}",
    )

    unmetered_with_charges = [
        item["id"]
        for item in inventory
        if item["type"] in UNMETERED_TYPES and item["id"].lower() in charged_ids_lower
    ]
    check(
        not unmetered_with_charges,
        "nothing Azure does not meter carries charges",
        str(unmetered_with_charges[:3]),
    )

    # Anything billed inside a resource group the listing covers must be in the
    # listing. Charges from anywhere else are outside what this listing claims.
    inventory_ids_lower = {resource_id.lower() for resource_id in by_id}
    unlisted_inside = sorted(
        {
            row["ResourceId"]
            for row in focus
            if row["x_ResourceGroupName"] in listed_groups
            and row["ResourceId"].lower() not in inventory_ids_lower
        }
    )
    check(
        not unlisted_inside,
        "every charge inside a listed resource group has a listed resource",
        f"{len(unlisted_inside)}: {unlisted_inside[:3]}",
    )

    focus_ids = {row["ResourceId"] for row in focus}
    for label, rows in (("actual", actual), ("amortized", amortized)):
        ids = {row["ResourceId"] for row in rows}
        check(ids <= focus_ids, f"the {label} export bills nothing the FOCUS export does not")

    outside = sorted(
        {row["x_ResourceGroupName"] for row in focus if row["x_ResourceGroupName"]} - listed_groups
    )
    print(
        f"  note  charges arrive from {len(listed_groups) + len(outside)} resource groups; "
        f"the listing covers {len(listed_groups)}"
    )

    # ---- commitments ---------------------------------------------------------
    section("commitments")
    reserved_rows = [r for r in amortized if r["PricingModel"] == "Reservation"]
    order_ids = {r["ProductOrderId"] for r in reserved_rows}
    reservation_ids = {r["ReservationId"] for r in reserved_rows}
    check(len(order_ids) == 1 and "" not in order_ids, "one order id on every reservation row", str(order_ids))
    check(len(reservation_ids) == 1, "one reservation id on every reservation row", str(reservation_ids))

    detail_orders = {r["ReservationOrderId"] for r in reservations}
    detail_reservations = {r["ReservationId"] for r in reservations}
    check(detail_orders == order_ids, "reservation details join on the same order id")
    check(
        detail_reservations == reservation_ids,
        "reservation details join on the same reservation id",
    )

    by_day: dict[str, list[dict]] = defaultdict(list)
    for row in reservations:
        by_day[row["UsageDate"]].append(row)
    reserved_hours_ok = True
    used_plus_unused_ok = True
    unused_by_day = defaultdict(float)
    for row in amortized:
        if row["ChargeType"] == "UnusedReservation":
            unused_by_day[row["Date"]] += float(row["Quantity"])
    for day, rows in by_day.items():
        quantity = int(rows[0]["TotalReservedQuantity"])
        reserved = float(rows[0]["ReservedHours"])
        if reserved != quantity * 24.0:
            reserved_hours_ok = False
        used = sum(float(r["UsedHours"]) for r in rows)
        if abs(used + unused_by_day.get(day, 0.0) - reserved) > 1e-6:
            used_plus_unused_ok = False
    check(reserved_hours_ok, "reserved hours are the reserved instance count times 24")
    check(
        used_plus_unused_ok,
        "hours used by instances plus hours not used add up to the hours reserved",
    )
    check(
        all(r["RIUsedHours"] == r["UsedHours"] for r in reservations),
        "the two used-hours columns agree",
    )
    detail_instances = {r["InstanceId"].lower() for r in reservations}
    check(
        detail_instances <= inventory_ids_lower,
        "every instance in the reservation details is in the resource listing",
    )
    covered = {r["ResourceId"].lower() for r in reserved_rows if r["ChargeType"] == "Usage"}
    check(
        detail_instances <= covered,
        "every instance in the reservation details is billed under the reservation",
    )

    savings_rows = [r for r in amortized if r["PricingModel"] == "SavingsPlan"]
    check(bool(savings_rows), "the amortized export carries savings plan rows")
    check(
        all(r["benefitId"] and r["benefitName"] for r in savings_rows),
        "every savings plan row carries a benefit id and name",
    )
    purchases = [r for r in actual if r["ChargeType"] == "Purchase"]
    check(bool(purchases), "the actual export carries a purchase row")
    check(
        all(r["PartNumber"] == "" for r in purchases),
        "purchase rows carry no part number",
    )

    # ---- money ---------------------------------------------------------------
    section("totals")
    focus_billed = money(focus, "BilledCost")
    focus_effective = money(focus, "EffectiveCost")
    actual_total = money(actual, "CostInBillingCurrency")
    amortized_total = money(amortized, "CostInBillingCurrency")
    check(
        abs(focus_billed - actual_total) < EPSILON,
        f"FOCUS BilledCost matches the actual export ({focus_billed:,.2f})",
        f"actual {actual_total:,.2f}",
    )
    check(
        abs(focus_effective - amortized_total) < EPSILON,
        f"FOCUS EffectiveCost matches the amortized export ({focus_effective:,.2f})",
        f"amortized {amortized_total:,.2f}",
    )
    check(
        focus_effective > focus_billed,
        "the two bases differ, as a commitment paid outside this month implies",
    )

    # ---- region --------------------------------------------------------------
    section("region")
    regions = {row["RegionId"] for row in focus} | {row["ResourceLocation"] for row in actual}
    locations = {item["location"] for item in inventory}
    check(len(regions) == 1, "the cost exports name one region", str(regions))
    check(regions == locations, "the resource listing names the same region", str(locations))

    region_names = {row["RegionName"] for row in focus}
    check(len(region_names) == 1, "FOCUS names one region in long form", str(region_names))
    region_name = next(iter(region_names))
    meter_regions = {row["MeterRegion"] for row in actual} | {
        row["MeterRegion"] for row in amortized
    }
    check(
        meter_regions == {region_name},
        "MeterRegion agrees with the FOCUS region name",
        str(meter_regions),
    )
    normalized = {row["ResourceLocationNormalized"] for row in actual}
    check(len(normalized) == 1 and "" not in normalized, "one normalized location", str(normalized))
    # Product names end with the region the meter was rated in. A region that
    # moves has to move here too.
    tails = {
        row["ProductName"].rsplit(" - ", 1)[-1]
        for row in actual
        if " - " in row["ProductName"]
    }
    stale = {t for t in tails if re.match(r"^(East|West|North|South|Central) ", t) and t != region_name}
    check(not stale, "no product name carries a different region", str(stale))
    check(region_name in tails, "product names carry the billed region", str(sorted(tails)[:4]))

    print()
    if FAILURES:
        print(f"FAILED — {len(FAILURES)} check(s)")
        for failure in FAILURES:
            print(f"  {failure}")
        return 1
    print("All checks passed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
