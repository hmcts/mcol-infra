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

variable "legacy_resource_group_name" {
  type        = string
  description = "The resource group holding the retained MCOL load balancers (managed by hmcts/oracle-azure-infrastructure)."
}

variable "load_balancer_backends" {
  type = map(object({
    load_balancer_name    = string
    backend_pool_name     = optional(string, "BackEndAddressPool")
    virtual_machine_names = optional(list(string), [])
  }))
  description = <<-EOT
    Tech-refresh VMs to add to the backend pools of the retained MCOL load balancers.
    Adding or removing VM names is the traffic cutover / rollback control; legacy NIC membership
    stays in hmcts/oracle-azure-infrastructure.
  EOT
}
