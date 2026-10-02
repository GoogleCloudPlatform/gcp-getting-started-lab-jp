#!/usr/bin/env bash
# deploy.sh — deploy the azure/j3-aks-microservices test bed (the parcel-
# tracking platform, akm-*) to Azure.
# -----------------------------------------------------------------------------
# Requires kubectl, docker and envsubst in addition to az + terraform: this
# stack is dual-layer. Terraform owns the platform; the workloads that run ON
# the cluster are Kubernetes manifests under k8s/, applied with kubectl.
#
# Idempotent: `terraform apply` converges, `kubectl apply -k` is
# create-or-update, and the images are rebuilt and re-pushed every run. There
# are no passwords anywhere in this estate to rotate — the pods authenticate
# with a federated Entra identity and the registry admin account is off — so a
# re-deploy changes no credentials.
#
# Everything Terraform creates lands in ONE resource group (akm-rg). AKS
# creates a SECOND group, akm-nodes-rg, for the node VMs and for the load
# balancer the tracking-api Service asks for; that group belongs to AKS and is
# removed when the cluster is. See scripts/teardown.sh.
#
# Deploy order:
#   1. terraform apply    AKS, ACR (Premium + second region), Service Bus,
#                         Cosmos DB, the identity and its role assignments.
#                         ~10-15 min on the first run.
#   2. kubeconfig         a dedicated file, so ~/.kube/config is left alone
#   3. docker build/push  both images, into the registry from step 1
#   4. envsubst k8s/ -> k8s-build/, kubectl apply -k, wait for the rollout
#   5. wait for the tracking-api Service to publish its load-balancer IP,
#      then poll /health until the edge answers; print BASE_URL
#
# Required env vars (set them in ~/.azure/journeys.env):
#   EXPECTED_SUBSCRIPTION_ID   abort unless the current az context matches
#   AUTOTEARDOWN_DATE          YYYY-MM-DD for the AutoTeardown tag
#   AZURE_LOCATION             region for every resource (no fallback)
# Optional:
#   AKM_ACR_REPLICATION_REGION second registry region; defaults to the one the
#                              platform code carries, which has to differ from
#                              AZURE_LOCATION
#   AKM_NODE_VM_SIZE           node size override, for a subscription whose
#                              region does not offer the default
#   AKM_IMAGE_PLATFORM         docker build --platform; default linux/amd64.
#                              Set linux/arm64 alongside an Arm64 node size.
#   AKM_DEPLOY_ROLE_ASSIGNMENTS  "false" to stand the platform up without the
#                              role assignments (see README: needs more than
#                              Contributor). Nothing authenticates without them,
#                              so the rollout wait warns instead of failing, the
#                              /health poll that cannot succeed is skipped, and
#                              smoke-test.sh reports those checks as XFAIL.
#   AKM_IMAGE_TAG              default: git short sha of this repo, else "latest"
# -----------------------------------------------------------------------------

set -euo pipefail

