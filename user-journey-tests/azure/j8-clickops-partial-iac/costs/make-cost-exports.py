#!/usr/bin/env python3
"""Build the synthetic cost exports for the university estate (fictional).

EVERYTHING THIS SCRIPT WRITES IS SYNTHETIC. No figure was measured, on Azure or
anywhere else. It imitates the shape of what Microsoft Cost Management writes so
that a parser written against real exports works against these unmodified. See
README.md in this directory.

Written artifacts:

    focus/_manifest.json          run manifest listing the partitions
    focus/part_*.csv.gz           FOCUS 1.2-preview partitions, gzip
    cpi-actual-cost.csv           EA cost and usage details, actual metric
    cpi-amortized-cost.csv        EA cost and usage details, amortized metric
    cpi-reservation-usage.csv   EA reservation details, uncompressed CSV

Deterministic by construction: fixed dates, a fixed seed, no clock reads, and
gzip members written with mtime 0 and no stored filename, so two runs any
distance apart produce byte-identical output.

Usage:
    python3 make-cost-exports.py            # rewrite the artifacts in place
    python3 make-cost-exports.py /tmp/out   # write a full copy elsewhere
"""

from __future__ import annotations

import csv
import gzip
import io
import json
import pathlib
import sys

import estate as e

# --- FOCUS 1.2-preview -------------------------------------------------------
#
# The full column set, in the order the schema page lists it. Two details this
# reproduces rather than glosses over, because both change how a parser behaves:
# the three columns renamed in 1.2-preview appear under their new names, with
# x_SkuMeterName still carried alongside SkuMeter, and x_SkuTerm — a 1.0 column
# — is absent.

FOCUS_COLUMNS = [
    "BilledCost",
    "BillingAccountId",
    "BillingAccountName",
    "BillingAccountType",
    "BillingCurrency",
    "BillingPeriodEnd",
    "BillingPeriodStart",
    "CapacityReservationId",
    "CapacityReservationStatus",
    "ChargeCategory",
    "ChargeClass",
    "ChargeDescription",
    "ChargeFrequency",
    "ChargePeriodEnd",
    "ChargePeriodStart",
    "CommitmentDiscountCategory",
    "CommitmentDiscountId",
    "CommitmentDiscountName",
    "CommitmentDiscountQuantity",
    "CommitmentDiscountStatus",
    "CommitmentDiscountType",
    "CommitmentDiscountUnit",
    "ConsumedQuantity",
    "ConsumedUnit",
    "ContractedCost",
    "ContractedUnitPrice",
    "EffectiveCost",
    "InvoiceId",
    "InvoiceIssuerName",
    "ListCost",
    "ListUnitPrice",
    "PricingCategory",
    "PricingCurrency",
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
    "ServiceSubcategory",
    "SkuId",
    "SkuMeter",
    "SkuPriceDetails",
    "SkuPriceId",
    "SubAccountId",
    "SubAccountName",
    "SubAccountType",
    "Tags",
    "x_AccountId",
    "x_AccountName",
    "x_AccountOwnerId",
    "x_AmortizationClass",
    "x_BilledCostInUsd",
    "x_BilledUnitPrice",
    "x_BillingAccountId",
    "x_BillingAccountName",
    "x_BillingExchangeRate",
    "x_BillingExchangeRateDate",
    "x_BillingProfileId",
    "x_BillingProfileName",
    "x_ContractedCostInUsd",
    "x_CostAllocationRuleName",
    "x_CostCenter",
    "x_CustomerId",
    "x_CustomerName",
    "x_EffectiveCostInUsd",
    "x_EffectiveUnitPrice",
    "x_InvoiceSectionId",
    "x_InvoiceSectionName",
    "x_ListCostInUsd",
    "x_PartnerCreditApplied",
    "x_PartnerCreditRate",
    "x_PricingBlockSize",
    "x_PricingCurrency",
    "x_PricingSubcategory",
    "x_PricingUnitDescription",
    "x_PublisherCategory",
    "x_PublisherId",
    "x_ResellerId",
    "x_ResellerName",
    "x_ResourceGroupName",
    "x_ResourceType",
    "x_ServiceModel",
    "x_ServicePeriodEnd",
    "x_ServicePeriodStart",
    "x_SkuDescription",
    "x_SkuDetails",
    "x_SkuIsCreditEligible",
    "x_SkuMeterCategory",
    "x_SkuMeterId",
    "x_SkuMeterName",
    "x_SkuMeterSubcategory",
    "x_SkuOfferId",
    "x_SkuOrderId",
    "x_SkuOrderName",
    "x_SkuPlanName",
    "x_SkuPartNumber",
    "x_SkuRegion",
    "x_SkuServiceFamily",
    "x_SkuTier",
]

