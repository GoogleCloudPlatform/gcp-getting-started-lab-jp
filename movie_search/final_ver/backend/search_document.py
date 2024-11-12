import os
from google.cloud import discoveryengine_v1alpha as discoveryengine
from google.api_core.client_options import ClientOptions
from google import auth

credentials, project_id = auth.default()
PROJECT_ID = os.environ.get("PROJECT_ID", project_id)
DATASTORE_ID = os.environ.get("DATASTORE_ID", "")
LOCATION = os.environ.get("LOCATION", "global")

def search_documents_by_query(query: str, show_summary: bool = True) -> discoveryengine.SearchResponse:
    """Discovery Engine でドキュメントを検索する

    Args:
        query: 検索クエリ
        show_summary: サマリーを表示するかどうか

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
                summary_result_count=3,
                include_citations=True,
                model_spec=discoveryengine.SearchRequest.ContentSearchSpec.SummarySpec.ModelSpec(
                    version='stable'
                )
            ),
        ),
        query=query,
    )
    response = client.search(request)
    # if show_summary:
    #     print(response.summary.summary_text)
    # for c, item in enumerate(response.results):
    #     print(f'[{c+1}]: {item.document.derived_struct_data["link"]}')
    return response

# テスト用
result = search_documents_by_query('AI')
print(result)
