import os
import json
import requests

from flask import Flask, request, jsonify

app = Flask(__name__)


@app.route("/")
def hello_world():
    name = os.environ.get("NAME", "World")
    return "Hello {}!".format(name)


@app.route("/sum", methods=["POST"])
def sum_numbers():
    try:
        json_data = request.get_json()
    except:
        return jsonify({'error': 'Bad Request', 'message': 'Invalid request: {}'.format(request.get_data(as_text=True))}), 400
    if not 'numbers' in json_data:
        return jsonify({'error': 'Bad Request', 'message': 'Request format error: {}'.format(request.get_data(as_text=True))}), 400
    try:
        ans = sum(json_data['numbers'])
    except TypeError:
        return jsonify({'error': 'Bad Request', 'message': 'Request format error: {}'.format(request.get_data(as_text=True))}), 400
    return jsonify({'sum': ans}), 200


#@app.route("/sumcurrency", methods=["POST"])
#def sum_currency():
#    try:
#        json_data = request.get_json()
#    except:
#        return jsonify({'error': 'Bad Request', 'message': 'Invalid request: {}'.format(request.get_data(as_text=True))}), 400
#    if not 'amounts' in json_data:
#        return jsonify({'error': 'Bad Request', 'message': 'Request format error: {}'.format(request.get_data(as_text=True))}), 400
#
#    currency_service_url = os.environ.get(
#        "CURRENCY_SERVICE_URL", "http://localhost:8080")
#
#    receiving_service_headers = {'Content-Type': 'application/json'}
#    #receiving_service_headers['Authorization'] = 'Bearer {}'.format(retrieve_token(currency_service_url))
#
#    answer = 0
#    try:
#        for amount in json_data['amounts']:
#            service_response = requests.post(currency_service_url + '/convert', json.dumps(
#                {'value': amount}), headers=receiving_service_headers)
#            if service_response.status_code != 200:
#                return jsonify({'error': 'Bad Request', 'message': 'Failed to retrieve currecy data'}), 500
#            answer += service_response.json()['answer']
#
#    except:
#        return jsonify({'error': 'Bad Request', 'message': 'Failed to retrieve currecy data'}), 500
#
#    return jsonify({'sum': answer}), 200
#
#
#def retrieve_token(target_url):
#    # Set up metadata server request
#    metadata_server_token_url = 'http://metadata/computeMetadata/v1/instance/service-accounts/default/identity?audience='
#
#    token_request_url = metadata_server_token_url + target_url
#    token_request_headers = {'Metadata-Flavor': 'Google'}
#
#    # Fetch the token
#    token_response = requests.get(
#        token_request_url, headers=token_request_headers)
#    return token_response.content.decode("utf-8")


if __name__ == "__main__":
    app.run(debug=True, host="0.0.0.0", port=int(os.environ.get("PORT", 8080)))
