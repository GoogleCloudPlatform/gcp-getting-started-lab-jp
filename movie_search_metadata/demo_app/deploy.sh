#!/bin/bash

## Set the datastore id here
DATASTORE_ID=movie-search-datastore_xxxxx
##

echo "## Enabling APIs..."

services=(
  "cloudbuild.googleapis.com"
  "run.googleapis.com"
)
services_list="(""$(IFS='|'; echo "${services[*]}")"")"
enabled=$(gcloud services list --format json | jq .[].config.name |\
  grep -E "$services_list" | wc -l)
if [[ $enabled != ${#services[@]} ]]; then
  echo "Enabling APIs."
  services_list="$(IFS=' '; echo "${services[*]}")"
  gcloud services enable $services_list

  echo "Wait 60 seconds for APIs to be ready."
  sleep 60
fi

echo ""
echo "## Deploying backend..."

SERVICE_ACCOUNT=$(gcloud iam service-accounts list --format json | \
  jq .[].email | grep 'compute@developer.gserviceaccount.com' | sed s/\"//g)

gcloud iam service-accounts add-iam-policy-binding \
  --role=roles/iam.serviceAccountTokenCreator  \
  --member=serviceAccount:$SERVICE_ACCOUNT \
  $SERVICE_ACCOUNT

pushd backend
gcloud run deploy movie-search-backend --source . --region asia-northeast1 \
  --no-allow-unauthenticated \
  --service-account $SERVICE_ACCOUNT \
  --set-env-vars DATASTORE_ID=$DATASTORE_ID
popd

BACKEND_URL=$(gcloud run services list --format json | \
  jq .[].status.url | grep -E "movie-search-backend-.*\.run\.app" | sed s/\"//g)

echo ""
echo "## Deploying frontend..."

pushd frontend
gcloud run deploy movie-search-app --source . --region asia-northeast1 \
  --allow-unauthenticated \
  --service-account $SERVICE_ACCOUNT \
  --set-env-vars BACKEND_URL=$BACKEND_URL
popd

APP_URL=$(gcloud run services list --format json | \
  jq .[].status.url | grep -E "movie-search-app-.*\.run\.app" | sed s/\"//g)

echo ""
echo "Done."
echo "Application URL: $APP_URL"
