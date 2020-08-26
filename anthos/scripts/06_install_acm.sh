#!/bin/bash

source ./scripts/init.env

ARCHIVE_DIR="archives"
REPO_URL="https://source.developers.google.com/p/${PROJECT_ID}/r/anthos-sample-deployment-config-repo"

function download_operator_manifest {
	gsutil cp gs://config-management-release/released/latest/config-management-operator.yaml ${ARCHIVE_DIR}/config-management-operator.yaml
}

function install_acm {
	cluster_name=${1}
	kubectl apply -f ${ARCHIVE_DIR}/config-management-operator.yaml --context ${cluster_name}
	sed -e "s|<CLUSTER_NAME>|${cluster_name}|g" -e "s|<REPO_URL>|${REPO_URL}|g" k8s-manifest/config-management.yaml | kubectl apply --context ${cluster_name} -f -
}

function add_iam_policy_binding {
	gcloud iam service-accounts add-iam-policy-binding \
	--role roles/iam.workloadIdentityUser \
	--member "serviceAccount:${PROJECT_ID}.svc.id.goog[config-management-system/importer]" \
	anthos-sample-service-account@${PROJECT_ID}.iam.gserviceaccount.com
}

function annotate_serviceaccount {
	cluster_name=${1}
	kubectl annotate serviceaccount -n config-management-system importer \
	iam.gke.io/gcp-service-account=anthos-sample-service-account@${PROJECT_ID}.iam.gserviceaccount.com --context ${cluster_name}
}

download_operator_manifest
install_acm ${CLUSTER2}
add_iam_policy_binding 
sleep 60
annotate_serviceaccount ${CLUSTER2}
