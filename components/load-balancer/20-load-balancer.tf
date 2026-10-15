resource "azurerm_network_interface_backend_address_pool_association" "backend_vm" {
  for_each                = { for value in local.flattened_backend_vms : value.key => value }
  network_interface_id    = data.azurerm_network_interface.backend_vm[each.key].id
  ip_configuration_name   = "${each.value.vm_name}-ipconfig"
  backend_address_pool_id = data.azurerm_lb_backend_address_pool.backend[each.value.backend_key].id
}
