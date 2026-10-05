variable "project_id" {
  type = string
}

variable "env" {
  type    = string
  default = "dev"
}

variable "region" {
  type    = string
  default = "europe-west1"
}

variable "zone" {
  type    = string
  default = "europe-west1-b"
}

variable "cluster_name" {
  type    = string
  default = "platform-dev"
}

variable "admin_cidrs" {
  description = "Who may reach the Kubernetes API. Your IP: curl -s https://ifconfig.me"
  type        = list(string)
}

variable "apps_max_nodes" {
  description = "Upper bound for the Spot app pool. Keep total vCPUs inside your quota (check-quotas.sh)."
  type        = number
  default     = 3
}
