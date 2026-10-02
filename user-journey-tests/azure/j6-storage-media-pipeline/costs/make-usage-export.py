#!/usr/bin/env python3
"""Build the synthetic FOCUS cost export for the media-licensing operator (fictional).

EVERYTHING THIS SCRIPT WRITES IS SYNTHETIC. No figure here was measured, on
Azure or anywhere else. It imitates the shape of a Microsoft Cost Management
FOCUS 1.0r2 cost-and-usage export so that a parser written against a real export
works against this one unmodified. See README.md in this directory.

Deterministic by construction: fixed dates, a fixed seed, one seeded generator
per meter, no clock reads and no random module state carried between meters, so
two runs any distance apart produce byte-identical output.

Usage:
    python3 make-usage-export.py                 # rewrite smp-usage-focus.csv here
    python3 make-usage-export.py /tmp/other.csv  # write a copy elsewhere
"""

from __future__ import annotations

import csv
import pathlib
import random
import sys
from datetime import date, datetime, timedelta

# --- shape of the billed window ----------------------------------------------
#
# Four consecutive monthly billing periods. Daily granularity, which is what
# Cost Management writes for a FOCUS export, plus one recurring monthly charge
# per period for the Front Door base fee.

PERIOD_START = date(2026, 4, 1)
PERIOD_END = date(2026, 8, 1)  # exclusive, matching FOCUS half-open periods
DAYS = (PERIOD_END - PERIOD_START).days

# First day of each billing period inside the window, and the exclusive end of
# the last one. Used for BillingPeriodStart/End, which are per-month, not
# per-window.
BILLING_PERIODS = [
    (date(2026, 4, 1), date(2026, 5, 1)),
    (date(2026, 5, 1), date(2026, 6, 1)),
    (date(2026, 6, 1), date(2026, 7, 1)),
    (date(2026, 7, 1), date(2026, 8, 1)),
]

SEED = 20260401

CURRENCY = "USD"

# The billed region. A cost export cannot leave this column empty, so it is the
# one place in this journey that names a region: it has to agree with wherever
# the estate is actually deployed. Edit both lines together if that moves — the
# quantities are seeded per meter and do not depend on the region, so the rest
# of the file is unchanged. Front Door is billed against a Zone rather than a
# region; FD_ZONE below is the CDN billing zone that covers REGION_ID.
REGION_ID = "westus3"
REGION_NAME = "West US 3"
FD_ZONE = "Zone 1"

RESOURCE_GROUP = "smp-rg"

# Fabricated identifiers. No real subscription, tenant or billing account.
SUBSCRIPTION_ID = "c81a53f7-2d64-4e19-9f30-7ab4c6e52d18"
SUBSCRIPTION_NAME = "the media-licensing operator (fictional) Library"
BILLING_ACCOUNT_ID = "7714902"
BILLING_ACCOUNT_NAME = "the media-licensing operator (fictional)"
INVOICE_ID = "G0042215508"

# Deploy-time uniqueness suffix, held constant across the export so the rows
# describe one concrete deployment of the library.
SUFFIX = "7f3c91ad"

TAGS = (
    '{"Owner":"migration-test","CostCenter":"test-journeys",'
    '"AutoTeardown":"2026-08-01","Journey":"azure/j6-storage-media-pipeline"}'
)

MEDIA_ACCOUNT = f"smpmedia{SUFFIX}"
WIP_ACCOUNT = f"smpwip{SUFFIX}"
DELIVERY_ACCOUNT = f"smpdelivery{SUFFIX}"
DATA_FACTORY = f"smp-adf-{SUFFIX}"
FRONT_DOOR = "smp-fd"

# --- the bulk restore ---------------------------------------------------------
#
# In June the studio pulled the 2019-2021 shoots back out of the archive tier
# for a licensing review. Rehydration runs over twelve days; the restored blobs
# land in the hot tier and the lifecycle rules will not move them back down for
# another six months, so the hot and archive capacity lines step at the same
# time and stay stepped for the rest of the window.
RESTORE_FIRST_DAY = date(2026, 6, 8)
RESTORE_LAST_DAY = date(2026, 6, 19)  # inclusive
RESTORE_DAYS = (RESTORE_LAST_DAY - RESTORE_FIRST_DAY).days + 1
RESTORED_GB = 18_400.0

