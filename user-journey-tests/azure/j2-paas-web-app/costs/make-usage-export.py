#!/usr/bin/env python3
"""Build the synthetic FOCUS cost export for the stationery shop (fictional).

EVERYTHING THIS SCRIPT WRITES IS SYNTHETIC. No figure here was measured, on
Azure or anywhere else. It imitates the shape of a Microsoft Cost Management
FOCUS 1.0r2 cost-and-usage export so that a parser written against a real export
works against this one unmodified. See README.md in this directory.

Deterministic by construction: fixed dates, a fixed seed, no clock reads and no
random module state carried between rows, so two runs any distance apart produce
byte-identical output.

Usage:
    python3 make-usage-export.py                 # rewrite pwa-usage-focus.csv here
    python3 make-usage-export.py /tmp/other.csv  # write a copy elsewhere
"""

from __future__ import annotations

import csv
import pathlib
import random
import sys
from datetime import date, datetime, timedelta

# --- shape of the billed month ----------------------------------------------

PERIOD_START = date(2026, 6, 1)
PERIOD_END = date(2026, 7, 1)  # exclusive, matching FOCUS half-open periods
DAYS = (PERIOD_END - PERIOD_START).days

SEED = 20260601

CURRENCY = "JPY"

# The billed region. A cost export cannot leave this column empty, so it is the
# one place in this journey that names a region: it has to agree with wherever
# the estate is actually deployed. Edit both lines together if that moves — the
# quantities are seeded per meter and do not depend on the region, so the rest
# of the file is unchanged. Billing currency follows the billing account, not
# the region, which is why a Japanese account is billed in JPY here.
REGION_ID = "westus3"
REGION_NAME = "West US 3"

RESOURCE_GROUP = "pwa-rg"

# Fabricated identifiers. No real subscription, tenant or billing account.
SUBSCRIPTION_ID = "3f2b6c1e-9a44-4d7e-8b21-5c0f7a9d4e63"
SUBSCRIPTION_NAME = "Stationery Shop Production (fictional)"
BILLING_ACCOUNT_ID = "8801234"
BILLING_ACCOUNT_NAME = "Stationery Shop KK (fictional)"
INVOICE_ID = "T0099887766"

# Deploy-time uniqueness suffix, held constant across the export so the rows
# describe one concrete deployment of the shop.
SUFFIX = "k4xq7m2vb9zdc"

TAGS = (
    '{"Owner":"migration-test","CostCenter":"test-journeys",'
    '"AutoTeardown":"2026-07-01","Journey":"azure/j2-paas-web-app"}'
)

JPY_PER_USD = 150.0

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


# --- the billed line items ---------------------------------------------------
#
# Each entry describes one meter on one resource. `quantity(day_index, rng)`
# returns the units consumed on that day; `unit_price` is the JPY rate.

POSTGRES_NAME = f"pwa-pg-{SUFFIX}"
STORAGE_NAME = f"pwamedia{SUFFIX}"
KEYVAULT_NAME = f"pwa-kv-{SUFFIX}"

