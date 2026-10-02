#!/usr/bin/env python3
"""Build the synthetic resource listing for the university estate (fictional).

EVERYTHING THIS SCRIPT WRITES IS SYNTHETIC. No listing was taken from a real
subscription. It imitates the shape of `az resource list --output json` so that
a parser written against a real listing works against this one unmodified. See
README.md in this directory.

The estate it describes lives in ../costs/estate.py, which is also what the cost
exports are built from.

Deterministic by construction: no clock reads, no random values, and the entries
are emitted in a fixed order.

Usage:
    python3 make-resource-list.py              # rewrite az-resource-list.json here
    python3 make-resource-list.py /tmp/a.json  # write a copy elsewhere
"""

from __future__ import annotations

import json
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent / "costs"))

import estate as e  # noqa: E402 — the path insert above has to come first

# The resource groups the IT office keeps. The listing was assembled by running
# the command once per group; see README.md.
LISTED_RESOURCE_GROUPS = (e.PORTAL_RG, e.ADMIN_RG, e.DATA_RG)


# A generic resource listing returns whatever the provider puts at the top level
# of the resource. `sku` is top-level on an App Service plan, a database, a
# storage account, a public IP, a vault and a managed disk — but not on a
# virtual machine, whose size sits under `properties.hardwareProfile`, which
# this operation does not expand.
TYPES_WITHOUT_TOP_LEVEL_SKU = {"Microsoft.Compute/virtualMachines"}


def entry(resource: dict) -> dict:
    """One element of the array `az resource list` prints."""
    sku = None if resource["type"] in TYPES_WITHOUT_TOP_LEVEL_SKU else resource["sku"]
    return {
        "id": e.resource_arm_id(resource),
        # A child resource is named for its whole path under the parent, which
        # is how Resource Manager names it — `<server>/<database>`, not
        # `<database>`.
        "name": resource["name"],
        "type": resource["type"],
        "location": e.REGION_ID,
        "resourceGroup": resource["resource_group"],
        "kind": resource["kind"],
        "sku": sku,
        "identity": resource["identity"],
        "managedBy": None,
        "tags": resource["tags"] or None,
        "plan": None,
    }


def build() -> list[dict]:
    return [e_ for e_ in (entry(r) for r in e.RESOURCES if _in_scope(r))]


def _in_scope(resource: dict) -> bool:
    return resource["resource_group"] in LISTED_RESOURCE_GROUPS


def main() -> None:
    target = (
        pathlib.Path(sys.argv[1])
        if len(sys.argv) > 1
        else pathlib.Path(__file__).resolve().parent / "az-resource-list.json"
    )
    entries = build()
    target.write_text(json.dumps(entries, indent=2) + "\n", encoding="utf-8")
    print(f"wrote {len(entries)} entries to {target}")


if __name__ == "__main__":
    main()
