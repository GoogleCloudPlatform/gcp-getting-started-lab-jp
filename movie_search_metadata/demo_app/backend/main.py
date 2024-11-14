import os
import traceback
from typing import List

import uvicorn
from fastapi import FastAPI, Query

from scene_search import search_scenes
from file_search import search_files
from utils import generate_download_signed_url_v4


app = FastAPI()


@app.get('/')
def root():
    pass


@app.get('/file_search')
async def api_file_search(
    query: str = Query(..., description='検索キーワード')
) -> dict:
    try:
        results = search_files(query)
        return {'results': results}

    except Exception as e:
        traceback.print_exc()
        return {'error': str(e)}, 500


@app.get('/scene_search')
async def api_scene_search(
    query: str = Query(..., description='検索キーワード'),
    top_n: int = Query(1, le=3, description='上位何件の動画に対してシーン検索を行うか')
) -> dict:
    try:
        results = search_scenes(query, top_n=top_n)
        return {'results': results}
    except Exception as e:
        traceback.print_exc()
        return {'error': str(e)}, 500


if __name__ == '__main__':
    port = int(os.getenv('PORT', 8080))
    uvicorn.run(app, host="0.0.0.0", port=port)
