#!/bin/bash

source ./scripts/init.env

ARCHIVE_DIR="archives"

function cleanup {
	rm -rf ${ARCHIVE_DIR}/
	rm -rf anthos-service-mesh/
}

function download_archives {
	mkdir -p ${ARCHIVE_DIR}
	wget -nv https://storage.googleapis.com/gke-release/asm/istio-1.6.11-asm.0-linux-amd64.tar.gz -P ${ARCHIVE_DIR}
	wget -nv https://storage.googleapis.com/gke-release/asm/istio-1.6.11-asm.0-linux-amd64.tar.gz.1.sig -P ${ARCHIVE_DIR}
	wget -nv https://github.com/GoogleContainerTools/kpt/releases/download/v0.33.0/kpt_linux_amd64_0.33.0.tar.gz -P ${ARCHIVE_DIR}
}

function verify_asm_archive {
	openssl dgst -verify /dev/stdin -signature ${ARCHIVE_DIR}/istio-1.6.11-asm.0-linux-amd64.tar.gz.1.sig ${ARCHIVE_DIR}/istio-1.6.11-asm.0-linux-amd64.tar.gz <<'EOF'
-----BEGIN PUBLIC KEY-----
MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEWZrGCUaJJr1H8a36sG4UUoXvlXvZ
wQfk16sxprI2gOJ2vFFggdq3ixF2h4qNBt0kI7ciDhgpwS8t+/960IsIgw==
-----END PUBLIC KEY-----
EOF
}

function unarchive {
	tar xzf ${ARCHIVE_DIR}/istio-1.6.11-asm.0-linux-amd64.tar.gz -C ${ARCHIVE_DIR}
	tar xzf ${ARCHIVE_DIR}/kpt_linux_amd64_0.33.0.tar.gz -C ${ARCHIVE_DIR}
}

function copy_binary_to_pathdir {
	cp -p ${ARCHIVE_DIR}/istio-1.6.11-asm.0/bin/istioctl ${HOME}/bin/
	cp -p ${ARCHIVE_DIR}/kpt ${HOME}/bin/
}

function prepare_asm_configurations_per_cluster {
	current_dir=${PWD}
	cluster_name=${1}
	cluster_zone=${2}
	mkdir -p work/anthos-service-mesh/${cluster_name}
	cd work/anthos-service-mesh/${cluster_name}
	kpt pkg get https://github.com/GoogleCloudPlatform/anthos-service-mesh-packages.git/asm@release-1.6-asm .
	kpt cfg set asm gcloud.core.project ${PROJECT_ID}
	kpt cfg set asm gcloud.compute.location ${cluster_zone}
	kpt cfg set asm gcloud.project.projectNumber ${PROJECT_NUMBER}
	kpt cfg set asm gcloud.container.cluster ${cluster_name}
	cd ${current_dir}
}

function install_asm {
	current_dir=${PWD}
	cluster_name=${1}
	cd work/anthos-service-mesh/${cluster_name}
	istioctl install -f asm/cluster/istio-operator.yaml --context ${cluster_name}
	cd ${current_dir}
}

cleanup
download_archives
verify_asm_archive
unarchive
copy_binary_to_pathdir
prepare_asm_configurations_per_cluster ${CLUSTER2} ${CLUSTER2_ZONE}
prepare_asm_configurations_per_cluster ${CLUSTER3} ${CLUSTER3_ZONE}
sleep 10
install_asm ${CLUSTER2} 
install_asm ${CLUSTER3} 
