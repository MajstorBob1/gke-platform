variable "project_id" {
  type = string
}

variable "name" {
  description = "Base name for the VPC and its resources."
  type        = string
}

variable "region" {
  type = string
}

variable "nodes_cidr" {
  type    = string
  default = "10.10.0.0/20"
}

variable "pods_cidr" {
  description = "Secondary range for pod IPs. /16 = 65k pod IPs."
  type        = string
  default     = "10.20.0.0/16"
}

variable "services_cidr" {
  type    = string
  default = "10.30.0.0/20"
}
