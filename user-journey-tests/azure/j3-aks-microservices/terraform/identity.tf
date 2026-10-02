# Pod identity.
#
# Both services run as one Kubernetes service account, and that service
# account is federated to a single user-assigned identity in Entra ID. No
# client secret exists anywhere: the pod presents a projected service-account
# token to Entra ID, which trusts the cluster's OIDC issuer, and gets back a
# token for the identity below.
#
# The Kubernetes half of this binding — the service account itself and the
# annotation that names the client id — lives in ../k8s/10-serviceaccount.yaml.

resource "azurerm_user_assigned_identity" "workload" {
  name                = "akm-workload-id"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  tags = local.tags
}

resource "azurerm_federated_identity_credential" "workload" {
  name                      = "akm-fic-tracking"
  user_assigned_identity_id = azurerm_user_assigned_identity.workload.id
  audience                  = ["api://AzureADTokenExchange"]
  issuer                    = azurerm_kubernetes_cluster.main.oidc_issuer_url
  subject                   = "system:serviceaccount:${var.k8s_namespace}:${var.k8s_service_account}"
}

# ---- the four grants ---------------------------------------------------------
#
# All four are switched by var.deploy_role_assignments, because writing an Azure
# role assignment needs Owner or RBAC Administrator on the scope — Contributor
# is not enough. Where the deployer only holds Contributor, the platform can be
# stood up with the switch off and the grants added afterwards by someone with
# the rights; until then nothing authenticates and no image can be pulled. (The
# Cosmos DB grant below is the one exception that Contributor could write on its
# own, but it is switched with the others so the flag has a single meaning.)

# ---- what the cluster may do -------------------------------------------------

# Image pulls are done by the kubelet identity, not by the pod identity and not
# by the control-plane identity.
resource "azurerm_role_assignment" "kubelet_acr_pull" {
  count = var.deploy_role_assignments ? 1 : 0

  scope                            = azurerm_container_registry.main.id
  role_definition_name             = "AcrPull"
  principal_id                     = azurerm_kubernetes_cluster.main.kubelet_identity[0].object_id
  skip_service_principal_aad_check = true
}

# ---- what the pods may do ----------------------------------------------------

# tracking-api publishes scan events, notifier consumes them. Both run as the
# same identity, so both roles land on it at namespace scope.
resource "azurerm_role_assignment" "workload_servicebus_sender" {
  count = var.deploy_role_assignments ? 1 : 0

  scope                = azurerm_servicebus_namespace.main.id
  role_definition_name = "Azure Service Bus Data Sender"
  principal_id         = azurerm_user_assigned_identity.workload.principal_id
}

resource "azurerm_role_assignment" "workload_servicebus_receiver" {
  count = var.deploy_role_assignments ? 1 : 0

  scope                = azurerm_servicebus_namespace.main.id
  role_definition_name = "Azure Service Bus Data Receiver"
  principal_id         = azurerm_user_assigned_identity.workload.principal_id
}

# Cosmos DB documents are reached through the account's own data-plane role
# system, which is separate from Azure RBAC on the control plane.
# 00000000-0000-0000-0000-000000000002 is the built-in Data Contributor.
resource "azurerm_cosmosdb_sql_role_assignment" "workload_data_contributor" {
  count = var.deploy_role_assignments ? 1 : 0

  resource_group_name = azurerm_resource_group.main.name
  account_name        = azurerm_cosmosdb_account.main.name
  role_definition_id  = "${azurerm_cosmosdb_account.main.id}/sqlRoleDefinitions/00000000-0000-0000-0000-000000000002"
  principal_id        = azurerm_user_assigned_identity.workload.principal_id
  scope               = azurerm_cosmosdb_account.main.id
}
