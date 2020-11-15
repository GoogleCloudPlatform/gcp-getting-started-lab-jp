#!/bin/bash

source ./script/init.env

gcloud services enable multiclusteringress.googleapis.com
gcloud alpha container hub ingress enable \
  --config-membership=projects/${PROJECT_ID}/locations/global/memberships/${CLUSTER2}