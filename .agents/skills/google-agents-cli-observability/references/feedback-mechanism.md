# Feedback Mechanism (Scaffolded Projects)

> **Assumes `/google-agents-cli-scaffold` scaffolding.** Reuses the same telemetry infrastructure documented in `cloud-trace-and-logging.md`.

To collect end-user feedback (ratings, thumbs up/down, free-text) and land it in BigQuery for analysis, reuse the same pattern as GenAI logs: **structured log → log sink → BigQuery**. There are three components.

## 1. Request model

A Pydantic model with a fixed discriminator field so the log sink can filter on it. Put it wherever your app keeps request/response models (e.g. `app/app_utils/typing.py`):

```python
import uuid
from typing import Literal

from pydantic import BaseModel, Field


class Feedback(BaseModel):
    """Represents feedback for a conversation."""

    score: int | float
    text: str | None = ""
    log_type: Literal["feedback"] = "feedback"
    service_name: Literal["<project-name>"] = "<project-name>"
    user_id: str = Field(default_factory=lambda: str(uuid.uuid4()))
    session_id: str = Field(default_factory=lambda: str(uuid.uuid4()))
```

The `log_type` and `service_name` fields are what the log sink filters on — keep them stable.

> **User text is retained.** `text` is free-form user input and lands in Cloud Logging and BigQuery — redact or omit it if you can't retain PII, keep `user_id`/`session_id` opaque (the defaults are random UUIDs), and set a table expiration on the telemetry dataset if you do.

## 2. FastAPI endpoint

An endpoint in `app/fast_api_app.py` that writes the payload as a **structured** log entry (so it lands in `jsonPayload`, not a plain text message). Create a Cloud Logging client once at module scope:

```python
from google.cloud import logging as google_cloud_logging

logging_client = google_cloud_logging.Client()
logger = logging_client.logger(__name__)


@app.post("/feedback")
def collect_feedback(feedback: Feedback) -> dict[str, str]:
    """Collect and log feedback."""
    logger.log_struct(feedback.model_dump(), severity="INFO")
    return {"status": "success"}
```

`severity="INFO"` keeps the entries out of error alerting. `log_struct` writes each field into `jsonPayload`, which the sink filter matches against.

## 3. Terraform log sink → BigQuery

A log sink in `deployment/terraform/single-project/telemetry.tf` (and the `cicd/` variant) that routes feedback entries to the telemetry BigQuery dataset, plus an IAM binding granting the sink's `writer_identity` write access:

```hcl
resource "google_logging_project_sink" "feedback_logs_to_bq" {
  name                   = "${var.project_name}-feedback"
  project                = var.project_id
  destination            = "bigquery.googleapis.com/projects/${var.project_id}/datasets/${google_bigquery_dataset.telemetry_dataset.dataset_id}"
  filter                 = "jsonPayload.log_type=\"feedback\" jsonPayload.service_name=\"${var.project_name}\""
  unique_writer_identity = true

  bigquery_options {
    use_partitioned_tables = true
  }

  depends_on = [google_bigquery_dataset.telemetry_dataset]
}

resource "google_bigquery_dataset_iam_member" "feedback_logs_bq_writer" {
  project    = var.project_id
  dataset_id = google_bigquery_dataset.telemetry_dataset.dataset_id
  role       = "roles/bigquery.dataEditor"
  member     = google_logging_project_sink.feedback_logs_to_bq.writer_identity
}
```

For the **cicd** variant, add `for_each = local.deploy_project_ids` and index the referenced resources with `[each.key]` / `[each.value]`, matching the other sinks in that file.

## Verify

On first write the sink auto-creates a date-partitioned table (named after the log) in the telemetry dataset. After POSTing a feedback payload, confirm the log entry:

```bash
gcloud logging read 'jsonPayload.log_type="feedback"' --limit 5 --project PROJECT_ID
```

Then query the exported table in the `<project_name>_telemetry` BigQuery dataset (a few minutes after the first write) to confirm the sink is delivering rows.
