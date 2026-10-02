"""gcp_clients.py — the single funnel for every GCP SDK call in the online
shop (GCP port of the journey's aws_clients.py, same public surface).

Service mapping:

    Amazon S3 (assets bucket)          -> Cloud Storage (ttw-assets-<project>)
    AWS Secrets Manager                -> Secret Manager (same secret names)
    Amazon RDS for PostgreSQL          -> Cloud SQL for PostgreSQL 16
                                          (reached via the Cloud SQL Auth
                                          Proxy on 127.0.0.1:5432 — see db.py)
    Amazon CloudWatch (custom metric)  -> Cloud Monitoring
                                          custom.googleapis.com/online_shop/health_ping
    AWS STS get_caller_identity        -> metadata-server service-account identity
    (runtime: EC2 ASG -> MIG, ALB -> global external Application LB,
     CloudFront -> Cloud CDN on the backend service)

Permission notes (ttw-app-sa):
    * storage probes use object listing, not bucket.get — objectViewer does
      not carry storage.buckets.get, so bucket_ok() lists one object instead
      of HEADing the bucket.
    * secret_status() reads secret METADATA (never the value), which needs
      roles/secretmanager.viewer on top of secretAccessor; deploy/03 grants
      both per secret.

Configuration is env-var driven (written to /etc/shop.env by the instance
template's startup script):

    GCP_PROJECT       project id (default aws-migration-501814)
    ASSETS_BUCKET     bucket holding app/app.tar.gz + covers/*.png
    SECRET_ID_DB      Secret Manager id of the DB credentials JSON
                      ({"username": ..., "password": ...} — same shape as AWS)
    SECRET_ID_LEGACY  Secret Manager id of the retired marketplace API key
                      (status displayed on /admin/aws-check; value never read)
"""

import json
import os
import time
import urllib.request

from google.cloud import monitoring_v3, secretmanager, storage

_CACHE = {}

_METADATA_ROOT = "http://metadata.google.internal/computeMetadata/v1"


def _project():
    return os.environ.get("GCP_PROJECT", "aws-migration-501814")


def _bucket_name():
    return os.environ["ASSETS_BUCKET"]


def _storage():
    if "storage" not in _CACHE:
        _CACHE["storage"] = storage.Client(project=_project())
    return _CACHE["storage"]


def _secrets():
    if "secrets" not in _CACHE:
        _CACHE["secrets"] = secretmanager.SecretManagerServiceClient()
    return _CACHE["secrets"]


def _monitoring():
    if "monitoring" not in _CACHE:
        _CACHE["monitoring"] = monitoring_v3.MetricServiceClient()
    return _CACHE["monitoring"]


def _metadata(path):
    req = urllib.request.Request(
        f"{_METADATA_ROOT}/{path}", headers={"Metadata-Flavor": "Google"}
    )
    with urllib.request.urlopen(req, timeout=3) as resp:
        return resp.read().decode()


# ---- Cloud Storage: cover images + bundle bucket -----------------------------

def get_asset(key):
    """Fetch one object from the assets bucket. Returns (bytes, content_type)."""
    blob = _storage().bucket(_bucket_name()).get_blob(key)
    if blob is None:
        raise LookupError(f"object not found: {key}")
    return blob.download_as_bytes(), blob.content_type or "application/octet-stream"


def bucket_ok():
    """Cheap liveness probe for /health: list at most one object."""
    list(_storage().list_blobs(_bucket_name(), max_results=1))
    return True


def list_one():
    """List at most one object — the /admin/aws-check storage ping."""
    return len(list(_storage().list_blobs(_bucket_name(), max_results=1)))


# ---- Secret Manager --------------------------------------------------------------

def get_secret_json(secret_id):
    """Fetch and parse the latest JSON secret version (DB credentials)."""
    name = f"projects/{_project()}/secrets/{secret_id}/versions/latest"
    resp = _secrets().access_secret_version(name=name)
    return json.loads(resp.payload.data.decode())


def secret_status(secret_id):
    """Metadata-only ping — proves the secret exists without reading the
    value (all the store ever does with the legacy marketplace key)."""
    secret = _secrets().get_secret(name=f"projects/{_project()}/secrets/{secret_id}")
    return secret.name.rsplit("/", 1)[-1]


# ---- Cloud Monitoring ----------------------------------------------------------------

def put_health_ping():
    """Push custom.googleapis.com/online_shop/health_ping = 1."""
    now = time.time()
    series = monitoring_v3.TimeSeries()
    series.metric.type = "custom.googleapis.com/online_shop/health_ping"
    series.resource.type = "global"
    series.resource.labels["project_id"] = _project()
    point = monitoring_v3.Point(
        {
            "interval": {
                "end_time": {"seconds": int(now), "nanos": int((now % 1) * 1e9)}
            },
            "value": {"double_value": 1.0},
        }
    )
    series.points = [point]
    _monitoring().create_time_series(
        name=f"projects/{_project()}", time_series=[series]
    )


# ---- identity ------------------------------------------------------------------------------

def whoami():
    """Instance service-account identity — same JSON keys as the AWS build
    so the /admin/aws-check payload stays parity-comparable."""
    return {
        "account": _metadata("project/project-id"),
        "arn": _metadata("instance/service-accounts/default/email"),
    }
