resource "google_compute_network" "vpc" {
  name                    = "${var.network_prefix}-vpc"
  auto_create_subnetworks = false
  mtu                     = 8896
  depends_on              = [google_project_service.base_apis]
}

resource "google_compute_subnetwork" "subnets" {
  for_each                 = toset(var.regions)
  name                     = "${var.network_prefix}-node-subnet"
  region                   = each.value
  network                  = google_compute_network.vpc.id
  ip_cidr_range            = each.value == "europe-west4" ? "10.0.1.0/24" : "10.0.2.0/24"
  private_ip_google_access = true
}

resource "google_compute_subnetwork" "proxy_subnets" {
  for_each      = toset(var.regions)
  name          = "${var.network_prefix}-proxy-subnet-${each.value}"
  region        = each.value
  network       = google_compute_network.vpc.id
  ip_cidr_range = each.value == "europe-west4" ? "10.1.1.0/24" : "10.1.2.0/24"
  purpose       = "GLOBAL_MANAGED_PROXY"
  role          = "ACTIVE"
}

resource "google_compute_subnetwork" "regional_proxy_subnets" {
  for_each      = toset(var.regions)
  name          = "${var.network_prefix}-regional-proxy-subnet-${each.value}"
  region        = each.value
  network       = google_compute_network.vpc.id
  ip_cidr_range = each.value == "europe-west4" ? "10.2.1.0/24" : "10.2.2.0/24"
  purpose       = "REGIONAL_MANAGED_PROXY"
  role          = "ACTIVE"
}

resource "google_compute_address" "gateway_ips" {
  for_each     = toset(var.regions)
  name         = "qwen-gateway-ip-${each.value}"
  region       = each.value
  subnetwork   = google_compute_subnetwork.subnets[each.value].id
  address_type = "INTERNAL"
  purpose      = "SHARED_LOADBALANCER_VIP"
}

resource "google_compute_address" "single_gateway_ips" {
  for_each     = toset(var.regions)
  name         = "qwen-single-gateway-ip-${each.value}"
  region       = each.value
  subnetwork   = google_compute_subnetwork.subnets[each.value].id
  address_type = "INTERNAL"
  purpose      = "SHARED_LOADBALANCER_VIP"
}

resource "google_compute_router" "nat_routers" {
  for_each = toset(var.regions)
  name     = "${var.network_prefix}-router-${each.value}"
  region   = each.value
  network  = google_compute_network.vpc.id
}

resource "google_compute_router_nat" "egress_nat" {
  for_each = toset(var.regions)
  name     = "${var.network_prefix}-nat-${each.value}"
  router   = google_compute_router.nat_routers[each.value].name
  region   = each.value

  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "LIST_OF_SUBNETWORKS"

  subnetwork {
    name                    = google_compute_subnetwork.subnets[each.value].id
    source_ip_ranges_to_nat = ["ALL_IP_RANGES"]
  }

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

resource "google_compute_firewall" "allow_internal" {
  name    = "${var.network_prefix}-allow-internal"
  network = google_compute_network.vpc.name
  allow { protocol = "all" }
  source_ranges = ["10.0.0.0/8", "10.1.0.0/16"]
}

resource "google_compute_firewall" "allow_health_checks" {
  name    = "${var.network_prefix}-allow-hc"
  network = google_compute_network.vpc.name
  allow {
    protocol = "tcp"
    ports    = ["8000"]
  }
  source_ranges = ["130.211.0.0/22", "35.191.0.0/16"]
}
