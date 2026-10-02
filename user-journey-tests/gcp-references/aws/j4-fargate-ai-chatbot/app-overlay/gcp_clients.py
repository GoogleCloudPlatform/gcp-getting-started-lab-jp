"""gcp_clients.py — the single funnel for every GCP SDK call in fac-api.

GCP port of the journey's aws_clients.py; replaces it entirely (build.sh
removes aws_clients.py after applying this overlay). Service mapping:

    Amazon Bedrock (Nova, Converse API)  -> Vertex AI Gemini (google-genai)
    Amazon DynamoDB (fac-conversations)  -> Firestore named DB fac-conversations
    Amazon S3 (fac-transcripts-*)        -> Cloud Storage (fac-transcripts-<project>)
    AWS STS get_caller_identity          -> ADC token refresh (service account email)
    (runtime: ECS Fargate                -> Cloud Run)

Configuration is env-var driven (12-factor):
    GOOGLE_CLOUD_PROJECT   project id (set by deploy/07-cloud-run.sh)
    VERTEX_LOCATION        Vertex endpoint location, default "global" — the
                           Gemini 2.5 family is served from the global
                           endpoint (verified 2026-07)
"""

import os

import google.auth
import google.auth.transport.requests
from google import genai
from google.cloud import firestore, storage

_PROJECT = os.environ.get("GOOGLE_CLOUD_PROJECT", "aws-migration-501814")
_VERTEX_LOCATION = os.environ.get("VERTEX_LOCATION", "global")

# Re-exported so main.py never imports google.cloud.firestore directly.
ASCENDING = firestore.Query.ASCENDING
DESCENDING = firestore.Query.DESCENDING

_CACHE = {}


def firestore_db(database_id):
    """Firestore client bound to the named database (conversation turns)."""
    key = ("firestore", database_id)
    if key not in _CACHE:
        _CACHE[key] = firestore.Client(project=_PROJECT, database=database_id)
    return _CACHE[key]


def storage_client():
    """Cloud Storage client — archived transcript objects."""
    if "storage" not in _CACHE:
        _CACHE["storage"] = storage.Client(project=_PROJECT)
    return _CACHE["storage"]


def genai_client():
    """google-genai client on the Vertex AI backend — Gemini replies."""
    if "genai" not in _CACHE:
        _CACHE["genai"] = genai.Client(
            vertexai=True, project=_PROJECT, location=_VERTEX_LOCATION
        )
    return _CACHE["genai"]


def identity_email():
    """Refresh ADC and return the runtime service account email.

    The GCP analogue of sts.get_caller_identity(): a real round-trip that
    proves the workload identity can mint tokens.
    """
    credentials, _ = google.auth.default()
    credentials.refresh(google.auth.transport.requests.Request())
    return getattr(credentials, "service_account_email", None) or "authenticated"