COLUMNS = [
    "BilledCost",
    "BillingAccountId",
    "BillingAccountName",
    "BillingCurrency",
    "BillingPeriodEnd",
    "BillingPeriodStart",
    "ChargeCategory",
    "ChargeClass",
    "ChargeDescription",
    "ChargeFrequency",
    "ChargePeriodEnd",
    "ChargePeriodStart",
    "CommitmentDiscountCategory",
    "CommitmentDiscountId",
    "CommitmentDiscountName",
    "CommitmentDiscountStatus",
    "CommitmentDiscountType",
    "ConsumedQuantity",
    "ConsumedUnit",
    "ContractedCost",
    "ContractedUnitPrice",
    "EffectiveCost",
    "InvoiceIssuerName",
    "ListCost",
    "ListUnitPrice",
    "PricingCategory",
    "PricingQuantity",
    "PricingUnit",
    "ProviderName",
    "PublisherName",
    "RegionId",
    "RegionName",
    "ResourceId",
    "ResourceName",
    "ResourceType",
    "ServiceCategory",
    "ServiceName",
    "SkuId",
    "SkuPriceId",
    "SubAccountId",
    "SubAccountName",
    "Tags",
    "x_CostCenter",
    "x_EffectiveCostInUsd",
    "x_InvoiceId",
    "x_PricingCurrency",
    "x_ResourceGroupName",
    "x_ResourceType",
    "x_SkuMeterCategory",
    "x_SkuMeterId",
    "x_SkuMeterName",
    "x_SkuMeterSubcategory",
    "x_SkuOfferId",
    "x_SkuRegion",
]


def resource_id(provider_type: str, name: str) -> str:
    return (
        f"/subscriptions/{SUBSCRIPTION_ID}/resourceGroups/{RESOURCE_GROUP}"
        f"/providers/{provider_type}/{name}"
    )


def day_of(index: int) -> date:
    return PERIOD_START + timedelta(days=index)


def restoring(index: int) -> bool:
    return RESTORE_FIRST_DAY <= day_of(index) <= RESTORE_LAST_DAY


def restored_by(index: int) -> float:
    """Gigabytes already back in the hot tier at the start of the given day."""
    day = day_of(index)
    if day <= RESTORE_FIRST_DAY:
        return 0.0
    if day > RESTORE_LAST_DAY:
        return RESTORED_GB
    done = (day - RESTORE_FIRST_DAY).days
    return round(RESTORED_GB * done / RESTORE_DAYS, 3)


def weekend(index: int) -> bool:
    return day_of(index).weekday() >= 5


def month_days(index: int) -> int:
    """Days in the billing period the given day falls in.

    A `1 GB/Month` meter is emitted daily as one day's fraction of the month, so
    the daily quantities over a period sum to exactly the GB-months stored. The
    divisor is the length of that month, not a flat 30, or a 31-day month bills
    more than it should.
    """
    for start, end in BILLING_PERIODS:
        if start <= day_of(index) < end:
            return (end - start).days
    raise ValueError(f"{day_of(index)} is outside the billed window")


# --- the billed line items ----------------------------------------------------
#
# Each entry describes one meter on one resource. `quantity(day_index, rng)`
# returns the units consumed on that day, or None to emit no row for that day.
# Meter names, units, meter ids and unit prices are the westus3 / Zone 1 list
# rates published by the Azure Retail Prices API.

