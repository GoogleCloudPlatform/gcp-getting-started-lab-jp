resource "google_storage_bucket" "model_bucket" {
  name                        = "${var.project_id}-qwen-weights"
  location                    = "US"
  force_destroy               = true
  uniform_bucket_level_access = true
  depends_on                  = [google_project_service.base_apis]
}

resource "google_service_account" "gcs_fuse_sa" {
  account_id   = "gcs-fuse-sa"
  display_name = "Service Account for GCS FUSE"
  depends_on   = [google_project_service.base_apis]
}

resource "google_storage_bucket_iam_member" "gcs_fuse_sa_admin" {
  bucket = google_storage_bucket.model_bucket.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.gcs_fuse_sa.email}"
}

resource "google_storage_bucket_iam_member" "gcs_fuse_sa_bucket_reader" {
  bucket = google_storage_bucket.model_bucket.name
  role   = "roles/storage.legacyBucketReader"
  member = "serviceAccount:${google_service_account.gcs_fuse_sa.email}"
}

resource "google_service_account_iam_member" "workload_identity_binding" {
  service_account_id = google_service_account.gcs_fuse_sa.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[default/qwen-ksa]"
  depends_on         = [time_sleep.wait_for_workload_identity_pool]
}
