terraform {
  required_version = ">= 1.9"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 8.5"
    }
  }

  # Bucket comes from the bootstrap layer:
  #   terraform init -backend-config="bucket=<project_id>-tfstate"
  backend "gcs" {
    prefix = "envs/dev"
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}
