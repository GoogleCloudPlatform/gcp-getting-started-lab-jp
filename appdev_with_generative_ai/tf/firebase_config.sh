#!/bin/bash

CONFIG_FILE=firebase-config.json
ENV_PATH=../src/knowledge-drive

function reset_configuration() {
    env_key=$1
    sed -i -e "s/$env_key=.*$/$env_key=/g" $ENV_PATH/.env
}

function update_env() {
    json_key=$1
    env_key=$2
    reset_configuration $env_key
    json_value=$(cat $CONFIG_FILE | jq ".$json_key")
    sed -i -e "s/$env_key=$/$env_key=$json_value/g" $ENV_PATH/.env
}

update_env projectId         NEXT_PUBLIC_FIREBASE_PROJECT_ID
update_env appId             NEXT_PUBLIC_FIREBASE_APP_ID
update_env storageBucket     NEXT_PUBLIC_FIREBASE_STORAGE_BUCKET
update_env apiKey            NEXT_PUBLIC_FIREBASE_API_KEY
update_env authDomain        NEXT_PUBLIC_FIREBASE_AUTH_DOMAIN
update_env messagingSenderId NEXT_PUBLIC_FIREBASE_MESSAGING_SENDER_ID

echo "Updated configuration..."
echo 
cat $ENV_PATH/.env
