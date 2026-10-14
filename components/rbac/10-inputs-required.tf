variable "env" {
  type        = string
  description = "The environment to deploy resources to."
}

variable "builtFrom" {
  type        = string
  description = "The name of the repository these resources are builtFrom."
}

variable "product" {
  type        = string
  description = "The name of the product this infrastructure supports."
}

variable "web_vms" {
  type        = any
  description = "The web tier VMs to create role assignments for."
}

variable "app_vms" {
  type        = any
  description = "The application tier VMs to create role assignments for."
}

variable "db_vms" {
  type        = any
  description = "The database VMs to create role assignments for."
}

variable "subscription_id" {
  type        = string
  description = "The subscription ID to create role assignments in."
}
