#!/usr/bin/env python3
"""Regenerate discovery/mcdc-export/ — SYNTHETIC fixture data.

Produces the two files the Migration Center discovery client writes when it is
asked to export what it collected instead of uploading it: a metadata.json
describing the export, and a data.1.json holding a bare JSON array of
AssetFrame objects.

Nothing here was measured. Every address, identifier and number is invented.
The sibling README.md records exactly which parts of the shape are published by
Google and which are an imitation.

Deterministic by construction: the report and sample timestamps are frozen
constants, the performance figures come from a seeded generator, and nothing
reads the clock. Regenerating produces byte-identical files, which is what lets
a parity check hash them.

Usage:
    python3 discovery/make-mcdc-export.py [output-dir]
"""

from __future__ import annotations

import json
import pathlib
import random
import sys

# The region is the one value in this directory that has to be kept in step by
# hand. Nothing else in this package names a region: the Terraform takes it
# from a variable and the scripts take it from AZURE_LOCATION. An export has no
# such option, so it is pinned here and nowhere else.
REGION_ID = "westus3"

# Frozen so nothing picks up the wall clock.
REPORT_TIME = "2026-07-28T02:14:31Z"
EXPORT_TIME = "2026-07-28T02:15:04Z"
SAMPLE_TIMES = [
    "2026-07-27T21:00:00Z",
    "2026-07-27T22:00:00Z",
    "2026-07-27T23:00:00Z",
]

# Fabricated. This is not a real subscription and never was.
SUBSCRIPTION_ID = "b41d8a97-2ce6-4f05-9a3b-71e0c5d8fa62"
RESOURCE_GROUP = "vsi-rg"

GIB = 1024**3

TAGS = {
    "Owner": "migration-test",
    "CostCenter": "test-journeys",
    "AutoTeardown": "2026-08-31",
    "Journey": "azure/j5-vmss-sql-iaas",
}

WINDOWS_2022 = {
    "osName": "Microsoft Windows Server 2022 Datacenter",
    "family": "OS_FAMILY_WINDOWS",
    "version": "10.0.20348",
}

VMSS_RESOURCE = (
    f"/subscriptions/{SUBSCRIPTION_ID}/resourceGroups/{RESOURCE_GROUP}"
    "/providers/Microsoft.Compute/virtualMachineScaleSets/vsi-mes-vmss"
)


def vm_resource_id(name: str) -> str:
    return (
        f"/subscriptions/{SUBSCRIPTION_ID}/resourceGroups/{RESOURCE_GROUP}"
        f"/providers/Microsoft.Compute/virtualMachines/{name}"
    )


# machineName, uuid, createTime, size, cores, memoryMb, powerState,
# azure power-state string, private IP, MAC, IP assignment, cpu model,
# firmware, disks (label, GiB), azure resource id
MACHINES = [
    {
        "machineName": "vsi-mes000000",
        "uuid": "6f2c1a54-8d33-4b70-9c18-2e4a7b0d5931",
        "createTime": "2022-06-14T04:22:10Z",
        "size": "Standard_D2s_v5",
        "coreCount": 2,
        "memoryMb": 8192,
        "powerState": "ACTIVE",
        "azurePowerState": "PowerState/running",
        "ip": "10.40.1.4",
        "mac": "00-0D-3A-1C-4E-71",
        "assignment": "ADDRESS_ASSIGNMENT_DHCP",
        "cpuName": "Intel(R) Xeon(R) Platinum 8370C CPU @ 2.80GHz",
        "firmwareType": "EFI",
        "disks": [("C:", 127)],
        "resourceId": f"{VMSS_RESOURCE}/virtualMachines/0",
        "cpuRange": (14.0, 31.0),
        "memRange": (38.0, 52.0),
    },
    {
        "machineName": "vsi-mes000001",
        "uuid": "0a95b7e2-4c61-4d8f-83a7-cc5f19b6e204",
        "createTime": "2022-06-14T04:22:11Z",
        "size": "Standard_D2s_v5",
        "coreCount": 2,
        "memoryMb": 8192,
        "powerState": "ACTIVE",
        "azurePowerState": "PowerState/running",
        "ip": "10.40.1.5",
        "mac": "00-0D-3A-1C-4E-72",
        "assignment": "ADDRESS_ASSIGNMENT_DHCP",
        "cpuName": "Intel(R) Xeon(R) Platinum 8370C CPU @ 2.80GHz",
        "firmwareType": "EFI",
        "disks": [("C:", 127)],
        "resourceId": f"{VMSS_RESOURCE}/virtualMachines/1",
        "cpuRange": (13.0, 29.0),
        "memRange": (37.0, 51.0),
    },
    {
        "machineName": "vsi-sql01",
        "uuid": "e78d4310-5b92-4a06-bf51-9d3c2a8e6470",
        "createTime": "2022-06-14T03:58:44Z",
        "size": "Standard_D2s_v5",
        "coreCount": 2,
        "memoryMb": 8192,
        "powerState": "ACTIVE",
        "azurePowerState": "PowerState/running",
        "ip": "10.40.2.4",
        "mac": "00-0D-3A-2B-77-05",
        "assignment": "ADDRESS_ASSIGNMENT_STATIC",
        "cpuName": "Intel(R) Xeon(R) Platinum 8370C CPU @ 2.80GHz",
        "firmwareType": "EFI",
        "disks": [("C:", 127), ("F:", 128)],
        "resourceId": vm_resource_id("vsi-sql01"),
        "cpuRange": (22.0, 61.0),
        "memRange": (71.0, 88.0),
    },
    {
        "machineName": "vsi-hist01",
        "uuid": "3c60f8b1-a274-4e19-8d05-46b7ce921f38",
        "createTime": "2021-11-02T07:41:09Z",
        "size": "Standard_D4s_v3",
        "coreCount": 4,
        "memoryMb": 16384,
        "powerState": "SUSPENDED",
        "azurePowerState": "PowerState/stopped",
        "ip": "10.40.2.10",
        "mac": "00-0D-3A-2B-77-1C",
        "assignment": "ADDRESS_ASSIGNMENT_DHCP",
        "cpuName": "Intel(R) Xeon(R) Platinum 8272CL CPU @ 2.60GHz",
        "firmwareType": "BIOS",
        "disks": [("C:", 127), ("E:", 512)],
        "resourceId": vm_resource_id("vsi-hist01"),
        "cpuRange": None,
        "memRange": None,
    },
]


