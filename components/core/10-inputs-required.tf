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

variable "subnets" {
  type = map(object({
    address_prefixes  = list(string),
    service_endpoints = optional(list(string), []),
    use_default_rt    = optional(bool, false)
    delegations = optional(map(object({
      service_name = string,
      actions      = optional(list(string), [])
    })))
  }))
  description = "Map of subnets to create."
  default     = {}
}

variable "route_tables" {
  type = map(object({
    subnets = list(string),
    routes = map(object({
      address_prefix         = string,
      next_hop_type          = string,
      next_hop_in_ip_address = optional(string)
    }))
  }))
  description = "Map of route tables to create."
}

variable "network_security_groups" {
  type = map(object({
    subnets = optional(list(string))
    rules = map(object({
      priority                                   = number,
      direction                                  = string,
      access                                     = string,
      protocol                                   = string,
      source_port_range                          = optional(string)
      source_port_ranges                         = optional(list(string))
      destination_port_range                     = optional(string)
      destination_port_ranges                    = optional(list(string))
      source_address_prefix                      = optional(string)
      source_address_prefixes                    = optional(list(string))
      source_application_security_group_ids      = optional(list(string))
      destination_address_prefix                 = optional(string)
      destination_address_prefixes               = optional(list(string))
      destination_application_security_group_ids = optional(list(string))
      description                                = optional(string)
    }))
  }))
  description = "Map of network security groups to create."
}
