#!/bin/bash

APP_ID=$(firebase -j apps:list -P $GOOGLE_CLOUD_PROJECT | jq '.result[] | select(.displayName == "streamchat")' | jq -r '.appId')
TMP_FILE=firebaseConfig.json
ENV_PATH=./src/streamchat

if [ ! -z ${1} ]; then
    ENV_PATH=$1
fi

firebase -j apps:sdkconfig -P $GOOGLE_CLOUD_PROJECT WEB $APP_ID | jq '.result.sdkConfig' > $TMP_FILE

function update_env() {
    json_key=$1
    env_key=$2
    json_value=$(cat firebaseConfig.json | jq ".$json_key")
    sed -i -e "s/$env_key=$/$env_key=$json_value/g" $ENV_PATH/.env
}

update_env projectId NEXT_PUBLIC_FIREBASE_PROJECT_ID
update_env appId NEXT_PUBLIC_FIREBASE_APP_ID
update_env storageBucket NEXT_PUBLIC_FIREBASE_STORAGE_BUCKET
update_env apiKey NEXT_PUBLIC_FIREBASE_API_KEY
update_env authDomain NEXT_PUBLIC_FIREBASE_AUTH_DOMAIN
update_env messagingSenderId NEXT_PUBLIC_FIREBASE_MESSAGING_SENDER_ID

echo "Updated configuration..."
echo 
cat $ENV_PATH/.env

rm -rf $TMP_FILE