# --- EA cost and usage details, dataset version 2024-08-01 -------------------
#
# Names and order are the schema page's numbered table, columns 1 to 57.

COST_DETAILS_COLUMNS = [
    "InvoiceSectionName",
    "AccountName",
    "AccountOwnerId",
    "SubscriptionId",
    "SubscriptionName",
    "ResourceGroup",
    "ResourceLocation",
    "Date",
    "ProductName",
    "MeterCategory",
    "MeterSubCategory",
    "MeterId",
    "MeterName",
    "MeterRegion",
    "UnitOfMeasure",
    "Quantity",
    "EffectivePrice",
    "CostInBillingCurrency",
    "CostCenter",
    "ConsumedService",
    "ResourceId",
    "Tags",
    "OfferId",
    "AdditionalInfo",
    "ServiceInfo1",
    "ServiceInfo2",
    "ResourceName",
    "ReservationId",
    "ReservationName",
    "UnitPrice",
    "ProductOrderId",
    "ProductOrderName",
    "Term",
    "PublisherType",
    "PublisherName",
    "ChargeType",
    "Frequency",
    "PricingModel",
    "AvailabilityZone",
    "BillingAccountId",
    "BillingAccountName",
    "BillingCurrencyCode",
    "BillingPeriodStartDate",
    "BillingPeriodEndDate",
    "BillingProfileId",
    "BillingProfileName",
    "InvoiceSectionId",
    "IsAzureCreditEligible",
    "PartNumber",
    "PayGPrice",
    "PlanName",
    "ServiceFamily",
    "CostAllocationRuleName",
    "benefitId",
    "benefitName",
    "AccountId",
    "ResourceLocationNormalized",
]

# --- EA reservation details, dataset version 2023-03-01 ----------------------

RESERVATION_DETAILS_COLUMNS = [
    "InstanceFlexibilityGroup",
    "InstanceFlexibilityRatio",
    "InstanceId",
    "Kind",
    "ReservationOrderId",
    "ReservationId",
    "ReservedHours",
    "RIUsedHours",
    "SkuName",
    "TotalReservedQuantity",
    "UsageDate",
    "UsedHours",
]

FOCUS_EXPORT_NAME = "cpi-focus-monthly"
FOCUS_RUN_ID = "0f3b8d47-52ea-4c19-b6d0-91a5e7c48f2b"
FOCUS_CONTAINER_URI = e.resource_id(
    e.ADMIN_RG, "Microsoft.Storage/storageAccounts", e.BILLING_STORAGE_NAME
)
FOCUS_CONTAINER_NAME = "cost-exports"
FOCUS_ROOT_FOLDER = "cpi-estate"
PARTITION_COUNT = 2

USD = lambda jpy: f"{jpy / e.JPY_PER_USD:.6f}"  # noqa: E731 — one expression, used everywhere


def money(value: float) -> str:
    return f"{value:.4f}"


def quantity(value: float) -> str:
    return f"{value:.6f}"


# --- one intermediate row shape, rendered into every output ------------------
#
# Each charge is described once and then written out in whichever column set the
# target file uses, which is what keeps the exports agreeing with one another.


