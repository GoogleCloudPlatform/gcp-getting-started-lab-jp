#!/usr/bin/env python3
"""Regenerate costs/vsi-actual-cost.csv — SYNTHETIC fixture data.

Produces the CSV that Microsoft Cost Management writes for a
"Cost and usage details (actual)" export on an Enterprise Agreement billing
account: one row per resource per meter per day, at list prices, with no
commitment purchases anywhere in the file.

Nothing here was measured. No real billing account, enrolment, subscription or
invoice is represented; every identifier is invented. The sibling README.md
records what the file claims and what it does not.

Deterministic by construction: the billing period is a frozen constant, every
varying quantity comes from a per-meter seeded generator, and nothing reads the
clock. Regenerating produces a byte-identical file, which is what lets a parity
check hash it.

Usage:
    python3 costs/make-actual-cost.py [output.csv]
"""

from __future__ import annotations

import csv
import datetime as dt
import pathlib
import random
import sys

# The region is the one value in this directory that has to be kept in step by
# hand. Nothing else in this package names a region: the Terraform takes it
# from a variable and the scripts take it from AZURE_LOCATION. An export has no
# such option, so both spellings are pinned here and nowhere else.
REGION_ID = "westus3"
REGION_NAME = "US West 3"

PERIOD_START = dt.date(2026, 6, 1)
PERIOD_END = dt.date(2026, 6, 30)
DAYS = (PERIOD_END - PERIOD_START).days + 1

# Fabricated. This is not a real enrolment, account or subscription.
BILLING_ACCOUNT_ID = "77104412"
BILLING_ACCOUNT_NAME = "the precision-parts MES operator (fictional)"
ACCOUNT_NAME = "the precision-parts MES operator (fictional) - Plant Systems"
ACCOUNT_OWNER_ID = "plant-it@vsi.example"
SUBSCRIPTION_ID = "b41d8a97-2ce6-4f05-9a3b-71e0c5d8fa62"
SUBSCRIPTION_NAME = "the precision-parts MES operator (fictional) Production"
RESOURCE_GROUP = "vsi-rg"
OFFER_ID = "MS-AZR-0017P"
CURRENCY = "JPY"

TAGS = (
    '{"Owner":"migration-test","CostCenter":"test-journeys",'
    '"AutoTeardown":"2026-08-31","Journey":"azure/j5-vmss-sql-iaas"}'
)

COLUMNS = [
    "BillingAccountId",
    "BillingAccountName",
    "BillingPeriodStartDate",
    "BillingPeriodEndDate",
    "AccountName",
    "AccountOwnerId",
    "SubscriptionId",
    "SubscriptionName",
    "Date",
    "Product",
    "PartNumber",
    "MeterId",
    "ServiceFamily",
    "MeterCategory",
    "MeterSubCategory",
    "MeterRegion",
    "MeterName",
    "Quantity",
    "UnitOfMeasure",
    "EffectivePrice",
    "UnitPrice",
    "PayGPrice",
    "CostInBillingCurrency",
    "BillingCurrency",
    "ResourceLocation",
    "ConsumedService",
    "ResourceId",
    "ResourceName",
    "ResourceGroup",
    "ChargeType",
    "Frequency",
    "PublisherType",
    "PricingModel",
    "ReservationId",
    "ReservationName",
    "ProductOrderId",
    "ProductOrderName",
    "Term",
    "benefitId",
    "benefitName",
    "AdditionalInfo",
    "ServiceInfo1",
    "ServiceInfo2",
    "CostCenter",
    "IsAzureCreditEligible",
    "OfferId",
    "Tags",
]


def resource_id(provider_path: str) -> str:
    return (
        f"/subscriptions/{SUBSCRIPTION_ID}/resourceGroups/{RESOURCE_GROUP}"
        f"/providers/{provider_path}"
    )


COMPUTE = "Microsoft.Compute"
NETWORK = "Microsoft.Network"
INSIGHTS = "Microsoft.OperationalInsights"
RECOVERY = "Microsoft.RecoveryServices"


def fixed(value: float):
    """A quantity that is the same every day of the month."""
    return lambda _rng, _day: value


def jitter(low: float, high: float, digits: int = 6):
    """A quantity that moves day to day, from the meter's own seeded stream."""
    return lambda rng, _day: round(rng.uniform(low, high), digits)


