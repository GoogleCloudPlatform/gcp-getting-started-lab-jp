import os
import datetime
from google.cloud import storage
from google import auth

PROJECT_ID = os.environ['PROJECT_ID']
DATASTORE_ID = os.environ['DATASTORE_ID']
LOCATION = os.environ['LOCATION']
K_REVISION = os.getenv('K_REVISION')

credentials, project_id = auth.default()
if K_REVISION is not None:
    print("Running on Cloud Run")
    credentials.refresh(auth.transport.requests.Request())
else:
    print("Running on local")


def generate_download_signed_url_v4(bucket_name: str, blob_name: str) -> str:
    """Cloud Storage の Blob の v4 signed URL を生成する

    Args:
        bucket_name: バケット名
        blob_name: Blob 名

    Returns:
        署名付きURL
    """
    storage_client = storage.Client(project=project_id, credentials=credentials)
    bucket = storage_client.bucket(bucket_name)
    blob = bucket.blob(blob_name)

    url = blob.generate_signed_url(
        version="v4",
        expiration=datetime.timedelta(minutes=15),
        method="GET",
        access_token=credentials.token,
        service_account_email=credentials.service_account_email,
    )

    return url

def metadata_url_to_movie_blob_name(metadata_url: str) -> str:
    """metadata ファイルの URL を動画ファイルの blob 名に変換する

    Args:
        metadata_url: metadata ファイルの URL (例、gs://xxxxxx-handson/metadata/abcdefg.txt)

    Returns:
        blob 名 (例、mp4/s_abcdefg.mp4)
    """
    return metadata_url.split("//")[1].split('/', 1)[1].replace('metadata/', 'mp4/s_').replace('.txt', '.mp4')