def charge(
    *,
    meter: dict | None,
    day: int | None,
    start,
    end,
    qty: float,
    list_unit_price: float,
    billed: float,
    effective: float,
    charge_category: str,
    charge_frequency: str,
    charge_type: str,
    pricing_model: str,
    pricing_category: str,
    pricing_subcategory: str,
    resource_name: str,
    resource_type: str,
    resource_group: str,
    resource_arm_id: str,
    resource_key: str = "",
    service_metadata: str = "",
    pricing_unit: str = "",
    product_name: str = "",
    subscription_blank: bool = False,
    commitment_id: str = "",
    commitment_name: str = "",
    commitment_category: str = "",
    commitment_type: str = "",
    product_order_id: str = "",
    product_order_name: str = "",
    reservation_id: str = "",
    reservation_name: str = "",
    benefit_id: str = "",
    benefit_name: str = "",
    amortization_class: str = "",
    description: str | None = None,
    term: str = "",
    part_number: str | None = None,
) -> dict:
    return {
        "meter": meter,
        "day": day,
        "start": start,
        "end": end,
        "qty": qty,
        "list_unit_price": list_unit_price,
        "billed": billed,
        "effective": effective,
        "charge_category": charge_category,
        "charge_frequency": charge_frequency,
        "charge_type": charge_type,
        "pricing_model": pricing_model,
        "pricing_category": pricing_category,
        "pricing_subcategory": pricing_subcategory,
        "resource_name": resource_name,
        "resource_type": resource_type,
        "resource_group": resource_group,
        "resource_arm_id": resource_arm_id,
        "resource_key": resource_key,
        "service_metadata": service_metadata,
        "pricing_unit": pricing_unit,
        "product_name": product_name,
        "subscription_blank": subscription_blank,
        "commitment_id": commitment_id,
        "commitment_name": commitment_name,
        "commitment_category": commitment_category,
        "commitment_type": commitment_type,
        "product_order_id": product_order_id,
        "product_order_name": product_order_name,
        "reservation_id": reservation_id,
        "reservation_name": reservation_name,
        "benefit_id": benefit_id,
        "benefit_name": benefit_name,
        "amortization_class": amortization_class,
        "description": description,
        "term": term,
        "part_number": part_number,
    }


