resource "azurerm_lb" "lb" {
  for_each            = var.load_balancers
  name                = "${each.value.name}-${var.env}"
  resource_group_name = local.resource_group_name
  location            = var.location

  sku      = each.value.sku
  sku_tier = each.value.sku_tier

  dynamic "frontend_ip_configuration" {
    for_each = each.value.frontend_ip_configurations
    content {
      name                          = frontend_ip_configuration.key
      subnet_id                     = data.azurerm_subnet.frontend_subnets[frontend_ip_configuration.value.subnet_name].id
      private_ip_address            = frontend_ip_configuration.value.private_ip_address
      private_ip_address_allocation = frontend_ip_configuration.value.private_ip_address_allocation
      zones                         = frontend_ip_configuration.value.zones
    }
  }

  tags = module.ctags.common_tags
}

resource "azurerm_lb_backend_address_pool" "backend" {
  for_each        = { for value in local.flattened_backend_address_pools : value.pool_key => value }
  loadbalancer_id = azurerm_lb.lb[each.value.lb_key].id
  name            = each.key
}

resource "azurerm_lb_backend_address_pool_address" "backend_vm_ip_address" {
  for_each                = { for value in local.flattened_backend_vm_ip_addresses : value.key => value }
  name                    = each.value.vm_name
  backend_address_pool_id = azurerm_lb_backend_address_pool.backend[each.value.pool_key].id
  ip_address              = data.azurerm_virtual_machine.backend_vm[each.key].private_ip_address
  virtual_network_id      = data.azurerm_virtual_network.vnet.id
}

resource "azurerm_lb_probe" "probe" {
  for_each            = { for value in local.flattened_probes : value.probe_key => value }
  loadbalancer_id     = azurerm_lb.lb[each.value.lb_key].id
  name                = each.key
  protocol            = each.value.protocol
  port                = each.value.port
  interval_in_seconds = each.value.interval
  probe_threshold     = each.value.threshold
  number_of_probes    = each.value.unhealthy_threshold
  request_path        = each.value.request_path
}

resource "azurerm_lb_rule" "rule" {
  for_each                       = { for value in local.flattened_rules : value.rule_key => value }
  loadbalancer_id                = azurerm_lb.lb[each.value.lb_key].id
  name                           = each.key
  protocol                       = each.value.protocol
  frontend_port                  = each.value.frontend_port
  backend_port                   = each.value.backend_port
  frontend_ip_configuration_name = each.value.frontend_ip_configuration_name
  enable_floating_ip             = each.value.enable_floating_ip
  backend_address_pool_ids       = [for pool_name in each.value.backend_address_pool_names : azurerm_lb_backend_address_pool.backend[pool_name].id]
  probe_id                       = azurerm_lb_probe.probe[each.value.probe_name].id
  load_distribution              = each.value.load_distribution
  enable_tcp_reset               = each.value.enable_tcp_reset
  idle_timeout_in_minutes        = each.value.idle_timeout_in_minutes
  disable_outbound_snat          = each.value.disable_outbound_snat
}
