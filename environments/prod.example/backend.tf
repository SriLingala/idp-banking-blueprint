terraform {
  backend "gcs" {
    bucket = "REPLACE-prod-tfstate-bucket"
    prefix = "env/prod"
  }
}

