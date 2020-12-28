# Copyright 2020 Google Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

import base64
import datetime
import json
import os

from google.cloud import datastore

from flask import Flask, request


app = Flask(__name__)
ds_client = datastore.Client()


@app.route('/')
def index():
    return 'Storage logging service. '


# Receive API calls from Pub/Sub push subscription
@app.route('/api/v1/pubsub', methods=['POST'])
def storage_event():
    envelope = request.get_json()
    message = envelope['message']
    attributes = message['attributes'] # Event meta data
    if attributes['eventType'] != 'OBJECT_FINALIZE':
        resp = {'message': 'This is Not a file upload event.'}
        return resp, 200

    data = json.loads(base64.b64decode(message['data']).decode('utf-8')) # Event body
    data['timestamp'] = datetime.datetime.utcnow()  # Add timestamp

    incomplete_key = ds_client.key('StorageLog')   # Create a new key for kind 'StorageLog'.
    event_entity = datastore.Entity(key=incomplete_key) # Create a new entity.
    event_entity.update(data)                 # Update the entity's contents.
    ds_client.put(event_entity)               # Store the entity in Datastore.

    return data, 200


@app.route('/api/v1/purge', methods=['GET'])
def purge_log():
    query = ds_client.query(kind='StorageLog')
    retain_limit = datetime.datetime.utcnow()-datetime.timedelta(minutes=3)
    query.keys_only()
    query.add_filter('timestamp', '<', retain_limit)
    for result in query.fetch():
        ds_client.delete(result.key)

    resp = {'message': 'succeeded.'}
    return resp, 200


if __name__ == "__main__":
    app.run(debug=True, host='0.0.0.0', port=int(os.environ.get('PORT', 8080)))
