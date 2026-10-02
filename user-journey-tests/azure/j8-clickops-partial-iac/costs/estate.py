#!/usr/bin/env python3
"""Shared description of the university estate (fictional) subscription.

EVERYTHING DESCRIBED HERE IS SYNTHETIC. No figure was measured, on Azure or
anywhere else. No real subscription, tenant, enrolment, invoice or customer is
represented. See README.md in this directory and in ../discovery/.

This module is the single source the generators read:

    make-cost-exports.py    -> focus/, cpi-actual-cost.csv,
                               cpi-amortized-cost.csv, cpi-reservation-details.csv
    ../discovery/make-resource-list.py -> az-resource-list.json

Holding one description in one place is what keeps the four artifacts agreeing
with each other; check-consistency.py then re-derives that agreement from the
written files rather than from this module, so a broken generator still fails
the check.

Nothing here reads the clock, the environment or the network, and every
quantity is drawn from a per-meter seeded generator, so the artifacts rebuild
byte-identically.
"""

from __future__ import annotations

import random
from datetime import date, datetime, timedelta

# --- the billed month --------------------------------------------------------

PERIOD_START = date(2026, 7, 1)
PERIOD_END = date(2026, 8, 1)  # exclusive, matching FOCUS half-open periods
DAYS = (PERIOD_END - PERIOD_START).days
HOURS_IN_PERIOD = DAYS * 24

SEED = 20260701

# --- fabricated identifiers --------------------------------------------------

SUBSCRIPTION_ID = "7d4e2a91-6c38-4b55-9f0a-3e81d5c72b64"
SUBSCRIPTION_NAME = "University Estate"
TENANT_ID = "5b18c0f7-42ad-4e93-8c61-9d70e2fa3b48"
BILLING_ACCOUNT_ID = "4410297"
BILLING_ACCOUNT_NAME = "University Estate"
BILLING_PROFILE_ID = "4410297"
BILLING_PROFILE_NAME = "University Estate"
ENROLMENT_ACCOUNT_NAME = "University Estate IT Office"
ENROLMENT_ACCOUNT_OWNER = "it-office@cpi.example"
DEPARTMENT_ID = "216004"
DEPARTMENT_NAME = "Information Systems"
INVOICE_ID = "E4410297-202607"
OFFER_ID = "MS-AZR-0017P"  # EA

CURRENCY = "JPY"
JPY_PER_USD = 150.0
EXCHANGE_RATE_DATE = "2026-07-01"

# The billed region. A cost export cannot leave this column empty, so the
# fixtures are the one place in this journey that names a region: it has to
# agree with wherever the estate is deployed. Edit both lines together if that
# moves — quantities are seeded per meter and do not depend on the region.
REGION_ID = "westus3"
REGION_NAME = "West US 3"
# The normalized spelling Azure resolves inconsistent provider region names to.
REGION_NORMALIZED = "US West 3"

# Deploy-time uniqueness suffix, held constant so the rows describe one
# concrete deployment of the portal.
SUFFIX = "w4n7q2xkm5cdb"

PORTAL_RG = "cpi-rg"
ADMIN_RG = "cpi-admin-rg"
DATA_RG = "cpi-data-rg"
WEB_RG = "cpi-web-rg"

AUTO_TEARDOWN = "2026-09-30"

# Tags the portal template stamps on everything it creates. The rest of the
# estate was clicked together over eight years and mostly carries nothing.
PORTAL_TAGS = {
    "Owner": "migration-test",
    "CostCenter": "test-journeys",
    "AutoTeardown": AUTO_TEARDOWN,
    "Journey": "azure/j8-clickops-partial-iac",
}
DATA_OFFICE_TAGS = {"owner": "data-office"}
NO_TAGS: dict[str, str] = {}

# --- resource names ----------------------------------------------------------

PLAN_NAME = "cpi-plan"
SITE_NAME = f"cpi-portal-{SUFFIX}"
SQL_SERVER_NAME = f"cpi-sql-{SUFFIX}"
SQL_DATABASE_NAME = "cpiportal"
PORTAL_STORAGE_NAME = f"cpiportal{SUFFIX}"
DOCUMENTS_CONTAINER = "documents"

DC_NAME = "cpi-dc01"
ADMIN1_NAME = "cpi-admin01"
ADMIN2_NAME = "cpi-admin02"
FILES_STORAGE_NAME = "cpifiles2018"
# Cost Management writes the subscription's exports into this account.
BILLING_STORAGE_NAME = "cpibilling01"
BACKUP_VAULT_NAME = "cpi-backup-vault"
ADMIN_IP_NAME = "cpi-admin-ip"
VNET_NAME = "cpi-vnet"
NSG_NAME = "cpi-nsg-admin"

SYNAPSE_WORKSPACE_NAME = "cpi-analytics"
SYNAPSE_POOL_NAME = "cpipool01"
DATALAKE_NAME = "cpidatalake01"

BOOKING_IP_NAME = "cpi-booking-ip"

