resource "google_container_cluster" "clusters" {
  provider = google-beta
  for_each = toset(var.regions)
  name     = "gke-${each.value}"
  location = var.region_to_tpu_zone[each.value]

  deletion_protection = false
  network             = google_compute_network.vpc.id
  subnetwork          = google_compute_subnetwork.subnets[each.value].id
  datapath_provider   = "ADVANCED_DATAPATH"
  networking_mode     = "VPC_NATIVE"

  release_channel { channel = "RAPID" }
  gateway_api_config { channel = "CHANNEL_STANDARD" }
  fleet { project = var.project_id }

  ip_allocation_policy {
    cluster_ipv4_cidr_block  = ""
    services_ipv4_cidr_block = ""
  }

  workload_identity_config { workload_pool = "${var.project_id}.svc.id.goog" }

  addons_config {
    gcs_fuse_csi_driver_config { enabled = true }
  }

  initial_node_count = 1
  node_config {
    machine_type = "e2-standard-16"
    oauth_scopes = ["https://www.googleapis.com/auth/cloud-platform"]
    workload_metadata_config { mode = "GKE_METADATA" }
  }

  depends_on = [
    google_compute_router_nat.egress_nat,
    google_compute_subnetwork.subnets,
    google_project_service.base_apis,
    time_sleep.wait_for_apis,
    time_sleep.wait_for_gke_service_agent
  ]
}

resource "time_sleep" "wait_for_workload_identity_pool" {
  create_duration = "90s"
  depends_on      = [google_container_cluster.clusters]
}

resource "google_container_node_pool" "tpu_pools" {
  provider   = google-beta
  for_each   = toset(var.regions)
  name       = "tpu-v6e-pool"
  location   = var.region_to_tpu_zone[each.value]
  cluster    = google_container_cluster.clusters[each.value].name
  node_count = 2

  network_config { accelerator_network_profile = "auto" }

  node_config {
    machine_type = "ct6e-standard-1t"
    spot         = true
    oauth_scopes = ["https://www.googleapis.com/auth/cloud-platform"]
    labels       = { "cloud.google.com/gke-networking-dra-driver" = "true" }
    workload_metadata_config { mode = "GKE_METADATA" }
  }

  depends_on = [time_sleep.wait_for_workload_identity_pool]

  lifecycle { ignore_changes = [node_config[0].labels] }
}
