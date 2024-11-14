import datetime
import os
import re
from google.cloud import storage
from google import auth


credentials, project_id = auth.default()

PROJECT_ID = os.getenv('PROJECT_ID', project_id)
DATASTORE_ID = os.getenv('DATASTORE_ID')
LOCATION = os.getenv('LOCATION', 'global')


def get_bucket_and_blobnames(metadata_uri: str) -> tuple[str, str, str]:
    bucket, blob_metadata = re.findall(r'gs://([^/]+)/(.+)', metadata_uri)[0]
    blob_mp4 = 'mp4/s_' + blob_metadata.lstrip('metadata/').rstrip('.txt') + '.mp4'
    return bucket, blob_metadata, blob_mp4


def generate_download_signed_url_v4(bucket_name: str, blob_name: str) -> str:
    if not credentials.valid:
        credentials.refresh(auth.transport.requests.Request())

    storage_client = storage.Client()
    bucket = storage_client.bucket(bucket_name)
    blob = bucket.blob(blob_name)

    url = blob.generate_signed_url(
        version='v4',
        expiration=datetime.timedelta(minutes=15),
        method='GET',
        access_token=credentials.token,
        service_account_email=credentials.service_account_email
    )

    return url
