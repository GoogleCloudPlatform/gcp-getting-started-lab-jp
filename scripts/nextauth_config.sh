#!/bin/bash

CLOUD_RUN_URL=$(gcloud run services describe streamchat --region asia-northeast1 --format json | jq -r '.status.address.url')
SECRET=$(openssl rand -base64 32)
ENV_PATH=./src/streamchat

sed -i -e "s NEXTAUTH_URL=$ NEXTAUTH_URL=\"$CLOUD_RUN_URL\" g" $ENV_PATH/.env
sed -i -e "s NEXTAUTH_SECRET=$ NEXTAUTH_SECRET=\"$SECRET\" g" $ENV_PATH/.env

echo "Updated configuration..."
cat $ENV_PATH/.env

