variable "gcp_project" {
  description = "The default GCP project ID to use"
  type        = string
}

variable "gcp_billing_account" {
  description = "The GCP billing account ID to use for new projects"
  type        = string
}

variable "gcp_region" {
  description = "The GCP region to use"
  type        = string
  default     = "us-west1"
} 