LINE_ITEMS = [
    {
        "key": "pg-vcore",
        "resource_name": POSTGRES_NAME,
        "arm_type": "Microsoft.DBforPostgreSQL/flexibleServers",
        "service_name": "Azure Database for PostgreSQL",
        "service_category": "Databases",
        "meter_category": "Azure Database for PostgreSQL",
        "meter_subcategory": "Azure Database for PostgreSQL Flexible Server Burstable",
        "meter_name": "B1ms vCore",
        "meter_id": "9a1c7f60-3b52-4f10-9d84-1c6f5b02ad77",
        "description": "B1ms vCore - Azure Database for PostgreSQL Flexible Server Burstable",
        "unit": "1 Hour",
        "pricing_unit": "1 Hour",
        "unit_price": 3.20,
        # The shop's database is never stopped and never scaled: a flat 24
        # metered hours on every single day of the month.
        "quantity": lambda day, rng: 24.0,
    },
    {
        "key": "pg-storage",
        "resource_name": POSTGRES_NAME,
        "arm_type": "Microsoft.DBforPostgreSQL/flexibleServers",
        "service_name": "Azure Database for PostgreSQL",
        "service_category": "Databases",
        "meter_category": "Azure Database for PostgreSQL",
        "meter_subcategory": "Azure Database for PostgreSQL Flexible Server Storage",
        "meter_name": "Storage Data Stored",
        "meter_id": "b74e2d18-5c99-4a03-8f26-72d0a1e4c355",
        "description": "Storage Data Stored - Azure Database for PostgreSQL Flexible Server",
        "unit": "1 GiB/Month",
        "pricing_unit": "1 GiB/Month",
        "unit_price": 17.25,
        "quantity": lambda day, rng: round(32.0 / DAYS, 6),
    },
    {
        "key": "pg-backup",
        "resource_name": POSTGRES_NAME,
        "arm_type": "Microsoft.DBforPostgreSQL/flexibleServers",
        "service_name": "Azure Database for PostgreSQL",
        "service_category": "Databases",
        "meter_category": "Azure Database for PostgreSQL",
        "meter_subcategory": "Azure Database for PostgreSQL Flexible Server Backup",
        "meter_name": "Backup Storage LRS Data Stored",
        "meter_id": "6d3a90f4-11be-4c77-95ab-0f5d8e2c4471",
        "description": "Backup Storage LRS Data Stored - Azure Database for PostgreSQL Flexible Server",
        "unit": "1 GiB/Month",
        "pricing_unit": "1 GiB/Month",
        "unit_price": 14.90,
        # Retained backups grow as the catalogue and the order table grow.
        "quantity": lambda day, rng: round((1.6 + day * 0.035) / DAYS, 6),
    },
    {
        "key": "plan-s1",
        "resource_name": "pwa-plan",
        "arm_type": "Microsoft.Web/serverfarms",
        "service_name": "Azure App Service",
        "service_category": "Compute",
        "meter_category": "Azure App Service",
        "meter_subcategory": "Standard Plan - Linux",
        "meter_name": "S1 App",
        "meter_id": "2f8c4b71-a6d0-4e39-b512-9c7e30dd6a08",
        "description": "S1 App - Azure App Service Standard Plan Linux",
        "unit": "1 Hour",
        "pricing_unit": "1 Hour",
        "unit_price": 15.00,
        "quantity": lambda day, rng: 24.0,
    },
    {
        "key": "blob-stored",
        "resource_name": STORAGE_NAME,
        "arm_type": "Microsoft.Storage/storageAccounts",
        "service_name": "Azure Blob Storage",
        "service_category": "Storage",
        "meter_category": "Storage",
        "meter_subcategory": "General Block Blob v2 Hot LRS",
        "meter_name": "Hot LRS Data Stored",
        "meter_id": "cf5b1e26-8a74-4d0b-93c1-6e2f7ab5d904",
        "description": "Hot LRS Data Stored - General Block Blob v2",
        "unit": "1 GiB/Month",
        "pricing_unit": "1 GiB/Month",
        "unit_price": 3.45,
        "quantity": lambda day, rng: round((0.38 + day * 0.004) / DAYS, 6),
    },
    {
        "key": "blob-reads",
        "resource_name": STORAGE_NAME,
        "arm_type": "Microsoft.Storage/storageAccounts",
        "service_name": "Azure Blob Storage",
        "service_category": "Storage",
        "meter_category": "Storage",
        "meter_subcategory": "General Block Blob v2 Hot LRS",
        "meter_name": "Hot Read Operations",
        "meter_id": "e0f4a2b9-7c31-4e58-9d06-25b8f1ca3e77",
        "description": "Hot Read Operations - General Block Blob v2",
        "unit": "10K",
        "pricing_unit": "10K",
        "unit_price": 0.85,
        # Product images are cached at the edge, so origin reads stay low.
        "quantity": lambda day, rng: round(rng.uniform(0.9, 1.6), 4),
    },
    {
        "key": "fd-requests",
        "resource_name": "pwa-fd",
        "arm_type": "Microsoft.Cdn/profiles",
        "service_name": "Azure Front Door Service",
        "service_category": "Networking",
        "meter_category": "Azure Front Door Service",
        "meter_subcategory": "Azure Front Door Standard",
        "meter_name": "Standard Requests",
        "meter_id": "1b6d5c84-9f27-4a13-8e70-3d4c9b21e556",
        "description": "Standard Requests - Azure Front Door Standard",
        "unit": "10K",
        "pricing_unit": "10K",
        "unit_price": 1.35,
        # Traffic climbs steadily through June, weekends a little quieter.
        "quantity": lambda day, rng: round(
            (11.0 + day * 0.42) * (0.72 if (PERIOD_START + timedelta(days=day)).weekday() >= 5 else 1.0)
            + rng.uniform(-0.5, 0.5),
            4,
        ),
    },
    {
        "key": "fd-egress",
        "resource_name": "pwa-fd",
        "arm_type": "Microsoft.Cdn/profiles",
        "service_name": "Azure Front Door Service",
        "service_category": "Networking",
        "meter_category": "Azure Front Door Service",
        "meter_subcategory": "Azure Front Door Standard",
        "meter_name": "Standard Data Transfer From Edge",
        "meter_id": "77e2a409-5bd6-4c81-9207-f4a3b8c05e12",
        "description": "Standard Data Transfer From Edge - Azure Front Door Standard",
        "unit": "1 GB",
        "pricing_unit": "1 GB",
        "unit_price": 13.50,
        "quantity": lambda day, rng: round(0.55 + day * 0.018 + rng.uniform(-0.04, 0.04), 4),
    },
    {
        "key": "law-ingest",
        "resource_name": "pwa-logs",
        "arm_type": "Microsoft.OperationalInsights/workspaces",
        "service_name": "Azure Monitor",
        "service_category": "Management and Governance",
        "meter_category": "Log Analytics",
        "meter_subcategory": "Pay-as-you-go Data Ingestion",
        "meter_name": "Pay-as-you-go Data Ingestion",
        "meter_id": "4c8b3e17-62a5-4f94-b0d3-8e17c95a2f60",
        "description": "Pay-as-you-go Data Ingestion - Log Analytics",
        "unit": "1 GB",
        "pricing_unit": "1 GB",
        "unit_price": 414.00,
        # Ingestion rises with traffic: request telemetry plus the slow-query
        # and timeout records the storefront emits under load.
        "quantity": lambda day, rng: round(0.041 + day * 0.0027 + rng.uniform(-0.002, 0.002), 5),
    },
    {
        "key": "kv-ops",
        "resource_name": KEYVAULT_NAME,
        "arm_type": "Microsoft.KeyVault/vaults",
        "service_name": "Azure Key Vault",
        "service_category": "Identity",
        "meter_category": "Key Vault",
        "meter_subcategory": "Vault Operations",
        "meter_name": "Operations",
        "meter_id": "a5d17c02-3e96-4b48-81f7-06c2eb9d4a35",
        "description": "Operations - Key Vault Vault Operations",
        "unit": "10K",
        "pricing_unit": "10K",
        "unit_price": 4.50,
        "quantity": lambda day, rng: round(rng.uniform(0.010, 0.022), 5),
    },
]

