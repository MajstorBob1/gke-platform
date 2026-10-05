output "get_credentials" {
  description = "Run this to point kubectl at the cluster."
  value       = "gcloud container clusters get-credentials ${module.gke.name} --zone ${module.gke.location} --project ${var.project_id}"
}

output "cluster_name" {
  value = module.gke.name
}

output "gateway_ip_name" {
  value = google_compute_global_address.gateway.name
}

output "gateway_ip" {
  value = google_compute_global_address.gateway.address
}

output "loki_bucket" {
  value = google_storage_bucket.loki.name
}

output "artifact_registry" {
  value = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.apps.repository_id}"
}
