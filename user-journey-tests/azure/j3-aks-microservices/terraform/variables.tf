variable "location" {
  description = "Azure region for every resource in the platform. No default: scripts/deploy.sh exports it from AZURE_LOCATION in ~/.azure/journeys.env."
  type        = string
}

variable "resource_group_name" {
  description = "The single resource group holding the platform."
  type        = string
  default     = "akm-rg"
}

variable "autoteardown_date" {
  description = "YYYY-MM-DD for the AutoTeardown tag (set by scripts/deploy.sh from ~/.azure/journeys.env)."
  type        = string
}

variable "kubernetes_version" {
  description = "AKS minor version. Left unset so the cluster takes whatever AKS offers as default in the region."
  type        = string
  default     = null
}

variable "node_vm_size" {
  description = "Size of every node in the pool. Overridable, because which sizes a subscription may actually create varies by region and by quota."
  type        = string
  default     = "Standard_D2s_v5"
}

variable "node_count" {
  description = "Fixed node count for the pool. There is no autoscaler on this cluster."
  type        = number
  default     = 2
}

variable "acr_replication_region" {
  description = "Second region the registry replicates into. Unlike location, this one belongs to the estate rather than to whoever is standing it up: the replica was added for the planned western depot and has stayed there ever since. A registry cannot hold a replica in its own region, so it must differ from var.location; AKM_ACR_REPLICATION_REGION overrides it for a platform standing up in this region."
  type        = string
  default     = "japanwest"
}

variable "deploy_role_assignments" {
  description = "Create the role assignments that let the cluster pull images and let the pods reach Service Bus and Cosmos DB. Creating them needs more than Contributor on the subscription; set false to stand the estate up without them, in which case the workloads cannot authenticate."
  type        = bool
  default     = true
}

variable "k8s_namespace" {
  description = "Namespace the services run in. Must match ../k8s/00-namespace.yaml."
  type        = string
  default     = "tracking"
}

variable "k8s_service_account" {
  description = "Kubernetes service account the pods run as. Must match ../k8s/10-serviceaccount.yaml."
  type        = string
  default     = "akm-workload"
}
