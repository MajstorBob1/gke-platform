output "name" {
  value = google_container_cluster.this.name
}

output "location" {
  value = google_container_cluster.this.location
}

output "endpoint" {
  value     = google_container_cluster.this.endpoint
  sensitive = true
}

output "workload_pool" {
  value = google_container_cluster.this.workload_identity_config[0].workload_pool
}

output "node_service_account" {
  value = google_service_account.nodes.email
}