def performance_samples(machine: dict) -> list[dict]:
    """Three hourly samples. A machine that is off reports none at all."""
    if machine["cpuRange"] is None:
        return []

    rng = random.Random(machine["uuid"])
    cpu_low, cpu_high = machine["cpuRange"]
    mem_low, mem_high = machine["memRange"]

    samples = []
    for sample_time in SAMPLE_TIMES:
        read_iops = round(rng.uniform(40.0, 320.0), 1)
        write_iops = round(rng.uniform(15.0, 140.0), 1)
        samples.append({
            "sampleTime": sample_time,
            "cpu": {"utilizedPercentage": round(rng.uniform(cpu_low, cpu_high), 2)},
            "memory": {"utilizedPercentage": round(rng.uniform(mem_low, mem_high), 2)},
            "network": {
                "averageIngressBps": round(rng.uniform(12000.0, 240000.0), 1),
                "averageEgressBps": round(rng.uniform(9000.0, 180000.0), 1),
            },
            "disk": {
                # Read and write override the average when either is set, so
                # emitting an average that disagrees with their sum would be
                # silently discarded rather than honoured.
                "averageIops": round(read_iops + write_iops, 1),
                "averageReadIops": read_iops,
                "averageWriteIops": write_iops,
            },
        })
    return samples


def disk_details(machine: dict) -> dict:
    entries = []
    for index, (label, gib) in enumerate(machine["disks"]):
        entries.append({
            # Every int64 in this API crosses the wire as a JSON string.
            "capacityBytes": str(gib * GIB),
            "diskLabel": label,
            "diskLabelType": "GPT" if machine["firmwareType"] == "EFI" else "MBR",
            "interfaceType": "SCSI",
            "hwAddress": f"0:{index}",
        })
    total = sum(gib for _, gib in machine["disks"]) * GIB
    # No free-space figures: the Azure collection path reads the platform's own
    # APIs rather than the guest, so it never sees inside the file systems.
    return {"totalCapacityBytes": str(total), "disks": {"entries": entries}}


def asset_frame(machine: dict) -> dict:
    return {
        "reportTime": REPORT_TIME,
        "collectionType": "SOURCE_TYPE_DISCOVERY_CLIENT",
        "labels": dict(TAGS),
        "attributes": {
            "azure.subscriptionId": SUBSCRIPTION_ID,
            "azure.resourceGroup": RESOURCE_GROUP,
            "azure.resourceId": machine["resourceId"],
            "azure.powerState": machine["azurePowerState"],
        },
        "performanceSamples": performance_samples(machine),
        "machineDetails": {
            "uuid": machine["uuid"],
            "machineName": machine["machineName"],
            "createTime": machine["createTime"],
            "coreCount": machine["coreCount"],
            "memoryMb": machine["memoryMb"],
            "powerState": machine["powerState"],
            "architecture": {
                "cpuArchitecture": "x64-based PC",
                "cpuName": machine["cpuName"],
                "cpuManufacturer": "Intel",
                "cpuSocketCount": 1,
                "firmwareType": machine["firmwareType"],
                "hyperthreading": "ENABLED",
            },
            "guestOs": dict(WINDOWS_2022),
            "network": {
                "primaryIpAddress": machine["ip"],
                "primaryMacAddress": machine["mac"],
                "adapters": {
                    "entries": [{
                        "adapterType": "Microsoft Hyper-V Network Adapter",
                        "macAddress": machine["mac"],
                        "addresses": {
                            "entries": [{
                                "ipAddress": machine["ip"],
                                "subnetMask": "255.255.255.0",
                                "assignment": machine["assignment"],
                            }],
                        },
                    }],
                },
            },
            "disks": disk_details(machine),
            "platform": {
                "azureVmDetails": {
                    "machineTypeLabel": machine["size"],
                    "location": REGION_ID,
                    "provisioningState": "Succeeded",
                    "hyperthreading": "HYPERTHREADING_STATUS_ENABLED",
                },
            },
        },
    }


def write_json(path: pathlib.Path, payload) -> None:
    path.write_text(json.dumps(payload, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def main() -> int:
    out_dir = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else (
        pathlib.Path(__file__).resolve().parent / "mcdc-export"
    )
    out_dir.mkdir(parents=True, exist_ok=True)

    frames = [asset_frame(machine) for machine in MACHINES]

    write_json(out_dir / "data.1.json", frames)
    write_json(out_dir / "metadata.json", {
        "formatVersion": "1",
        "apiVersion": "v1",
        "collectorVersion": "6.3.0",
        "exportTime": EXPORT_TIME,
        "assetCount": len(frames),
        "dataFiles": ["data.1.json"],
    })

    print(f"wrote {out_dir}/metadata.json and {out_dir}/data.1.json ({len(frames)} asset frames)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
