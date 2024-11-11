import os
from google.cloud import discoveryengine_v1alpha as discoveryengine
from google.api_core.client_options import ClientOptions
from fastapi import FastAPI, Query
from fastapi.responses import JSONResponse
import traceback
from utils import generate_download_signed_url_v4

# from . import PROJECT_ID, DATASTORE_ID, LOCATION 
PROJECT_ID = os.environ.get('PROJECT_ID')
DATASTORE_ID = os.environ.get('DATASTORE_ID')
LOCATION = os.environ.get('LOCATION')

from google import auth

credentials, project_id = auth.default()
credentials.refresh(auth.transport.requests.Request())

import json
from typing import List

import vertexai
import vertexai.preview.generative_models as generative_models
from vertexai.preview.generative_models import GenerativeModel, GenerationConfig
from google.cloud import storage

from prompt_content_search import PROMPT_CONTENT_SEARCH
from pprint import pprint


app = FastAPI()

# --- グローバル変数 ---
# Vertex AI の初期化は Cloud Run 環境では不要
vertexai.init(project=PROJECT_ID, location='us-central1')
model_pro = GenerativeModel('gemini-1.5-pro')
model_flash = GenerativeModel('gemini-1.5-flash')

def search_documents_by_query(query: str) -> discoveryengine.SearchResponse:
    """Discovery Engine でドキュメントを検索する

    Args:
        query: 検索クエリ

    Returns:
        Discovery Engine の検索レスポンス
    """
    client = discoveryengine.SearchServiceClient(
        client_options=ClientOptions(api_endpoint=f'{LOCATION}-discoveryengine.googleapis.com'),
        credentials=credentials
    )
    request = discoveryengine.SearchRequest(
        serving_config=client.serving_config_path(
            project=PROJECT_ID,
            location=LOCATION,
            data_store=DATASTORE_ID,
            serving_config='default_search:search',
        ),
        content_search_spec=discoveryengine.SearchRequest.ContentSearchSpec(
            search_result_mode='DOCUMENTS',
            summary_spec=discoveryengine.SearchRequest.ContentSearchSpec.SummarySpec(
                summary_result_count=1,  # サマリーは1つだけ取得
                include_citations=True,
                model_spec=discoveryengine.SearchRequest.ContentSearchSpec.SummarySpec.ModelSpec(
                    version='stable'
                )
            ),
        ),
        query=query,
    )
    response = client.search(request)
    return response


@app.get("/file_search")
async def api_file_search(
    q: str = Query(..., description="検索キーワード"), limit: int = Query(3, le=3, description="最大表示件数")
) -> dict:
    """ファイル検索 API

    Args:
        q: 検索キーワード
        limit: 最大表示件数

    Returns:
        検索結果を含む辞書
    """
    try:
        response = search_documents_by_query(q)
        results = []
        results.append({"summary": response.summary.summary_text})
        for c, item in enumerate(response.results):
            url = item.document.derived_struct_data["link"]
            bucket_name = url.split("//")[1].split("/", 1)[0]
            blob_name = url.replace('gs://minitap-genai-app-dev-handson/metadata/', 'mp4/s_').replace('.txt', '.mp4')
            signed_url = generate_download_signed_url_v4(bucket_name, blob_name)

            title = item.document.derived_struct_data["title"]
            results.append({"id": c+1, "title": title, "bucket_name": bucket_name, "blob_name": blob_name, "url": url, "signed_url": signed_url})
        return {"results": results}
    except Exception as e:
        traceback.print_exc()
        return {"error": str(e)}, 500

# --- シーン検索 ---


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


def scene_search(query: str, top_n: int = 1, model: GenerativeModel = model_flash) -> List[dict]:
    """シーン検索を実行する

    Args:
        query: 検索クエリ
        top_n: 検索対象とする動画の数
        model: 利用する Gemini モデル

    Returns:
        検索結果のリスト
    """
    response = search_documents_by_query(query)
    storage_client = storage.Client(credentials=credentials)
    results = []

    for doc_id in range(min(top_n, len(response.results))):
        meta_uri = response.results[doc_id].document.derived_struct_data['link']
        title = response.results[doc_id].document.derived_struct_data['title']
        print(f'meta_uri: {meta_uri}')

        bucket_name = meta_uri.split("//")[1].split("/", 1)[0]
        blob_name = meta_uri.replace(f'gs://{bucket_name}/', '')
        bucket = storage_client.bucket(bucket_name)
        blob = bucket.blob(blob_name)

        # download_to_filename を使わずに、blob から直接テキストデータを読み込む
        metatext = blob.download_as_text()

        prompt = PROMPT_CONTENT_SEARCH.format(query=query, metatext=metatext)
        temperature = 0.4
        result = None
        while temperature < 1.0:
            try:
                movie_blob_name = meta_uri.replace('gs://minitap-genai-app-dev-handson/metadata/', 'mp4/s_').replace('.txt', '.mp4')
                print(f'movie_blob_name: {movie_blob_name}')
                signed_url = generate_download_signed_url_v4(bucket_name, movie_blob_name)

                # print(prompt)

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

response = scene_search(query='AI')
pprint(response)

# @app.get("/scene_search")
# async def api_scene_search(
#     q: str = Query(..., description="検索キーワード"),
#     limit: int = Query(3, le=3, description="最大表示件数"),
#     top_n: int = Query(1, le=3, description="上位何件の動画に対してシーン検索を行うか")
# ) -> dict:
#     """シーン検索 API

#     Args:
#         q: 検索キーワード
#         limit: 最大表示件数
#         top_n: 上位何件の動画に対してシーン検索を行うか

#     Returns:
#         検索結果を含む辞書
#     """
#     try:
#         results = search_scene(q, top_n=top_n)
#         return {"results": results}
#     except Exception as e:
#         traceback.print_exc()
#         return {"error": str(e)}, 500
