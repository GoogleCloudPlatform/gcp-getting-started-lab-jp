variable "project_id" { type = string }
variable "network_prefix" { default = "tpu-gke-dranet" }
variable "regions" { default = ["europe-west4", "asia-northeast1"] }
variable "region_to_tpu_zone" {
  default = {
    "europe-west4"    = "europe-west4-a"
    "asia-northeast1" = "asia-northeast1-b"
  }
}
