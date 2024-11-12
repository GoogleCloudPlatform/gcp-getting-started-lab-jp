import traceback
import os
from typing import List

from fastapi import FastAPI, Query
import uvicorn

from search_document import search_documents_by_query
from scene_search import search_scene
from utils import generate_download_signed_url_v4

from google import auth
credentials, project_id = auth.default()

# --- FastAPI アプリケーション ---
app = FastAPI()

@app.get("/")
def root():
    """ルートエンドポイント"""
    pass


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
            title = item.document.derived_struct_data["title"]
            url = item.document.derived_struct_data["link"]
            bucket_name = url.replace("gs://", "").split("/", 1)[0]
            blob_name = url.replace(f"gs://{bucket_name}/metadata/", "mp4/s_").replace(".txt", ".mp4")
            signed_url = generate_download_signed_url_v4(bucket_name, blob_name)
            results.append({
                "id": c+1, "title": title,
                "bucket_name": bucket_name, "blob_name": blob_name,
                "url": url, "signed_url": signed_url
            })
        return {"results": results}
    except Exception as e:
        traceback.print_exc()
        return {"error": str(e)}, 500


@app.get("/scene_search")
async def api_scene_search(
    q: str = Query(..., description="検索キーワード"),
    limit: int = Query(3, le=3, description="最大表示件数"),
    top_n: int = Query(1, le=3, description="上位何件の動画に対してシーン検索を行うか")
) -> dict:
    """シーン検索 API

    Args:
        q: 検索キーワード
        limit: 最大表示件数
        top_n: 上位何件の動画に対してシーン検索を行うか

    Returns:
        検索結果を含む辞書
    """
    try:
        results = search_scene(q, top_n=top_n)
        return {"results": results}
    except Exception as e:
        traceback.print_exc()
        return {"error": str(e)}, 500

# --- アプリケーション起動 ---
if __name__ == "__main__":
    port = int(os.environ.get("PORT", 8080))
    uvicorn.run(app, host="0.0.0.0", port=port)
