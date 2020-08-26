#!/bin/bash

source ./scripts/init.env

function register_cluster_to_hub {
	cluster_name=${1}
	cluster_zone=${2}
	gcloud alpha container hub memberships register ${cluster_name} \
	--enable-workload-identity \
	--gke-cluster="${cluster_zone}/${cluster_name}" \
	--project=${PROJECT_ID} \
	--public-issuer-url="https://container.googleapis.com/v1/projects/${PROJECT_ID}/locations/${cluster_zone}/clusters/${cluster_name}"
}

register_cluster_to_hub ${CLUSTER2} ${CLUSTER2_ZONE}
