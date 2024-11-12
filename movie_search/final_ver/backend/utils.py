import datetime
from google.cloud import storage
from google import auth
from google.auth import impersonated_credentials


def get_impersonated_credentials():
    scopes=['https://www.googleapis.com/auth/cloud-platform']
    credentials, project = auth.default(scopes=scopes)
    if credentials.token is None:
        credentials.refresh(auth.transport.requests.Request())
    signing_credentials = impersonated_credentials.Credentials(
        source_credentials=credentials,
        target_principal=credentials.service_account_email,
        target_scopes=scopes,
        lifetime=datetime.timedelta(seconds=3600),
        delegates=[credentials.service_account_email]
    )
    return signing_credentials


def generate_download_signed_url_v4(bucket_name: str, blob_name: str) -> str:
    """Cloud Storage の Blob の v4 signed URL を生成する

    Args:
        bucket_name: バケット名
        blob_name: Blob 名

    Returns:
        署名付きURL
    """
    storage_client = storage.Client()
    bucket = storage_client.bucket(bucket_name)
    blob = bucket.blob(blob_name)

    url = blob.generate_signed_url(
        version="v4",
        expiration=datetime.timedelta(minutes=15),
        method="GET",
        credentials=get_impersonated_credentials()
    )

    return url
