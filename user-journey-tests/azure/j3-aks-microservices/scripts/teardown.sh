#!/usr/bin/env bash
# teardown.sh — delete every azure/j3-aks-microservices resource.
# -----------------------------------------------------------------------------
# Confirmation-gated: type "yes" at the prompt, or set FORCE_TEARDOWN=1 for
# non-interactive runs.
#
# TWO resource groups exist, and only one of them is ours:
#
#   akm-rg         everything Terraform created — cluster, registry, queue,
#                  database, identity.
#   akm-nodes-rg   created and owned by AKS. Holds the node VMs, the cluster's
#                  own virtual network, the load balancer, and the public IP
#                  the tracking-api Service added to it. Deleting the cluster
#                  deletes this group with it; deleting this group by hand
#                  while the cluster still exists is not supported and can
#                  wedge the cluster.
#
# Order matters, because the Service's public IP was provisioned by the CLUSTER
# and Terraform knows nothing about it:
#   1. kubectl delete svc tracking-api  -> the cloud controller releases that
#      frontend address. Skipping this can leave the group delete stuck on
#      PublicIPAddressCannotBeDeleted. The cluster's own OUTBOUND public IP
#      stays until the cluster goes, which is expected.
#   2. delete the remaining workload objects
#   3. az group delete akm-rg           -> deletes the cluster, which in turn
#      deletes akm-nodes-rg
#   4. verify BOTH groups are gone
#
# Deleting rather than stopping matters: a stopped AKS cluster still holds its
# node VMs and still consumes regional vCPU quota.
# -----------------------------------------------------------------------------

set -euo pipefail

