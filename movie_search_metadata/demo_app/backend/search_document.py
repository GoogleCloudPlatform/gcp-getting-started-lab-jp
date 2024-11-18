import os
from google.cloud import discoveryengine_v1alpha as discoveryengine
from google.api_core.client_options import ClientOptions
from google import auth

# global variables
from utils import PROJECT_ID, DATASTORE_ID, LOCATION


def search_documents_by_query(query: str, show_summary: bool = True) -> discoveryengine.SearchResponse:
    client = discoveryengine.SearchServiceClient(
        client_options=ClientOptions(api_endpoint=f'{LOCATION}-discoveryengine.googleapis.com')
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

    return response
