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

import datetime
import os

from google.cloud import datastore

from flask import Flask, request


app = Flask(__name__)
ds_client = datastore.Client()


@app.route('/')
def index():
    return 'Message board service. '


@app.route('/api/v1/store', methods=['POST'])
def store():
    json_data = request.get_json()
    name, message = None, None
    if 'name' in json_data.keys():
        name = json_data['name']
    if 'message' in json_data.keys():
        message = json_data['message']

    if name is None or message is None:
        resp = {'message': 'name and message properties are required.'}
        return resp, 500

    resp = {
        'name': name,
        'message': message,
        'timestamp': datetime.datetime.utcnow()
    }
    incomplete_key = ds_client.key('Message')   # Create a new key for kind 'Message'.
    message_entity = datastore.Entity(key=incomplete_key) # Create a new entity.
    message_entity.update(resp)                 # Update the entity's contents.
    ds_client.put(message_entity)               # Store the entity in Datastore.

    return resp, 200


@app.route('/api/v1/retrieve', methods=['POST'])
def retrieve():
    json_data = request.get_json()
    name = None
    if 'name' in json_data.keys():
        name = json_data['name']

    if name is None:
        resp = {'message': 'name property is required.'}
        return resp, 500

    query = ds_client.query(kind='Message') # Create a query object for kind 'Message'.
    query.add_filter('name', '=', name)     # Add a filter condition.
    query.order = ['timestamp']             # Add a sort condition.
    messages = []
    for result in query.fetch():            # Iterate over the query result.
        messages.append(
            {
                'message': result['message'],
                'timestamp': result['timestamp']
            }
        )

    resp = {
        'name': name,
        'messages': messages
    }
    return resp, 200


if __name__ == "__main__":
    app.run(debug=True, host='0.0.0.0', port=int(os.environ.get('PORT', 8080)))
