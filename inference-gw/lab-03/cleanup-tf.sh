#!/bin/bash
set -u

echo "=== PART 2: Infrastructure & Terraform Teardown ==="
export PROJECT_ID=$(gcloud config get-value project)
export LAB_NETWORK="tpu-gke-dranet-vpc"

echo "Destroying GKE Fleet Features to prevent firewall resurrection..."
terraform destroy -target=google_gke_hub_feature.mcs -target=google_gke_hub_feature.ingress -auto-approve

echo "Waiting 30 seconds for the self-healing controllers to spin down..."
sleep 30

echo "Hunting down orphaned auto-generated firewall rules strictly on the lab network..."
GHOST_RULES=$(gcloud compute firewall-rules list --filter="network~${LAB_NETWORK} AND (name~mcsd OR name~k8s-fw-l7)" --format="value(name)" --project="$PROJECT_ID")

if [ ! -z "$GHOST_RULES" ]; then
  for rule in $GHOST_RULES; do
    echo "Deleting ghost rule: $rule"
    gcloud compute firewall-rules delete "$rule" --project="$PROJECT_ID" --quiet
  done
else
  echo "No ghost rules found on ${LAB_NETWORK}."
fi

echo "=== Controllers and Firewalls dead. Destroying remaining Base Infrastructure. ==="

MAX_RETRIES=3
RETRY_COUNT=0
SUCCESS=false

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
  if terraform destroy -auto-approve; then
    SUCCESS=true
    break
  else
    RETRY_COUNT=$((RETRY_COUNT+1))
    echo -e "\n[WARNING] Terraform destroy encountered an error (likely a GCP resource lock)."

    if [ $RETRY_COUNT -lt $MAX_RETRIES ]; then
      echo "Waiting 30 seconds before retry $RETRY_COUNT of $MAX_RETRIES..."
      sleep 30
    fi
  fi
done

if [ "$SUCCESS" = true ]; then
  echo -e "\n=== Lab Cleanup Successfully Completed! ==="
else
  echo -e "\n[ERROR] Lab Cleanup failed after $MAX_RETRIES attempts."
  echo "Some resources may still be locked. Run 'terraform destroy -auto-approve' manually later to finish."
  exit 1
fi
