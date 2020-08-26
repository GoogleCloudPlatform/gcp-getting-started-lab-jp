#!/bin/bash

source ./scripts/init.env

function create_clusterrolebinding {
	cluster_name=${1}
	kubectl create clusterrolebinding cluster-admin-binding \
	--clusterrole=cluster-admin \
	--user=anthos-sample-service-account@${PROJECT}.iam.gserviceaccount.com \
	--context ${cluster_name}
}

create_clusterrolebinding ${CLUSTER2}