# --- commitments -------------------------------------------------------------
#
# One reserved-instance order and one compute savings plan. The reservation was
# paid for in a single up-front sum in April, so July's invoice carries no
# purchase line for it; the savings plan is billed monthly, so July's invoice
# does.

RESERVATION_ORDER_ID = "b0c9d84e-71f2-4a36-95cb-2e6f0a7d3184"
RESERVATION_ID = "3fa27c65-9d10-4b8e-a742-c05be91d6f23"
RESERVATION_NAME = "cpi-dsv3-ri"
RESERVATION_SKU = "Standard_D2s_v3"
RESERVATION_QUANTITY = 3  # instances reserved
RESERVATION_TERM_MONTHS = 12
RESERVATION_PURCHASE_DATE = date(2026, 4, 15)
RESERVATION_UPFRONT_JPY = 242196.0
# Straight-line over the term, then split across the reserved instances.
RESERVATION_HOURLY_AMORTIZED = round(
    RESERVATION_UPFRONT_JPY / (365 * 24 * RESERVATION_QUANTITY), 6
)

SAVINGS_PLAN_ORDER_ID = "9e4b7a02-5c81-4d69-b3f7-8a1c6d05e274"
SAVINGS_PLAN_ID = "c71d3f86-2b40-49a5-8e13-6f904b7ca5d2"
SAVINGS_PLAN_NAME = "cpi-compute-sp"
SAVINGS_PLAN_HOURLY_COMMITMENT = 24.50
SAVINGS_PLAN_PURCHASE_DAY = 8  # billed monthly, on the order anniversary


def resource_id(resource_group: str, provider_type: str, name: str) -> str:
    return (
        f"/subscriptions/{SUBSCRIPTION_ID}/resourceGroups/{resource_group}"
        f"/providers/{provider_type}/{name}"
    )


RESERVATION_RESOURCE_ID = (
    f"/providers/Microsoft.Capacity/reservationOrders/{RESERVATION_ORDER_ID}"
    f"/reservations/{RESERVATION_ID}"
)
SAVINGS_PLAN_RESOURCE_ID = (
    f"/providers/Microsoft.BillingBenefits/savingsPlanOrders/{SAVINGS_PLAN_ORDER_ID}"
    f"/savingsPlans/{SAVINGS_PLAN_ID}"
)

# --- the inventory -----------------------------------------------------------
#
# Grouped by resource group. Not every entry carries a meter: a SQL logical
# server, a virtual network, a network security group, a network interface and
# a VM extension are all free, and App Service compute is billed against the
# plan rather than the site.

