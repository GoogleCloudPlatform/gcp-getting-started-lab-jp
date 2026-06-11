#!/bin/bash
set -euo pipefail

: "${PROJECT_ID:?Set PROJECT_ID before running this script.}"

tpu_zone() {
  case "$1" in
    europe-west4) echo "europe-west4-a" ;;
    asia-northeast1) echo "asia-northeast1-b" ;;
    *)
      echo "ERROR: Unsupported region $1." >&2
      exit 1
      ;;
  esac
}

membership_exists() {
  local membership="$1"
  local location="$2"

  gcloud container fleet memberships describe "$membership" \
    --location="$location" \
    --project="$PROJECT_ID" \
    >/dev/null 2>&1
}

membership_external_id() {
  local membership="$1"
  local location="$2"

  gcloud container fleet memberships describe "$membership" \
    --location="$location" \
    --project="$PROJECT_ID" \
    --format="value(externalId)" 2>/dev/null || true
}

wait_for_regional_membership() {
  local cluster="$1"
  local region="$2"

  echo "Waiting for regional Fleet membership ${cluster} in ${region}..."
  for _ in {1..30}; do
    if membership_exists "$cluster" "$region"; then
      gcloud container fleet memberships describe "$cluster" \
        --location="$region" \
        --project="$PROJECT_ID" \
        --format="table(name,externalId,state.code,state.description)"
      return
    fi
    sleep 10
  done

  echo "ERROR: Regional Fleet membership ${cluster} was not created in ${region}."
  exit 1
}

wait_for_connect_agent() {
  local cluster="$1"
  local ctx="$2"

  echo "Waiting for Connect agent namespace on ${cluster}..."
  for _ in {1..30}; do
    if kubectl get namespace gke-connect --context="$ctx" >/dev/null 2>&1; then
      break
    fi
    sleep 10
  done

  if ! kubectl get namespace gke-connect --context="$ctx" >/dev/null 2>&1; then
    echo "ERROR: gke-connect namespace was not created on ${cluster}."
    exit 1
  fi

  echo "Waiting for Connect agent pods on ${cluster}..."
  for _ in {1..30}; do
    if [[ -n "$(kubectl get pods --namespace=gke-connect --context="$ctx" --no-headers 2>/dev/null || true)" ]]; then
      kubectl get deployment,pod --namespace=gke-connect --context="$ctx"
      kubectl wait \
        --for=condition=Ready \
        pod \
        --all \
        --namespace=gke-connect \
        --timeout=5m \
        --context="$ctx"
      return
    fi
    sleep 10
  done

  echo "ERROR: Connect agent pods did not appear on ${cluster}."
  kubectl get all --namespace=gke-connect --context="$ctx" || true
  exit 1
}

disable_fleet_ingress() {
  gcloud container fleet ingress disable \
    --project="$PROJECT_ID" \
    --quiet || true
}

unregister_membership() {
  local cluster="$1"
  local location="$2"
  local zone="$3"
  local uninstall_connect_agent="${4:-false}"

  if [[ "$uninstall_connect_agent" == "true" ]]; then
    gcloud container fleet memberships unregister "$cluster" \
      --location="$location" \
      --gke-cluster="${zone}/${cluster}" \
      --uninstall-connect-agent \
      --project="$PROJECT_ID" \
      --quiet
    return
  fi

  gcloud container fleet memberships unregister "$cluster" \
    --location="$location" \
    --gke-cluster="${zone}/${cluster}" \
    --project="$PROJECT_ID" \
    --quiet
}

delete_membership() {
  local cluster="$1"
  local location="$2"

  gcloud container fleet memberships delete "$cluster" \
    --location="$location" \
    --project="$PROJECT_ID" \
    --quiet || true
}

clear_cluster_fleet_project() {
  local cluster="$1"
  local zone="$2"

  gcloud container clusters update "$cluster" \
    --location="$zone" \
    --clear-fleet-project \
    --project="$PROJECT_ID" \
    --quiet || true
}

register_membership() {
  local cluster="$1"
  local region="$2"
  local zone="$3"

  gcloud container fleet memberships register "$cluster" \
    --location="$region" \
    --gke-cluster="${zone}/${cluster}" \
    --install-connect-agent \
    --enable-workload-identity \
    --project="$PROJECT_ID" \
    --quiet
}

recreate_membership() {
  local cluster="$1"
  local region="$2"
  local zone="$3"

  echo "Recreating Fleet membership ${cluster} in ${region}..."
  disable_fleet_ingress

  if membership_exists "$cluster" "$region"; then
    unregister_membership "$cluster" "$region" "$zone" true || {
      echo "Could not unregister ${cluster}; deleting stale membership resource instead..."
      clear_cluster_fleet_project "$cluster" "$zone"
      if membership_exists "$cluster" "$region"; then
        delete_membership "$cluster" "$region"
      else
        echo "Stale membership resource for ${cluster} was already removed."
      fi
    }
  fi

  register_membership "$cluster" "$region" "$zone"
}

for REGION in europe-west4 asia-northeast1; do
  ZONE="$(tpu_zone "$REGION")"
  CLUSTER="gke-${REGION}"
  CTX="gke_${PROJECT_ID}_${ZONE}_${CLUSTER}"

  echo "Ensuring ${CLUSTER} uses a regional Fleet membership in ${REGION}..."
  gcloud container clusters get-credentials "$CLUSTER" \
    --location="$ZONE" \
    --project="$PROJECT_ID"

  if membership_exists "$CLUSTER" global && ! membership_exists "$CLUSTER" "$REGION"; then
    echo "Found legacy global Fleet membership for ${CLUSTER}; moving it to ${REGION}..."
    disable_fleet_ingress
    unregister_membership "$CLUSTER" global "$ZONE" true
  fi

  if membership_exists "$CLUSTER" "$REGION" && [[ -z "$(membership_external_id "$CLUSTER" "$REGION")" ]]; then
    echo "Found stale ${REGION} membership for ${CLUSTER}; externalId is empty."
    recreate_membership "$CLUSTER" "$REGION" "$ZONE"
  else
    echo "Registering ${CLUSTER} with Fleet and installing Connect agent..."
    if ! register_membership "$CLUSTER" "$REGION" "$ZONE"; then
      recreate_membership "$CLUSTER" "$REGION" "$ZONE"
    fi
  fi

  wait_for_regional_membership "$CLUSTER" "$REGION"
  wait_for_connect_agent "$CLUSTER" "$CTX"
done

echo "Fleet memberships are registered in their cluster regions and Connect agents are ready."
