import datetime
from google.cloud import storage
from google import auth


credentials, project_id = auth.default()

def generate_download_signed_url_v4(bucket_name: str, blob_name: str) -> str:
    """Cloud Storage の Blob の v4 signed URL を生成する

    Args:
        bucket_name: バケット名
        blob_name: Blob 名

    Returns:
        署名付きURL
    """

    if not credentials.valid:
        credentials.refresh(auth.transport.requests.Request())

    storage_client = storage.Client()
    bucket = storage_client.bucket(bucket_name)
    blob = bucket.blob(blob_name)

    url = blob.generate_signed_url(
        version="v4",
        expiration=datetime.timedelta(minutes=15),
        method="GET",
        access_token=credentials.token,
        service_account_email=credentials.service_account_email
    )

    return url