RESOURCES = [
    # --- the student portal, the part with a template ------------------------
    {
        "name": PLAN_NAME,
        "type": "Microsoft.Web/serverfarms",
        "resource_group": PORTAL_RG,
        "kind": "linux",
        "sku": {"name": "B1", "tier": "Basic", "size": "B1", "family": "B", "capacity": 1},
        "identity": None,
        "tags": PORTAL_TAGS,
    },
    {
        "name": SITE_NAME,
        "type": "Microsoft.Web/sites",
        "resource_group": PORTAL_RG,
        "kind": "app,linux",
        "sku": None,
        "identity": None,
        "tags": PORTAL_TAGS,
    },
    {
        "name": SQL_SERVER_NAME,
        "type": "Microsoft.Sql/servers",
        "resource_group": PORTAL_RG,
        "kind": "v12.0",
        "sku": None,
        "identity": None,
        "tags": PORTAL_TAGS,
    },
    {
        "name": f"{SQL_SERVER_NAME}/{SQL_DATABASE_NAME}",
        "type": "Microsoft.Sql/servers/databases",
        "resource_group": PORTAL_RG,
        "kind": "v12.0,user",
        "sku": {"name": "Basic", "tier": "Basic", "capacity": 5},
        "identity": None,
        "tags": PORTAL_TAGS,
    },
    {
        "name": PORTAL_STORAGE_NAME,
        "type": "Microsoft.Storage/storageAccounts",
        "resource_group": PORTAL_RG,
        "kind": "StorageV2",
        "sku": {"name": "Standard_LRS", "tier": "Standard"},
        "identity": None,
        "tags": PORTAL_TAGS,
    },
    # --- the administrative estate, clicked together from 2018 ---------------
    {
        "name": DC_NAME,
        "type": "Microsoft.Compute/virtualMachines",
        "resource_group": ADMIN_RG,
        "kind": None,
        "sku": {"name": "Standard_D2s_v3"},
        "identity": None,
        "tags": NO_TAGS,
    },
    {
        "name": ADMIN1_NAME,
        "type": "Microsoft.Compute/virtualMachines",
        "resource_group": ADMIN_RG,
        "kind": None,
        "sku": {"name": "Standard_D4s_v3"},
        "identity": None,
        "tags": NO_TAGS,
    },
    {
        "name": ADMIN2_NAME,
        "type": "Microsoft.Compute/virtualMachines",
        "resource_group": ADMIN_RG,
        "kind": None,
        "sku": {"name": "Standard_D2s_v3"},
        "identity": None,
        "tags": NO_TAGS,
    },
    {
        "name": f"{ADMIN1_NAME}/joindomain",
        "type": "Microsoft.Compute/virtualMachines/extensions",
        "resource_group": ADMIN_RG,
        "kind": None,
        "sku": None,
        "identity": None,
        "tags": NO_TAGS,
    },
    {
        "name": f"{ADMIN2_NAME}/joindomain",
        "type": "Microsoft.Compute/virtualMachines/extensions",
        "resource_group": ADMIN_RG,
        "kind": None,
        "sku": None,
        "identity": None,
        "tags": NO_TAGS,
    },
    {
        "name": f"{DC_NAME}_OsDisk",
        "type": "Microsoft.Compute/disks",
        "resource_group": ADMIN_RG,
        "kind": None,
        "sku": {"name": "Premium_LRS", "tier": "Premium"},
        "identity": None,
        "tags": NO_TAGS,
    },
    {
        "name": f"{ADMIN1_NAME}_OsDisk",
        "type": "Microsoft.Compute/disks",
        "resource_group": ADMIN_RG,
        "kind": None,
        "sku": {"name": "Premium_LRS", "tier": "Premium"},
        "identity": None,
        "tags": NO_TAGS,
    },
    {
        "name": f"{ADMIN1_NAME}_DataDisk_0",
        "type": "Microsoft.Compute/disks",
        "resource_group": ADMIN_RG,
        "kind": None,
        "sku": {"name": "Premium_LRS", "tier": "Premium"},
        "identity": None,
        "tags": NO_TAGS,
    },
    {
        "name": f"{ADMIN2_NAME}_OsDisk",
        "type": "Microsoft.Compute/disks",
        "resource_group": ADMIN_RG,
        "kind": None,
        "sku": {"name": "Premium_LRS", "tier": "Premium"},
        "identity": None,
        "tags": NO_TAGS,
    },
    {
        "name": FILES_STORAGE_NAME,
        "type": "Microsoft.Storage/storageAccounts",
        "resource_group": ADMIN_RG,
        "kind": "StorageV2",
        "sku": {"name": "Standard_LRS", "tier": "Standard"},
        "identity": None,
        "tags": NO_TAGS,
    },
    {
        "name": BACKUP_VAULT_NAME,
        "type": "Microsoft.RecoveryServices/vaults",
        "resource_group": ADMIN_RG,
        "kind": None,
        "sku": {"name": "RS0", "tier": "Standard"},
        "identity": None,
        "tags": NO_TAGS,
    },
    {
        "name": BILLING_STORAGE_NAME,
        "type": "Microsoft.Storage/storageAccounts",
        "resource_group": ADMIN_RG,
        "kind": "StorageV2",
        "sku": {"name": "Standard_LRS", "tier": "Standard"},
        "identity": None,
        "tags": NO_TAGS,
    },
    {
        "name": ADMIN_IP_NAME,
        "type": "Microsoft.Network/publicIPAddresses",
        "resource_group": ADMIN_RG,
        "kind": None,
        "sku": {"name": "Basic", "tier": "Regional"},
        "identity": None,
        "tags": NO_TAGS,
    },
    {
        "name": VNET_NAME,
        "type": "Microsoft.Network/virtualNetworks",
        "resource_group": ADMIN_RG,
        "kind": None,
        "sku": None,
        "identity": None,
        "tags": NO_TAGS,
    },
    {
        "name": NSG_NAME,
        "type": "Microsoft.Network/networkSecurityGroups",
        "resource_group": ADMIN_RG,
        "kind": None,
        "sku": None,
        "identity": None,
        "tags": NO_TAGS,
    },
    {
        "name": f"{DC_NAME}-nic",
        "type": "Microsoft.Network/networkInterfaces",
        "resource_group": ADMIN_RG,
        "kind": None,
        "sku": None,
        "identity": None,
        "tags": NO_TAGS,
    },
    {
        "name": f"{ADMIN1_NAME}-nic",
        "type": "Microsoft.Network/networkInterfaces",
        "resource_group": ADMIN_RG,
        "kind": None,
        "sku": None,
        "identity": None,
        "tags": NO_TAGS,
    },
    {
        "name": f"{ADMIN2_NAME}-nic",
        "type": "Microsoft.Network/networkInterfaces",
        "resource_group": ADMIN_RG,
        "kind": None,
        "sku": None,
        "identity": None,
        "tags": NO_TAGS,
    },
    # --- the data office's project -------------------------------------------
    {
        "name": SYNAPSE_WORKSPACE_NAME,
        "type": "Microsoft.Synapse/workspaces",
        "resource_group": DATA_RG,
        "kind": None,
        "sku": None,
        "identity": {"type": "SystemAssigned"},
        "tags": DATA_OFFICE_TAGS,
    },
    {
        "name": f"{SYNAPSE_WORKSPACE_NAME}/{SYNAPSE_POOL_NAME}",
        "type": "Microsoft.Synapse/workspaces/sqlPools",
        "resource_group": DATA_RG,
        "kind": None,
        "sku": {"name": "DW100c", "tier": "DataWarehouse", "capacity": 0},
        "identity": None,
        "tags": DATA_OFFICE_TAGS,
    },
    {
        "name": DATALAKE_NAME,
        "type": "Microsoft.Storage/storageAccounts",
        "resource_group": DATA_RG,
        "kind": "StorageV2",
        "sku": {"name": "Standard_LRS", "tier": "Standard"},
        "identity": None,
        "tags": DATA_OFFICE_TAGS,
    },
    # --- cpi-web-rg --------------------------------------------------------
    {
        "name": BOOKING_IP_NAME,
        "type": "Microsoft.Network/publicIPAddresses",
        "resource_group": WEB_RG,
        "kind": None,
        "sku": {"name": "Basic", "tier": "Regional"},
        "identity": None,
        "tags": NO_TAGS,
    },
]