# One entry per (resource, meter). Each becomes DAYS rows.
#
# The two scale-set instances bill under the scale set's own resource id, which
# is how Azure attributes Uniform scale-set usage, so their compute is a single
# row per day carrying 48 hours rather than two rows carrying 24.
METERS = [
    {
        "seed": "mes-compute",
        "product": "Virtual Machines DSv5 Series Windows - D2s v5 - US West 3",
        "part_number": "AAH-79341",
        "meter_id": "5a2f81c4-7b09-4d63-9e18-c0d5473f2a86",
        "service_family": "Compute",
        "meter_category": "Virtual Machines",
        "meter_sub_category": "DSv5 Series Windows",
        "meter_name": "D2s v5",
        "unit": "1 Hour",
        "price": 28.80,
        "quantity": fixed(48.0),
        "consumed_service": COMPUTE,
        "resource_id": resource_id("Microsoft.Compute/virtualMachineScaleSets/vsi-mes-vmss"),
        "resource_name": "vsi-mes-vmss",
        "additional_info": '{"ServiceType":"Standard_D2s_v5","UsageType":"ComputeHR"}',
    },
    {
        "seed": "sql-compute",
        "product": "Virtual Machines DSv5 Series Windows - D2s v5 - US West 3",
        "part_number": "AAH-79341",
        "meter_id": "5a2f81c4-7b09-4d63-9e18-c0d5473f2a86",
        "service_family": "Compute",
        "meter_category": "Virtual Machines",
        "meter_sub_category": "DSv5 Series Windows",
        "meter_name": "D2s v5",
        "unit": "1 Hour",
        "price": 28.80,
        "quantity": fixed(24.0),
        "consumed_service": COMPUTE,
        "resource_id": resource_id("Microsoft.Compute/virtualMachines/vsi-sql01"),
        "resource_name": "vsi-sql01",
        "additional_info": '{"ServiceType":"Standard_D2s_v5","UsageType":"ComputeHR"}',
    },
    {
        "seed": "hist-compute",
        "product": "Virtual Machines Dsv3 Series Windows - D4s v3 - US West 3",
        "part_number": "AAD-33742",
        "meter_id": "c81b04ae-6f27-4b95-8d10-73ea9c5f2b41",
        "service_family": "Compute",
        "meter_category": "Virtual Machines",
        "meter_sub_category": "Dsv3 Series Windows",
        "meter_name": "D4s v3",
        "unit": "1 Hour",
        "price": 56.40,
        "quantity": fixed(24.0),
        "consumed_service": COMPUTE,
        "resource_id": resource_id("Microsoft.Compute/virtualMachines/vsi-hist01"),
        "resource_name": "vsi-hist01",
        "additional_info": '{"ServiceType":"Standard_D4s_v3","UsageType":"ComputeHR"}',
    },
    {
        "seed": "mes-disks",
        "product": "Standard SSD Managed Disks - E10 LRS Disk - US West 3",
        "part_number": "AAF-11204",
        "meter_id": "9d3c7f10-5a48-4e2b-b761-8c04e5d92f37",
        "service_family": "Storage",
        "meter_category": "Storage",
        "meter_sub_category": "Standard SSD Managed Disks",
        "meter_name": "E10 LRS Disk",
        "unit": "1/Month",
        "price": 1320.00,
        "quantity": fixed(round(2 / DAYS, 6)),
        "consumed_service": COMPUTE,
        "resource_id": resource_id("Microsoft.Compute/virtualMachineScaleSets/vsi-mes-vmss"),
        "resource_name": "vsi-mes-vmss",
        "additional_info": "",
    },
    {
        "seed": "sql-osdisk",
        "product": "Standard SSD Managed Disks - E10 LRS Disk - US West 3",
        "part_number": "AAF-11204",
        "meter_id": "9d3c7f10-5a48-4e2b-b761-8c04e5d92f37",
        "service_family": "Storage",
        "meter_category": "Storage",
        "meter_sub_category": "Standard SSD Managed Disks",
        "meter_name": "E10 LRS Disk",
        "unit": "1/Month",
        "price": 1320.00,
        "quantity": fixed(round(1 / DAYS, 6)),
        "consumed_service": COMPUTE,
        "resource_id": resource_id("Microsoft.Compute/disks/vsi-sql01-osdisk"),
        "resource_name": "vsi-sql01-osdisk",
        "additional_info": "",
    },
    {
        "seed": "sql-datadisk",
        "product": "Standard SSD Managed Disks - E10 LRS Disk - US West 3",
        "part_number": "AAF-11204",
        "meter_id": "9d3c7f10-5a48-4e2b-b761-8c04e5d92f37",
        "service_family": "Storage",
        "meter_category": "Storage",
        "meter_sub_category": "Standard SSD Managed Disks",
        "meter_name": "E10 LRS Disk",
        "unit": "1/Month",
        "price": 1320.00,
        "quantity": fixed(round(1 / DAYS, 6)),
        "consumed_service": COMPUTE,
        "resource_id": resource_id("Microsoft.Compute/disks/vsi-sql01-data01"),
        "resource_name": "vsi-sql01-data01",
        "additional_info": "",
    },
    {
        "seed": "hist-osdisk",
        "product": "Standard SSD Managed Disks - E10 LRS Disk - US West 3",
        "part_number": "AAF-11204",
        "meter_id": "9d3c7f10-5a48-4e2b-b761-8c04e5d92f37",
        "service_family": "Storage",
        "meter_category": "Storage",
        "meter_sub_category": "Standard SSD Managed Disks",
        "meter_name": "E10 LRS Disk",
        "unit": "1/Month",
        "price": 1320.00,
        "quantity": fixed(round(1 / DAYS, 6)),
        "consumed_service": COMPUTE,
        "resource_id": resource_id("Microsoft.Compute/disks/vsi-hist01-osdisk"),
        "resource_name": "vsi-hist01-osdisk",
        "additional_info": "",
    },
    {
        "seed": "hist-datadisk",
        "product": "Standard SSD Managed Disks - E20 LRS Disk - US West 3",
        "part_number": "AAF-11208",
        "meter_id": "2e6a94db-13c7-49f0-a58e-6bd207c4139a",
        "service_family": "Storage",
        "meter_category": "Storage",
        "meter_sub_category": "Standard SSD Managed Disks",
        "meter_name": "E20 LRS Disk",
        "unit": "1/Month",
        "price": 5100.00,
        "quantity": fixed(round(1 / DAYS, 6)),
        "consumed_service": COMPUTE,
        "resource_id": resource_id("Microsoft.Compute/disks/vsi-hist01-data01"),
        "resource_name": "vsi-hist01-data01",
        "additional_info": "",
    },
    {
        "seed": "lb-rules",
        "product": "Load Balancer - Standard Included LB Rules and Outbound Rules - US West 3",
        "part_number": "AAD-56091",
        "meter_id": "4b7e2510-cd83-4a06-91f2-70d6c8b3e415",
        "service_family": "Networking",
        "meter_category": "Load Balancer",
        "meter_sub_category": "Standard",
        "meter_name": "Standard Included LB Rules and Outbound Rules",
        "unit": "1 Hour",
        "price": 3.75,
        "quantity": fixed(24.0),
        "consumed_service": NETWORK,
        "resource_id": resource_id("Microsoft.Network/loadBalancers/vsi-mes-lb"),
        "resource_name": "vsi-mes-lb",
        "additional_info": "",
    },
    {
        "seed": "mes-pip",
        "product": "Virtual Network - Standard IPv4 Static Public IP - US West 3",
        "part_number": "AAD-31908",
        "meter_id": "8f05c3a7-b419-4d26-95e3-1a7c0be48d52",
        "service_family": "Networking",
        "meter_category": "Virtual Network",
        "meter_sub_category": "IP Addresses",
        "meter_name": "Standard IPv4 Static Public IP",
        "unit": "1 Hour",
        "price": 0.54,
        "quantity": fixed(24.0),
        "consumed_service": NETWORK,
        "resource_id": resource_id("Microsoft.Network/publicIPAddresses/vsi-mes-pip"),
        "resource_name": "vsi-mes-pip",
        "additional_info": "",
    },
    {
        "seed": "nat-pip",
        "product": "Virtual Network - Standard IPv4 Static Public IP - US West 3",
        "part_number": "AAD-31908",
        "meter_id": "8f05c3a7-b419-4d26-95e3-1a7c0be48d52",
        "service_family": "Networking",
        "meter_category": "Virtual Network",
        "meter_sub_category": "IP Addresses",
        "meter_name": "Standard IPv4 Static Public IP",
        "unit": "1 Hour",
        "price": 0.54,
        "quantity": fixed(24.0),
        "consumed_service": NETWORK,
        "resource_id": resource_id("Microsoft.Network/publicIPAddresses/vsi-nat-pip"),
        "resource_name": "vsi-nat-pip",
        "additional_info": "",
    },
    {
        "seed": "natgw-hours",
        "product": "NAT Gateway - Standard NAT Gateway - US West 3",
        "part_number": "AAD-44117",
        "meter_id": "6c1d8093-2f47-4ba5-8e30-d95b70fa2c68",
        "service_family": "Networking",
        "meter_category": "NAT Gateway",
        "meter_sub_category": "NAT Gateway",
        "meter_name": "Standard NAT Gateway",
        "unit": "1 Hour",
        "price": 6.75,
        "quantity": fixed(24.0),
        "consumed_service": NETWORK,
        "resource_id": resource_id("Microsoft.Network/natGateways/vsi-data-natgw"),
        "resource_name": "vsi-data-natgw",
        "additional_info": "",
    },
    {
        # A NAT gateway always bills per-GB alongside its hours; an export
        # showing only the hours would be missing half the meter.
        "seed": "natgw-data",
        "product": "NAT Gateway - Standard Data Processed - US West 3",
        "part_number": "AAD-44118",
        "meter_id": "b70e5f21-8c46-4d93-a15b-2073ce8f461d",
        "service_family": "Networking",
        "meter_category": "NAT Gateway",
        "meter_sub_category": "NAT Gateway",
        "meter_name": "Standard Data Processed",
        "unit": "1 GB",
        "price": 6.75,
        "quantity": jitter(0.4, 1.3),
        "consumed_service": NETWORK,
        "resource_id": resource_id("Microsoft.Network/natGateways/vsi-data-natgw"),
        "resource_name": "vsi-data-natgw",
        "additional_info": "",
    },
    {
        "seed": "bandwidth",
        "product": "Bandwidth - Standard Data Transfer Out - US West 3",
        "part_number": "AAA-21075",
        "meter_id": "d24f70b8-9e15-4c83-a067-3b8e51c9d740",
        "service_family": "Networking",
        "meter_category": "Bandwidth",
        "meter_sub_category": "Standard Data Transfer Out",
        "meter_name": "Standard Data Transfer Out",
        "unit": "1 GB",
        "price": 12.50,
        "quantity": jitter(0.9, 2.4),
        "consumed_service": NETWORK,
        "resource_id": resource_id("Microsoft.Network/loadBalancers/vsi-mes-lb"),
        "resource_name": "vsi-mes-lb",
        "additional_info": "",
    },
    {
        "seed": "law-ingestion",
        "product": "Log Analytics - Pay-as-you-go Data Ingestion - US West 3",
        "part_number": "AAD-60218",
        "meter_id": "a0937fe5-4c81-4b7d-9032-58e6c1a7d493",
        "service_family": "Management and Governance",
        "meter_category": "Log Analytics",
        "meter_sub_category": "Pay-as-you-go Data",
        "meter_name": "Pay-as-you-go Data Ingestion",
        "unit": "1 GB",
        "price": 345.00,
        "quantity": jitter(7.4, 10.6),
        "consumed_service": INSIGHTS,
        "resource_id": resource_id("Microsoft.OperationalInsights/workspaces/vsi-law"),
        "resource_name": "vsi-law",
        "additional_info": "",
    },
    {
        # Retained volume grows with every month the workspace keeps rather
        # than drops. Two production years of it now costs about two thirds of
        # what ingesting a month costs, and at the default retention this line
        # would not exist at all.
        "seed": "law-retention",
        "product": "Log Analytics - Pay-as-you-go Data Retention - US West 3",
        "part_number": "AAD-60219",
        "meter_id": "f3e5b207-8a94-4d10-b6c7-2915e0d84b6f",
        "service_family": "Management and Governance",
        "meter_category": "Log Analytics",
        "meter_sub_category": "Pay-as-you-go Data",
        "meter_name": "Pay-as-you-go Data Retention",
        "unit": "1 GB/Month",
        "price": 15.00,
        # ~4,050 GB retained: roughly twelve months at today's volume behind
        # twelve at the pre-2025 volume, less the 31 days that carry no
        # retention charge.
        "quantity": jitter(133.0, 137.0),
        "consumed_service": INSIGHTS,
        "resource_id": resource_id("Microsoft.OperationalInsights/workspaces/vsi-law"),
        "resource_name": "vsi-law",
        "additional_info": "",
    },
    {
        "seed": "backup-instances",
        "product": "Backup - Standard Protected Instances - US West 3",
        "part_number": "AAD-18830",
        "meter_id": "7b482c6f-05de-4913-ac27-e1f6039b5a24",
        "service_family": "Storage",
        "meter_category": "Backup",
        "meter_sub_category": "Azure Backup",
        "meter_name": "Standard Protected Instances",
        "unit": "1/Month",
        "price": 1500.00,
        "quantity": fixed(round(1 / DAYS, 6)),
        "consumed_service": RECOVERY,
        "resource_id": resource_id("Microsoft.RecoveryServices/vaults/vsi-rsv-4c9a7e13"),
        "resource_name": "vsi-rsv-4c9a7e13",
        "additional_info": "",
    },
    {
        "seed": "backup-storage",
        "product": "Backup - LRS Data Stored - US West 3",
        "part_number": "AAD-18841",
        "meter_id": "1f9d06c3-74a8-4b52-8e01-c6237ba4f90d",
        "service_family": "Storage",
        "meter_category": "Backup",
        "meter_sub_category": "Azure Backup",
        "meter_name": "LRS Data Stored",
        "unit": "1 GB/Month",
        "price": 3.30,
        "quantity": jitter(5.4, 6.2),
        "consumed_service": RECOVERY,
        "resource_id": resource_id("Microsoft.RecoveryServices/vaults/vsi-rsv-4c9a7e13"),
        "resource_name": "vsi-rsv-4c9a7e13",
        "additional_info": "",
    },
]