def build_charges() -> list[dict]:
    charges: list[dict] = []

    for meter in e.METERS:
        rng = e.meter_rng(meter["key"])
        resource = e.RESOURCES_BY_NAME[meter["resource"]]
        arm_id = e.resource_arm_id(resource)
        model = e.pricing_model(meter)
        for day in range(e.DAYS):
            start = e.day_start(day)
            qty = meter["quantity"](day, rng)
            list_cost = round(qty * meter["unit_price"], 4)

            if model == "Reservation":
                billed, effective = 0.0, round(qty * e.RESERVATION_HOURLY_AMORTIZED, 4)
                pricing_category, pricing_subcategory = "Committed", "Reservation"
                commitment = dict(
                    commitment_id=e.RESERVATION_RESOURCE_ID,
                    commitment_name=e.RESERVATION_NAME,
                    commitment_category="Usage",
                    commitment_type="Reservation",
                    product_order_id=e.RESERVATION_ORDER_ID,
                    product_order_name=e.RESERVATION_NAME,
                    reservation_id=e.RESERVATION_ID,
                    reservation_name=e.RESERVATION_NAME,
                    amortization_class="Amortized Charge",
                    term="12 Months",
                )
            elif model == "SavingsPlan":
                billed, effective = 0.0, round(qty * e.SAVINGS_PLAN_HOURLY_RATE, 4)
                pricing_category, pricing_subcategory = "Committed", "Savings Plan"
                commitment = dict(
                    commitment_id=e.SAVINGS_PLAN_RESOURCE_ID,
                    commitment_name=e.SAVINGS_PLAN_NAME,
                    commitment_category="Spend",
                    commitment_type="Savings Plan",
                    product_order_id=e.SAVINGS_PLAN_ORDER_ID,
                    product_order_name=e.SAVINGS_PLAN_NAME,
                    benefit_id=e.SAVINGS_PLAN_RESOURCE_ID,
                    benefit_name=e.SAVINGS_PLAN_NAME,
                    amortization_class="Amortized Charge",
                    term="12 Months",
                )
            else:
                billed = effective = list_cost
                pricing_category, pricing_subcategory = "Standard", "Consumption"
                commitment = {"amortization_class": "Amortized Charge"}

            charges.append(
                charge(
                    meter=meter,
                    day=day,
                    start=start,
                    end=e.day_start(day + 1),
                    qty=qty,
                    list_unit_price=meter["unit_price"],
                    billed=billed,
                    effective=effective,
                    charge_category="Usage",
                    charge_frequency="Usage-Based",
                    charge_type="Usage",
                    pricing_model=model,
                    pricing_category=pricing_category,
                    pricing_subcategory=pricing_subcategory,
                    resource_name=e.leaf_name(resource),
                    resource_type=resource["type"],
                    resource_group=resource["resource_group"],
                    resource_arm_id=arm_id,
                    resource_key=meter["resource"],
                    service_metadata=e.additional_info(meter, model),
                    pricing_unit=meter["unit"],
                    **commitment,
                )
            )

    # Reserved instance-hours that no machine consumed. Hours, not money, on
    # July's invoice: the order was paid for in April.
    reservation_meter = e.METERS_BY_KEY["dc01-compute"]
    for day in range(e.DAYS):
        unapplied_hours = 24.0 * e.RESERVED_INSTANCE_HOURS_UNAPPLIED
        charges.append(
            charge(
                meter=reservation_meter,
                day=day,
                start=e.day_start(day),
                end=e.day_start(day + 1),
                qty=unapplied_hours,
                list_unit_price=reservation_meter["unit_price"],
                billed=0.0,
                effective=round(unapplied_hours * e.RESERVATION_HOURLY_AMORTIZED, 4),
                charge_category="Usage",
                charge_frequency="Usage-Based",
                charge_type="UnusedReservation",
                pricing_model="Reservation",
                pricing_category="Committed",
                pricing_subcategory="Reservation",
                resource_name=e.RESERVATION_NAME,
                resource_type="microsoft.capacity/reservationorders/reservations",
                resource_group="",
                resource_arm_id=e.RESERVATION_RESOURCE_ID,
                pricing_unit=reservation_meter["unit"],
                subscription_blank=True,
                commitment_id=e.RESERVATION_RESOURCE_ID,
                commitment_name=e.RESERVATION_NAME,
                commitment_category="Usage",
                commitment_type="Reservation",
                product_order_id=e.RESERVATION_ORDER_ID,
                product_order_name=e.RESERVATION_NAME,
                reservation_id=e.RESERVATION_ID,
                reservation_name=e.RESERVATION_NAME,
                amortization_class="Amortized Charge",
                term="12 Months",
                part_number="",
            )
        )

    # The savings plan is billed every month rather than up front, so the
    # invoice carries a purchase line for it.
    sp_day = e.SAVINGS_PLAN_PURCHASE_DAY - 1
    sp_amount = round(e.SAVINGS_PLAN_HOURLY_COMMITMENT * e.HOURS_IN_PERIOD, 4)
    charges.append(
        charge(
            meter=None,
            day=sp_day,
            start=e.day_start(sp_day),
            end=e.day_start(sp_day + 1),
            qty=float(e.HOURS_IN_PERIOD),
            list_unit_price=e.SAVINGS_PLAN_HOURLY_COMMITMENT,
            pricing_unit="1 Hour",
            product_name="Compute Savings Plan - 1 Year - Monthly",
            billed=sp_amount,
            effective=0.0,
            charge_category="Purchase",
            charge_frequency="Recurring",
            charge_type="Purchase",
            pricing_model="SavingsPlan",
            pricing_category="Committed",
            pricing_subcategory="Savings Plan",
            resource_name=e.SAVINGS_PLAN_NAME,
            resource_type="microsoft.billingbenefits/savingsplanorders/savingsplans",
            resource_group="",
            resource_arm_id=e.SAVINGS_PLAN_RESOURCE_ID,
            commitment_id=e.SAVINGS_PLAN_RESOURCE_ID,
            commitment_name=e.SAVINGS_PLAN_NAME,
            commitment_category="Spend",
            commitment_type="Savings Plan",
            product_order_id=e.SAVINGS_PLAN_ORDER_ID,
            product_order_name=e.SAVINGS_PLAN_NAME,
            benefit_id=e.SAVINGS_PLAN_RESOURCE_ID,
            benefit_name=e.SAVINGS_PLAN_NAME,
            amortization_class="Principal",
            description="Compute Savings Plan - 1 Year - Monthly",
            term="12 Months",
            part_number="",
        )
    )

    charges.sort(
        key=lambda c: (
            e.date_only(c["start"]),
            c["resource_name"],
            (c["meter"]["meter_name"] if c["meter"] else ""),
            c["charge_type"],
        )
    )
    return charges


# --- rendering ---------------------------------------------------------------