RESOURCES_BY_NAME = {r["name"]: r for r in RESOURCES}


def resource_arm_id(resource: dict) -> str:
    """ARM id, handling the parent/child names."""
    parts = resource["name"].split("/")
    if len(parts) == 1:
        return resource_id(resource["resource_group"], resource["type"], resource["name"])
    # Microsoft.Sql/servers/databases -> .../servers/<parent>/databases/<child>
    type_parts = resource["type"].split("/")
    namespace = type_parts[0]
    segments = []
    for level, name in enumerate(parts):
        segments.append(f"{type_parts[level + 1]}/{name}")
    return (
        f"/subscriptions/{SUBSCRIPTION_ID}/resourceGroups/{resource['resource_group']}"
        f"/providers/{namespace}/" + "/".join(segments)
    )


def leaf_name(resource: dict) -> str:
    return resource["name"].split("/")[-1]


# --- the metered line items --------------------------------------------------
#
# One entry per meter on one resource. `quantity(day_index, rng)` returns the
# units consumed on that day. `unit_price` is the JPY list rate. `pricing_model`
# is OnDemand unless a commitment covers the meter.
#
# ComputeHR quantities are metered hours; a machine that never stops meters 24
# every day.

_WEEKEND = {5, 6}


def _is_weekend(day: int) -> bool:
    return (PERIOD_START + timedelta(days=day)).weekday() in _WEEKEND


