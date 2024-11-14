import os
from google.api_core.client_options import ClientOptions
from google.cloud import discoveryengine

PROJECT_ID = os.getenv('PROJECT_ID')
BUCKET = os.getenv('BUCKET')
LOCATION = 'global'
DATASTORE_ID = 'movie-search-datastore'
ENGINE_ID = 'movie-search-engine'


def create_datastore(project_id, location, datastore_id):
    client_options = (
        ClientOptions(api_endpoint=f'{location}-discoveryengine.googleapis.com')
        if location != 'global'
        else None
    )
    client = discoveryengine.DataStoreServiceClient(client_options=client_options)
    
    parent = client.collection_path(
        project=project_id,
        location=location,
        collection='default_collection',
    )

    data_store = discoveryengine.DataStore(
        display_name='Movie search datastore',
        industry_vertical=discoveryengine.IndustryVertical.GENERIC,
        solution_types=[discoveryengine.SolutionType.SOLUTION_TYPE_SEARCH],
        content_config=discoveryengine.DataStore.ContentConfig.CONTENT_REQUIRED,
    )

    request = discoveryengine.CreateDataStoreRequest(
        parent=parent,
        data_store_id=datastore_id,
        data_store=data_store,
    )

    operation = client.create_data_store(request=request)
    print(f'Waiting for operation to complete: {operation.operation.name}')
    response = operation.result()

    return response


def import_documents(project_id, location, datastore_id, bucket):
    client_options = (
        ClientOptions(api_endpoint=f'{location}-discoveryengine.googleapis.com')
        if location != 'global'
        else None
    )
    client = discoveryengine.DocumentServiceClient(client_options=client_options)
    
    parent = client.branch_path(
        project=project_id,
        location=location,
        data_store=datastore_id,
        branch='default_branch'
    )


    request = discoveryengine.ImportDocumentsRequest(
        parent=parent,
        gcs_source=discoveryengine.GcsSource(
            input_uris=[f'{bucket}/metadata/*.txt'],
            data_schema='content',
        ),
        reconciliation_mode=discoveryengine.ImportDocumentsRequest.ReconciliationMode.FULL
    )

    operation = client.import_documents(request=request)
    print(f'Waiting for operation to complete: {operation.operation.name}')
    print('This may take around 20 mins...')
    response = operation.result(timeout=1800)

    return response


def create_engine(project_id, location, datastore_id, engine_id):
    client_options = (
        ClientOptions(api_endpoint=f'{location}-discoveryengine.googleapis.com')
        if location != 'global'
        else None
    )
    client = discoveryengine.EngineServiceClient(client_options=client_options)

    parent = client.collection_path(
        project=project_id,
        location=location,
        collection='default_collection'
    )

    engine = discoveryengine.Engine(
        display_name='Movie Search Engine',
        industry_vertical=discoveryengine.IndustryVertical.GENERIC,
        solution_type=discoveryengine.SolutionType.SOLUTION_TYPE_SEARCH,
        search_engine_config=discoveryengine.Engine.SearchEngineConfig(
            search_tier=discoveryengine.SearchTier.SEARCH_TIER_ENTERPRISE,
            search_add_ons=[discoveryengine.SearchAddOn.SEARCH_ADD_ON_LLM],
        ),
        data_store_ids=[datastore_id],
    )

    request = discoveryengine.CreateEngineRequest(
        parent=parent,
        engine=engine,
        engine_id=engine_id,
    )

    operation = client.create_engine(request=request)
    print(f'Waiting for operation to complete: {operation.operation.name}')
    response = operation.result()

    return response


if __name__ == '__main__':
    print('\n## Creating datastore...')
    try:
        create_datastore(PROJECT_ID, LOCATION, DATASTORE_ID)
    except Exception as e:
        print(e)
    print('\n## Importing documents...')
    import_documents(PROJECT_ID, LOCATION, DATASTORE_ID, BUCKET)
    print('\n## Creating search engine...')
    try:
        create_engine(PROJECT_ID, LOCATION, DATASTORE_ID, ENGINE_ID)
    except Exception as e:
        print(e)
    print('\nDone.')
