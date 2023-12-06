output "Service_URL" {
  value = google_cloud_run_service.knowledge_drive.status[0].url
}