METERS = [
    # --- portal ---------------------------------------------------------------
    {
        "key": "plan-b1",
        "resource": PLAN_NAME,
        "service_name": "Azure App Service",
        "service_category": "Compute",
        "service_subcategory": "Application Platforms",
        "service_model": "PaaS",
        "consumed_service": "Microsoft.Web",
        "meter_category": "Azure App Service",
        "meter_subcategory": "Basic Plan - Linux",
        "meter_name": "B1 App",
        "meter_id": "4d1a7e93-08bc-4f26-9d51-b7c30e625af8",
        "part_number": "AAD-33612",
        "product": "Azure App Service Basic Plan - B1 App - {region}",
        "description": "B1 App - Azure App Service Basic Plan Linux",
        "unit": "1 Hour",
        "unit_price": 2.55,
        "quantity": lambda day, rng: 24.0,
    },
    {
        "key": "portal-egress",
        "resource": SITE_NAME,
        "service_name": "Bandwidth",
        "service_category": "Networking",
        "service_subcategory": "Network Connectivity",
        "service_model": "IaaS",
        "consumed_service": "Microsoft.Web",
        "meter_category": "Bandwidth",
        "meter_subcategory": "Inter-Continent Data Transfer",
        "meter_name": "Data Transfer Out",
        "meter_id": "b91f4c07-2d6a-4358-8e14-7f0c3ba95d61",
        "part_number": "AAD-11780",
        "product": "Bandwidth Inter-Continent Data Transfer - Data Transfer Out",
        "description": "Data Transfer Out - Bandwidth Inter-Continent Data Transfer",
        "unit": "1 GB",
        "unit_price": 13.05,
        # Term is out; document downloads are steady and low.
        "quantity": lambda day, rng: round(
            (0.42 if _is_weekend(day) else 1.15) + rng.uniform(-0.08, 0.08), 4
        ),
    },
    {
        "key": "sql-basic",
        "resource": f"{SQL_SERVER_NAME}/{SQL_DATABASE_NAME}",
        "service_name": "SQL Database",
        "service_category": "Databases",
        "service_subcategory": "Relational Databases",
        "service_model": "PaaS",
        "consumed_service": "Microsoft.Sql",
        "meter_category": "SQL Database",
        "meter_subcategory": "Single Basic",
        "meter_name": "B DTUs",
        "meter_id": "0a7c5e14-9b83-4d02-a6f7-31c8be40d952",
        "part_number": "AAD-25501",
        "product": "SQL Database Single Basic - B DTUs - {region}",
        "description": "B DTUs - SQL Database Single Basic",
        "unit": "1 Hour",
        "unit_price": 0.99,
        "quantity": lambda day, rng: 24.0,
    },
    {
        "key": "portal-blob-stored",
        "resource": PORTAL_STORAGE_NAME,
        "service_name": "Azure Blob Storage",
        "service_category": "Storage",
        "service_subcategory": "Object Storage",
        "service_model": "PaaS",
        "consumed_service": "Microsoft.Storage",
        "meter_category": "Storage",
        "meter_subcategory": "General Block Blob v2 Hot LRS",
        "meter_name": "Hot LRS Data Stored",
        "meter_id": "cf5b1e26-8a74-4d0b-93c1-6e2f7ab5d904",
        "part_number": "AAD-30012",
        "product": "Storage General Block Blob v2 Hot LRS - Hot LRS Data Stored - {region}",
        "description": "Hot LRS Data Stored - General Block Blob v2",
        "unit": "1 GiB/Month",
        "unit_price": 3.45,
        # The registrar publishes a handful of PDFs a term.
        "quantity": lambda day, rng: round((0.21 + day * 0.0015) / DAYS, 6),
    },
    {
        "key": "portal-blob-reads",
        "resource": PORTAL_STORAGE_NAME,
        "service_name": "Azure Blob Storage",
        "service_category": "Storage",
        "service_subcategory": "Object Storage",
        "service_model": "PaaS",
        "consumed_service": "Microsoft.Storage",
        "meter_category": "Storage",
        "meter_subcategory": "General Block Blob v2 Hot LRS",
        "meter_name": "Hot Read Operations",
        "meter_id": "e0f4a2b9-7c31-4e58-9d06-25b8f1ca3e77",
        "part_number": "AAD-30015",
        "product": "Storage General Block Blob v2 Hot LRS - Hot Read Operations - {region}",
        "description": "Hot Read Operations - General Block Blob v2",
        "unit": "10K",
        "unit_price": 0.80,
        "quantity": lambda day, rng: round(
            (0.09 if _is_weekend(day) else 0.31) + rng.uniform(-0.03, 0.03), 5
        ),
    },
    # --- administrative machines ---------------------------------------------
    {
        "key": "dc01-compute",
        "resource": DC_NAME,
        "service_name": "Virtual Machines",
        "service_category": "Compute",
        "service_subcategory": "Virtual Machines",
        "service_model": "IaaS",
        "consumed_service": "Microsoft.Compute",
        "meter_category": "Virtual Machines",
        "meter_subcategory": "Dv3/DSv3 Series",
        "meter_name": "D2s v3",
        "meter_id": "7c2e8b40-1f95-4a63-b8d7-05ea41c9376f",
        "part_number": "AAD-40021",
        "product": "Virtual Machines Dv3/DSv3 Series - D2s v3 - {region}",
        "description": "D2s v3 - Virtual Machines Dv3/DSv3 Series",
        "unit": "1 Hour",
        "unit_price": 14.40,
        "quantity": lambda day, rng: 24.0,
        "pricing_model": "Reservation",
        "image_type": "WindowsServerBYOL",
        "service_type": "Standard_D2s_v3",
    },
    {
        "key": "admin01-compute",
        "resource": ADMIN1_NAME,
        "service_name": "Virtual Machines",
        "service_category": "Compute",
        "service_subcategory": "Virtual Machines",
        "service_model": "IaaS",
        "consumed_service": "Microsoft.Compute",
        "meter_category": "Virtual Machines",
        "meter_subcategory": "Dv3/DSv3 Series",
        "meter_name": "D4s v3",
        "meter_id": "1e93af57-6c02-4d81-95b3-8f47c0e2ba16",
        "part_number": "AAD-40023",
        "product": "Virtual Machines Dv3/DSv3 Series - D4s v3 - {region}",
        "description": "D4s v3 - Virtual Machines Dv3/DSv3 Series",
        "unit": "1 Hour",
        "unit_price": 28.80,
        "quantity": lambda day, rng: 24.0,
        "pricing_model": "SavingsPlan",
        "image_type": "WindowsServerBYOL",
        "service_type": "Standard_D4s_v3",
    },
    {
        "key": "admin02-compute",
        "resource": ADMIN2_NAME,
        "service_name": "Virtual Machines",
        "service_category": "Compute",
        "service_subcategory": "Virtual Machines",
        "service_model": "IaaS",
        "consumed_service": "Microsoft.Compute",
        "meter_category": "Virtual Machines",
        "meter_subcategory": "Dv3/DSv3 Series",
        "meter_name": "D2s v3",
        "meter_id": "7c2e8b40-1f95-4a63-b8d7-05ea41c9376f",
        "part_number": "AAD-40021",
        "product": "Virtual Machines Dv3/DSv3 Series - D2s v3 - {region}",
        "description": "D2s v3 - Virtual Machines Dv3/DSv3 Series",
        "unit": "1 Hour",
        "unit_price": 14.40,
        "quantity": lambda day, rng: 24.0,
        "pricing_model": "Reservation",
        "image_type": "WindowsServerBYOL",
        "service_type": "Standard_D2s_v3",
    },
    {
        "key": "admin01-egress",
        "resource": ADMIN1_NAME,
        "service_name": "Bandwidth",
        "service_category": "Networking",
        "service_subcategory": "Network Connectivity",
        "service_model": "IaaS",
        "consumed_service": "Microsoft.Compute",
        "meter_category": "Bandwidth",
        "meter_subcategory": "Inter-Continent Data Transfer",
        "meter_name": "Data Transfer Out",
        "meter_id": "b91f4c07-2d6a-4358-8e14-7f0c3ba95d61",
        "part_number": "AAD-11780",
        "product": "Bandwidth Inter-Continent Data Transfer - Data Transfer Out",
        "description": "Data Transfer Out - Bandwidth Inter-Continent Data Transfer",
        "unit": "1 GB",
        "unit_price": 13.05,
        "quantity": lambda day, rng: round(
            (0.30 if _is_weekend(day) else 0.92) + rng.uniform(-0.06, 0.06), 4
        ),
    },
]

