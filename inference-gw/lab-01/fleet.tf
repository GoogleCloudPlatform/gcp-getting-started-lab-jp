data "google_project" "project" {
  project_id = var.project_id
}

locals {
  mcs_importer_members = toset([
    "serviceAccount:${var.project_id}.svc.id.goog[gke-mcs/gke-mcs-importer]",
    "principal://iam.googleapis.com/projects/${data.google_project.project.number}/locations/global/workloadIdentityPools/${var.project_id}.svc.id.goog/subject/ns/gke-mcs/sa/gke-mcs-importer"
  ])
}

resource "google_project_service" "fleet_apis" {
  for_each = toset([
    "autoscaling.googleapis.com",
    "connectgateway.googleapis.com",
    "dns.googleapis.com",
    "gkehub.googleapis.com",
    "multiclusterservicediscovery.googleapis.com",
    "multiclusteringress.googleapis.com",
    "networkservices.googleapis.com",
    "trafficdirector.googleapis.com"
  ])
  project            = var.project_id
  service            = each.value
  disable_on_destroy = false
}

resource "google_project_service_identity" "mci_sa" {
  provider   = google-beta
  project    = var.project_id
  service    = "multiclusteringress.googleapis.com"
  depends_on = [google_project_service.fleet_apis]
}

resource "time_sleep" "wait_for_apis" {
  create_duration = "60s"
  depends_on      = [google_project_service.fleet_apis]
}

resource "google_project_iam_member" "mci_sa_admin" {
  project    = var.project_id
  role       = "roles/container.admin"
  member     = "serviceAccount:${google_project_service_identity.mci_sa.email}"
  depends_on = [google_project_service_identity.mci_sa, time_sleep.wait_for_apis]
}

resource "google_project_iam_member" "mci_sa_service_agent" {
  project    = var.project_id
  role       = "roles/multiclusteringress.serviceAgent"
  member     = "serviceAccount:${google_project_service_identity.mci_sa.email}"
  depends_on = [google_project_service_identity.mci_sa, time_sleep.wait_for_apis]
}

resource "google_gke_hub_feature" "mcs" {
  provider   = google-beta
  name       = "multiclusterservicediscovery"
  location   = "global"
  project    = var.project_id
  depends_on = [time_sleep.wait_for_apis]
}

resource "google_project_iam_member" "mcs_importer_network_viewer" {
  for_each = local.mcs_importer_members
  project  = var.project_id
  role     = "roles/compute.networkViewer"
  member   = each.value
  depends_on = [
    google_gke_hub_feature.mcs,
    time_sleep.wait_for_workload_identity_pool
  ]
}

resource "google_gke_hub_feature" "ingress" {
  provider = google-beta
  name     = "multiclusteringress"
  location = "global"
  project  = var.project_id
  depends_on = [
    google_container_cluster.clusters,
    google_gke_hub_feature.mcs,
    google_project_iam_member.mci_sa_admin,
    google_project_iam_member.mci_sa_service_agent,
    google_project_iam_member.mcs_importer_network_viewer
  ]
  spec {
    multiclusteringress { config_membership = "projects/${var.project_id}/locations/asia-northeast1/memberships/gke-asia-northeast1" }
  }
}
