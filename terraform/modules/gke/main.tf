# Production-style GKE Standard cluster:
#   - zonal (covered by the GKE free tier management-fee credit)
#   - private nodes (no public IPs), public control-plane endpoint locked to admin CIDRs
#   - Dataplane V2 (eBPF/Cilium): NetworkPolicy enforcement built in
#   - Workload Identity: pods get GCP permissions without key files
#   - Gateway API controller: Gateway/HTTPRoute -> Google Cloud load balancer
#   - separately managed node pools with a least-privilege node service account

# --- Node identity -----------------------------------------------------------
# Never run nodes as the Compute Engine default SA (it has Editor on the project).
resource "google_service_account" "nodes" {
  project      = var.project_id
  account_id   = "${var.name}-nodes"
  display_name = "GKE nodes for ${var.name}"
}

resource "google_project_iam_member" "nodes" {
  for_each = toset([
    "roles/container.defaultNodeServiceAccount", # logging, monitoring, metadata
    "roles/artifactregistry.reader",             # pull images from our registry
  ])

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.nodes.email}"
}

# --- Control plane -----------------------------------------------------------
resource "google_container_cluster" "this" {
  name     = var.name
  project  = var.project_id
  location = var.zone

  deletion_protection = var.deletion_protection

  # We manage node pools ourselves; GKE needs a temporary default pool to create the cluster.
  remove_default_node_pool = true
  initial_node_count       = 1

  # Settings for that temporary pool only: small, our SA, no SSD quota consumed.
  node_config {
    machine_type    = "e2-small"
    disk_type       = "pd-standard"
    disk_size_gb    = 30
    service_account = google_service_account.nodes.email
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]
  }

  network           = var.network_id
  subnetwork        = var.subnet_id
  networking_mode   = "VPC_NATIVE"
  datapath_provider = "ADVANCED_DATAPATH" # Dataplane V2

  ip_allocation_policy {
    cluster_secondary_range_name  = var.pods_range_name
    services_secondary_range_name = var.services_range_name
  }

  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false
  }

  master_authorized_networks_config {
    dynamic "cidr_blocks" {
      for_each = var.admin_cidrs
      content {
        cidr_block   = cidr_blocks.value
        display_name = "admin-${cidr_blocks.key}"
      }
    }
  }

  release_channel {
    channel = var.release_channel
  }

  # Auto-upgrades only happen inside this window (weekend nights, UTC).
  maintenance_policy {
    recurring_window {
      start_time = "2026-01-03T01:00:00Z"
      end_time   = "2026-01-03T07:00:00Z"
      recurrence = "FREQ=WEEKLY;BYDAY=SA,SU"
    }
  }

  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  gateway_api_config {
    channel = "CHANNEL_STANDARD"
  }

  # Keep Google-side observability to system components only: app metrics and
  # logs go to our own Prometheus/Loki, which keeps Cloud Monitoring/Logging bills at ~0.
  logging_config {
    enable_components = ["SYSTEM_COMPONENTS"]
  }

  monitoring_config {
    enable_components = ["SYSTEM_COMPONENTS"]
    managed_prometheus {
      enabled = false
    }
  }

  cost_management_config {
    enabled = true # per-namespace cost breakdown in the billing export
  }

  resource_labels = var.labels

  lifecycle {
    ignore_changes = [node_config, initial_node_count]
  }

  depends_on = [google_project_iam_member.nodes]
}

# --- Node pools --------------------------------------------------------------
resource "google_container_node_pool" "this" {
  for_each = var.node_pools

  name     = each.key
  project  = var.project_id
  location = var.zone
  cluster  = google_container_cluster.this.name

  initial_node_count = each.value.min_nodes

  autoscaling {
    min_node_count = each.value.min_nodes
    max_node_count = each.value.max_nodes
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  # Surge upgrades: add 1 new node, move pods, then remove 1 old node.
  upgrade_settings {
    max_surge       = 1
    max_unavailable = 0
  }

  node_config {
    machine_type    = each.value.machine_type
    spot            = each.value.spot
    disk_type       = "pd-standard" # pd-balanced/ssd count against the small trial SSD quota
    disk_size_gb    = each.value.disk_size_gb
    service_account = google_service_account.nodes.email
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]

    labels = merge(var.labels, { pool = each.key })

    dynamic "taint" {
      for_each = each.value.taints
      content {
        key    = taint.value.key
        value  = taint.value.value
        effect = taint.value.effect
      }
    }

    workload_metadata_config {
      mode = "GKE_METADATA" # required for Workload Identity
    }

    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }

    metadata = {
      disable-legacy-endpoints = "true"
    }
  }

  lifecycle {
    ignore_changes = [initial_node_count]
  }
}