# Managed disks: one meter each, all charged as whole provisioned disks.
for _disk_name, _tier, _size_gib, _monthly in (
    (f"{DC_NAME}_OsDisk", "P10", 128, 2956.50),
    (f"{ADMIN1_NAME}_OsDisk", "P10", 128, 2956.50),
    (f"{ADMIN1_NAME}_DataDisk_0", "P20", 512, 10983.00),
    (f"{ADMIN2_NAME}_OsDisk", "P10", 128, 2956.50),
):
    METERS.append(
        {
            "key": f"disk-{_disk_name.lower()}",
            "resource": _disk_name,
            "service_name": "Storage",
            "service_category": "Storage",
            "service_subcategory": "Block Storage",
            "service_model": "IaaS",
            "consumed_service": "Microsoft.Compute",
            "meter_category": "Storage",
            "meter_subcategory": "Premium SSD Managed Disks",
            "meter_name": f"{_tier} Disks",
            "meter_id": {
                "P10": "5a0d61c7-4e38-42b9-9f05-c8b1e73d20a4",
                "P20": "8b46e2d1-93fc-4057-a6e8-1d20b95c7f38",
            }[_tier],
            "part_number": {"P10": "AAD-51110", "P20": "AAD-51120"}[_tier],
            "product": f"Storage Premium SSD Managed Disks - {_tier} Disks - " + "{region}",
            "description": f"{_tier} Disks - Premium SSD Managed Disks ({_size_gib} GiB)",
            "unit": "1/Month",
            "unit_price": _monthly,
            "quantity": (lambda day, rng: round(1.0 / DAYS, 8)),
        }
    )

