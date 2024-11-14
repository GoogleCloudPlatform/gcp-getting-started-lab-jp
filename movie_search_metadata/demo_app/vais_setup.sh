#!/bin/bash

export PROJECT_ID=$(gcloud config list --format "value(core.project)")
export BUCKET="gs://${PROJECT_ID}-movie-search"

echo "## Creating bucket..."
gsutil mb -b on -l us-central1 $BUCKET

curl -OL https://github.com/GoogleCloudPlatform/gcp-getting-started-lab-jp/releases/download/v0.1.0/handson_resource.tgz
tar -xvzf handson_resource.tgz
pushd handson_resource
  gsutil -m cp -r metadata $BUCKET/
  gsutil -m cp -r mp4 $BUCKET/
popd

python3 -m venv _setup_env
source _setup_env/bin/activate
pip3 install google-cloud-discoveryengine==0.13.3

python3 _vais_setup.py
