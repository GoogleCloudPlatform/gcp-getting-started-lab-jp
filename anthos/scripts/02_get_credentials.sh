#!/bin/bash

source ./scripts/init.env

function cleanup {
	cluster_name=${1}
	kubectl config delete-context ${cluster_name}
}

function get_credential_and_rename_context {
	cluster_name=${1}
	cluster_zone=${2}
	gcloud container clusters get-credentials ${cluster_name} --zone ${cluster_zone}
	kubectl config rename-context gke_${PROJECT_ID}_${cluster_zone}_${cluster_name} ${cluster_name}
}

cleanup ${CLUSTER2}
get_credential_and_rename_context ${CLUSTER2} ${CLUSTER2_ZONE}
