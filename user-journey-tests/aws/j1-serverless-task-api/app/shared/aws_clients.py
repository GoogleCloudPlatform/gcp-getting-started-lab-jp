"""AWS client funnel for the task-reminder service.

Every AWS SDK call in this codebase goes through this module so call sites
stay grep-able. Intended GCP mapping if this workload is ever migrated:

    DynamoDB (sta-tasks)        -> Firestore (Native mode)
    S3 (sta-exports-*)          -> Cloud Storage
    Lambda functions            -> Cloud Run functions (2nd gen)
    EventBridge schedule        -> Cloud Scheduler
    STS get_caller_identity     -> Application Default Credentials / metadata

Configuration comes from environment variables only:
    TABLE_NAME   DynamoDB table (default sta-tasks)
    BUCKET       exports bucket
    AWS_REGION   provided by the Lambda runtime
"""

import os

import boto3

_TABLE = None
_S3 = None
_STS = None


def table():
    """DynamoDB Table resource (cached across warm invocations)."""
    global _TABLE
    if _TABLE is None:
        _TABLE = boto3.resource("dynamodb").Table(os.environ.get("TABLE_NAME", "sta-tasks"))
    return _TABLE


def s3():
    global _S3
    if _S3 is None:
        _S3 = boto3.client("s3")
    return _S3


def sts():
    global _STS
    if _STS is None:
        _STS = boto3.client("sts")
    return _STS


def bucket_name():
    return os.environ["BUCKET"]
