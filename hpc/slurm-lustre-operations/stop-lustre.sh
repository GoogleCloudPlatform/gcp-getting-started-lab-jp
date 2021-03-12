#!/bin/sh

oss=$( gcloud deployment-manager deployments describe lustre --format json \
    | jq -r '.resources[]|select(.type=="compute.v1.instance")|.name' \
    | grep oss)
for id in ${oss}; do
    gcloud compute instances stop "${id}" --zone=asia-northeast1-c
done

mds=$( gcloud deployment-manager deployments describe lustre --format json \
    | jq -r '.resources[]|select(.type=="compute.v1.instance")|.name' \
    | grep mds)
for id in ${mds}; do
    gcloud compute instances stop "${id}" --zone=asia-northeast1-c
done
