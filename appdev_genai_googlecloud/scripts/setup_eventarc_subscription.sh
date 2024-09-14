#!/bin/bash

EVENTARC_NAME=$1

DEAD_LETTER_TOPIC=genai-app-dead-letter

PROJECT_NUMBER=$(gcloud projects describe $GOOGLE_CLOUD_PROJECT --format="value(projectNumber)")

SUBSCRIPTION=$(gcloud pubsub subscriptions list --format json | jq -r '.[].name' | grep $EVENTARC_NAME)

gcloud pubsub subscriptions add-iam-policy-binding $SUBSCRIPTION \
  --member="serviceAccount:service-$PROJECT_NUMBER@gcp-sa-pubsub.iam.gserviceaccount.com" \
  --role="roles/pubsub.subscriber"

gcloud pubsub subscriptions update $SUBSCRIPTION \
  --ack-deadline 60 \
  --dead-letter-topic $DEAD_LETTER_TOPIC \
  --min-retry-delay 60 \
  --max-retry-delay 600
