variable "project_id" {
  description = "GCP project ID that will host the platform."
  type        = string
}

variable "region" {
  description = "Default region for the provider."
  type        = string
  default     = "europe-west1"
}

variable "state_bucket_location" {
  description = "Location of the Terraform state bucket."
  type        = string
  default     = "EU"
}

variable "billing_account_id" {
  description = "Billing account ID (XXXXXX-XXXXXX-XXXXXX) for the budget alert. Empty string = no budget."
  type        = string
  default     = ""
}

variable "budget_currency" {
  description = "Must match the billing account's currency (check Billing > Account management)."
  type        = string
  default     = "USD"
}

variable "monthly_budget" {
  description = "Monthly budget in budget_currency. Alerts at 25/50/90/100%."
  type        = number
  default     = 100
}
