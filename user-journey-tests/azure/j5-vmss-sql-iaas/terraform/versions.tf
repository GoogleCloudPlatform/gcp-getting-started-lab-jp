# The precision-parts MES operator (fictional) — provider and version pins.
#
# Scope note: this tree is the whole estate. There is no application layer to
# apply on top of it — the MES web tier is an IIS site that the scale set's
# script extension writes at provisioning time, and the database is SQL Server
# running inside a VM, so nothing here hands off to a second tool.

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.0"
    }
  }
}

provider "azurerm" {
  # Subscription comes from ARM_SUBSCRIPTION_ID, exported by scripts/deploy.sh
  # after it has checked the current az context against the expected value.
  features {
    recovery_service {
      # Without these, destroying the protected item leaves the vault holding
      # backup data and the resource group refuses to delete. scripts/
      # teardown.sh does not rely on them — it disables protection through the
      # CLI first — but anyone running `terraform destroy` by hand needs them.
      #
      # Every flag in this block is optional on its own. The catch is that the
      # two vm_backup_* flags are bound to each other by an at-least-one-of
      # rule, so a block that sets only the purge flag fails validation with
      # "one of ...vm_backup_stop... , ...vm_backup_suspend... must be
      # specified". Stating stop = false is what answers that. Do not "tidy"
      # the false one away.
      vm_backup_stop_protection_and_retain_data_on_destroy = false
      purge_protected_items_from_vault_on_destroy          = true
    }

    recovery_services_vaults {
      # Re-apply insurance. A run that destroys the SQL VM but leaves the vault
      # standing does not remove that VM's backup item, it soft-deletes it —
      # and protecting a VM whose item is sitting soft-deleted in the same
      # vault is refused outright. This makes the provider recover the
      # soft-deleted item and carry on instead of failing the apply.
      recover_soft_deleted_backup_protected_vm = true
    }
  }
}