# ---- load env + pre-flight subscription guard --------------------------------
ENV_FILE="${HOME}/.azure/journeys.env"
if [[ -f "$ENV_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$ENV_FILE"
else
  echo "FATAL: $ENV_FILE not found (needs EXPECTED_SUBSCRIPTION_ID, AUTOTEARDOWN_DATE)" >&2
  exit 1
fi
: "${EXPECTED_SUBSCRIPTION_ID:?Set EXPECTED_SUBSCRIPTION_ID in ~/.azure/journeys.env}"
: "${AUTOTEARDOWN_DATE:?Set AUTOTEARDOWN_DATE=YYYY-MM-DD in ~/.azure/journeys.env}"
RESOURCE_GROUP="akm-rg"
NODE_RESOURCE_GROUP="akm-nodes-rg"
CLUSTER_NAME="akm-aks"
K8S_NAMESPACE="tracking"

SUBSCRIPTION_ID=$(az account show --query id -o tsv)
if [[ "$SUBSCRIPTION_ID" != "$EXPECTED_SUBSCRIPTION_ID" ]]; then
  echo "FATAL: subscription mismatch (got $SUBSCRIPTION_ID, expected $EXPECTED_SUBSCRIPTION_ID)" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TF_DIR="${SCRIPT_DIR}/../terraform"
BUILD_DIR="${SCRIPT_DIR}/../k8s-build"

if ! az group show --name "$RESOURCE_GROUP" --output none 2>/dev/null; then
  echo "${RESOURCE_GROUP} does not exist."
  # The node group outlives its cluster only when something went wrong, and it
  # is where the billable resources are, so never report "nothing to delete"
  # without looking.
  if az group show --name "$NODE_RESOURCE_GROUP" --output none 2>/dev/null; then
    echo "FATAL: ${NODE_RESOURCE_GROUP} still exists without its cluster — node VMs are still billing." >&2
    az resource list --resource-group "$NODE_RESOURCE_GROUP" --query "[].{name:name, type:type}" -o table || true
    echo "The cluster is already gone, so deleting the group directly is safe:" >&2
    echo "  az group delete --name ${NODE_RESOURCE_GROUP} --yes" >&2
    exit 1
  fi
  echo "${NODE_RESOURCE_GROUP} is gone too — nothing to delete."
  exit 0
fi

# ---- confirmation gate --------------------------------------------------------
echo "About to DELETE resource group ${RESOURCE_GROUP} in subscription ${SUBSCRIPTION_ID},"
echo "and with it the AKS cluster, which removes ${NODE_RESOURCE_GROUP} too."
az resource list --resource-group "$RESOURCE_GROUP" --query "[].{name:name, type:type}" -o table || true

if [[ "${FORCE_TEARDOWN:-0}" != "1" ]]; then
  read -r -p 'Type "yes" to confirm: ' CONFIRM
  if [[ "$CONFIRM" != "yes" ]]; then
    echo "Aborted — nothing was deleted."
    exit 1
  fi
fi

# ---- 1-2. workload layer first (only while the cluster still exists) ----------
if command -v kubectl >/dev/null 2>&1 &&
  az aks show --resource-group "$RESOURCE_GROUP" --name "$CLUSTER_NAME" --output none 2>/dev/null; then
  export KUBECONFIG="${HOME}/.kube/config-akm"
  az aks get-credentials \
    --resource-group "$RESOURCE_GROUP" --name "$CLUSTER_NAME" \
    --file "$KUBECONFIG" --overwrite-existing >/dev/null 2>&1 || true

  # Note the address BEFORE deleting the Service. Counting every public IP in
  # the node group would never reach zero: AKS keeps its own outbound address
  # there for as long as the cluster exists.
  SERVICE_IP=$(kubectl -n "$K8S_NAMESPACE" get svc tracking-api \
    -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)

  echo ">>> Deleting the tracking-api Service (releases its frontend address)..."
  kubectl -n "$K8S_NAMESPACE" delete svc tracking-api --ignore-not-found --timeout=180s || true

  if [[ -n "${SERVICE_IP:-}" ]]; then
    echo ">>> Waiting for ${SERVICE_IP} to be released (up to 5 min)..."
    IP_GONE=0
    for _ in $(seq 1 30); do
      COUNT=$(az network public-ip list --resource-group "$NODE_RESOURCE_GROUP" \
        --query "length([?ipAddress=='${SERVICE_IP}'])" -o tsv 2>/dev/null || echo "0")
      if [[ "$COUNT" == "0" ]]; then
        IP_GONE=1
        break
      fi
      sleep 10
    done
    if [[ "$IP_GONE" == "1" ]]; then
      echo ">>> Frontend address released."
    else
      echo "WARNING: ${SERVICE_IP} is still allocated in ${NODE_RESOURCE_GROUP}; continuing." >&2
    fi
  else
    echo ">>> The Service had no load-balancer address to release."
  fi

  echo ">>> Deleting the remaining workload objects..."
  if [[ -d "$BUILD_DIR" ]]; then
    kubectl delete -k "$BUILD_DIR" --ignore-not-found --timeout=180s || true
  fi
  kubectl delete namespace "$K8S_NAMESPACE" --ignore-not-found --timeout=180s || true
else
  echo ">>> Cluster ${CLUSTER_NAME} not reachable — skipping the workload layer."
fi

# ---- 3. the platform layer ----------------------------------------------------
echo ">>> Deleting ${RESOURCE_GROUP} (this takes several minutes)..."
az group delete --name "$RESOURCE_GROUP" --yes

# ---- 4. verify both groups are gone -------------------------------------------
if az group show --name "$RESOURCE_GROUP" --output none 2>/dev/null; then
  echo "FATAL: ${RESOURCE_GROUP} still exists after delete — investigate before re-running." >&2
  exit 1
fi

NODE_RG_GONE=0
for _ in $(seq 1 30); do # up to 5 min for the cascade to finish
  if ! az group show --name "$NODE_RESOURCE_GROUP" --output none 2>/dev/null; then
    NODE_RG_GONE=1
    break
  fi
  sleep 10
done
if [[ "$NODE_RG_GONE" != "1" ]]; then
  echo "FATAL: ${NODE_RESOURCE_GROUP} survived the cluster delete." >&2
  echo "The cluster is gone, so deleting it directly is now safe:" >&2
  echo "  az group delete --name ${NODE_RESOURCE_GROUP} --yes" >&2
  echo "Check first for a leftover load balancer or public IP:" >&2
  echo "  az resource list --resource-group ${NODE_RESOURCE_GROUP} -o table" >&2
  exit 1
fi

# Local state now describes resources that no longer exist; clearing it keeps
# the next deploy.sh from trying to reconcile them.
rm -rf "${TF_DIR}/terraform.tfstate" "${TF_DIR}/terraform.tfstate.backup" "$BUILD_DIR"
rm -f "${HOME}/.kube/config-akm"

echo ""
echo "azure/j3-aks-microservices teardown complete — ${RESOURCE_GROUP} and ${NODE_RESOURCE_GROUP} are both gone."