def focus_row(c: dict) -> dict:
    meter = c["meter"]
    is_purchase = c["charge_category"] == "Purchase"
    tags = e.tags_json(_full_resource_key(c))
    list_cost = round(c["qty"] * c["list_unit_price"], 4)
    # The negotiated cost before any commitment discount is applied; for a
    # purchase there is nothing underneath it but the purchase itself.
    contracted = c["billed"] if is_purchase else list_cost
    return {
        "BilledCost": money(c["billed"]),
        "BillingAccountId": e.BILLING_ACCOUNT_ID,
        "BillingAccountName": e.BILLING_ACCOUNT_NAME,
        "BillingAccountType": "Enrollment",
        "BillingCurrency": e.CURRENCY,
        "BillingPeriodEnd": e.stamp(e.PERIOD_END),
        "BillingPeriodStart": e.stamp(e.PERIOD_START),
        "CapacityReservationId": "",
        "CapacityReservationStatus": "",
        "ChargeCategory": c["charge_category"],
        "ChargeClass": "",
        "ChargeDescription": c["description"] or meter["description"],
        "ChargeFrequency": c["charge_frequency"],
        "ChargePeriodEnd": e.stamp(c["end"]),
        "ChargePeriodStart": e.stamp(c["start"]),
        "CommitmentDiscountCategory": c["commitment_category"],
        "CommitmentDiscountId": c["commitment_id"],
        "CommitmentDiscountName": c["commitment_name"],
        "CommitmentDiscountQuantity": "",
        "CommitmentDiscountStatus": "",
        "CommitmentDiscountType": c["commitment_type"],
        "CommitmentDiscountUnit": "",
        "ConsumedQuantity": "" if is_purchase else quantity(c["qty"]),
        "ConsumedUnit": "" if is_purchase else c["pricing_unit"],
        "ContractedCost": money(contracted),
        "ContractedUnitPrice": money(c["list_unit_price"]),
        "EffectiveCost": money(c["effective"]),
        "InvoiceId": e.INVOICE_ID,
        "InvoiceIssuerName": "Microsoft",
        "ListCost": money(list_cost),
        "ListUnitPrice": money(c["list_unit_price"]),
        "PricingCategory": c["pricing_category"],
        "PricingCurrency": e.CURRENCY,
        "PricingQuantity": quantity(c["qty"]),
        "PricingUnit": c["pricing_unit"],
        "ProviderName": "Microsoft",
        "PublisherName": "Microsoft",
        "RegionId": e.REGION_ID,
        "RegionName": e.REGION_NAME,
        "ResourceId": c["resource_arm_id"],
        "ResourceName": c["resource_name"],
        "ResourceType": c["resource_type"],
        "ServiceCategory": meter["service_category"] if meter else "Compute",
        "ServiceName": meter["service_name"] if meter else "Virtual Machines",
        "ServiceSubcategory": meter["service_subcategory"] if meter else "Virtual Machines",
        "SkuId": meter["meter_id"] if meter else "",
        "SkuMeter": "" if is_purchase else meter["meter_name"],
        "SkuPriceDetails": "",
        "SkuPriceId": f"{meter['meter_id']}-{e.REGION_ID}" if meter else "",
        "SubAccountId": "" if c["subscription_blank"] else f"/subscriptions/{e.SUBSCRIPTION_ID}",
        "SubAccountName": "" if c["subscription_blank"] else e.SUBSCRIPTION_NAME,
        "SubAccountType": "Subscription",
        "Tags": tags,
        "x_AccountId": e.BILLING_ACCOUNT_ID,
        "x_AccountName": e.ENROLMENT_ACCOUNT_NAME,
        "x_AccountOwnerId": e.ENROLMENT_ACCOUNT_OWNER,
        "x_AmortizationClass": c["amortization_class"],
        "x_BilledCostInUsd": USD(c["billed"]),
        "x_BilledUnitPrice": money(0.0 if c["billed"] == 0 else c["list_unit_price"]),
        "x_BillingAccountId": e.BILLING_ACCOUNT_ID,
        "x_BillingAccountName": e.BILLING_ACCOUNT_NAME,
        "x_BillingExchangeRate": "1",
        "x_BillingExchangeRateDate": e.EXCHANGE_RATE_DATE,
        "x_BillingProfileId": e.BILLING_PROFILE_ID,
        "x_BillingProfileName": e.BILLING_PROFILE_NAME,
        "x_ContractedCostInUsd": USD(contracted),
        "x_CostAllocationRuleName": "",
        "x_CostCenter": _cost_center(c),
        "x_CustomerId": "",
        "x_CustomerName": "",
        "x_EffectiveCostInUsd": USD(c["effective"]),
        "x_EffectiveUnitPrice": money(
            0.0 if c["qty"] == 0 else round(c["effective"] / c["qty"], 6)
        ),
        "x_InvoiceSectionId": e.DEPARTMENT_ID,
        "x_InvoiceSectionName": e.DEPARTMENT_NAME,
        "x_ListCostInUsd": USD(list_cost),
        "x_PartnerCreditApplied": "",
        "x_PartnerCreditRate": "",
        "x_PricingBlockSize": "",
        "x_PricingCurrency": e.CURRENCY,
        "x_PricingSubcategory": c["pricing_subcategory"],
        "x_PricingUnitDescription": c["pricing_unit"],
        "x_PublisherCategory": "Microsoft",
        "x_PublisherId": "",
        "x_ResellerId": "",
        "x_ResellerName": "",
        "x_ResourceGroupName": c["resource_group"],
        "x_ResourceType": c["resource_type"],
        "x_ServiceModel": meter["service_model"] if meter else "IaaS",
        "x_ServicePeriodEnd": e.stamp(e.PERIOD_END),
        "x_ServicePeriodStart": e.stamp(e.PERIOD_START),
        "x_SkuDescription": meter["product"] if meter else c["product_name"],
        "x_SkuDetails": c["service_metadata"],
        "x_SkuIsCreditEligible": "True",
        "x_SkuMeterCategory": meter["meter_category"] if meter else "",
        "x_SkuMeterId": meter["meter_id"] if meter else "",
        "x_SkuMeterName": "" if is_purchase else meter["meter_name"],
        "x_SkuMeterSubcategory": meter["meter_subcategory"] if meter else "",
        "x_SkuOfferId": e.OFFER_ID,
        "x_SkuOrderId": "",
        "x_SkuOrderName": "",
        "x_SkuPlanName": "",
        "x_SkuPartNumber": _part_number(c),
        "x_SkuRegion": e.REGION_ID,
        "x_SkuServiceFamily": meter["service_category"] if meter else "Compute",
        "x_SkuTier": "",
    }


