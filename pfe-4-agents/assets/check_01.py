import os
from pathlib import Path

import google.auth
from google.auth.transport.requests import Request

cloudsdk_config = os.environ.get("CLOUDSDK_CONFIG")
candidate_paths = [
    Path.home() / ".config/gcloud/application_default_credentials.json",
]

if cloudsdk_config:
    candidate_paths.insert(
        0,
        Path(cloudsdk_config) / "application_default_credentials.json"
    )

print("PROJECT_ID:", os.environ.get("PROJECT_ID"))
print("GOOGLE_CLOUD_PROJECT:", os.environ.get("GOOGLE_CLOUD_PROJECT"))
print("CLOUDSDK_CONFIG:", cloudsdk_config)

for p in candidate_paths:
    print(f"ADC candidate: {p} exists={p.exists()}")

credentials, project = google.auth.default(
    scopes=["https://www.googleapis.com/auth/cloud-platform"]
)

print("credentials class:", credentials.__class__.__name__)
print("default project from ADC:", project)
print("quota project:", getattr(credentials, "quota_project_id", None))

credentials.refresh(Request())
print("token refresh: OK")
