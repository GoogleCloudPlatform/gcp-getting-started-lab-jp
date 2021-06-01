#!/bin/bash

## Reserve a static ip address for sumservice's load balancer
gcloud compute addresses create --global sumservice-ip

## Create a backend service 
gcloud compute backend-services create --global sumservice-backend

## Create a urlmap
gcloud compute url-maps create sumservice-urlmap \
  --default-service=sumservice-backend

## Create a TLS certificate
gcloud compute ssl-certificates create sumservice-certificate \
  --certificate ./sumservice.crt --private-key ./private.key --global

## Create HTTPS proxy
gcloud compute target-https-proxies create sumservice-https \
  --ssl-certificates=sumservice-certificate \
  --url-map=sumservice-urlmap

## Create a forwardig-rule
gcloud compute forwarding-rules create --global sumservice-lb \
  --target-https-proxy=sumservice-https \
  --address=sumservice-ip \
  --ports=443