variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "region" {
  description = "GCP region"
  type        = string
  default     = "us-central1"
}

variable "env" {
  description = "Environment name (e.g. dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "public_subnet_cidr" {
  description = "CIDR range for the public subnet"
  type        = string
  default     = "10.0.1.0/24"
}

variable "private_subnet_cidr" {
  description = "CIDR range for the private subnet"
  type        = string
  default     = "10.0.2.0/24"
}

variable "web_machine_type" {
  description = "Machine type for the web instance"
  type        = string
  default     = "e2-small"
}

variable "app_machine_type" {
  description = "Machine type for the app instance"
  type        = string
  default     = "e2-standard-2"
}

variable "bastion_machine_type" {
  description = "Machine type for the bastion instance"
  type        = string
  default     = "e2-micro"
}

variable "common_labels" {
  description = "Labels applied to all resources"
  type        = map(string)
  default = {
    managed-by  = "terraform"
    environment = "dev"
    team        = "platform"
    cost-center = "engineering"
  }
}
