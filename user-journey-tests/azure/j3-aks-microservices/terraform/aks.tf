# The cluster.
#
# One pool. It carries kube-system and both workload services together — the
# contractor never saw a reason to separate them, and at this size nothing has
# forced the issue.
#
# The node VMs land in their own resource group, akm-nodes-rg, which AKS
# creates and owns; nothing there may be edited by hand. The tags below are
# carried onto the resources AKS creates in it.

resource "azurerm_kubernetes_cluster" "main" {
  name                = "akm-aks"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  dns_prefix          = "akm-aks"
  kubernetes_version  = var.kubernetes_version
  node_resource_group = "akm-nodes-rg"
  sku_tier            = "Free"

  # Federated credentials from Entra ID are issued against the cluster's own
  # OIDC issuer, so both switches have to be on.
  oidc_issuer_enabled       = true
  workload_identity_enabled = true

  default_node_pool {
    name       = "apps"
    node_count = var.node_count
    vm_size    = var.node_vm_size

    # Managed rather than ephemeral: the nodes are long-lived and the
    # contractor wanted the OS disk to survive a stop/start.
    os_disk_type    = "Managed"
    os_disk_size_gb = 64
    max_pods        = 50
    tags            = local.tags

    # Changing vm_size (or either disk setting, or max_pods) on the default
    # pool cycles it through a temporary pool of this name. Without the
    # attribute the plan is rejected outright, so a later resize would mean
    # rebuilding the cluster.
    temporary_name_for_rotation = "appstmp"
  }

  identity {
    type = "SystemAssigned"
  }

  # Nodes are the fixed pool declared here; nothing is provisioned on demand.
  node_provisioning_profile {
    mode = "Manual"
  }

  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
    load_balancer_sku   = "standard"
    outbound_type       = "loadBalancer"
  }

  tags = local.tags

  lifecycle {
    # AKS patches the node image and the control-plane patch level out from
    # under Terraform; neither is worth a diff on every plan.
    ignore_changes = [
      kubernetes_version,
      default_node_pool[0].node_count,
    ]
  }
}
