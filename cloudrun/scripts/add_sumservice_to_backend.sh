#!/bin/bash

gcloud beta compute network-endpoint-groups create sumservice-neg-$1 \
    --region=$1 \
    --network-endpoint-type=SERVERLESS \
    --cloud-run-service=sumservice

gcloud beta compute backend-services add-backend --global sumservice-backend \
    --network-endpoint-group-region=$1 \
    --network-endpoint-group=sumservice-neg-$1