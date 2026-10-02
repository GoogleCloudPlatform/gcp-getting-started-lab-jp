"""aws_clients.py — the single funnel for every AWS SDK call in the online
shop. No other module may import boto3.

Intended GCP mapping (if the store is ever re-platformed):

    Amazon S3 (assets bucket)          -> Cloud Storage
    AWS Secrets Manager                -> Secret Manager
    Amazon RDS for PostgreSQL          -> Cloud SQL for PostgreSQL
    Amazon CloudWatch (custom metric)  -> Cloud Monitoring
    AWS STS get_caller_identity        -> instance service-account identity
    (runtime: EC2 Auto Scaling group   -> Managed Instance Group,
     ALB                               -> Cloud Load Balancing,
     CloudFront                        -> Cloud CDN)

Configuration is env-var driven (written to /etc/shop.env by the compute
stack's launch template):

    AWS_REGION        client region (ap-northeast-1 in production)
    ASSETS_BUCKET     private bucket holding app/app.tar.gz + covers/*.png
    SECRET_ID_DB      Secrets Manager id of the RDS credentials JSON
                      ({"username": ..., "password": ...})
    SECRET_ID_LEGACY  Secrets Manager id of the retired marketplace API key
                      (status displayed on /admin/aws-check; value never read)
"""

import json
import os

import boto3

_CLIENTS = {}


def _client(service):
    """One cached boto3 client per service, region from AWS_REGION."""
    if service not in _CLIENTS:
        _CLIENTS[service] = boto3.client(
            service, region_name=os.environ.get("AWS_REGION", "ap-northeast-1")
        )
    return _CLIENTS[service]


def _bucket():
    return os.environ["ASSETS_BUCKET"]


# ---- S3: cover images + bundle bucket ---------------------------------------

def get_asset(key):
    """Fetch one object from the assets bucket. Returns (bytes, content_type)."""
    resp = _client("s3").get_object(Bucket=_bucket(), Key=key)
    return resp["Body"].read(), resp.get("ContentType", "application/octet-stream")


def bucket_ok():
    """Cheap liveness probe for /health: HEAD the assets bucket."""
    _client("s3").head_bucket(Bucket=_bucket())
    return True


def list_one():
    """List at most one object — the /admin/aws-check S3 ping."""
    resp = _client("s3").list_objects_v2(Bucket=_bucket(), MaxKeys=1)
    return resp.get("KeyCount", 0)


# ---- Secrets Manager ----------------------------------------------------------

def get_secret_json(secret_id):
    """Fetch and parse a JSON SecretString (used for the DB credentials)."""
    resp = _client("secretsmanager").get_secret_value(SecretId=secret_id)
    return json.loads(resp["SecretString"])


def secret_status(secret_id):
    """DescribeSecret only — metadata ping without reading the value.

    This is all the store ever does with the legacy marketplace key: prove
    the secret still exists for the /admin/aws-check dashboard.
    """
    resp = _client("secretsmanager").describe_secret(SecretId=secret_id)
    return resp["Name"]


# ---- CloudWatch -----------------------------------------------------------------

def put_health_ping():
    """Push OnlineShop/HealthPing = 1 (the /admin/aws-check metric ping)."""
    _client("cloudwatch").put_metric_data(
        Namespace="OnlineShop",
        MetricData=[{"MetricName": "HealthPing", "Value": 1.0, "Unit": "Count"}],
    )


# ---- STS ---------------------------------------------------------------------------

def whoami():
    """Caller identity — shown on /admin/aws-check to prove the instance role."""
    resp = _client("sts").get_caller_identity()
    return {"account": resp["Account"], "arn": resp["Arn"]}
