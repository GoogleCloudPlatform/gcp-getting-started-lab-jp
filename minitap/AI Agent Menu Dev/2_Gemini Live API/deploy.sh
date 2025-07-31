#!/bin/bash

PROJECT_ID=$(gcloud config list --format "value(core.project)")
PROJECT_NUMBER=$(gcloud projects describe $PROJECT_ID --format="value(projectNumber)")
REGION=us-central1
REPO_NAME=cafe-agent-repo
REPO=${REGION}-docker.pkg.dev/$PROJECT_ID/$REPO_NAME

DEPLOY_BACKEND=true
DEPLOY_FRONTEND=true

echo "Project ID: $PROJECT_ID"
echo "Project Number: $PROJECT_NUMBER"
echo "Region: $REGION"
echo ""

echo "## Enabling APIs..."

# Enable required APIs
gcloud services enable aiplatform.googleapis.com cloudbuild.googleapis.com run.googleapis.com storage.googleapis.com compute.googleapis.com

echo "Wait 15 seconds for APIs to be ready."
sleep 15

echo ""
echo "## Creating the image repository..."

# Create artifact repository if it doesn't exist
if ! gcloud artifacts repositories describe $REPO_NAME --location $REGION >/dev/null 2>&1; then
  echo "Creating artifact repository..."
  gcloud artifacts repositories create $REPO_NAME \
    --repository-format docker --location $REGION
fi

echo ""
echo "## Setting up Cloud Build permissions..."

# Grant Cloud Build service account necessary permissions
echo "Setting permissions for Cloud Build service account..."
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:${PROJECT_NUMBER}@cloudbuild.gserviceaccount.com" \
  --role="roles/storage.admin"

gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:${PROJECT_NUMBER}@cloudbuild.gserviceaccount.com" \
  --role="roles/artifactregistry.writer"

# Grant Compute Engine default service account necessary permissions 
echo "Setting permissions for Compute Engine default service account..."
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:${PROJECT_NUMBER}-compute@developer.gserviceaccount.com" \
  --role="roles/storage.admin"

gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:${PROJECT_NUMBER}-compute@developer.gserviceaccount.com" \
  --role="roles/artifactregistry.writer"

gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:${PROJECT_NUMBER}-compute@developer.gserviceaccount.com" \
  --role="roles/cloudbuild.builds.builder"

echo ""
echo "## Configuring Cloud Build..."

# Enable Cloud Build to use the proper service account
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:${PROJECT_NUMBER}@cloudbuild.gserviceaccount.com" \
  --role="roles/iam.serviceAccountUser"

# Wait for permissions to propagate
echo "Waiting 30 seconds for permissions to propagate..."
sleep 30

if [[ $DEPLOY_BACKEND ]]; then
  echo ""
  echo "## Setting up backend service account..."

  SERVICE_ACCOUNT=cafe-agent-sa@${PROJECT_ID}.iam.gserviceaccount.com
  
  # Check if service account exists
  if ! gcloud iam service-accounts describe $SERVICE_ACCOUNT >/dev/null 2>&1; then
    echo "Creating backend service account..."
    gcloud iam service-accounts create cafe-agent-sa \
      --display-name "Service Account for Cafe Agent Backend"
    sleep 10

    gcloud projects add-iam-policy-binding $PROJECT_ID \
      --role roles/aiplatform.user \
      --member=serviceAccount:$SERVICE_ACCOUNT

    echo "Wait 20 seconds for IAM policies to propagate."
    sleep 20
  fi
fi
  
if $DEPLOY_BACKEND; then
  echo ""
  echo "## Deploying backend..."
  
  cd backend
  
  echo "Starting Cloud Run deployment for backend..."
  gcloud run deploy cafe-agent-backend --source . \
    --region $REGION \
    --allow-unauthenticated \
    --service-account $SERVICE_ACCOUNT \
    --timeout=3600 \
    --memory=2Gi \
    --cpu=2 \
    --min-instances=1 \
    --max-instances=10 \
    --concurrency=80 \
    --port=8081 \
    --set-env-vars="GOOGLE_CLOUD_LOCATION=us-central1,VOICE_NAME=Puck,LANGUAGE=Japanese"
  
  if [ $? -eq 0 ]; then
    echo "Backend deployment successful!"
  else
    echo "Backend deployment failed. Checking logs..."
    gcloud builds list --limit=1 --format="table(id,status,logUrl)"
    exit 1
  fi
  
  cd ..
  
  # Get backend URL
  BACKEND_URL=$(gcloud run services describe cafe-agent-backend --region=$REGION --format="value(status.url)")
  echo "Backend URL: $BACKEND_URL"
fi

if $DEPLOY_FRONTEND; then
  echo ""
  echo "## Setting up frontend service account..."
  
  FRONTEND_SERVICE_ACCOUNT=cafe-agent-app-sa@${PROJECT_ID}.iam.gserviceaccount.com
  
  # Check if service account exists
  if ! gcloud iam service-accounts describe $FRONTEND_SERVICE_ACCOUNT >/dev/null 2>&1; then
    echo "Creating frontend service account..."
    gcloud iam service-accounts create cafe-agent-app-sa \
      --display-name "Service Account for Cafe App Frontend"
    sleep 10
  fi

  echo ""
  echo "## Deploying frontend..."

  cd frontend
  
  # Set environment variable for frontend
  if [ -n "$BACKEND_URL" ]; then
    echo "NEXT_PUBLIC_BACKEND_URL=\"${BACKEND_URL//https/wss}/ws\"" > .env.local
    echo "Frontend will connect to: ${BACKEND_URL//https/wss}/ws"
  else
    echo "Warning: Backend URL is empty, frontend deployment may fail."
  fi
  
  echo "Starting Cloud Run deployment for frontend..."
  gcloud run deploy cafe-agent-app --source . \
    --region $REGION \
    --allow-unauthenticated \
    --service-account $FRONTEND_SERVICE_ACCOUNT \
    --memory=1Gi \
    --cpu=1 \
    --min-instances=1 \
    --max-instances=10 \
    --concurrency=80 \
    --port=3000
  
  if [ $? -eq 0 ]; then
    echo "Frontend deployment successful!"
  else
    echo "Frontend deployment failed. Checking logs..."
    gcloud builds list --limit=1 --format="table(id,status,logUrl)"
    exit 1
  fi
  
  cd ..
  
  # Get frontend URL
  APP_URL=$(gcloud run services describe cafe-agent-app --region=$REGION --format="value(status.url)")
  echo "Frontend URL: $APP_URL"
fi

echo ""
echo "=== Deployment Complete ==="
echo "Application URL: $APP_URL"
echo ""
echo "🎉 Starlight Cafe is now deployed!"
echo "Visit the URL above to start talking to Patrick!"
echo ""
echo "📋 Deployment Summary:"
echo "  Backend:  $BACKEND_URL"
echo "  Frontend: $APP_URL"
echo "  Region:   $REGION"
