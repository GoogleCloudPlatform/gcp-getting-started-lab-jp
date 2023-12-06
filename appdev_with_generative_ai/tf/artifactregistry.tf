resource "time_sleep" "wait_2_minutes_for_artifact_registry" {
  create_duration = "2m"
}

resource "google_artifact_registry_repository" "drive_repo" {
  location      = var.region
  repository_id = "drive-repo"
  description   = "Docker repository for knowledge drive"
  format        = "DOCKER"
  depends_on = [
    time_sleep.wait_2_minutes_for_artifact_registry,
    null_resource.update_dot_env_for_knowledge_drive
  ]
}