METERS += [
    {
        "key": "files-stored",
        "resource": FILES_STORAGE_NAME,
        "service_name": "Azure Files",
        "service_category": "Storage",
        "service_subcategory": "File Storage",
        "service_model": "PaaS",
        "consumed_service": "Microsoft.Storage",
        "meter_category": "Storage",
        "meter_subcategory": "Files v2 Transaction Optimized LRS",
        "meter_name": "Data Stored",
        "meter_id": "d3f7a916-58e0-4c24-bd91-6a05e7c3f284",
        "part_number": "AAD-30401",
        "product": "Storage Files v2 Transaction Optimized LRS - Data Stored - {region}",
        "description": "Data Stored - Files v2 Transaction Optimized LRS",
        "unit": "1 GiB/Month",
        "unit_price": 9.00,
        # Nothing has ever been deleted off the staff shares.
        "quantity": lambda day, rng: round((4180.0 + day * 3.4) / DAYS, 6),
    },
    {
        "key": "files-transactions",
        "resource": FILES_STORAGE_NAME,
        "service_name": "Azure Files",
        "service_category": "Storage",
        "service_subcategory": "File Storage",
        "service_model": "PaaS",
        "consumed_service": "Microsoft.Storage",
        "meter_category": "Storage",
        "meter_subcategory": "Files v2 Transaction Optimized LRS",
        "meter_name": "Protocol Operations",
        "meter_id": "6e15b830-cd47-4a92-8b06-f3712ea9c5d0",
        "part_number": "AAD-30404",
        "product": "Storage Files v2 Transaction Optimized LRS - Protocol Operations - {region}",
        "description": "Protocol Operations - Files v2 Transaction Optimized LRS",
        "unit": "10K",
        "unit_price": 2.25,
        "quantity": lambda day, rng: round(
            (2.1 if _is_weekend(day) else 14.6) + rng.uniform(-1.1, 1.1), 4
        ),
    },
    {
        "key": "billing-blob-stored",
        "resource": BILLING_STORAGE_NAME,
        "service_name": "Azure Blob Storage",
        "service_category": "Storage",
        "service_subcategory": "Object Storage",
        "service_model": "PaaS",
        "consumed_service": "Microsoft.Storage",
        "meter_category": "Storage",
        "meter_subcategory": "General Block Blob v2 Hot LRS",
        "meter_name": "Hot LRS Data Stored",
        "meter_id": "cf5b1e26-8a74-4d0b-93c1-6e2f7ab5d904",
        "part_number": "AAD-30012",
        "product": "Storage General Block Blob v2 Hot LRS - Hot LRS Data Stored - {region}",
        "description": "Hot LRS Data Stored - General Block Blob v2",
        "unit": "1 GiB/Month",
        "unit_price": 3.45,
        # Every month's export, kept since the exports were switched on.
        "quantity": lambda day, rng: round((11.4 + day * 0.02) / DAYS, 6),
    },
    {
        "key": "admin-ip",
        "resource": ADMIN_IP_NAME,
        "service_name": "Virtual Network",
        "service_category": "Networking",
        "service_subcategory": "Network Connectivity",
        "service_model": "IaaS",
        "consumed_service": "Microsoft.Network",
        "meter_category": "Virtual Network",
        "meter_subcategory": "IP Addresses",
        "meter_name": "Basic IPv4 Static Public IP",
        "meter_id": "a2c48f05-7b19-4e63-90da-51f7c28b6e34",
        "part_number": "AAD-60011",
        "product": "Virtual Network IP Addresses - Basic IPv4 Static Public IP - {region}",
        "description": "Basic IPv4 Static Public IP - Virtual Network IP Addresses",
        "unit": "1 Hour",
        "unit_price": 0.54,
        "quantity": lambda day, rng: 24.0,
    },
    {
        "key": "booking-ip",
        "resource": BOOKING_IP_NAME,
        "service_name": "Virtual Network",
        "service_category": "Networking",
        "service_subcategory": "Network Connectivity",
        "service_model": "IaaS",
        "consumed_service": "Microsoft.Network",
        "meter_category": "Virtual Network",
        "meter_subcategory": "IP Addresses",
        "meter_name": "Basic IPv4 Static Public IP",
        "meter_id": "a2c48f05-7b19-4e63-90da-51f7c28b6e34",
        "part_number": "AAD-60011",
        "product": "Virtual Network IP Addresses - Basic IPv4 Static Public IP - {region}",
        "description": "Basic IPv4 Static Public IP - Virtual Network IP Addresses",
        "unit": "1 Hour",
        "unit_price": 0.54,
        "quantity": lambda day, rng: 24.0,
    },
    {
        "key": "backup-instances",
        "resource": BACKUP_VAULT_NAME,
        "service_name": "Azure Backup",
        "service_category": "Storage",
        "service_subcategory": "Backup and Recovery",
        "service_model": "PaaS",
        "consumed_service": "Microsoft.RecoveryServices",
        "meter_category": "Backup",
        "meter_subcategory": "Standard",
        "meter_name": "Protected Instances",
        "meter_id": "f80a3e29-4d16-4b57-9c02-7ae5136bd4c1",
        "part_number": "AAD-70201",
        "product": "Backup Standard - Protected Instances - {region}",
        "description": "Protected Instances - Azure Backup Standard",
        "unit": "1/Month",
        "unit_price": 1500.00,
        # Three machines and the staff shares, protected all month.
        "quantity": lambda day, rng: round(4.0 / DAYS, 8),
    },
    {
        "key": "backup-storage",
        "resource": BACKUP_VAULT_NAME,
        "service_name": "Azure Backup",
        "service_category": "Storage",
        "service_subcategory": "Backup and Recovery",
        "service_model": "PaaS",
        "consumed_service": "Microsoft.RecoveryServices",
        "meter_category": "Backup",
        "meter_subcategory": "Standard",
        "meter_name": "LRS Data Stored",
        "meter_id": "2b6c07f4-a851-4e39-b7d0-94f6c1a30e75",
        "part_number": "AAD-70205",
        "product": "Backup Standard - LRS Data Stored - {region}",
        "description": "LRS Data Stored - Azure Backup Standard",
        "unit": "1 GiB/Month",
        "unit_price": 3.36,
        "quantity": lambda day, rng: round((6240.0 + day * 8.5) / DAYS, 6),
    },
    # --- the data office's project -------------------------------------------
    {
        "key": "synapse-pool",
        "resource": f"{SYNAPSE_WORKSPACE_NAME}/{SYNAPSE_POOL_NAME}",
        "service_name": "Azure Synapse Analytics",
        "service_category": "Analytics",
        "service_subcategory": "Analytics Platforms",
        "service_model": "PaaS",
        "consumed_service": "Microsoft.Synapse",
        "meter_category": "Azure Synapse Analytics",
        "meter_subcategory": "Compute Optimized Gen2",
        "meter_name": "cDWU",
        "meter_id": "9d0c7b62-3f4a-4185-ae27-6b0d59e14ca3",
        "part_number": "AAD-80301",
        "product": "Azure Synapse Analytics Compute Optimized Gen2 - cDWU - {region}",
        "description": "cDWU - Azure Synapse Analytics Compute Optimized Gen2",
        "unit": "100 cDWU/Hour",
        "unit_price": 180.00,
        # Nobody pauses it.
        "quantity": lambda day, rng: 24.0,
    },
    {
        "key": "synapse-serverless",
        "resource": SYNAPSE_WORKSPACE_NAME,
        "service_name": "Azure Synapse Analytics",
        "service_category": "Analytics",
        "service_subcategory": "Analytics Platforms",
        "service_model": "PaaS",
        "consumed_service": "Microsoft.Synapse",
        "meter_category": "Azure Synapse Analytics",
        "meter_subcategory": "Serverless SQL Pool",
        "meter_name": "Data Processed",
        "meter_id": "4a71e0c8-52d6-4913-b78f-0e6a3c15d947",
        "part_number": "AAD-80310",
        "product": "Azure Synapse Analytics Serverless SQL Pool - Data Processed - {region}",
        "description": "Data Processed - Azure Synapse Analytics Serverless SQL Pool",
        "unit": "1 TB",
        "unit_price": 750.00,
        "quantity": lambda day, rng: round(
            (0.02 if _is_weekend(day) else 0.18) + rng.uniform(-0.015, 0.015), 5
        ),
    },
    {
        "key": "datalake-stored",
        "resource": DATALAKE_NAME,
        "service_name": "Azure Data Lake Storage",
        "service_category": "Storage",
        "service_subcategory": "Object Storage",
        "service_model": "PaaS",
        "consumed_service": "Microsoft.Storage",
        "meter_category": "Storage",
        "meter_subcategory": "General Block Blob v2 Hierarchical Namespace Hot LRS",
        "meter_name": "Hot LRS Data Stored",
        "meter_id": "3c8f5a17-6e29-4b04-81d3-7f2a06c9be51",
        "part_number": "AAD-30022",
        "product": (
            "Storage General Block Blob v2 Hierarchical Namespace Hot LRS "
            "- Hot LRS Data Stored - {region}"
        ),
        "description": "Hot LRS Data Stored - General Block Blob v2 Hierarchical Namespace",
        "unit": "1 GiB/Month",
        "unit_price": 3.45,
        "quantity": lambda day, rng: round((812.0 + day * 6.2) / DAYS, 6),
    },
    {
        "key": "datalake-ops",
        "resource": DATALAKE_NAME,
        "service_name": "Azure Data Lake Storage",
        "service_category": "Storage",
        "service_subcategory": "Object Storage",
        "service_model": "PaaS",
        "consumed_service": "Microsoft.Storage",
        "meter_category": "Storage",
        "meter_subcategory": "General Block Blob v2 Hierarchical Namespace Hot LRS",
        "meter_name": "Hot Write Operations",
        "meter_id": "7f19d4b3-05ea-4c68-92a7-3b81f0c5da26",
        "part_number": "AAD-30024",
        "product": (
            "Storage General Block Blob v2 Hierarchical Namespace Hot LRS "
            "- Hot Write Operations - {region}"
        ),
        "description": "Hot Write Operations - General Block Blob v2 Hierarchical Namespace",
        "unit": "10K",
        "unit_price": 9.75,
        "quantity": lambda day, rng: round(
            (0.4 if _is_weekend(day) else 3.6) + rng.uniform(-0.3, 0.3), 4
        ),
    },
]

