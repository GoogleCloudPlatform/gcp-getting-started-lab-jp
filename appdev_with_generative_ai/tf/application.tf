module "gcloud" {
  source  = "terraform-google-modules/gcloud/google"
  version = "~> 3.3"

  platform = "linux"

  create_cmd_entrypoint  = "gcloud"
  create_cmd_body        = "builds submit ../src/knowledge-drive --tag asia-northeast1-docker.pkg.dev/${var.project_id}/drive-repo/knowledge-drive"
  destroy_cmd_entrypoint = "gcloud"
  destroy_cmd_body       = "version"
  module_depends_on      = [
    null_resource.update_dot_env_for_knowledge_drive
  ]
}

resource "google_cloud_run_service" "knowledge_drive" {
  name     = "knowledge-drive"
  location = var.region

  template {
    spec {
      containers {
        image = "asia-northeast1-docker.pkg.dev/${var.project_id}/drive-repo/knowledge-drive"
      }
      service_account_name = google_service_account.knowledge_drive.email
    }
  }

  traffic {
    percent         = 100
    latest_revision = true
  }
  depends_on = [
    module.gcloud
  ]
}

data "google_iam_policy" "noauth" {
  binding {
    role = "roles/run.invoker"
    members = [
      "allUsers",
    ]
  }
}

resource "google_cloud_run_service_iam_policy" "noauth" {
  location    = google_cloud_run_service.knowledge_drive.location
  project     = google_cloud_run_service.knowledge_drive.project
  service     = google_cloud_run_service.knowledge_drive.name
  policy_data = data.google_iam_policy.noauth.policy_data
}