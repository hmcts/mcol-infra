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

variable "load_balancers" {
  type = map(object({
    name     = string
    sku      = string
    sku_tier = optional(string, "Regional")
    frontend_ip_configurations = map(object({
      subnet_name                   = string
      private_ip_address            = optional(string)
      private_ip_address_allocation = optional(string, "Dynamic")
      zones                         = optional(list(string), ["1", "2", "3"])
    }))
    backend_address_pools = map(object({
      virtual_machine_names = optional(list(string), [])
    }))
    probes = map(object({
      protocol            = string
      port                = number
      request_path        = optional(string)
      interval            = optional(number, 15)
      threshold           = optional(number, 1)
      unhealthy_threshold = optional(number, 3)
    }))
    rules = map(object({
      protocol                       = string
      frontend_port                  = number
      backend_port                   = number
      frontend_ip_configuration_name = string
      backend_address_pool_names     = list(string)
      probe_name                     = optional(string)
      load_distribution              = optional(string, "Default")
      enable_floating_ip             = optional(bool, false)
      enable_tcp_reset               = optional(bool, false)
      idle_timeout_in_minutes        = optional(number, 4)
      disable_outbound_snat          = optional(bool, false)
    }))
  }))
  description = "The private web and application tier load balancers, keyed by tier."
}
