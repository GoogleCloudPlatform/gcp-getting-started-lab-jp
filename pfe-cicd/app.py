from flask import Flask, jsonify
import random

app = Flask(__name__)

breeds = [
    "Labrador Retriever",
    "German Shepherd",
    "Golden Retriever",
    "French Bulldog",
    "Bulldog",
    "Poodle",
    "Beagle",
    "Rottweiler",
    "German Shorthaired Pointer",
    "Yorkshire Terrier"
]


@app.route('/random-pets', methods=['GET'])
def get_random_dog():
    random_breed = random.choice(breeds)
    return jsonify({'breed': random_breed})


if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
