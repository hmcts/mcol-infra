variable "location" {
  type        = string
  description = "The Azure region to deploy resources to."
  default     = "uksouth"
}

variable "install_azure_monitor" {
  default = false
}

variable "os_disk_size_gb" {
  type        = number
  description = "OS disk size for all MCOL VMs."
  default     = 64
}

variable "os_disk_storage_account_type" {
  type        = string
  description = "OS disk storage account type for all MCOL VMs."
  default     = "Premium_LRS"
}
