locals {
  env_map = {
    "stg"  = "nle"
    "prod" = "prod"
  }
  resource_group_name = "mcol-rg-${var.env}"

  frontend_subnet_names = toset(flatten([
    for lb in var.load_balancers : [
      for frontend in values(lb.frontend_ip_configurations) : frontend.subnet_name
    ]
  ]))
  flattened_backend_address_pools = flatten([
    for lb_key, lb in var.load_balancers : [
      for pool_key, pool in lb.backend_address_pools : {
        lb_key   = lb_key
        pool_key = pool_key
      }
    ]
  ])
  flattened_backend_vm_ip_addresses = flatten([
    for lb_key, lb in var.load_balancers : [
      for pool_key, pool in lb.backend_address_pools : [
        for vm_name in pool.virtual_machine_names : {
          pool_key = pool_key
          key      = "${pool_key}-${vm_name}"
          vm_name  = vm_name
        }
      ]
    ]
  ])
  flattened_probes = flatten([
    for lb_key, lb in var.load_balancers : [
      for probe_key, probe in lb.probes : merge(probe, {
        lb_key    = lb_key
        probe_key = probe_key
      })
    ]
  ])
  flattened_rules = flatten([
    for lb_key, lb in var.load_balancers : [
      for rule_key, rule in lb.rules : merge(rule, {
        lb_key   = lb_key
        rule_key = rule_key
      })
    ]
  ])
}

module "ctags" {
  source = "github.com/hmcts/terraform-module-common-tags"

  builtFrom   = var.builtFrom
  environment = var.env
  product     = var.product
}

data "azurerm_subnet" "frontend_subnets" {
  for_each             = local.frontend_subnet_names
  name                 = "MCOL-${title(each.key)}-${upper(local.env_map[var.env])}"
  virtual_network_name = "vnet-${local.env_map[var.env]}-ext-01"
  resource_group_name  = "ExternalSpoke-rg"
}

data "azurerm_virtual_machine" "backend_vm" {
  for_each            = { for value in local.flattened_backend_vm_ip_addresses : value.key => value.vm_name }
  name                = each.value
  resource_group_name = local.resource_group_name
}

data "azurerm_virtual_network" "vnet" {
  name                = "vnet-${local.env_map[var.env]}-ext-01"
  resource_group_name = "ExternalSpoke-rg"
}
