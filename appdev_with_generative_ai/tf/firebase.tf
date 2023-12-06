resource "google_firebase_web_app" "knowledge_drive" {
  provider     = google-beta
  display_name = "knowledge-drive"
}

data "google_firebase_web_app_config" "knowledge_drive" {
  provider   = google-beta
  web_app_id = google_firebase_web_app.knowledge_drive.app_id
}

resource "local_file" "firebase_config" {
  filename = "firebase-config.json"

  content = jsonencode({
    projectId          = var.project_id
    appId              = google_firebase_web_app.knowledge_drive.app_id
    apiKey             = data.google_firebase_web_app_config.knowledge_drive.api_key
    authDomain         = data.google_firebase_web_app_config.knowledge_drive.auth_domain
    storageBucket      = lookup(data.google_firebase_web_app_config.knowledge_drive, "storage_bucket", "")
  })
}

resource "google_identity_platform_config" "default" {
  sign_in {
    allow_duplicate_emails = false
    anonymous {
        enabled = false
    }
    email {
        enabled = true
        password_required = true
    }
  }
}

resource "google_firestore_database" "default" {
  provider    = google-beta
  name        = "(default)"
  location_id = var.region
  type        = "FIRESTORE_NATIVE"
}

resource "google_firebaserules_ruleset" "firestore" {
  provider = google-beta
  source {
    files {
      name = "firestore.rules"
      content = file("firestore.rules")
    }
  }
  depends_on = [
    google_firestore_database.default
  ]
}

resource "google_firebaserules_release" "firestore" {
  provider     = google-beta
  name         = "cloud.firestore"
  ruleset_name = google_firebaserules_ruleset.firestore.name
}

resource "google_firestore_index" "items1" {
  provider    = google-beta

  collection  = "items"
  query_scope = "COLLECTION"

  fields {
    field_path = "parent"
    order      = "ASCENDING"
  }

  fields {
    field_path = "timestamp"
    order      = "DESCENDING"
  }

  depends_on = [
    google_firestore_database.default
  ]
}

resource "google_firestore_index" "items2" {
  provider    = google-beta

  collection  = "items"
  query_scope = "COLLECTION"

  fields {
    field_path = "name"
    order      = "ASCENDING"
  }

  fields {
    field_path = "timestamp"
    order      = "DESCENDING"
  }

  depends_on = [
    google_firestore_index.items1
  ]
}

resource "time_sleep" "wait_30_seconds_for_firebase" {
  depends_on = [
    google_firestore_database.default
  ]
  create_duration = "30s"
}

resource "google_app_engine_application" "default" {
  location_id = var.region

  depends_on = [
    time_sleep.wait_30_seconds_for_firebase
  ]
}

resource "google_firebase_storage_bucket" "default" {
  provider  = google-beta
  bucket_id = google_app_engine_application.default.default_bucket
}

resource "google_firebaserules_ruleset" "storage" {
  provider = google-beta
  source {
    files {
      name    = "storage.rules"
      content = file("storage.rules")
    }
  }

  depends_on = [
    google_firebase_storage_bucket.default
  ]
}

resource "google_firebaserules_release" "storage" {
  provider     = google-beta
  name         = "firebase.storage/${google_app_engine_application.default.default_bucket}"
  ruleset_name = "projects/${var.project_id}/rulesets/${google_firebaserules_ruleset.storage.name}"

  depends_on = [
    google_firebaserules_ruleset.storage
  ]
}

resource "null_resource" "update_dot_env_for_knowledge_drive" {
  provisioner "local-exec" {
    command = "./firebase_config.sh"
  }
  depends_on = [
    local_file.firebase_config
  ]
}
