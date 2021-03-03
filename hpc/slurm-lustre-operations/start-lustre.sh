#!/bin/sh

mds=$( gcloud deployment-manager deployments describe lustre --format json \
    | jq -r '.resources[]|select(.type=="compute.v1.instance")|.name' \
    | grep mds)
for id in "${mds}"; do
    gcloud compute instances start "${id}" --zone=asia-northeast1-c
done

while :
do
  if gcloud compute ssh lustre-mds1 --zone=asia-northeast1-c --tunnel-through-iap \
        --command "sudo journalctl -u google-startup-scripts.service" 2>/dev/null \
        | grep -q -m 1 'Started Google Compute Engine Startup Scripts'; then
    echo "MDSs are ready."
    break
  else
    sleep 5
  fi
done

oss=$( gcloud deployment-manager deployments describe lustre --format json \
    | jq -r '.resources[]|select(.type=="compute.v1.instance")|.name' \
    | grep oss)
for id in "${oss}"; do
    gcloud compute instances start "${id}" --zone=asia-northeast1-c
done

while :
do
  if gcloud compute ssh lustre-oss1 --zone=asia-northeast1-c --tunnel-through-iap \
        --command "sudo journalctl -u google-startup-scripts.service" 2>/dev/null \
        | grep -q -m 1 'Started Google Compute Engine Startup Scripts'; then
    echo "OSSs are ready."
    break
  else
    sleep 5
  fi
done