LINE_ITEMS = [
    # ---- Front Door: the edge, and the largest line on the bill -------------
    {
        "key": "fd-egress",
        "resource_name": FRONT_DOOR,
        "arm_type": "Microsoft.Cdn/profiles",
        "service_name": "Azure Front Door Service",
        "service_category": "Networking",
        "meter_category": "Azure Front Door Service",
        "meter_subcategory": "Azure Front Door",
        "meter_name": "Standard Data Transfer Out",
        "meter_id": "b0d1f3e7-4c25-5f8a-9e61-3ab7c204d95f",
        "description": "Standard Data Transfer Out - Azure Front Door",
        "unit": "1 GB",
        "pricing_unit": "1 GB",
        "unit_price": 0.0825,
        "region_id": FD_ZONE,
        "region_name": FD_ZONE,
        # Preview renders leaving the edge for browsers. Licensing customers
        # browse on weekdays; the summer catalogue refresh lifts the whole
        # baseline from May onward.
        "quantity": lambda day, rng: round(
            (268.0 + day * 1.65) * (0.58 if weekend(day) else 1.0) + rng.uniform(-9.0, 9.0),
            4,
        ),
    },
    {
        "key": "fd-requests",
        "resource_name": FRONT_DOOR,
        "arm_type": "Microsoft.Cdn/profiles",
        "service_name": "Azure Front Door Service",
        "service_category": "Networking",
        "meter_category": "Azure Front Door Service",
        "meter_subcategory": "Azure Front Door",
        "meter_name": "Standard Requests",
        "meter_id": "5e9a17c4-8b02-5d6e-a374-c1f8b62e0473",
        "description": "Standard Requests - Azure Front Door",
        "unit": "10K",
        "pricing_unit": "10K",
        "unit_price": 0.009,
        "region_id": FD_ZONE,
        "region_name": FD_ZONE,
        "quantity": lambda day, rng: round(
            (148.0 + day * 0.83) * (0.58 if weekend(day) else 1.0) + rng.uniform(-4.0, 4.0),
            4,
        ),
    },
    # ---- the library account (RA-GRS) ---------------------------------------
    {
        "key": "media-hot-stored",
        "resource_name": MEDIA_ACCOUNT,
        "arm_type": "Microsoft.Storage/storageAccounts",
        "service_name": "Azure Blob Storage",
        "service_category": "Storage",
        "meter_category": "Storage",
        "meter_subcategory": "General Block Blob v2 Hot RA-GRS",
        "meter_name": "Hot RA-GRS Data Stored",
        "meter_id": "b588960a-646b-56f1-8ac7-fbd7ae3b2dd8",
        "description": "Hot RA-GRS Data Stored - General Block Blob v2",
        "unit": "1 GB/Month",
        "pricing_unit": "1 GB/Month",
        "unit_price": 0.046,
        # New shoots plus everything the restore put back on hot.
        "quantity": lambda day, rng: round(
            (2050.0 + day * 3.4 + restored_by(day)) / month_days(day), 6
        ),
    },
    {
        "key": "media-cool-stored",
        "resource_name": MEDIA_ACCOUNT,
        "arm_type": "Microsoft.Storage/storageAccounts",
        "service_name": "Azure Blob Storage",
        "service_category": "Storage",
        "meter_category": "Storage",
        "meter_subcategory": "General Block Blob v2 Cool RA-GRS",
        "meter_name": "Cool RA-GRS Data Stored",
        "meter_id": "5dc1fe8a-5f84-5f2f-8c3e-fd9343f8ee9f",
        "description": "Cool RA-GRS Data Stored - General Block Blob v2",
        "unit": "1 GB/Month",
        "pricing_unit": "1 GB/Month",
        "unit_price": 0.025,
        "quantity": lambda day, rng: round((3390.0 + day * 2.1) / month_days(day), 6),
    },
    {
        "key": "media-archive-stored",
        "resource_name": MEDIA_ACCOUNT,
        "arm_type": "Microsoft.Storage/storageAccounts",
        "service_name": "Azure Blob Storage",
        "service_category": "Storage",
        "meter_category": "Storage",
        "meter_subcategory": "General Block Blob v2 Archive RA-GRS",
        "meter_name": "Archive RA-GRS Data Stored",
        "meter_id": "10084ddb-fdd8-5ad1-b229-fbba21518037",
        "description": "Archive RA-GRS Data Stored - General Block Blob v2",
        "unit": "1 GB/Month",
        "pricing_unit": "1 GB/Month",
        "unit_price": 0.00299,
        # The back catalogue, less whatever the restore pulled back up.
        "quantity": lambda day, rng: round(
            (44000.0 + day * 5.5 - restored_by(day)) / month_days(day), 6
        ),
    },
    {
        "key": "media-hot-reads",
        "resource_name": MEDIA_ACCOUNT,
        "arm_type": "Microsoft.Storage/storageAccounts",
        "service_name": "Azure Blob Storage",
        "service_category": "Storage",
        "meter_category": "Storage",
        "meter_subcategory": "General Block Blob v2 Hot RA-GRS",
        "meter_name": "Hot Read Operations",
        "meter_id": "16dedefa-f6ab-55e8-9755-6c6d2a69574e",
        "description": "Hot Read Operations - General Block Blob v2",
        "unit": "10K",
        "pricing_unit": "10K",
        "unit_price": 0.004,
        "quantity": lambda day, rng: round(rng.uniform(11.0, 19.5), 4),
    },
    {
        "key": "media-hot-writes",
        "resource_name": MEDIA_ACCOUNT,
        "arm_type": "Microsoft.Storage/storageAccounts",
        "service_name": "Azure Blob Storage",
        "service_category": "Storage",
        "meter_category": "Storage",
        "meter_subcategory": "General Block Blob v2 Hot RA-GRS",
        "meter_name": "Hot GRS Write Operations",
        "meter_id": "37e6ada1-29a9-5242-ab20-4db777786097",
        "description": "Hot GRS Write Operations - General Block Blob v2",
        "unit": "10K",
        "pricing_unit": "10K",
        # Card dumps land on weekdays; the restore adds a write per rehydrated
        # blob on top.
        "unit_price": 0.1,
        "quantity": lambda day, rng: round(
            rng.uniform(0.9, 2.4) * (0.35 if weekend(day) else 1.0)
            + (7.6 if restoring(day) else 0.0),
            4,
        ),
    },
    {
        "key": "media-archive-writes",
        "resource_name": MEDIA_ACCOUNT,
        "arm_type": "Microsoft.Storage/storageAccounts",
        "service_name": "Azure Blob Storage",
        "service_category": "Storage",
        "meter_category": "Storage",
        "meter_subcategory": "General Block Blob v2 Archive RA-GRS",
        "meter_name": "Archive GRS Write Operations",
        "meter_id": "2549be6d-f7b1-51ba-b3a8-f68092a8db42",
        "description": "Archive GRS Write Operations - General Block Blob v2",
        "unit": "10K",
        "pricing_unit": "10K",
        "unit_price": 0.2,
        # Written by the lifecycle rules as they tier the day's eligible blobs.
        "quantity": lambda day, rng: round(rng.uniform(0.18, 0.52), 4),
    },
    {
        "key": "media-georeplication",
        "resource_name": MEDIA_ACCOUNT,
        "arm_type": "Microsoft.Storage/storageAccounts",
        "service_name": "Azure Blob Storage",
        "service_category": "Storage",
        "meter_category": "Storage",
        "meter_subcategory": "Storage - Bandwidth",
        "meter_name": "Geo-Replication v2 Data Transfer",
        "meter_id": "dd24c000-9a10-5567-a57e-939e2ef7d5dd",
        "description": "Geo-Replication v2 Data Transfer - Storage - Bandwidth",
        "unit": "1 GB",
        "pricing_unit": "1 GB",
        "unit_price": 0.02,
        # Every byte written to the library is copied to the paired region.
        "quantity": lambda day, rng: round(
            rng.uniform(4.0, 9.0) * (0.35 if weekend(day) else 1.0), 4
        ),
    },
    # ---- the bulk restore: rows exist only inside the restore window --------
    {
        "key": "archive-retrieval",
        "resource_name": MEDIA_ACCOUNT,
        "arm_type": "Microsoft.Storage/storageAccounts",
        "service_name": "Azure Blob Storage",
        "service_category": "Storage",
        "meter_category": "Storage",
        "meter_subcategory": "General Block Blob v2 Archive RA-GRS",
        "meter_name": "Archive Data Retrieval",
        "meter_id": "9ce78b14-ad92-512d-984b-29c6cbcc64a3",
        "description": "Archive Data Retrieval - General Block Blob v2",
        "unit": "1 GB",
        "pricing_unit": "1 GB",
        "unit_price": 0.02,
        "quantity": lambda day, rng: (
            round(RESTORED_GB / RESTORE_DAYS + rng.uniform(-40.0, 40.0), 4)
            if restoring(day)
            else None
        ),
    },
    {
        "key": "archive-read-ops",
        "resource_name": MEDIA_ACCOUNT,
        "arm_type": "Microsoft.Storage/storageAccounts",
        "service_name": "Azure Blob Storage",
        "service_category": "Storage",
        "meter_category": "Storage",
        "meter_subcategory": "General Block Blob v2 Archive RA-GRS",
        "meter_name": "Archive Read Operations",
        "meter_id": "7db6e4df-e230-5c36-bf62-81574d109e8b",
        "description": "Archive Read Operations - General Block Blob v2",
        "unit": "10K",
        "pricing_unit": "10K",
        "unit_price": 5.0,
        "quantity": lambda day, rng: (
            round(3.1 + rng.uniform(-0.25, 0.25), 4) if restoring(day) else None
        ),
    },
    {
        "key": "archive-priority-retrieval",
        "resource_name": MEDIA_ACCOUNT,
        "arm_type": "Microsoft.Storage/storageAccounts",
        "service_name": "Azure Blob Storage",
        "service_category": "Storage",
        "meter_category": "Storage",
        "meter_subcategory": "General Block Blob v2 Archive RA-GRS",
        "meter_name": "Archive Priority Data Retrieval",
        "meter_id": "2b8d4573-2e44-5c8e-b665-6ed5a560eb2f",
        "description": "Archive Priority Data Retrieval - General Block Blob v2",
        "unit": "1 GB",
        "pricing_unit": "1 GB",
        "unit_price": 0.1,
        # The first two days were run at high priority, before anyone looked at
        # what high priority costs.
        "quantity": lambda day, rng: (
            round(575.0 + rng.uniform(-25.0, 25.0), 4)
            if RESTORE_FIRST_DAY <= day_of(day) <= RESTORE_FIRST_DAY + timedelta(days=1)
            else None
        ),
    },
    {
        "key": "archive-priority-read-ops",
        "resource_name": MEDIA_ACCOUNT,
        "arm_type": "Microsoft.Storage/storageAccounts",
        "service_name": "Azure Blob Storage",
        "service_category": "Storage",
        "meter_category": "Storage",
        "meter_subcategory": "General Block Blob v2 Archive RA-GRS",
        "meter_name": "Archive Priority Read Operations",
        "meter_id": "7efa2071-de20-5646-8fc8-9f820cd3bbff",
        "description": "Archive Priority Read Operations - General Block Blob v2",
        "unit": "10K",
        "pricing_unit": "10K",
        "unit_price": 50.0,
        "quantity": lambda day, rng: (
            round(1.15 + rng.uniform(-0.06, 0.06), 4)
            if RESTORE_FIRST_DAY <= day_of(day) <= RESTORE_FIRST_DAY + timedelta(days=1)
            else None
        ),
    },
    # ---- the delivery origin -------------------------------------------------
    {
        "key": "delivery-stored",
        "resource_name": DELIVERY_ACCOUNT,
        "arm_type": "Microsoft.Storage/storageAccounts",
        "service_name": "Azure Blob Storage",
        "service_category": "Storage",
        "meter_category": "Storage",
        "meter_subcategory": "General Block Blob v2 Hot LRS",
        "meter_name": "Hot LRS Data Stored",
        "meter_id": "346659ec-c0fc-5215-bff0-df5cc2c59a51",
        "description": "Hot LRS Data Stored - General Block Blob v2",
        "unit": "1 GB/Month",
        "pricing_unit": "1 GB/Month",
        "unit_price": 0.0184,
        "quantity": lambda day, rng: round((258.0 + day * 0.62) / month_days(day), 6),
    },
    {
        "key": "delivery-reads",
        "resource_name": DELIVERY_ACCOUNT,
        "arm_type": "Microsoft.Storage/storageAccounts",
        "service_name": "Azure Blob Storage",
        "service_category": "Storage",
        "meter_category": "Storage",
        "meter_subcategory": "General Block Blob v2 Hot LRS",
        "meter_name": "Hot Read Operations",
        "meter_id": "16dedefa-f6ab-55e8-9755-6c6d2a69574e",
        "description": "Hot Read Operations - General Block Blob v2",
        "unit": "10K",
        "pricing_unit": "10K",
        "unit_price": 0.004,
        # Only the cache misses reach the origin.
        "quantity": lambda day, rng: round(rng.uniform(2.1, 4.8), 4),
    },
    # ---- the edit bay's scratch share ---------------------------------------
    {
        "key": "wip-provisioned",
        "resource_name": WIP_ACCOUNT,
        "arm_type": "Microsoft.Storage/storageAccounts",
        "service_name": "Azure Files",
        "service_category": "Storage",
        "meter_category": "Storage",
        "meter_subcategory": "Premium Files",
        "meter_name": "Premium LRS Provisioned",
        "meter_id": "9985deed-6d56-51e1-8038-6f4ad4e00110",
        "description": "Premium LRS Provisioned - Premium Files",
        "unit": "1 GB/Month",
        "pricing_unit": "1 GB/Month",
        "unit_price": 0.16,
        # Premium shares bill on the provisioned 100 GiB whatever is in them.
        "quantity": lambda day, rng: round(100.0 / month_days(day), 6),
    },
    # ---- the nightly intake move --------------------------------------------
    {
        "key": "adf-activity-runs",
        "resource_name": DATA_FACTORY,
        "arm_type": "Microsoft.DataFactory/factories",
        "service_name": "Azure Data Factory v2",
        "service_category": "Analytics",
        "meter_category": "Azure Data Factory v2",
        "meter_subcategory": "Cloud",
        "meter_name": "Cloud Orchestration Activity Run",
        "meter_id": "04f2be54-5cfe-4ad7-97f3-0badfc1dc247",
        "description": "Cloud Orchestration Activity Run - Azure Data Factory v2",
        "unit": "1K",
        "pricing_unit": "1K",
        "unit_price": 1.0,
        "quantity": lambda day, rng: 0.002,
    },
    {
        "key": "adf-data-movement",
        "resource_name": DATA_FACTORY,
        "arm_type": "Microsoft.DataFactory/factories",
        "service_name": "Azure Data Factory v2",
        "service_category": "Analytics",
        "meter_category": "Azure Data Factory v2",
        "meter_subcategory": "Cloud",
        "meter_name": "Cloud Data Movement",
        "meter_id": "9d6f5dbf-90a1-46bc-85b7-e9c3f92bae35",
        "description": "Cloud Data Movement - Azure Data Factory v2",
        "unit": "1 Hour",
        "pricing_unit": "1 Hour",
        "unit_price": 0.25,
        # However long it takes to drain that night's intake container.
        "quantity": lambda day, rng: round(
            rng.uniform(0.35, 1.15) * (0.3 if weekend(day) else 1.0), 4
        ),
    },
]