# ---- load env + pre-flight subscription guard --------------------------------
ENV_FILE="${HOME}/.azure/journeys.env"
if [[ -f "$ENV_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$ENV_FILE"
else
  echo "FATAL: $ENV_FILE not found (needs EXPECTED_SUBSCRIPTION_ID, AUTOTEARDOWN_DATE, AZURE_LOCATION)" >&2
  exit 1
fi
: "${EXPECTED_SUBSCRIPTION_ID:?Set EXPECTED_SUBSCRIPTION_ID in ~/.azure/journeys.env}"
: "${AUTOTEARDOWN_DATE:?Set AUTOTEARDOWN_DATE=YYYY-MM-DD in ~/.azure/journeys.env}"
AZURE_LOCATION="${AZURE_LOCATION:?Set AZURE_LOCATION in ~/.azure/journeys.env}"
RESOURCE_GROUP="akm-rg"
CLUSTER_NAME="akm-aks"
K8S_NAMESPACE="tracking"
IMAGE_PLATFORM="${AKM_IMAGE_PLATFORM:-linux/amd64}"

for tool in az terraform kubectl docker envsubst; do
  command -v "$tool" >/dev/null || {
    echo "FATAL: $tool not found on PATH" >&2
    exit 1
  }
done

SUBSCRIPTION_ID=$(az account show --query id -o tsv)
if [[ "$SUBSCRIPTION_ID" != "$EXPECTED_SUBSCRIPTION_ID" ]]; then
  echo "FATAL: subscription mismatch (got $SUBSCRIPTION_ID, expected $EXPECTED_SUBSCRIPTION_ID)" >&2
  exit 1
fi
export ARM_SUBSCRIPTION_ID="$SUBSCRIPTION_ID"
echo "Deploying azure/j3-aks-microservices to subscription $SUBSCRIPTION_ID, location $AZURE_LOCATION"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TF_DIR="${SCRIPT_DIR}/../terraform"
K8S_DIR="${SCRIPT_DIR}/../k8s"
BUILD_DIR="${SCRIPT_DIR}/../k8s-build"
APP_DIR="${SCRIPT_DIR}/../app"

IMAGE_TAG="${AKM_IMAGE_TAG:-$(git -C "$SCRIPT_DIR" rev-parse --short HEAD 2>/dev/null || echo latest)}"

# ---- resource providers ------------------------------------------------------
# A subscription that has never created these resource types rejects the
# deployment with MissingSubscriptionRegistration. Registering is idempotent.
for ns in Microsoft.ContainerService Microsoft.ContainerRegistry Microsoft.ServiceBus \
  Microsoft.DocumentDB Microsoft.ManagedIdentity Microsoft.Compute Microsoft.Network \
  Microsoft.Storage; do
  state=$(az provider show --namespace "$ns" --query registrationState -o tsv 2>/dev/null || echo "NotRegistered")
  if [[ "$state" != "Registered" ]]; then
    echo ">>> Registering resource provider $ns (currently: $state)"
    az provider register --namespace "$ns" --wait
  fi
done

# ---- 1. terraform apply (platform layer only) --------------------------------
export TF_VAR_autoteardown_date="$AUTOTEARDOWN_DATE"
export TF_VAR_location="$AZURE_LOCATION"
# Plain `[[ ... ]] && export` would abort the script under `set -e` whenever the
# override is unset, which is the normal case.
if [[ -n "${AKM_ACR_REPLICATION_REGION:-}" ]]; then
  if [[ "$AKM_ACR_REPLICATION_REGION" == "$AZURE_LOCATION" ]]; then
    echo "FATAL: AKM_ACR_REPLICATION_REGION must differ from AZURE_LOCATION (both ${AZURE_LOCATION})." >&2
    exit 1
  fi
  export TF_VAR_acr_replication_region="$AKM_ACR_REPLICATION_REGION"
  echo "Registry replica region: $AKM_ACR_REPLICATION_REGION"
fi
if [[ -n "${AKM_NODE_VM_SIZE:-}" ]]; then
  export TF_VAR_node_vm_size="$AKM_NODE_VM_SIZE"
  echo "Node size override: $AKM_NODE_VM_SIZE"
fi
GRANTS_OFF=0
if [[ -n "${AKM_DEPLOY_ROLE_ASSIGNMENTS:-}" ]]; then
  export TF_VAR_deploy_role_assignments="$AKM_DEPLOY_ROLE_ASSIGNMENTS"
  echo "Role assignments: $AKM_DEPLOY_ROLE_ASSIGNMENTS"
  if [[ "${AKM_DEPLOY_ROLE_ASSIGNMENTS,,}" != "true" ]]; then
    GRANTS_OFF=1
  fi
fi

echo ""
echo ">>> terraform apply (first run takes ~10-15 minutes; the AKS control"
echo "    plane and the registry replication dominate)"
terraform -chdir="$TF_DIR" init -input=false
terraform -chdir="$TF_DIR" apply -input=false -auto-approve

ACR_NAME=$(terraform -chdir="$TF_DIR" output -raw container_registry_name)
ACR_LOGIN_SERVER=$(terraform -chdir="$TF_DIR" output -raw container_registry_login_server)
WORKLOAD_IDENTITY_CLIENT_ID=$(terraform -chdir="$TF_DIR" output -raw workload_identity_client_id)
COSMOS_ENDPOINT=$(terraform -chdir="$TF_DIR" output -raw cosmos_endpoint)
SERVICEBUS_NAMESPACE_FQDN=$(terraform -chdir="$TF_DIR" output -raw servicebus_namespace_fqdn)
NODE_RESOURCE_GROUP=$(terraform -chdir="$TF_DIR" output -raw node_resource_group)

# ---- 2. kubeconfig (dedicated file) ------------------------------------------
export KUBECONFIG="${HOME}/.kube/config-akm"
az aks get-credentials \
  --resource-group "$RESOURCE_GROUP" --name "$CLUSTER_NAME" \
  --file "$KUBECONFIG" --overwrite-existing >/dev/null
echo ">>> kubeconfig written to $KUBECONFIG"

# ---- 3. build + push both images ---------------------------------------------
echo ""
echo ">>> Building and pushing images (tag: ${IMAGE_TAG}, platform: ${IMAGE_PLATFORM})"
az acr login --name "$ACR_NAME" >/dev/null

docker build --platform "$IMAGE_PLATFORM" \
  -t "${ACR_LOGIN_SERVER}/akm-tracking-api:${IMAGE_TAG}" "${APP_DIR}/tracking-api"
docker push "${ACR_LOGIN_SERVER}/akm-tracking-api:${IMAGE_TAG}"

docker build --platform "$IMAGE_PLATFORM" \
  -t "${ACR_LOGIN_SERVER}/akm-notifier:${IMAGE_TAG}" "${APP_DIR}/notifier"
docker push "${ACR_LOGIN_SERVER}/akm-notifier:${IMAGE_TAG}"

# ---- 4. render manifests + apply the workload layer --------------------------
# envsubst is restricted to exactly the five placeholders so nothing else in
# the manifests can be mangled.
echo ""
echo ">>> Rendering k8s/ -> k8s-build/ and applying"
export ACR_LOGIN_SERVER IMAGE_TAG WORKLOAD_IDENTITY_CLIENT_ID COSMOS_ENDPOINT SERVICEBUS_NAMESPACE_FQDN
mkdir -p "$BUILD_DIR"
for manifest in "$K8S_DIR"/*.yaml; do
  envsubst '${ACR_LOGIN_SERVER} ${IMAGE_TAG} ${WORKLOAD_IDENTITY_CLIENT_ID} ${COSMOS_ENDPOINT} ${SERVICEBUS_NAMESPACE_FQDN}' \
    <"$manifest" >"${BUILD_DIR}/$(basename "$manifest")"
done

kubectl apply -k "$BUILD_DIR"

# Roll the pods so a freshly pushed image is picked up even when the tag string
# has not changed (repeat deploys with AKM_IMAGE_TAG=latest).
kubectl -n "$K8S_NAMESPACE" rollout restart deploy/tracking-api deploy/notifier

# Without the role assignments the kubelet holds no AcrPull on the registry, so
# the pods sit in ImagePullBackOff and this wait can only ever time out. That is
# the posture the deployment was asked for, not a broken cluster, so warn and
# carry on: the platform is still up and the smoke test reports the checks that
# depend on running pods as XFAIL. With the grants on, a timeout is a real
# failure and still stops the deploy.
ROLLOUT_INCOMPLETE=0
wait_for_rollout() {
  local deployment="$1"
  if kubectl -n "$K8S_NAMESPACE" rollout status "deploy/${deployment}" --timeout=300s; then
    return 0
  fi
  if [[ "$GRANTS_OFF" -eq 1 ]]; then
    ROLLOUT_INCOMPLETE=1
    echo "" >&2
    echo "WARNING: deploy/${deployment} did not become ready within 300s." >&2
    echo "AKM_DEPLOY_ROLE_ASSIGNMENTS is '${AKM_DEPLOY_ROLE_ASSIGNMENTS}', so this run" >&2
    echo "created no AcrPull assignment and the kubelet cannot pull the image." >&2
    echo "Continuing — the platform is deployed and smoke-test.sh reports the" >&2
    echo "pod-dependent checks as XFAIL. For a clean rollout, have someone with" >&2
    echo "Owner or RBAC Administrator on the scope re-run this script with" >&2
    echo "AKM_DEPLOY_ROLE_ASSIGNMENTS=true." >&2
    echo "" >&2
    return 0
  fi
  echo "FATAL: deploy/${deployment} did not become ready within 300s." >&2
  echo "Inspect with: kubectl -n ${K8S_NAMESPACE} describe deploy/${deployment}" >&2
  exit 1
}

wait_for_rollout tracking-api
wait_for_rollout notifier

# ---- 5. wait for the load balancer -------------------------------------------
echo ""
echo ">>> Waiting for the tracking-api Service to publish a load-balancer IP"
LB_IP=""
for _ in $(seq 1 60); do # up to 10 min
  LB_IP=$(kubectl -n "$K8S_NAMESPACE" get svc tracking-api \
    -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)
  [[ -n "$LB_IP" ]] && break
  sleep 10
done
if [[ -z "$LB_IP" ]]; then
  echo "FATAL: tracking-api Service has no load-balancer IP after 10 min." >&2
  echo "Inspect with: kubectl -n ${K8S_NAMESPACE} describe svc tracking-api" >&2
  exit 1
fi

BASE_URL="http://${LB_IP}"
echo ">>> Load balancer: ${LB_IP}"
EDGE_UP=0
if [[ "$ROLLOUT_INCOMPLETE" -eq 1 ]]; then
  # No pod ever reached Ready, so /health has nothing to answer it and the poll
  # below could only run out its full six minutes. BASE_URL is unaffected: it is
  # the load-balancer address read from the Service above, which the cluster
  # publishes whether or not anything is listening behind it.
  echo ">>> Skipping the /health poll — the rollout above did not complete, so"
  echo "    nothing is running behind ${BASE_URL} to answer it."
else
  echo ">>> Polling ${BASE_URL}/health until the edge answers..."
  for _ in $(seq 1 36); do # up to 6 min
    if curl -sf -m 5 "${BASE_URL}/health" >/dev/null 2>&1; then
      EDGE_UP=1
      break
    fi
    sleep 10
  done
fi

echo ""
echo "============================================================"
echo ">>> azure/j3-aks-microservices deployed to ${RESOURCE_GROUP}."
echo "BASE_URL=${BASE_URL}"
echo "ACR=${ACR_LOGIN_SERVER}"
echo "COSMOS_ENDPOINT=${COSMOS_ENDPOINT}"
echo "SERVICEBUS_NAMESPACE=${SERVICEBUS_NAMESPACE_FQDN}"
echo "NODE_RESOURCE_GROUP=${NODE_RESOURCE_GROUP}"
if [[ "$EDGE_UP" != "1" ]]; then
  echo ""
  if [[ "$ROLLOUT_INCOMPLETE" -eq 1 ]]; then
    echo "WARNING: the edge cannot answer /health — nothing is ready behind the load"
    echo "balancer, which follows from the incomplete rollout above."
    echo "Retrying will not change that until the role assignments exist."
  else
    echo "WARNING: the edge did not answer /health within 6 min. A brand-new"
    echo "load balancer can take a few extra minutes — retry shortly."
  fi
fi
echo ""
echo "No passwords were generated or stored: the pods reach Cosmos DB and"
echo "Service Bus with a federated Entra identity, and the registry pulls with"
echo "the cluster's kubelet identity."
echo ""
echo "Next steps:"
echo "  ./scripts/seed.sh ${BASE_URL}"
echo "  ./scripts/smoke-test.sh ${BASE_URL}"
echo "============================================================"
