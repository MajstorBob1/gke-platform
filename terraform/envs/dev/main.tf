locals {
  labels = {
    env        = var.env
    managed-by = "terraform"
    stack      = "gke-platform"
  }
}

data "google_project" "this" {
  project_id = var.project_id
}

module "network" {
  source = "../../modules/network"

  project_id = var.project_id
  name       = var.cluster_name
  region     = var.region
}

module "gke" {
  source = "../../modules/gke"

  project_id          = var.project_id
  name                = var.cluster_name
  zone                = var.zone
  network_id          = module.network.network_id
  subnet_id           = module.network.subnet_id
  pods_range_name     = module.network.pods_range_name
  services_range_name = module.network.services_range_name
  admin_cidrs         = var.admin_cidrs
  labels              = local.labels

  node_pools = {
    # Stable, on-demand: ArgoCD, Prometheus, Grafana, Loki.
    system = {
      machine_type = "e2-highmem-2"
      spot         = false
      min_nodes    = 1
      max_nodes    = 1
    }
    # ~70% cheaper Spot VMs for the app: can be reclaimed with 30 s notice,
    # which is great practice for resilience.
    apps = {
      machine_type = "e2-highmem-2"
      spot         = true
      min_nodes    = 1
      max_nodes    = var.apps_max_nodes
    }
  }
}

# --- Container registry for images built by CI ------------------------------
resource "google_artifact_registry_repository" "apps" {
  project       = var.project_id
  location      = var.region
  repository_id = "apps"
  format        = "DOCKER"
  labels        = local.labels

  cleanup_policies {
    id     = "keep-latest-10"
    action = "KEEP"
    most_recent_versions {
      keep_count = 10
    }
  }

  cleanup_policies {
    id     = "delete-older-than-30d"
    action = "DELETE"
    condition {
      older_than = "2592000s"
    }
  }
}

# --- Loki log storage in GCS, accessed via Workload Identity -----------------
resource "google_storage_bucket" "loki" {
  name                        = "${var.project_id}-loki-${var.env}"
  project                     = var.project_id
  location                    = var.region
  force_destroy               = true # logs are disposable in this practice env
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  labels                      = local.labels

  lifecycle_rule {
    condition {
      age = 14
    }
    action {
      type = "Delete"
    }
  }
}

# Grant the Kubernetes ServiceAccount monitoring/loki direct access to the bucket.
# No Google service account and no key file: GKE swaps the pod's KSA token for
# a short-lived Google token (Workload Identity Federation for GKE).
resource "google_storage_bucket_iam_member" "loki" {
  bucket = google_storage_bucket.loki.name
  role   = "roles/storage.objectAdmin"
  member = "principal://iam.googleapis.com/projects/${data.google_project.this.number}/locations/global/workloadIdentityPools/${module.gke.workload_pool}/subject/ns/monitoring/sa/loki"
}

# --- Static IP for the public Gateway (global external Application LB) -------
resource "google_compute_global_address" "gateway" {
  project = var.project_id
  name    = "${var.cluster_name}-gateway-ip"
  labels  = local.labels
}