# One monthly charge rather than a daily meter.
FRONT_DOOR_BASE_FEE = {
    "key": "fd-base",
    "resource_name": "pwa-fd",
    "arm_type": "Microsoft.Cdn/profiles",
    "service_name": "Azure Front Door Service",
    "service_category": "Networking",
    "meter_category": "Azure Front Door Service",
    "meter_subcategory": "Azure Front Door Standard",
    "meter_name": "Standard Base Fee",
    "meter_id": "9e40b2f5-1a87-4d63-ae09-52c7f3b8016d",
    "description": "Standard Base Fee - Azure Front Door Standard",
    "unit": "1/Month",
    "pricing_unit": "1/Month",
    "unit_price": 5250.00,
    "quantity": 1.0,
}


def stamp(value: date) -> str:
    """FOCUS 1.0r2 timestamps carry seconds."""
    return datetime(value.year, value.month, value.day).strftime("%Y-%m-%dT%H:%M:%SZ")


def build_row(item: dict, start: date, end: date, quantity: float, frequency: str) -> dict:
    cost = round(quantity * item["unit_price"], 4)
    return {
        "BilledCost": f"{cost:.4f}",
        "BillingAccountId": BILLING_ACCOUNT_ID,
        "BillingAccountName": BILLING_ACCOUNT_NAME,
        "BillingCurrency": CURRENCY,
        "BillingPeriodEnd": stamp(PERIOD_END),
        "BillingPeriodStart": stamp(PERIOD_START),
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
        "ContractedUnitPrice": f"{item['unit_price']:.4f}",
        "EffectiveCost": f"{cost:.4f}",
        "InvoiceIssuerName": "Microsoft",
        "ListCost": f"{cost:.4f}",
        "ListUnitPrice": f"{item['unit_price']:.4f}",
        "PricingCategory": "Standard",
        "PricingQuantity": f"{quantity:.6f}",
        "PricingUnit": item["pricing_unit"],
        "ProviderName": "Microsoft",
        "PublisherName": "Microsoft",
        "RegionId": REGION_ID,
        "RegionName": REGION_NAME,
        "ResourceId": resource_id(item["arm_type"], item["resource_name"]),
        "ResourceName": item["resource_name"],
        "ResourceType": item["arm_type"],
        "ServiceCategory": item["service_category"],
        "ServiceName": item["service_name"],
        "SkuId": item["meter_id"],
        "SkuPriceId": f"{item['meter_id']}-{REGION_ID}",
        "SubAccountId": f"/subscriptions/{SUBSCRIPTION_ID}",
        "SubAccountName": SUBSCRIPTION_NAME,
        "Tags": TAGS,
        "x_CostCenter": "test-journeys",
        "x_EffectiveCostInUsd": f"{cost / JPY_PER_USD:.6f}",
        "x_InvoiceId": INVOICE_ID,
        "x_PricingCurrency": CURRENCY,
        "x_ResourceGroupName": RESOURCE_GROUP,
        "x_ResourceType": item["arm_type"],
        "x_SkuMeterCategory": item["meter_category"],
        "x_SkuMeterId": item["meter_id"],
        "x_SkuMeterName": item["meter_name"],
        "x_SkuMeterSubcategory": item["meter_subcategory"],
        "x_SkuOfferId": "MS-AZR-0003P",
        "x_SkuRegion": REGION_ID,
    }


