resource "azurerm_role_assignment" "web_rbac" {
  for_each             = { for value in local.flattened_web_users : "${value.user_key}-${value.vm_key}" => value }
  scope                = each.value.vm_id
  role_definition_name = each.value.user.role_type == "admin" ? "Virtual Machine Administrator Login" : "Virtual Machine User Login"
  principal_id         = each.value.user.is_user == true ? data.azuread_user.web_users[each.value.user_key].id : each.value.user.is_group == true ? data.azuread_group.web_groups[each.value.user_key].id : data.azuread_service_principal.web_sps[each.value.user_key].id
}

resource "azurerm_role_assignment" "app_rbac" {
  for_each             = { for value in local.flattened_app_users : "${value.user_key}-${value.vm_key}" => value }
  scope                = each.value.vm_id
  role_definition_name = each.value.user.role_type == "admin" ? "Virtual Machine Administrator Login" : "Virtual Machine User Login"
  principal_id         = each.value.user.is_user == true ? data.azuread_user.app_users[each.value.user_key].id : each.value.user.is_group == true ? data.azuread_group.app_groups[each.value.user_key].id : data.azuread_service_principal.app_sps[each.value.user_key].id
}

resource "azurerm_role_assignment" "db_rbac" {
  for_each             = { for value in local.flattened_db_users : "${value.user_key}-${value.vm_key}" => value }
  scope                = each.value.vm_id
  role_definition_name = each.value.user.role_type == "admin" ? "Virtual Machine Administrator Login" : "Virtual Machine User Login"
  principal_id         = each.value.user.is_user == true ? data.azuread_user.db_users[each.value.user_key].id : each.value.user.is_group == true ? data.azuread_group.db_groups[each.value.user_key].id : data.azuread_service_principal.db_sps[each.value.user_key].id
}

# MCOL containers read secrets from the existing application key vault using the host's managed identity.
resource "azurerm_role_assignment" "app_kv_secrets_user" {
  for_each             = var.application_key_vault == null ? {} : data.azurerm_virtual_machine.app_vms
  scope                = data.azurerm_key_vault.application[0].id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = each.value.identity[0].principal_id
}

# The core key vault uses access policies rather than RBAC; Get and List are the Key Vault Secrets User equivalent.
resource "azurerm_key_vault_access_policy" "app_core_kv_secrets_user" {
  for_each           = data.azurerm_virtual_machine.app_vms
  key_vault_id       = data.azurerm_key_vault.core.id
  tenant_id          = data.azurerm_client_config.current.tenant_id
  object_id          = each.value.identity[0].principal_id
  secret_permissions = ["Get", "List"]
}

resource "azurerm_role_assignment" "acr_pull" {
  for_each             = data.azurerm_virtual_machine.docker_vms
  scope                = var.container_registry_id
  role_definition_name = "AcrPull"
  principal_id         = each.value.identity[0].principal_id
}
