#!/bin/bash

source ./scripts/init.env

function create_cluster {
	cluster_name=${1}
	cluster_zone=${2}
	gcloud container clusters create ${cluster_name} \
	--machine-type=e2-standard-4 \
	--num-nodes=4 \
	--workload-pool=${PROJECT_ID}.svc.id.goog \
	--enable-stackdriver-kubernetes \
	--labels=mesh_id=proj-${PROJECT_NUMBER} \
	--release-channel=rapid \
	--zone ${cluster_zone} \
	--enable-ip-alias \
	--scopes=https://www.googleapis.com/auth/cloud-platform \
	--service-account=anthos-sample-service-account@${PROJECT_ID}.iam.gserviceaccount.com
}

create_cluster ${CLUSTER2} ${CLUSTER2_ZONE}