# The meter product names carry the region the same way the billed columns do.
for _meter in METERS:
    _meter["product"] = _meter["product"].format(region=REGION_NAME)

METERS_BY_KEY = {m["key"]: m for m in METERS}

# Which meters each commitment applies to, and the rate the covered hours are
# amortized at.
RESERVED_METER_KEYS = ("dc01-compute", "admin02-compute")
SAVINGS_PLAN_METER_KEYS = ("admin01-compute",)
SAVINGS_PLAN_HOURLY_RATE = SAVINGS_PLAN_HOURLY_COMMITMENT

# Reserved instance-hours the order did not apply to a machine. The amortized
# dataset reports these under their own charge type.
RESERVED_INSTANCE_HOURS_UNAPPLIED = RESERVATION_QUANTITY - len(RESERVED_METER_KEYS)


def meter_rng(key: str) -> random.Random:
    """A generator per meter, so adding a meter never shifts another's numbers."""
    return random.Random(f"{SEED}-{key}")


def day_start(day: int) -> date:
    return PERIOD_START + timedelta(days=day)


def stamp(value: date) -> str:
    """FOCUS 1.2-preview timestamps carry seconds."""
    return datetime(value.year, value.month, value.day).strftime("%Y-%m-%dT%H:%M:%SZ")


def date_only(value: date) -> str:
    return value.strftime("%Y-%m-%d")


def pricing_model(meter: dict) -> str:
    return meter.get("pricing_model", "OnDemand")


def additional_info(meter: dict, model: str = "OnDemand") -> str:
    """The service metadata Azure stamps on virtual machine usage rows.

    Rows a reservation applied to carry the instance-size flexibility ratio
    alongside it.
    """
    if "image_type" not in meter:
        return ""
    fields = [
        ("ImageType", meter["image_type"]),
        ("ServiceType", meter["service_type"]),
        ("VMName", ""),
        ("UsageType", "ComputeHR"),
    ]
    if model == "Reservation":
        fields.append(("RINormalizationRatio", "1"))
    return "{" + ",".join(f'"{k}":"{v}"' for k, v in fields) + "}"


def tags_json(resource_name: str) -> str:
    resource = RESOURCES_BY_NAME.get(resource_name)
    if resource is None or not resource["tags"]:
        return ""
    pairs = ",".join(f'"{k}":"{v}"' for k, v in resource["tags"].items())
    return "{" + pairs + "}"
