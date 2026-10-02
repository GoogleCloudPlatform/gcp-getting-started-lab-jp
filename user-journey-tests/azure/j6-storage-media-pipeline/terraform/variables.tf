variable "location" {
  description = "Azure region for the regional resources in this tree. No default: scripts/deploy.sh exports it from AZURE_LOCATION in ~/.azure/journeys.env. The Front Door profile itself is a global resource and takes no region."
  type        = string
}

variable "resource_group_name" {
  description = "The single resource group holding the whole estate. This tree does not create it — scripts/deploy.sh does, before anything else runs."
  type        = string
  default     = "smp-rg"
}

variable "autoteardown_date" {
  description = "YYYY-MM-DD for the AutoTeardown tag (set by scripts/deploy.sh from ~/.azure/journeys.env)."
  type        = string
}

variable "name_suffix" {
  description = "Lowercase alphanumeric suffix that makes the delivery account's global DNS name unique. No default, and it must be the same value ../arm/azuredeploy.json is given: scripts/deploy.sh derives it once and passes it to both trees."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]{6,12}$", var.name_suffix))
    error_message = "name_suffix must be 6-12 lowercase letters and digits: it is concatenated onto a storage account name, which allows nothing else."
  }
}

variable "frontdoor_sku" {
  description = "Front Door tier. Standard covers routing and caching, which is all the preview delivery needs; Premium adds the managed WAF rule sets and bot protection the studio has never bought."
  type        = string
  default     = "Standard_AzureFrontDoor"
}
