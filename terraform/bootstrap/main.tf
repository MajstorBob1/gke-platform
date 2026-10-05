# Bootstrap layer: run ONCE per project, with local state.
# Creates what every other layer depends on: enabled APIs, the remote-state
# bucket, and a billing budget that emails you before the trial credit is gone.

# Reading the project needs the Cloud Resource Manager API, which this layer
# enables itself, so defer the read until after the APIs are on. Without
# depends_on, Terraform reads data sources at plan time and fails with 403
# SERVICE_DISABLED on a brand-new project.
data "google_project" "this" {
  project_id = var.project_id

  depends_on = [google_project_service.apis]
}

resource "google_project_service" "apis" {
  for_each = toset([
    "artifactregistry.googleapis.com",
    "billingbudgets.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "compute.googleapis.com",
    "container.googleapis.com",
    "iam.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com",
    "serviceusage.googleapis.com",
    "storage.googleapis.com",
  ])

  project            = var.project_id
  service            = each.value
  disable_on_destroy = false # never break other things in the project on destroy
}

# Remote state for every other Terraform layer. Versioned, so a bad apply or a
# corrupted state file can be rolled back to an older object version.
resource "google_storage_bucket" "tfstate" {
  name                        = "${var.project_id}-tfstate"
  project                     = var.project_id
  location                    = var.state_bucket_location
  force_destroy               = false
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"

  versioning {
    enabled = true
  }

  lifecycle_rule {
    condition {
      num_newer_versions = 20
    }
    action {
      type = "Delete"
    }
  }

  depends_on = [google_project_service.apis]
}

# Budget alerts measured BEFORE credits: with the free trial, cost after credits
# is ~0 until the $300 runs out, so a normal budget would never fire.
resource "google_billing_budget" "this" {
  count = var.billing_account_id == "" ? 0 : 1

  billing_account = var.billing_account_id
  display_name    = "${var.project_id} monthly budget"

  budget_filter {
    projects               = ["projects/${data.google_project.this.number}"]
    credit_types_treatment = "EXCLUDE_ALL_CREDITS"
  }

  amount {
    specified_amount {
      currency_code = var.budget_currency
      units         = tostring(var.monthly_budget)
    }
  }

  dynamic "threshold_rules" {
    for_each = [0.25, 0.5, 0.9, 1.0]
    content {
      threshold_percent = threshold_rules.value
    }
  }

  depends_on = [google_project_service.apis]
}
