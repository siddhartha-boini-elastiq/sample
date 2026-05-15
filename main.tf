terraform {
  backend "gcs" {
    bucket = "kanika-agrawal-poc-tfstate-19b"
    prefix = "ci"
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

resource "google_storage_bucket" "demo" {
  name                        = "${var.project_id}-oidc-demo-bucket-19b"
  location                    = var.region
  uniform_bucket_level_access = true
}