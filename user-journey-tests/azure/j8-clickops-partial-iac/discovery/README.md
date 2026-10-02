# discovery/ — synthetic Azure resource listing

**Everything in this directory is SYNTHETIC.** No listing here was taken from a real subscription. No
real subscription, tenant or customer is represented; the subscription GUID is fabricated. It exists so
that tooling reading this directory meets a resource listing shaped the way a real one is shaped.

## What it imitates

`az-resource-list.json` imitates the JSON that **Azure CLI 2.89.0** prints for

```bash
az resource list --resource-group <name> --output json
```

which is the CLI's presentation of the Azure Resource Manager
[Resources - List](https://learn.microsoft.com/en-us/rest/api/resources/resources/list) operation. Each
element carries `id`, `name`, `type`, `location`, `resourceGroup`, `kind`, `sku`, `identity`,
`managedBy`, `tags`, `plan` and `provisioningState`.

**The exact field contract is an observation, not a documented guarantee.** The REST reference
specifies the `GenericResourceExpanded` shape the API returns, but which of those fields the CLI emits,
which it omits, and which it prints as `null` varies by resource provider and by CLI version — and a
provider that returns nothing for `sku` or `identity` is indistinguishable here from one that has no
such concept. Two consequences are reproduced here and are worth knowing before parsing:

- **A virtual machine has no `sku`.** Its size lives under `properties.hardwareProfile.vmSize`, which
  this operation does not expand, so `sku` is null on those entries.
- **A child resource is named for its whole path under its parent** — `<server>/<database>`, not
  `<database>` — while `type` carries the full type path.

Anything depending on a specific field being present, or on either of those two behaviours, should
confirm it against a live `az resource list` on the CLI version in use rather than against this file.

## What it covers

A listing of this shape is produced by running the command once per resource group and concatenating
the results. The three groups here are the ones the IT office keeps:

| Resource group | What is in it                                                       |
| -------------- | ------------------------------------------------------------------- |
| `cpi-rg`       | the student portal, the part with a template in `bicep/`            |
| `cpi-admin-rg` | the administrative machines, the staff file shares and their backup |
| `cpi-data-rg`  | the data office's analytics project                                 |

26 entries in total. Names in the portal group carry the deploy-time uniqueness suffix from one
concrete deployment, so they will not match a freshly deployed copy character for character; see
`../costs/README.md`.

## Regenerating

```bash
python3 make-resource-list.py              # rewrite az-resource-list.json here
python3 make-resource-list.py /tmp/a.json  # or write a copy elsewhere
python3 ../costs/check-consistency.py      # verify against costs/ and bicep/
```

The generator reads the same description of the subscription that the cost exports are built from
(`../costs/estate.py`), which is what keeps the two directories agreeing. It needs nothing outside the
Python standard library, reads no clock and draws no random values, so regenerating produces a
**byte-identical** file.