def _full_resource_key(c: dict) -> str:
    """The estate key for a charge. Commitment rows are not attributed to one."""
    return c["resource_key"]


def _cost_center(c: dict) -> str:
    resource = e.RESOURCES_BY_NAME.get(_full_resource_key(c))
    if resource is None:
        return ""
    return resource["tags"].get("CostCenter", "")


def _part_number(c: dict) -> str:
    """Savings plan and prepurchased reservation rows carry no part number."""
    if c["part_number"] is not None:
        return c["part_number"]
    return c["meter"]["part_number"] if c["meter"] else ""


def cost_details_row(c: dict, *, amortized: bool) -> dict:
    meter = c["meter"]
    is_purchase = c["charge_type"] == "Purchase"
    cost = c["effective"] if amortized else c["billed"]
    effective_price = 0.0 if c["qty"] == 0 else round(cost / c["qty"], 6)
    return {
        "InvoiceSectionName": e.DEPARTMENT_NAME,
        "AccountName": e.ENROLMENT_ACCOUNT_NAME,
        "AccountOwnerId": e.ENROLMENT_ACCOUNT_OWNER,
        # Charges that belong to no subscription come through without one.
        "SubscriptionId": "" if c["subscription_blank"] else e.SUBSCRIPTION_ID,
        "SubscriptionName": "" if c["subscription_blank"] else e.SUBSCRIPTION_NAME,
        "ResourceGroup": c["resource_group"],
        "ResourceLocation": e.REGION_ID,
        "Date": e.date_only(c["start"]),
        "ProductName": meter["product"] if meter else c["product_name"],
        "MeterCategory": meter["meter_category"] if meter else "",
        "MeterSubCategory": meter["meter_subcategory"] if meter else "",
        "MeterId": meter["meter_id"] if meter else "",
        "MeterName": "" if is_purchase else meter["meter_name"],
        "MeterRegion": e.REGION_NAME,
        "UnitOfMeasure": c["pricing_unit"],
        "Quantity": quantity(c["qty"]),
        "EffectivePrice": money(effective_price),
        "CostInBillingCurrency": money(cost),
        "CostCenter": "",
        "ConsumedService": meter["consumed_service"] if meter else "Microsoft.BillingBenefits",
        "ResourceId": c["resource_arm_id"],
        "Tags": e.tags_json(_full_resource_key(c)),
        "OfferId": e.OFFER_ID,
        "AdditionalInfo": c["service_metadata"],
        "ServiceInfo1": "",
        "ServiceInfo2": "",
        "ResourceName": c["resource_name"],
        "ReservationId": c["reservation_id"],
        "ReservationName": c["reservation_name"],
        "UnitPrice": money(c["list_unit_price"]),
        "ProductOrderId": c["product_order_id"],
        "ProductOrderName": c["product_order_name"],
        "Term": c["term"],
        "PublisherType": "Azure",
        "PublisherName": "Microsoft",
        "ChargeType": c["charge_type"],
        "Frequency": c["charge_frequency"] if is_purchase else "UsageBased",
        "PricingModel": c["pricing_model"],
        "AvailabilityZone": "",
        "BillingAccountId": e.BILLING_ACCOUNT_ID,
        "BillingAccountName": e.BILLING_ACCOUNT_NAME,
        "BillingCurrencyCode": e.CURRENCY,
        "BillingPeriodStartDate": e.date_only(e.PERIOD_START),
        "BillingPeriodEndDate": e.date_only(e.PERIOD_END),
        "BillingProfileId": e.BILLING_PROFILE_ID,
        "BillingProfileName": e.BILLING_PROFILE_NAME,
        "InvoiceSectionId": e.DEPARTMENT_ID,
        "IsAzureCreditEligible": "True",
        "PartNumber": _part_number(c),
        "PayGPrice": money(c["list_unit_price"]),
        "PlanName": "",
        "ServiceFamily": meter["service_category"] if meter else "Compute",
        "CostAllocationRuleName": "",
        "benefitId": c["benefit_id"],
        "benefitName": c["benefit_name"],
        "AccountId": e.BILLING_ACCOUNT_ID,
        "ResourceLocationNormalized": e.REGION_NORMALIZED,
    }


