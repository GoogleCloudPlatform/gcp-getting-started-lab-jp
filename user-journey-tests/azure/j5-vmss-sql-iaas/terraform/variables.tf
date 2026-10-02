variable "location" {
  description = "Azure region for every resource in the estate. No default: scripts/deploy.sh exports it from AZURE_LOCATION in ~/.azure/journeys.env."
  type        = string
}

variable "resource_group_name" {
  description = "The single resource group holding the estate."
  type        = string
  default     = "vsi-rg"
}

variable "autoteardown_date" {
  description = "YYYY-MM-DD for the AutoTeardown tag (set by scripts/deploy.sh from ~/.azure/journeys.env)."
  type        = string
}

variable "admin_username" {
  description = "Local Windows administrator account created on the web tier and on the database server."
  type        = string
  default     = "vsiadmin"
}

variable "admin_password" {
  description = "Local Windows administrator password. No default: scripts/deploy.sh generates one per run and passes it in, so it is never written to this repository."
  type        = string
  sensitive   = true
}

variable "web_vm_size" {
  description = "Size of every instance in the MES web scale set. Overridable, because which sizes a subscription may actually create varies by region and by quota."
  type        = string
  default     = "Standard_D2s_v5"
}

variable "web_instance_count" {
  description = "Instances the scale set is created with. The autoscale profile takes over afterwards."
  type        = number
  default     = 2
}

variable "web_image_sku" {
  description = "Windows Server image the web tier is built from. The -g2 suffix selects the generation 2 image; a v5 size will boot either generation, but generation 2 is what the estate was built on. A smaller-disk variant can be substituted where the gallery offers one in the region."
  type        = string
  default     = "2022-datacenter-g2"
}

variable "sql_vm_size" {
  description = "Size of the database server. Overridable for the same reason as web_vm_size."
  type        = string
  default     = "Standard_D2s_v5"
}

variable "sql_image_offer" {
  description = "Gallery offer for the database server. The offer pairs a SQL Server release with a Windows Server release and the pairings are fixed — sql2022-ws2022 and sql2019-ws2019 are real, arbitrary combinations are not."
  type        = string
  default     = "sql2022-ws2022"
}

variable "sql_image_sku" {
  description = "Gallery SKU for the database server image. The -gen2 suffix is not optional here: the sql2022-ws2022 offer publishes no generation 1 SKU at all."
  type        = string
  default     = "sqldev-gen2"
}

variable "sql_data_disk_gb" {
  description = "Size of the data disk holding the MES database files and its backups-to-disk folder."
  type        = number
  default     = 128
}

variable "log_retention_days" {
  description = "Days the workspace keeps its data. The plant's quality system requires two production years to stay queryable, which is what this is set to."
  type        = number
  default     = 730
}

variable "backup_retention_days" {
  description = "Daily recovery points the vault keeps for the database server. Azure enforces a floor of 7 regardless of what the provider schema accepts."
  type        = number
  default     = 7
}