def build_rows() -> list[dict]:
    rows = []
    for meter in METERS:
        rng = random.Random(meter["seed"])
        for offset in range(DAYS):
            day = PERIOD_START + dt.timedelta(days=offset)
            quantity = meter["quantity"](rng, day)
            price = meter["price"]
            rows.append({
                "BillingAccountId": BILLING_ACCOUNT_ID,
                "BillingAccountName": BILLING_ACCOUNT_NAME,
                "BillingPeriodStartDate": PERIOD_START.isoformat(),
                "BillingPeriodEndDate": PERIOD_END.isoformat(),
                "AccountName": ACCOUNT_NAME,
                "AccountOwnerId": ACCOUNT_OWNER_ID,
                "SubscriptionId": SUBSCRIPTION_ID,
                "SubscriptionName": SUBSCRIPTION_NAME,
                "Date": day.isoformat(),
                "Product": meter["product"],
                "PartNumber": meter["part_number"],
                "MeterId": meter["meter_id"],
                "ServiceFamily": meter["service_family"],
                "MeterCategory": meter["meter_category"],
                "MeterSubCategory": meter["meter_sub_category"],
                "MeterRegion": REGION_NAME,
                "MeterName": meter["meter_name"],
                "Quantity": f"{quantity:.6f}",
                "UnitOfMeasure": meter["unit"],
                "EffectivePrice": f"{price:.4f}",
                "UnitPrice": f"{price:.4f}",
                "PayGPrice": f"{price:.4f}",
                "CostInBillingCurrency": f"{quantity * price:.4f}",
                "BillingCurrency": CURRENCY,
                "ResourceLocation": REGION_ID,
                "ConsumedService": meter["consumed_service"],
                "ResourceId": meter["resource_id"],
                "ResourceName": meter["resource_name"],
                "ResourceGroup": RESOURCE_GROUP,
                "ChargeType": "Usage",
                "Frequency": "UsageBased",
                "PublisherType": "Microsoft",
                "PricingModel": "OnDemand",
                "ReservationId": "",
                "ReservationName": "",
                "ProductOrderId": "",
                "ProductOrderName": "",
                "Term": "",
                "benefitId": "",
                "benefitName": "",
                "AdditionalInfo": meter["additional_info"],
                "ServiceInfo1": "",
                "ServiceInfo2": "",
                "CostCenter": "test-journeys",
                "IsAzureCreditEligible": "TRUE",
                "OfferId": OFFER_ID,
                "Tags": TAGS,
            })
    return rows


def main() -> int:
    out_path = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else (
        pathlib.Path(__file__).resolve().parent / "vsi-actual-cost.csv"
    )
    rows = build_rows()

    with out_path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=COLUMNS, lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)

    total = sum(float(row["CostInBillingCurrency"]) for row in rows)
    print(f"wrote {out_path} — {len(rows)} data rows, {total:,.0f} {CURRENCY} over {DAYS} days")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
