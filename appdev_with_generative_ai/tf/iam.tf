resource "google_service_account" "knowledge_drive" {
  account_id   = "knowledge-drive"
}

resource "google_project_iam_member" "knowledge_drive" {
  project  = var.project_id
  for_each = toset([
    "roles/firebase.sdkAdminServiceAgent",
    "roles/firebaseauth.admin",
    "roles/iam.serviceAccountTokenCreator",
  ])
  role = each.key
  member = "serviceAccount:${google_service_account.knowledge_drive.email}"
  depends_on = [
    google_service_account.knowledge_drive
  ]
}
