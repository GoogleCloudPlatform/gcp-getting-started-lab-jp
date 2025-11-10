#!/bin/bash

ENV_PATH=./src/streamchat

if [ $# != 2 ]; then
    echo "Error: Arguments are not correctly provided." 1>&2
    exit 1
fi

CLIENT_SECRET=$1
CLIENT_ID=$2

sed -i -e "s/GOOGLE_CLIENT_ID=$/GOOGLE_CLIENT_ID=\"$CLIENT_ID\"/g" $ENV_PATH/.env
sed -i -e "s/GOOGLE_CLIENT_SECRET=$/GOOGLE_CLIENT_SECRET=\"$CLIENT_SECRET\"/g" $ENV_PATH/.env

echo "Updated configuration..."
cat $ENV_PATH/.env