def build_rows() -> list[dict]:
    rows: list[dict] = []
    for item in LINE_ITEMS:
        # A per-item generator, so adding or removing a meter never shifts the
        # numbers of any other meter.
        rng = random.Random(f"{SEED}-{item['key']}")
        for day in range(DAYS):
            start = PERIOD_START + timedelta(days=day)
            quantity = item["quantity"](day, rng)
            rows.append(build_row(item, start, start + timedelta(days=1), quantity, "Usage-Based"))
    rows.append(
        build_row(
            FRONT_DOOR_BASE_FEE,
            PERIOD_START,
            PERIOD_END,
            FRONT_DOOR_BASE_FEE["quantity"],
            "Recurring",
        )
    )
    rows.sort(key=lambda row: (row["ChargePeriodStart"], row["ResourceName"], row["x_SkuMeterName"]))
    return rows


def main() -> None:
    target = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else (
        pathlib.Path(__file__).resolve().parent / "pwa-usage-focus.csv"
    )
    rows = build_rows()
    with target.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=COLUMNS, lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)
    total = sum(float(row["EffectiveCost"]) for row in rows)
    print(f"wrote {len(rows)} rows to {target} ({CURRENCY} {total:,.0f} total EffectiveCost)")


if __name__ == "__main__":
    main()
