import json
import os
from typing import List

import vertexai
import vertexai.preview.generative_models as generative_models
from vertexai.preview.generative_models import GenerativeModel, GenerationConfig
from google.cloud import storage

from search_document import search_documents_by_query
from prompt_content_search import PROMPT_CONTENT_SEARCH
from utils import get_bucket_and_blobnames
from utils import generate_download_signed_url_v4

# global variables
from utils import PROJECT_ID, credentials

vertexai.init(project=PROJECT_ID, location='us-central1')
model_flash = GenerativeModel('gemini-1.5-flash')


def generate_text(prompt: str, model: GenerativeModel = model_flash,
                  temperature: float = 0.4, top_p: float = 0.4) -> dict:

    response_schema = {
        'type': 'array',
        'items': {
            'type': 'object',
            'properties': {
                'Timestamp': {
                    'type': 'string',
                },
                'Description': {
                    'type': 'string',
                },
            },
            'required': ['Timestamp', 'Description'],
        },
    }

    safety_settings={
        generative_models.HarmCategory.HARM_CATEGORY_HATE_SPEECH: generative_models.HarmBlockThreshold.BLOCK_MEDIUM_AND_ABOVE,
        generative_models.HarmCategory.HARM_CATEGORY_DANGEROUS_CONTENT: generative_models.HarmBlockThreshold.BLOCK_MEDIUM_AND_ABOVE,
        generative_models.HarmCategory.HARM_CATEGORY_SEXUALLY_EXPLICIT: generative_models.HarmBlockThreshold.BLOCK_MEDIUM_AND_ABOVE,
        generative_models.HarmCategory.HARM_CATEGORY_HARASSMENT: generative_models.HarmBlockThreshold.BLOCK_MEDIUM_AND_ABOVE,
    }

    responses = model.generate_content(
        prompt,
        generation_config=GenerationConfig(
            max_output_tokens=8192,
            temperature=temperature,
            top_p=top_p,
            response_mime_type='application/json',
            response_schema=response_schema
        ),
        safety_settings=safety_settings
    )
    result = responses.text

    return json.loads(result)


def search_scenes(query: str, top_n: int = 1,
                  model: GenerativeModel = model_flash) -> List[dict]:
    storage_client = storage.Client(credentials=credentials)
    response = search_documents_by_query(query, show_summary=False)
    results = []

    for doc_id in range(min(top_n, len(response.results))):
        title = response.results[doc_id].document.derived_struct_data['title']
        meta_uri = response.results[doc_id].document.derived_struct_data['link']

        bucket_name, blob_metadata, blob_mp4 = get_bucket_and_blobnames(meta_uri)
        signed_url = generate_download_signed_url_v4(bucket_name, blob_mp4)
        
        bucket = storage_client.bucket(bucket_name)
        metatext = bucket.blob(blob_metadata).download_as_text()

        prompt = PROMPT_CONTENT_SEARCH.format(query=query, metatext=metatext)
        temperature = 0.4
        while temperature < 1.0:
            try:
                result = generate_text(prompt, model=model, temperature=temperature)
                for r in result:
                    r['signed_url'] = signed_url
                    r['title'] = title
                results.extend(result)
                break

            except Exception as e:
                print(e)
                temperature += 0.05

    return results
