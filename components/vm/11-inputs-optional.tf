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

# Gate the Dynatrace OneAgent extension so first boots can run the run
# commands first. On the Azure RHEL marketplace images the OneAgent installer
# needs >1.72 GiB free on /opt, but the images ship /opt on a 2 GiB LV that
# only grow-rhel-lvs.sh (a run-command step) resizes. The extension is created
# inside the VM module, which the run commands depend on, so without this gate
# a from-scratch build deadlocks: the extension fails with installer exit 6
# before the run command that would fix /opt is ever created.
variable "install_dynatrace_oneagent" {
  type        = bool
  description = "Install the Dynatrace OneAgent VM extension. Keep false until the run commands have grown /opt on first boot."
  default     = false
}
