#!/bin/bash

## Set the datastore id here
DATASTORE_ID=movie-search-datastore_xxxxx
##

PROJECT_ID=$(gcloud config list --format "value(core.project)")
PROJECT_NUMBER=$(gcloud projects describe $PROJECT_ID --format="value(projectNumber)")
SERVICE_ACCOUNT=${PROJECT_NUMBER}-compute@developer.gserviceaccount.com
REGION=asia-northeast1
REPO_NAME=cloud-run-source-deploy
REPO=${REGION}-docker.pkg.dev/$PROJECT_ID/$REPO_NAME

DEPLOY_BACKEND=true
DEPLOY_FRONTEND=true

if [[ $DATASTORE_ID == "movie-search-datastore_xxxxx" ]]; then
    DATASTORE_ID=movie-search-datastore
fi

echo "## Datastore ID: $DATASTORE_ID"

echo ""
echo "## Enabling APIs..."

services=(
  "aiplatform.googleapis.com"
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

  echo "Wait 10 seconds for APIs to be ready."
  sleep 10
fi


echo ""
echo "## Creating the image repository..."

gcloud artifacts repositories describe \
  --location $REGION $REPO_NAME 1>/dev/null 2>&1
rc=$?
if [[ $rc != 0 ]]; then
  gcloud artifacts repositories create $REPO_NAME \
    --repository-format docker --location $REGION

  echo "Wait 60 seconds for ACLs to be propagated."
  sleep 60
fi  


if $DEPLOY_BACKEND; then
  echo ""
  echo "## Deploying backend..."

  gcloud iam service-accounts add-iam-policy-binding \
    --role=roles/iam.serviceAccountTokenCreator  \
    --member=serviceAccount:$SERVICE_ACCOUNT

  pushd backend
  gcloud run deploy movie-search-backend --source . \
    --region $REGION \
    --no-allow-unauthenticated \
    --service-account $SERVICE_ACCOUNT \
    --set-env-vars DATASTORE_ID=$DATASTORE_ID
  popd
fi

BACKEND_URL=$(gcloud run services list --format json | \
  jq .[].status.url | grep -E "movie-search-backend-.*\.run\.app" | sed s/\"//g)


if $DEPLOY_FRONTEND; then
  echo ""
  echo "## Deploying frontend..."

  pushd frontend
  gcloud run deploy movie-search-app --source . \
    --region $REGION \
    --allow-unauthenticated \
    --service-account $SERVICE_ACCOUNT \
    --set-env-vars BACKEND_URL=$BACKEND_URL
  popd
fi

APP_URL=$(gcloud run services list --format json | \
  jq .[].status.url | grep -E "movie-search-app-.*\.run\.app" | sed s/\"//g)

echo ""
echo "Done."
echo "Application URL: $APP_URL"