def reservation_detail_rows() -> list[dict]:
    """One row per benefiting instance per day, as the report emits them."""
    rows = []
    reserved_hours = 24.0 * e.RESERVATION_QUANTITY
    for day in range(e.DAYS):
        for key in e.RESERVED_METER_KEYS:
            meter = e.METERS_BY_KEY[key]
            resource = e.RESOURCES_BY_NAME[meter["resource"]]
            rows.append(
                {
                    "InstanceFlexibilityGroup": "DSv3 Series",
                    "InstanceFlexibilityRatio": "1",
                    "InstanceId": e.resource_arm_id(resource),
                    "Kind": "Reservation",
                    "ReservationOrderId": e.RESERVATION_ORDER_ID,
                    "ReservationId": e.RESERVATION_ID,
                    "ReservedHours": f"{reserved_hours:.1f}",
                    "RIUsedHours": "24.0",
                    "SkuName": e.RESERVATION_SKU,
                    "TotalReservedQuantity": str(e.RESERVATION_QUANTITY),
                    "UsageDate": e.date_only(e.day_start(day)),
                    "UsedHours": "24.0",
                }
            )
    return rows


# --- writing -----------------------------------------------------------------


def write_csv(path: pathlib.Path, columns: list[str], rows: list[dict]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=columns, lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)


def csv_bytes(columns: list[str], rows: list[dict]) -> bytes:
    buffer = io.StringIO()
    writer = csv.DictWriter(buffer, fieldnames=columns, lineterminator="\n")
    writer.writeheader()
    writer.writerows(rows)
    return buffer.getvalue().encode("utf-8")


def write_gzip(path: pathlib.Path, payload: bytes) -> None:
    """Gzip with no stored filename and a zeroed timestamp, so bytes repeat."""
    path.parent.mkdir(parents=True, exist_ok=True)
    raw = io.BytesIO()
    with gzip.GzipFile(filename="", mode="wb", fileobj=raw, compresslevel=9, mtime=0) as gz:
        gz.write(payload)
    path.write_bytes(raw.getvalue())


