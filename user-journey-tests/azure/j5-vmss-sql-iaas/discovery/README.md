# discovery/ — synthetic Migration Center discovery-client export

**Everything in this directory is SYNTHETIC.** No number here was measured, on Azure or anywhere else.
No real tenant, subscription, customer or host is represented — the subscription GUID, the machine UUIDs
and the MAC addresses are all fabricated. It exists so that tooling reading this directory meets a
discovery artifact shaped the way a real one is shaped.

## What it imitates

`mcdc-export/` imitates what the **Google Cloud Migration Center discovery client CLI (`mcdc`, 6.3.x)**
writes when it is asked to export what it collected instead of uploading it — the command Google
documents as `mcdc export mc-frames-zip`, whose output the console imports under the file-format name
**MCDC (ZIP)**.

Two shape facts are reproduced because both are documented, and a parser that gets either wrong reads
nothing:

- **Two kinds of file.** A `metadata.json` describing the export, plus one or more `data.<n>.json`
  holding the asset data. Google's wording: "Each zip file contains at least two JSON files."
- **`data.<n>.json` is a bare top-level JSON array of `AssetFrame` objects** — not an object with a
  wrapper key. The offline-export page states this and links `AssetFrame` straight at the REST
  reference.

Sources:
<https://cloud.google.com/migration-center/docs/discovery-client-offline-export>,
<https://cloud.google.com/migration-center/docs/reference/rest/v1/MachineDetails>,
<https://cloud.google.com/migration-center/docs/discover-azure-vms>.

## What is documented here, and what is an imitation

This matters more than usual, because Google publishes a schema for one of these two files and not the
other.

| Part                                                                                                          | Status                                                                                                                                      |
| ------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------- |
| `AssetFrame` and `MachineDetails` field names, nesting and enum values                                        | **Documented** in the Migration Center v1 REST reference and reproduced faithfully                                                          |
| `powerState` values (`ACTIVE`, `SUSPENDED`)                                                                   | **Documented.** `SUSPENDED` means "the machine is off"; there is no separate stopped state                                                  |
| `platform.azureVmDetails` with `machineTypeLabel` / `location` / `provisioningState` / `hyperthreading`       | **Documented** — note the JSON key is `azureVmDetails`, shorter than the type name `AzureVmPlatformDetails`                                 |
| int64 fields (`totalCapacityBytes`, `capacityBytes`) carried as JSON **strings**                              | **Documented** — proto3 JSON mapping, and easy to get wrong                                                                                 |
| `network.primaryMacAddress` (not `macAddress`) at the top level                                               | **Documented**                                                                                                                              |
| lowerCamelCase keys throughout                                                                                | **Inferred** from the REST reference. No published sample of a real `mcdc` archive was available to check the emitted bytes against         |
| **`metadata.json` key names and types**                                                                       | **An imitation.** Google describes the file's _content_ ("the API version used and the timestamp of the export") and publishes no key names |
| The `attributes` keys (`azure.subscriptionId`, `azure.resourceGroup`, `azure.resourceId`, `azure.powerState`) | **An imitation.** `attributes` is a documented free-form `string -> string` map; which keys `mcdc` actually populates is not published      |
| `collectionType: SOURCE_TYPE_DISCOVERY_CLIENT`                                                                | Documented enum value; that `mcdc` stamps this particular one is a semantic choice, not a verified fact                                     |

Two further departures from a live run, both about packaging rather than about the data:

- **It is a directory, not a `.zip`.** The archive is unpacked so the JSON is readable in a diff and in
  review. Repack it if you need to feed a real import.
- **The performance samples are frozen in the past.** A live import ignores samples "from more than 40
  days ago or after tomorrow", so a committed file will eventually fall outside that window. The samples
  are here as sizing evidence, not as something to replay.

## What the file covers

| Property        | Value                                                            |
| --------------- | ---------------------------------------------------------------- |
| Asset frames    | 4                                                                |
| Report time     | 2026-07-28T02:14:31Z                                             |
| Collection path | Azure inventory (the platform's own APIs, not an in-guest agent) |
| Region          | `westus3`                                                        |

Because the Azure collection path reads Azure's APIs rather than looking inside the guest, it never sees
file-system free space. `totalFreeBytes` and `freeBytes` are therefore absent from every frame, which is
correct rather than missing. For the same reason the disk entries carry capacities and labels but no
partition detail.

`vsi-hist01` reports no performance samples at all. A machine that is not running emits no metrics.

Region is the one value that has to be kept in step by hand. Nothing else in this package names a
region: the Terraform takes it from a variable and the scripts take it from `AZURE_LOCATION`. An export
has no such option, so `REGION_ID` at the top of `make-mcdc-export.py` carries the region the estate is
deployed into, and it needs editing if the estate moves. Nothing else in the file changes when it does.

Resource names in the `azure.resourceId` attribute carry the resource group and subscription of the
estate this was modelled on. A fresh deployment computes a different subscription id, so those strings
will not match character for character.

For every machine the export and the deployment template both describe, their names, sizes, core and
memory counts, disk sizes and addresses agree. The export is not limited to what the template creates,
though — a collector inventories the subscription, not the code — so do not read it as a list of what
`terraform/` would stand up.

## Regenerating

```bash
python3 make-mcdc-export.py                 # rewrites mcdc-export/ in place
python3 make-mcdc-export.py /tmp/mcdc-out   # or write a copy elsewhere
```

`make-mcdc-export.py` needs nothing outside the Python standard library. It is deterministic — a frozen
report time, frozen sample times, one seeded generator per machine, and no clock reads anywhere — so
regenerating produces **byte-identical** files, which is what lets a parity check hash them.
