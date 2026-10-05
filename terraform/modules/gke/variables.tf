variable "project_id" {
  type = string
}

variable "name" {
  description = "Cluster name; also prefixes the node service account (max 30 chars total)."
  type        = string

  validation {
    condition     = length(var.name) <= 24
    error_message = "Keep the name <= 24 chars so \"<name>-nodes\" fits the 30-char service account limit."
  }
}

variable "zone" {
  description = "A zone (not a region): zonal clusters are covered by the GKE free tier."
  type        = string
}

variable "network_id" {
  type = string
}

variable "subnet_id" {
  type = string
}

variable "pods_range_name" {
  type = string
}

variable "services_range_name" {
  type = string
}

variable "admin_cidrs" {
  description = "CIDRs allowed to reach the Kubernetes API (your public IP as x.x.x.x/32)."
  type        = list(string)
}

variable "release_channel" {
  type    = string
  default = "REGULAR"
}

variable "deletion_protection" {
  description = "true in real production. false here so `terraform destroy` works at the end of a session."
  type        = bool
  default     = false
}

variable "labels" {
  type    = map(string)
  default = {}
}

variable "node_pools" {
  description = "Node pools keyed by name."
  type = map(object({
    machine_type = string
    spot         = bool
    min_nodes    = number
    max_nodes    = number
    disk_size_gb = optional(number, 50)
    taints = optional(list(object({
      key    = string
      value  = string
      effect = string
    })), [])
  }))
}