def partition(rows: list[dict], count: int) -> list[list[dict]]:
    size = -(-len(rows) // count)
    return [rows[i : i + size] for i in range(0, len(rows), size)]


def write_focus(root: pathlib.Path, charges: list[dict]) -> tuple[int, int]:
    rows = [focus_row(c) for c in charges]
    parts = partition(rows, PARTITION_COUNT)
    container_root = root / "focus"
    run_path = (
        f"{FOCUS_ROOT_FOLDER}/{FOCUS_EXPORT_NAME}/"
        f"{e.PERIOD_START:%Y%m%d}-{e.PERIOD_END:%Y%m%d}/{FOCUS_RUN_ID}"
    )
    run_dir = container_root / run_path
    blobs = []
    for index, part in enumerate(parts):
        name = f"part_{index}_0001.csv.gz"
        target = run_dir / name
        write_gzip(target, csv_bytes(FOCUS_COLUMNS, part))
        blobs.append(
            {
                "blobName": f"{run_path}/{name}",
                "byteCount": target.stat().st_size,
                "dataRowCount": len(part),
            }
        )

    manifest = {
        "manifestVersion": "2024-04-01",
        "byteCount": sum(b["byteCount"] for b in blobs),
        "blobCount": len(blobs),
        "dataRowCount": len(rows),
        "exportConfig": {
            "exportName": FOCUS_EXPORT_NAME,
            "resourceId": (
                f"/providers/Microsoft.Billing/billingAccounts/{e.BILLING_ACCOUNT_ID}"
                f"/providers/Microsoft.CostManagement/exports/{FOCUS_EXPORT_NAME}"
            ),
            "dataVersion": "1.2-preview",
            "apiVersion": "2023-07-01-preview",
            "type": "FocusCost",
            "timeFrame": "TheLastMonth",
            "granularity": "Daily",
        },
        "deliveryConfig": {
            "partitionData": True,
            "dataOverwriteBehavior": "OverwritePreviousReport",
            "fileFormat": "Csv",
            "compressionMode": "gzip",
            "containerUri": FOCUS_CONTAINER_URI,
            "containerName": FOCUS_CONTAINER_NAME,
            "rootFolderPath": FOCUS_ROOT_FOLDER,
        },
        "runInfo": {
            "executionType": "Scheduled",
            "submittedTime": "2026-08-01T03:15:22Z",
            "runId": FOCUS_RUN_ID,
            "startDate": e.stamp(e.PERIOD_START),
            "endDate": e.stamp(e.PERIOD_END),
        },
        "blobs": blobs,
    }
    (run_dir / "_manifest.json").write_text(
        json.dumps(manifest, indent=2) + "\n", encoding="utf-8"
    )
    return len(rows), len(blobs)


def main() -> None:
    root = (
        pathlib.Path(sys.argv[1])
        if len(sys.argv) > 1
        else pathlib.Path(__file__).resolve().parent
    )
    root.mkdir(parents=True, exist_ok=True)

    charges = build_charges()

    focus_rows, blob_count = write_focus(root, charges)

    actual = [
        cost_details_row(c, amortized=False)
        for c in charges
        if c["charge_type"] != "UnusedReservation"
    ]
    amortized = [
        cost_details_row(c, amortized=True) for c in charges if c["charge_type"] != "Purchase"
    ]
    write_csv(root / "cpi-actual-cost.csv", COST_DETAILS_COLUMNS, actual)
    write_csv(root / "cpi-amortized-cost.csv", COST_DETAILS_COLUMNS, amortized)

    reservations = reservation_detail_rows()
    write_csv(root / "cpi-reservation-usage.csv", RESERVATION_DETAILS_COLUMNS, reservations)

    billed = sum(c["billed"] for c in charges)
    effective = sum(c["effective"] for c in charges)
    print(
        f"focus/          {focus_rows} rows across {blob_count} partitions "
        f"({e.CURRENCY} {billed:,.0f} BilledCost, {e.CURRENCY} {effective:,.0f} EffectiveCost)"
    )
    print(f"cpi-actual-cost.csv         {len(actual)} rows")
    print(f"cpi-amortized-cost.csv      {len(amortized)} rows")
    print(f"cpi-reservation-usage.csv {len(reservations)} rows")


if __name__ == "__main__":
    main()
