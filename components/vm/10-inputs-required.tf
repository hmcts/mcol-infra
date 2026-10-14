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
  type = map(object({
    availability_zone     = string
    subnet_name           = string
    private_ip            = string
    size                  = optional(string, "Standard_D2s_v6")
    install_xdr_agent     = optional(bool, false)
    install_xdr_collector = optional(bool, false)
    install_docker        = optional(bool, true)
  }))
  description = "The web tier (Apache) Docker host VMs to deploy."
}

variable "app_vms" {
  type = map(object({
    availability_zone     = string
    subnet_name           = string
    private_ip            = string
    size                  = optional(string, "Standard_D4s_v6")
    install_xdr_agent     = optional(bool, false)
    install_xdr_collector = optional(bool, false)
    install_docker        = optional(bool, true)
  }))
  description = "The application tier (MCOL + QAS) Docker host VMs to deploy."
}

variable "db_vms" {
  type = map(object({
    availability_zone     = string
    subnet_name           = string
    private_ip            = string
    size                  = optional(string, "Standard_E4-2s_v5")
    install_xdr_agent     = optional(bool, false)
    install_xdr_collector = optional(bool, false)
    image = optional(object({
      publisher = string
      offer     = string
      sku       = string
      version   = optional(string, "latest")
      }), {
      publisher = "RedHat"
      offer     = "RHEL"
      sku       = "96-gen2"
    })
    data_disks = optional(map(object({
      lun                  = number
      disk_size_gb         = number
      storage_account_type = optional(string, "Premium_LRS")
      caching              = optional(string, "None")
      mount_path           = optional(string)
    })), {})
  }))
  description = "The Oracle database VMs to deploy: permanent Oracle 19c servers and the temporary migration database VM."
}

variable "cnp_vault_sub" {
  type        = string
  description = "Subscription for the CNP key vault"
}

variable "fileshare_storage_account_key" {
  type        = string
  sensitive   = true
  description = "Storage account key for the legacy storheritage003/build Azure Files share. Supply via the secure TF_VAR_fileshare_storage_account_key pipeline variable."
}
