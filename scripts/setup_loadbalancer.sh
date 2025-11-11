#!/bin/bash

# Copyright 2021 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

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
