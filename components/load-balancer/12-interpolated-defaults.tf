locals {
  resource_group_name = "mcol-rg-${var.env}"
  flattened_backend_vms = flatten([
    for backend_key, backend in var.load_balancer_backends : [
      for vm_name in backend.virtual_machine_names : {
        backend_key = backend_key
        key         = "${backend_key}-${vm_name}"
        vm_name     = vm_name
      }
    ]
  ])
}

data "azurerm_lb" "lb" {
  for_each            = var.load_balancer_backends
  name                = each.value.load_balancer_name
  resource_group_name = var.legacy_resource_group_name
}

data "azurerm_lb_backend_address_pool" "backend" {
  for_each        = var.load_balancer_backends
  name            = each.value.backend_pool_name
  loadbalancer_id = data.azurerm_lb.lb[each.key].id
}

data "azurerm_network_interface" "backend_vm" {
  for_each            = { for value in local.flattened_backend_vms : value.key => value.vm_name }
  name                = "${each.value}-nic"
  resource_group_name = local.resource_group_name
}
