terraform {
  required_version = ">= 1.5.7"
  required_providers {
    google      = { source = "hashicorp/google", version = "~> 7.0" }
    google-beta = { source = "hashicorp/google-beta", version = "~> 7.0" }
    time        = { source = "hashicorp/time", version = "~> 0.11.0" }
  }
}

provider "google" { project = var.project_id }
provider "google-beta" { project = var.project_id }

resource "google_project_service" "base_apis" {
  for_each = toset([
    "compute.googleapis.com",
    "container.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "iam.googleapis.com",
    "iamcredentials.googleapis.com",
    "storage.googleapis.com"
  ])
  project            = var.project_id
  service            = each.value
  disable_on_destroy = false
}

resource "google_project_service_identity" "gke_sa" {
  provider   = google-beta
  project    = var.project_id
  service    = "container.googleapis.com"
  depends_on = [google_project_service.base_apis]
}

resource "time_sleep" "wait_for_gke_service_agent" {
  create_duration = "90s"
  depends_on      = [google_project_service_identity.gke_sa]
}
