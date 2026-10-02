"""GCP client funnel for the task-reminder service — the migrated counterpart of aws_clients.py.

Mapping implemented here (mirrors the funnel header in the AWS app):
    DynamoDB (sta-tasks)        -> Firestore (Native), named database sta-tasks
    S3 (sta-exports-*)          -> Cloud Storage
    Lambda functions            -> Cloud Run functions (2nd gen)
    EventBridge schedule        -> Cloud Scheduler
    STS get_caller_identity     -> ADC token refresh (identity_ping)

Env vars:
    GCP_PROJECT       target project id
    FIRESTORE_DB      named Firestore database (default sta-tasks)
    BUCKET            exports bucket name
"""

import os

import google.auth
import google.auth.transport.requests
from google.cloud import firestore, storage

_FS = None
_GCS = None


def project_id():
    return os.environ.get("GCP_PROJECT") or google.auth.default()[1]


def tasks_collection():
    """Firestore collection handle (cached client)."""
    global _FS
    if _FS is None:
        _FS = firestore.Client(project=project_id(),
                               database=os.environ.get("FIRESTORE_DB", "sta-tasks"))
    return _FS.collection("sta-tasks")


def gcs():
    global _GCS
    if _GCS is None:
        _GCS = storage.Client(project=project_id())
    return _GCS


def bucket_name():
    return os.environ["BUCKET"]


def identity_ping():
    """GCP analogue of sts.get_caller_identity(): refresh ADC for real.

    Proves the runtime service account can mint tokens; returns its email.
    """
    credentials, _ = google.auth.default()
    credentials.refresh(google.auth.transport.requests.Request())
    return getattr(credentials, "service_account_email", None) or "authenticated"