# One recurring charge per billing period rather than a daily meter. A single
# profile is billed once whatever it has inside it.
FRONT_DOOR_BASE_FEE = {
    "key": "fd-base",
    "resource_name": FRONT_DOOR,
    "arm_type": "Microsoft.Cdn/profiles",
    "service_name": "Azure Front Door Service",
    "service_category": "Networking",
    "meter_category": "Azure Front Door Service",
    "meter_subcategory": "Azure Front Door",
    "meter_name": "Standard Base Fees",
    "meter_id": "a3c6e50b-71d9-5f24-8bb0-46e2d19c8375",
    "description": "Standard Base Fees - Azure Front Door",
    "unit": "1/Month",
    "pricing_unit": "1/Month",
    "unit_price": 35.0,
    "region_id": FD_ZONE,
    "region_name": FD_ZONE,
    "quantity": 1.0,
}


def stamp(value: date) -> str:
    """FOCUS 1.0r2 timestamps carry seconds."""
    return datetime(value.year, value.month, value.day).strftime("%Y-%m-%dT%H:%M:%SZ")


def billing_period(day: date) -> tuple[date, date]:
    for start, end in BILLING_PERIODS:
        if start <= day < end:
            return start, end
    raise ValueError(f"{day} is outside the billed window")


def build_row(item: dict, start: date, end: date, quantity: float, frequency: str) -> dict:
    cost = round(quantity * item["unit_price"], 4)
    bp_start, bp_end = billing_period(start)
    region_id = item.get("region_id", REGION_ID)
    region_name = item.get("region_name", REGION_NAME)
    return {
        "BilledCost": f"{cost:.4f}",
        "BillingAccountId": BILLING_ACCOUNT_ID,
        "BillingAccountName": BILLING_ACCOUNT_NAME,
        "BillingCurrency": CURRENCY,
        "BillingPeriodEnd": stamp(bp_end),
        "BillingPeriodStart": stamp(bp_start),
        "ChargeCategory": "Usage",
        "ChargeClass": "",
        "ChargeDescription": item["description"],
        "ChargeFrequency": frequency,
        "ChargePeriodEnd": stamp(end),
        "ChargePeriodStart": stamp(start),
        "CommitmentDiscountCategory": "",
        "CommitmentDiscountId": "",
        "CommitmentDiscountName": "",
        "CommitmentDiscountStatus": "",
        "CommitmentDiscountType": "",
        "ConsumedQuantity": f"{quantity:.6f}",
        "ConsumedUnit": item["unit"],
        "ContractedCost": f"{cost:.4f}",
        "ContractedUnitPrice": f"{item['unit_price']:.6f}",
        "EffectiveCost": f"{cost:.4f}",
        "InvoiceIssuerName": "Microsoft",
        "ListCost": f"{cost:.4f}",
        "ListUnitPrice": f"{item['unit_price']:.6f}",
        "PricingCategory": "Standard",
        "PricingQuantity": f"{quantity:.6f}",
        "PricingUnit": item["pricing_unit"],
        "ProviderName": "Microsoft",
        "PublisherName": "Microsoft",
        "RegionId": region_id,
        "RegionName": region_name,
        "ResourceId": resource_id(item["arm_type"], item["resource_name"]),
        "ResourceName": item["resource_name"],
        "ResourceType": item["arm_type"],
        "ServiceCategory": item["service_category"],
        "ServiceName": item["service_name"],
        "SkuId": item["meter_id"],
        "SkuPriceId": f"{item['meter_id']}-{region_id}",
        "SubAccountId": f"/subscriptions/{SUBSCRIPTION_ID}",
        "SubAccountName": SUBSCRIPTION_NAME,
        "Tags": TAGS,
        "x_CostCenter": "test-journeys",
        "x_EffectiveCostInUsd": f"{cost:.6f}",
        "x_InvoiceId": INVOICE_ID,
        "x_PricingCurrency": CURRENCY,
        "x_ResourceGroupName": RESOURCE_GROUP,
        "x_ResourceType": item["arm_type"],
        "x_SkuMeterCategory": item["meter_category"],
        "x_SkuMeterId": item["meter_id"],
        "x_SkuMeterName": item["meter_name"],
        "x_SkuMeterSubcategory": item["meter_subcategory"],
        "x_SkuOfferId": "MS-AZR-0017G",
        "x_SkuRegion": region_id,
    }


