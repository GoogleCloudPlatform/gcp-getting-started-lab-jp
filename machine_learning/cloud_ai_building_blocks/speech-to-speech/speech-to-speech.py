#!/usr/bin/python
#
# Copyright 2019 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

import base64
from googleapiclient import discovery

APIKEY = 'input-your-api-key-here'

# Load audio file as a base64 encoded text.
with open('ja-sample.flac', 'rb') as audio:
  content = base64.b64encode(audio.read()).decode()

# Use Cloud Speech-to-Text API to transcribe audio.
speech_service = discovery.build('speech', 'v1', developerKey=APIKEY)
_request_body={
  'audio': {
    'content': content        # 音声データ
  },
  'config': {
    'encoding': 'FLAC',       # 音声コーデックを指定
    'sampleRateHertz': 16000, # サンプリング周波数を指定
    'languageCode': 'ja-JP',  # 入力音声の言語に日本語を指定
  }}
response = speech_service.speech().recognize(body=_request_body).execute()
source_text = response['results'][0]['alternatives'][0]['transcript']

# Translate text from Japanese to English.
translate_service = discovery.build('translate', 'v2', developerKey=APIKEY)
response = translate_service.translations().list(
  q=source_text, source='ja', target='en'
).execute()
target_text = response['translations'][0]['translatedText']

# Synthesize English audio from text.
tts_service = discovery.build('texttospeech', 'v1beta1', developerKey=APIKEY)
_request_body = {
  'input': {
    'text': target_text        # 発話するテキストを指定する
  },
  'voice': {
    'languageCode': 'en-US',   # 発話する言語を指定する
    'name': 'en-US-Wavenet-D', # 発話する音声種類を指定する
  },
  'audioConfig': {
    'audioEncoding': 'MP3'     # 音声データの出力形式を指定する
  }}
response = tts_service.text().synthesize(body=_request_body).execute()

# Save audio file.
with open('en-sample.mp3', 'wb') as audio_file:
  audio_file.write(base64.b64decode(response['audioContent']))
