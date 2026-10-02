"""aws_clients.py — the single funnel for every AWS SDK call in fac-api.

All boto3 client construction lives here so that call sites stay grep-able
and region/endpoint policy is decided in exactly one place.

Service usage -> intended GCP mapping (for future cloud migration planning):

    Amazon Bedrock (Nova Micro via APAC inference profile,
    bedrock-runtime Converse API)          -> Vertex AI (Gemini)
    Amazon DynamoDB (fac-conversations)    -> Firestore
    Amazon S3 (fac-transcripts-*)          -> Cloud Storage (GCS)
    AWS STS (identity check)               -> service identity / ADC metadata
    (runtime: ECS Fargate                  -> Cloud Run)

Configuration is env-var driven (12-factor):
    AWS_REGION / AWS_DEFAULT_REGION  data-plane region (set in the task def)
    BEDROCK_REGION                   region for bedrock + bedrock-runtime
"""

import os

import boto3

_REGION = (
    os.environ.get("AWS_REGION")
    or os.environ.get("AWS_DEFAULT_REGION")
    or "ap-northeast-1"
)
_BEDROCK_REGION = os.environ.get("BEDROCK_REGION", "ap-northeast-1")

_CACHE = {}


def _client(service, region):
    """Create-or-reuse a boto3 client (one per service+region)."""
    key = (service, region)
    if key not in _CACHE:
        _CACHE[key] = boto3.client(service, region_name=region)
    return _CACHE[key]


def dynamodb():
    """DynamoDB client — conversation turn storage (fac-conversations)."""
    return _client("dynamodb", _REGION)


def s3():
    """S3 client — archived transcript objects (fac-transcripts-<account>)."""
    return _client("s3", _REGION)


def bedrock_runtime():
    """Bedrock runtime client — Converse calls to the Nova Micro profile."""
    return _client("bedrock-runtime", _BEDROCK_REGION)


def bedrock():
    """Bedrock control-plane client — model catalog ping on /admin/aws-check."""
    return _client("bedrock", _BEDROCK_REGION)


def sts():
    """STS client — caller identity ping on /admin/aws-check."""
    return _client("sts", _REGION)