def build_rows() -> list[dict]:
    rows: list[dict] = []
    for item in LINE_ITEMS:
        # A per-item generator, so adding or removing a meter never shifts the
        # numbers of any other meter.
        rng = random.Random(f"{SEED}-{item['key']}")
        for day in range(DAYS):
            quantity = item["quantity"](day, rng)
            if quantity is None:
                continue
            start = day_of(day)
            rows.append(build_row(item, start, start + timedelta(days=1), quantity, "Usage-Based"))

    for bp_start, bp_end in BILLING_PERIODS:
        rows.append(
            build_row(
                FRONT_DOOR_BASE_FEE,
                bp_start,
                bp_end,
                FRONT_DOOR_BASE_FEE["quantity"],
                "Recurring",
            )
        )

    rows.sort(key=lambda row: (row["ChargePeriodStart"], row["ResourceName"], row["x_SkuMeterName"]))
    return rows


def main() -> None:
    target = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else (
        pathlib.Path(__file__).resolve().parent / "smp-usage-focus.csv"
    )
    rows = build_rows()
    with target.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=COLUMNS, lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)

    total = sum(float(row["EffectiveCost"]) for row in rows)
    per_month: dict[str, float] = {}
    for row in rows:
        per_month.setdefault(row["BillingPeriodStart"][:7], 0.0)
        per_month[row["BillingPeriodStart"][:7]] += float(row["EffectiveCost"])
    print(f"wrote {len(rows)} rows to {target} ({CURRENCY} {total:,.2f} total EffectiveCost)")
    for month in sorted(per_month):
        print(f"  {month}  {CURRENCY} {per_month[month]:,.2f}")


if __name__ == "__main__":
    main()
