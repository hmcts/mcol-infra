locals {
  is_prod             = length(regexall(".*(prod).*", var.env)) > 0
  resource_group_name = "mcol-rg-${var.env}"

  flattened_web_users = flatten([
    for user_key, user in var.web_users : [
      for web_vm_key, web_vm in var.web_vms : {
        user_key = user_key
        user     = user
        vm_key   = web_vm_key
        vm_id    = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/resourceGroups/${local.resource_group_name}/providers/Microsoft.Compute/virtualMachines/${web_vm_key}"
      }
    ]
  ])

  flattened_app_users = flatten([
    for user_key, user in var.app_users : [
      for app_vm_key, app_vm in var.app_vms : {
        user_key = user_key
        user     = user
        vm_key   = app_vm_key
        vm_id    = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/resourceGroups/${local.resource_group_name}/providers/Microsoft.Compute/virtualMachines/${app_vm_key}"
      }
    ]
  ])

  flattened_db_users = flatten([
    for user_key, user in var.db_users : [
      for db_vm_key, db_vm in var.db_vms : {
        user_key = user_key
        user     = user
        vm_key   = db_vm_key
        vm_id    = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/resourceGroups/${local.resource_group_name}/providers/Microsoft.Compute/virtualMachines/${db_vm_key}"
      }
    ]
  ])

  docker_vm_names = concat(keys(var.web_vms), keys(var.app_vms))
}

module "ctags" {
  source = "github.com/hmcts/terraform-module-common-tags"

  builtFrom   = var.builtFrom
  environment = var.env
  product     = var.product
}

data "azurerm_client_config" "current" {}

data "azuread_user" "web_users" {
  for_each            = { for key, value in var.web_users : key => value if value.is_user == true }
  user_principal_name = each.key
}

data "azuread_group" "web_groups" {
  for_each         = { for key, value in var.web_users : key => value if value.is_group == true }
  display_name     = each.key
  security_enabled = each.value.group_security_enabled
}

data "azuread_service_principal" "web_sps" {
  for_each     = { for key, value in var.web_users : key => value if value.is_service_principal == true }
  display_name = each.key
}

data "azuread_user" "app_users" {
  for_each            = { for key, value in var.app_users : key => value if value.is_user == true }
  user_principal_name = each.key
}

data "azuread_group" "app_groups" {
  for_each         = { for key, value in var.app_users : key => value if value.is_group == true }
  display_name     = each.key
  security_enabled = each.value.group_security_enabled
}

data "azuread_service_principal" "app_sps" {
  for_each     = { for key, value in var.app_users : key => value if value.is_service_principal == true }
  display_name = each.key
}

data "azuread_user" "db_users" {
  for_each            = { for key, value in var.db_users : key => value if value.is_user == true }
  user_principal_name = each.key
}

data "azuread_group" "db_groups" {
  for_each         = { for key, value in var.db_users : key => value if value.is_group == true }
  display_name     = each.key
  security_enabled = each.value.group_security_enabled
}

data "azuread_service_principal" "db_sps" {
  for_each     = { for key, value in var.db_users : key => value if value.is_service_principal == true }
  display_name = each.key
}

data "azurerm_virtual_machine" "app_vms" {
  for_each            = var.app_vms
  name                = each.key
  resource_group_name = local.resource_group_name
}

data "azurerm_virtual_machine" "docker_vms" {
  for_each            = var.container_registry_id == null ? toset([]) : toset(local.docker_vm_names)
  name                = each.key
  resource_group_name = local.resource_group_name
}

data "azurerm_key_vault" "application" {
  count               = var.application_key_vault == null ? 0 : 1
  name                = var.application_key_vault.name
  resource_group_name = var.application_key_vault.resource_group_name
}
