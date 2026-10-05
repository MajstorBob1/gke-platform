terraform {
  required_version = ">= 1.9"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 8.5"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region

  # Needed for the Billing Budgets API when authenticating with user credentials (ADC).
  user_project_override = true
  billing_project       = var.project_id
}
