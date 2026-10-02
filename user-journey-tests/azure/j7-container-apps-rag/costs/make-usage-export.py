#!/usr/bin/env python3
"""Build the synthetic FOCUS cost export for the robo-advisory operator (fictional).

EVERYTHING THIS SCRIPT WRITES IS SYNTHETIC. No figure here was measured, on
Azure or anywhere else. It imitates the shape of a Microsoft Cost Management
FOCUS 1.0r2 cost-and-usage export so that a parser written against a real export
works against this one unmodified. See README.md in this directory.

Deterministic by construction: fixed dates, a fixed seed, no clock reads and no
random module state carried between rows, so two runs any distance apart produce
byte-identical output.

Usage:
    python3 make-usage-export.py                 # rewrite car-usage-focus.csv here
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
# one place in this estate that names a region: it has to agree with wherever
# the estate is actually deployed. Edit these lines together if that moves — the
# quantities are seeded per meter and do not depend on the region, so the rest
# of the file is unchanged. Billing currency follows the billing account, not
# the region, which is why a Japanese account is billed in JPY here.
REGION_ID = "westus3"
REGION_NAME = "West US 3"

# The model account carries its own region, because bicep/main.bicep gives it
# its own parameter and model availability can force it away from the rest of
# the estate. It is billed in the same currency either way. These two follow
# openAiLocation; on this deployment it resolved to the estate region.
OPENAI_REGION_ID = "westus3"
OPENAI_REGION_NAME = "West US 3"

RESOURCE_GROUP = "car-rg"

# Fabricated identifiers. No real subscription, tenant or billing account.
SUBSCRIPTION_ID = "c1d84a76-2f05-4b93-a7e8-6094db35fe12"
SUBSCRIPTION_NAME = "Robo-Advisory Production"
BILLING_ACCOUNT_ID = "9142077"
BILLING_ACCOUNT_NAME = "Robo-Advisory Operator"
INVOICE_ID = "T0140558231"

# Deploy-time uniqueness suffix, held constant across the export so the rows
# describe one concrete deployment of the estate.
SUFFIX = "q7mp4kx2wnb3f"

TAGS = (
    '{"Owner":"migration-test","CostCenter":"test-journeys",'
    '"AutoTeardown":"2026-07-01","Journey":"azure/j7-container-apps-rag"}'
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

CONTAINER_APP_NAME = "car-advisor"
ENVIRONMENT_NAME = "car-cae"
OPENAI_NAME = f"car-openai-{SUFFIX}"
SEARCH_NAME = f"car-search-{SUFFIX}"
COSMOS_NAME = f"car-cosmos-{SUFFIX}"
STORAGE_NAME = f"cardocs{SUFFIX}"
REGISTRY_NAME = f"caracr{SUFFIX}"


def _weekday_factor(day: int, weekend: float) -> float:
    """Customers log in to read explanations on weekdays."""
    return weekend if (PERIOD_START + timedelta(days=day)).weekday() >= 5 else 1.0


LINE_ITEMS = [
    # --- the app ------------------------------------------------------------
    {
        "key": "aca-vcpu",
        "resource_name": CONTAINER_APP_NAME,
        "arm_type": "Microsoft.App/containerApps",
        "service_name": "Azure Container Apps",
        "service_category": "Compute",
        "meter_category": "Azure Container Apps",
        "meter_subcategory": "Consumption",
        "meter_name": "vCPU Active Usage",
        "meter_id": "3b71c0e4-95af-4d62-8107-2ea6fbc34d19",
        "description": "vCPU Active Usage - Azure Container Apps Consumption",
        "unit": "1 vCPU Second",
        "pricing_unit": "1 vCPU Second",
        "unit_price": 0.0000536,
        # The app scales to zero. Metered seconds track when a replica is
        # actually up, which is a few hours of the working day and almost
        # nothing at the weekend — nowhere near 86,400.
        "quantity": lambda day, rng: round(
            (7400.0 + day * 95.0) * _weekday_factor(day, 0.18) + rng.uniform(-260, 260),
            2,
        ),
    },
    {
        "key": "aca-memory",
        "resource_name": CONTAINER_APP_NAME,
        "arm_type": "Microsoft.App/containerApps",
        "service_name": "Azure Container Apps",
        "service_category": "Compute",
        "meter_category": "Azure Container Apps",
        "meter_subcategory": "Consumption",
        "meter_name": "Memory Active Usage",
        "meter_id": "9c02f5a8-64b1-4e37-bd90-71c85ae2f043",
        "description": "Memory Active Usage - Azure Container Apps Consumption",
        "unit": "1 GiB Second",
        "pricing_unit": "1 GiB Second",
        "unit_price": 0.0000067,
        # Twice the vCPU seconds: 0.5 vCPU paired with 1.0 GiB.
        "quantity": lambda day, rng: round(
            2 * ((7400.0 + day * 95.0) * _weekday_factor(day, 0.18) + rng.uniform(-260, 260)),
            2,
        ),
    },
    {
        "key": "aca-requests",
        "resource_name": CONTAINER_APP_NAME,
        "arm_type": "Microsoft.App/containerApps",
        "service_name": "Azure Container Apps",
        "service_category": "Compute",
        "meter_category": "Azure Container Apps",
        "meter_subcategory": "Consumption",
        "meter_name": "Requests",
        "meter_id": "d5e83b17-2c96-4fa0-91d4-08b7e6c25a3f",
        "description": "Requests - Azure Container Apps Consumption",
        "unit": "1M",
        "pricing_unit": "1M",
        "unit_price": 60.00,
        "quantity": lambda day, rng: round(
            (0.0091 + day * 0.00012) * _weekday_factor(day, 0.22) + rng.uniform(-0.0004, 0.0004),
            6,
        ),
    },
    # --- the model ----------------------------------------------------------
    #
    # The explainer talks to the GlobalStandard deployment, so what it actually
    # burns arrives as these two per-token meters.
    {
        "key": "aoai-input",
        "resource_name": OPENAI_NAME,
        "arm_type": "Microsoft.CognitiveServices/accounts",
        "service_name": "Azure OpenAI",
        "service_category": "AI and Machine Learning",
        "meter_category": "Azure OpenAI",
        "meter_subcategory": "gpt-4o-mini Global",
        "meter_name": "gpt-4o-mini-0718 Global Input Tokens",
        "meter_id": "6a4f2e91-70c3-4b58-a2d6-9f18e5b03c47",
        "description": "gpt-4o-mini-0718 Global Input Tokens - Azure OpenAI",
        "unit": "1K",
        "pricing_unit": "1K",
        "unit_price": 0.0225,
        "region_id": OPENAI_REGION_ID,
        "region_name": OPENAI_REGION_NAME,
        # Each explanation carries three retrieved passages, so the prompt is
        # long relative to the answer.
        "quantity": lambda day, rng: round(
            (2480.0 + day * 41.0) * _weekday_factor(day, 0.21) + rng.uniform(-90, 90),
            3,
        ),
    },
    {
        "key": "aoai-output",
        "resource_name": OPENAI_NAME,
        "arm_type": "Microsoft.CognitiveServices/accounts",
        "service_name": "Azure OpenAI",
        "service_category": "AI and Machine Learning",
        "meter_category": "Azure OpenAI",
        "meter_subcategory": "gpt-4o-mini Global",
        "meter_name": "gpt-4o-mini-0718 Global Output Tokens",
        "meter_id": "c8b17d40-3ea9-42f6-85b1-7d093ca6e218",
        "description": "gpt-4o-mini-0718 Global Output Tokens - Azure OpenAI",
        "unit": "1K",
        "pricing_unit": "1K",
        "unit_price": 0.0900,
        "region_id": OPENAI_REGION_ID,
        "region_name": OPENAI_REGION_NAME,
        "quantity": lambda day, rng: round(
            (405.0 + day * 7.0) * _weekday_factor(day, 0.21) + rng.uniform(-18, 18),
            3,
        ),
    },
    # --- retrieval ----------------------------------------------------------
    {
        "key": "search-unit",
        "resource_name": SEARCH_NAME,
        "arm_type": "Microsoft.Search/searchServices",
        "service_name": "Azure AI Search",
        "service_category": "AI and Machine Learning",
        "meter_category": "Azure Cognitive Search",
        "meter_subcategory": "Basic",
        "meter_name": "Basic Unit",
        "meter_id": "1f6d90b3-4c27-4a85-9e30-b2f7ac581d64",
        "description": "Basic Unit - Azure AI Search Basic",
        "unit": "1 Hour",
        "pricing_unit": "1 Hour",
        "unit_price": 15.30,
        # One replica, one partition, billed around the clock whether or not
        # anybody queries it.
        "quantity": lambda day, rng: 24.0,
    },
    # --- persistence --------------------------------------------------------
    {
        "key": "cosmos-ru",
        "resource_name": COSMOS_NAME,
        "arm_type": "Microsoft.DocumentDB/databaseAccounts",
        "service_name": "Azure Cosmos DB",
        "service_category": "Databases",
        "meter_category": "Azure Cosmos DB",
        "meter_subcategory": "Azure Cosmos DB serverless",
        "meter_name": "Request Units Consumed",
        "meter_id": "7e2c8a45-b019-4d76-83fa-16c94e7b0d52",
        "description": "Request Units Consumed - Azure Cosmos DB serverless",
        "unit": "1M",
        "pricing_unit": "1M",
        "unit_price": 42.00,
        "quantity": lambda day, rng: round(
            (0.058 + day * 0.0009) * _weekday_factor(day, 0.24) + rng.uniform(-0.002, 0.002),
            6,
        ),
    },
    {
        "key": "cosmos-storage",
        "resource_name": COSMOS_NAME,
        "arm_type": "Microsoft.DocumentDB/databaseAccounts",
        "service_name": "Azure Cosmos DB",
        "service_category": "Databases",
        "meter_category": "Azure Cosmos DB",
        "meter_subcategory": "Azure Cosmos DB serverless",
        "meter_name": "Data Stored",
        "meter_id": "b3f07c62-9a18-4e05-bd71-2c48e9a5f713",
        "description": "Data Stored - Azure Cosmos DB serverless",
        "unit": "1 GiB/Month",
        "pricing_unit": "1 GiB/Month",
        "unit_price": 37.50,
        # Nothing is ever deleted from the conversation store.
        "quantity": lambda day, rng: round((0.21 + day * 0.006) / DAYS, 6),
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
        # Six fund notes. The corpus barely moves.
        "quantity": lambda day, rng: round(0.004 / DAYS, 8),
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
        # Only touched when the index is rebuilt, which is rare.
        "quantity": lambda day, rng: round(rng.uniform(0.0004, 0.0021), 6),
    },
    # --- the private path ---------------------------------------------------
    {
        "key": "private-endpoint-hours",
        "resource_name": "car-pe-openai",
        "arm_type": "Microsoft.Network/privateEndpoints",
        "service_name": "Azure Private Link",
        "service_category": "Networking",
        "meter_category": "Virtual Network Private Link",
        "meter_subcategory": "Private Link",
        "meter_name": "Standard Private Endpoint",
        "meter_id": "5c8e1a37-d240-4b96-8e05-73fa19c2b648",
        "description": "Standard Private Endpoint - Virtual Network Private Link",
        "unit": "1 Hour",
        "pricing_unit": "1 Hour",
        "unit_price": 1.65,
        "quantity": lambda day, rng: 24.0,
    },
    {
        "key": "private-endpoint-hours-search",
        "resource_name": "car-pe-search",
        "arm_type": "Microsoft.Network/privateEndpoints",
        "service_name": "Azure Private Link",
        "service_category": "Networking",
        "meter_category": "Virtual Network Private Link",
        "meter_subcategory": "Private Link",
        "meter_name": "Standard Private Endpoint",
        "meter_id": "5c8e1a37-d240-4b96-8e05-73fa19c2b648",
        "description": "Standard Private Endpoint - Virtual Network Private Link",
        "unit": "1 Hour",
        "pricing_unit": "1 Hour",
        "unit_price": 1.65,
        "quantity": lambda day, rng: 24.0,
    },
    {
        "key": "aca-lb",
        "resource_name": ENVIRONMENT_NAME,
        "arm_type": "Microsoft.App/managedEnvironments",
        "service_name": "Load Balancer",
        "service_category": "Networking",
        "meter_category": "Load Balancer",
        "meter_subcategory": "Standard",
        "meter_name": "Standard Included LB Rules and Outbound Rules",
        "meter_id": "a71fd035-6c84-4b29-90e7-58d3b1ec2740",
        "description": "Standard Included LB Rules and Outbound Rules - Load Balancer",
        "unit": "1 Hour",
        "pricing_unit": "1 Hour",
        "unit_price": 3.75,
        # Created by the platform when the environment joined the network, in a
        # managed resource group nobody at the operator has ever opened.
        "quantity": lambda day, rng: 24.0,
    },
    # --- everything else ----------------------------------------------------
    {
        "key": "acr-basic",
        "resource_name": REGISTRY_NAME,
        "arm_type": "Microsoft.ContainerRegistry/registries",
        "service_name": "Azure Container Registry",
        "service_category": "Compute",
        "meter_category": "Container Registry",
        "meter_subcategory": "Basic",
        "meter_name": "Basic Registry Unit",
        "meter_id": "8d40b7f2-1e63-4a09-b5c8-047ae2913df6",
        "description": "Basic Registry Unit - Container Registry",
        "unit": "1/Day",
        "pricing_unit": "1/Day",
        "unit_price": 25.20,
        "quantity": lambda day, rng: 1.0,
    },
    {
        "key": "dns-zones",
        "resource_name": "privatelink.openai.azure.com",
        "arm_type": "Microsoft.Network/privateDnsZones",
        "service_name": "Azure DNS",
        "service_category": "Networking",
        "meter_category": "Azure DNS",
        "meter_subcategory": "Private Zones",
        "meter_name": "Zone",
        "meter_id": "0e34b9d1-7f52-4c68-a903-1bd6e457c82a",
        "description": "Zone - Azure DNS Private Zones",
        "unit": "1/Month",
        "pricing_unit": "1/Month",
        "unit_price": 75.00,
        # Four zones, billed per zone per month, spread daily.
        "quantity": lambda day, rng: round(4.0 / DAYS, 8),
    },
    {
        "key": "appinsights-ingest",
        "resource_name": "car-appi",
        "arm_type": "Microsoft.Insights/components",
        "service_name": "Azure Monitor",
        "service_category": "Management and Governance",
        "meter_category": "Azure Monitor",
        "meter_subcategory": "Application Insights Enterprise",
        "meter_name": "Pay-as-you-go Data Ingestion",
        "meter_id": "f19d3c85-40a7-4b62-9e01-53c8ba7d0416",
        "description": "Pay-as-you-go Data Ingestion - Application Insights",
        "unit": "1 GB",
        "pricing_unit": "1 GB",
        "unit_price": 414.00,
        # The component is provisioned and the connection string is on the app,
        # but nothing instruments it. What arrives is whatever the platform
        # sends by itself, which is close to nothing.
        "quantity": lambda day, rng: round(rng.uniform(0.00004, 0.00021), 8),
    },
    {
        "key": "law-ingest",
        "resource_name": "car-logs",
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
        "quantity": lambda day, rng: round(
            0.019 + day * 0.0004 + rng.uniform(-0.001, 0.001), 5
        ),
    },
]

# The provisioned-throughput reservation. One recurring monthly charge, bought
# outright rather than metered, so it lands as a Purchase rather than Usage and
# carries the CommitmentDiscount columns the per-token meters leave empty.
#
# 15 units is the smallest global provisioned deployment Azure sells for this
# model, and the reservation runs month to month.
PROVISIONED_RESERVATION = {
    "key": "aoai-ptu-reservation",
    "resource_name": OPENAI_NAME,
    "arm_type": "Microsoft.CognitiveServices/accounts",
    "service_name": "Azure OpenAI",
    "service_category": "AI and Machine Learning",
    "meter_category": "Azure OpenAI",
    "meter_subcategory": "Provisioned Managed",
    "meter_name": "Global Provisioned Throughput Unit Reservation",
    "meter_id": "2ab95e10-c473-4d81-9f26-58e0b7d41ca3",
    "description": (
        "Global Provisioned Throughput Unit Reservation - Azure OpenAI Provisioned Managed"
    ),
    "unit": "15 PTU/Month",
    "pricing_unit": "15 PTU/Month",
    "unit_price": 1458000.00,
    "region_id": OPENAI_REGION_ID,
    "region_name": OPENAI_REGION_NAME,
    "quantity": 1.0,
}

RESERVATION_ID = (
    f"/providers/Microsoft.Capacity/reservationOrders/"
    "4e1b93c7-8d2a-4506-b17f-e0392ac6d845/reservations/"
    "0f7a2d16-59be-4c38-90e1-8b4dc37f2510"
)
RESERVATION_NAME = "car-openai-ptu-monthly"


def stamp(value: date) -> str:
    """FOCUS 1.0r2 timestamps carry seconds."""
    return datetime(value.year, value.month, value.day).strftime("%Y-%m-%dT%H:%M:%SZ")


def build_row(
    item: dict,
    start: date,
    end: date,
    quantity: float,
    frequency: str,
    charge_category: str = "Usage",
    pricing_category: str = "Standard",
    commitment: dict | None = None,
) -> dict:
    cost = round(quantity * item["unit_price"], 4)
    region_id = item.get("region_id", REGION_ID)
    region_name = item.get("region_name", REGION_NAME)
    discount = commitment or {}
    return {
        "BilledCost": f"{cost:.4f}",
        "BillingAccountId": BILLING_ACCOUNT_ID,
        "BillingAccountName": BILLING_ACCOUNT_NAME,
        "BillingCurrency": CURRENCY,
        "BillingPeriodEnd": stamp(PERIOD_END),
        "BillingPeriodStart": stamp(PERIOD_START),
        "ChargeCategory": charge_category,
        "ChargeClass": "",
        "ChargeDescription": item["description"],
        "ChargeFrequency": frequency,
        "ChargePeriodEnd": stamp(end),
        "ChargePeriodStart": stamp(start),
        "CommitmentDiscountCategory": discount.get("category", ""),
        "CommitmentDiscountId": discount.get("id", ""),
        "CommitmentDiscountName": discount.get("name", ""),
        "CommitmentDiscountStatus": discount.get("status", ""),
        "CommitmentDiscountType": discount.get("type", ""),
        "ConsumedQuantity": f"{quantity:.6f}",
        "ConsumedUnit": item["unit"],
        "ContractedCost": f"{cost:.4f}",
        "ContractedUnitPrice": f"{item['unit_price']:.4f}",
        "EffectiveCost": f"{cost:.4f}",
        "InvoiceIssuerName": "Microsoft",
        "ListCost": f"{cost:.4f}",
        "ListUnitPrice": f"{item['unit_price']:.4f}",
        "PricingCategory": pricing_category,
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
        "x_SkuRegion": region_id,
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
            rows.append(
                build_row(item, start, start + timedelta(days=1), quantity, "Usage-Based")
            )
    rows.append(
        build_row(
            PROVISIONED_RESERVATION,
            PERIOD_START,
            PERIOD_END,
            PROVISIONED_RESERVATION["quantity"],
            "Recurring",
            charge_category="Purchase",
            pricing_category="Committed",
            commitment={
                "category": "Usage",
                "id": RESERVATION_ID,
                "name": RESERVATION_NAME,
                "status": "",
                "type": "Reservation",
            },
        )
    )
    rows.sort(
        key=lambda row: (row["ChargePeriodStart"], row["ResourceName"], row["x_SkuMeterName"])
    )
    return rows


def main() -> None:
    target = (
        pathlib.Path(sys.argv[1])
        if len(sys.argv) > 1
        else (pathlib.Path(__file__).resolve().parent / "car-usage-focus.csv")
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
