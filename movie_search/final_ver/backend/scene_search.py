# backend/scene_search.py
import json
import os
from typing import List

import vertexai
import vertexai.preview.generative_models as generative_models
from vertexai.preview.generative_models import GenerativeModel, GenerationConfig
from google.cloud import storage

from search_document import search_documents_by_query
from utils import generate_download_signed_url_v4
from prompt_content_search import PROMPT_CONTENT_SEARCH

from google import auth

credentials, project_id = auth.default()
PROJECT_ID = os.environ.get("PROJECT_ID", project_id)
DATASTORE_ID = os.environ.get("DATASTORE_ID", "")
LOCATION = os.environ.get("LOCATION", "global")

# --- グローバル変数 ---
vertexai.init(project=PROJECT_ID, location='us-central1')
model_pro = GenerativeModel('gemini-1.5-pro')
model_flash = GenerativeModel('gemini-1.5-flash')


def generate_text(prompt: str, model: GenerativeModel = model_pro, temperature: float = 0.4, top_p: float = 0.4) -> dict:
    """Gemini でテキストを生成する

    Args:
        prompt: 入力プロンプト
        model: 利用する Gemini モデル
        temperature: 生成テキストのランダム性
        top_p: 生成テキストの多様性

    Returns:
        生成された JSON オブジェクト
    """

    response_schema = {
        "type": "array",
        "items": {
            "type": "object",
            "properties": {
                "Timestamp": {
                    "type": "string",
                },
                "Description": {
                    "type": "string",
                },
            },
            "required": ["Timestamp", "Description"],
        },
    }

    responses = model.generate_content(
        prompt,
        generation_config=GenerationConfig(
            max_output_tokens=8192,
            temperature=temperature,
            top_p=top_p,
            response_mime_type="application/json",
            response_schema=response_schema
        ),
        safety_settings={
            generative_models.HarmCategory.HARM_CATEGORY_HATE_SPEECH: generative_models.HarmBlockThreshold.BLOCK_MEDIUM_AND_ABOVE,
            generative_models.HarmCategory.HARM_CATEGORY_DANGEROUS_CONTENT: generative_models.HarmBlockThreshold.BLOCK_MEDIUM_AND_ABOVE,
            generative_models.HarmCategory.HARM_CATEGORY_SEXUALLY_EXPLICIT: generative_models.HarmBlockThreshold.BLOCK_MEDIUM_AND_ABOVE,
            generative_models.HarmCategory.HARM_CATEGORY_HARASSMENT: generative_models.HarmBlockThreshold.BLOCK_MEDIUM_AND_ABOVE,
        },
        # stream=True は不要になりました
    )

    # 最初のレスポンスのみを取得
    result = responses.text

    # JSON 文字列をパースして返す
    return json.loads(result)


def search_scene(query: str, top_n: int = 1, model: GenerativeModel = model_flash) -> List[dict]:
    """シーン検索を実行する

    Args:
        query: 検索クエリ
        top_n: 検索対象とする動画の数
        model: 利用する Gemini モデル

    Returns:
        検索結果のリスト
    """
    response = search_documents_by_query(query, show_summary=False)
    storage_client = storage.Client(credentials=credentials)
    results = []

    for doc_id in range(min(top_n, len(response.results))):
        # Discovery Engine の検索結果から、動画メタデータの URI とタイトルを取得
        meta_uri = response.results[doc_id].document.derived_struct_data['link']
        title = response.results[doc_id].document.derived_struct_data['title']
        print(f'meta_uri: {meta_uri}')

        # URI からバケット名と blob 名を取得
        bucket_name = meta_uri.split("//")[1].split("/", 1)[0]
        blob_name = meta_uri.replace(f'gs://{bucket_name}/', '')
        
        # Cloud Storage からメタデータを取得
        bucket = storage_client.bucket(bucket_name)
        blob = bucket.blob(blob_name)

        # download_to_filename を使わずに、blob から直接テキストデータを読み込む
        metatext = blob.download_as_text()

        prompt = PROMPT_CONTENT_SEARCH.format(query=query, metatext=metatext)
        temperature = 0.4
        result = None
        while temperature < 1.0:
            try:
                movie_blob_name = meta_uri.replace(f'gs://{bucket_name}/metadata/', 'mp4/s_').replace('.txt', '.mp4')
                print(f'movie_blob_name: {movie_blob_name}')
                signed_url = generate_download_signed_url_v4(bucket_name, movie_blob_name)

                # generate_text から直接結果リストを取得              
                result = generate_text(prompt, model=model, temperature=temperature)

                # 結果に signed_url と title を追加
                for r in result:
                    r['signed_url'] = signed_url
                    r['title'] = title
                results.extend(result)
                break

            except Exception as e:
                print(e)
                temperature += 0.05

        if temperature < 1.0:
            print('\n=====')
            
    return results
