module "virtual-machines" {
  providers = {
    azurerm     = azurerm
    azurerm.cnp = azurerm.cnp
    azurerm.soc = azurerm.soc
    azurerm.dcr = azurerm.dcr
  }

  for_each                = local.virtual_machines
  source                  = "github.com/hmcts/terraform-module-virtual-machine.git?ref=master"
  vm_type                 = "linux"
  vm_name                 = each.key
  env                     = var.env == "stg" ? "nonprod" : var.env
  vm_resource_group       = local.resource_group_name
  vm_location             = var.location
  vm_admin_name           = "mcol_${random_string.username[each.key].result}"
  vm_admin_password       = random_password.password[each.key].result
  vm_availabilty_zones    = each.value.availability_zone
  vm_subnet_id            = data.azurerm_subnet.subnets[each.key].id
  vm_publisher_name       = each.value.image.publisher
  vm_offer                = each.value.image.offer
  vm_sku                  = each.value.image.sku
  vm_size                 = each.value.size
  vm_version              = each.value.image.version
  vm_private_ip           = each.value.private_ip
  systemassigned_identity = true

  os_disk_size_gb              = var.os_disk_size_gb
  os_disk_storage_account_type = var.os_disk_storage_account_type
  managed_disks                = lookup(local.managed_disks, each.key, {})

  install_azure_monitor      = var.install_azure_monitor
  install_dynatrace_oneagent = true
  install_splunk_uf          = true
  nessus_install             = true
  install_docker             = each.value.install_docker

  run_command_sa_key = data.azurerm_storage_account.xdr_storage.primary_access_key
  run_command        = (each.value.install_xdr_agent || each.value.install_xdr_collector) ? true : false
  run_xdr_collector  = each.value.install_xdr_collector
  run_xdr_agent      = each.value.install_xdr_agent

  custom_script_extension_name = "HMCTSVMBootstrap"
  tags                         = module.ctags.common_tags
  xdr_tags                     = local.xdr_tags
}

resource "azurerm_backup_protected_vm" "vm" {
  for_each            = local.virtual_machines
  resource_group_name = local.resource_group_name
  recovery_vault_name = "mcol-rsv-${var.env}"
  source_vm_id        = module.virtual-machines[each.key].vm_id
  backup_policy_id    = data.azurerm_backup_policy_vm.policy.id
}

resource "azurerm_virtual_machine_extension" "AADSSHLoginForLinux" {
  for_each                   = local.virtual_machines
  name                       = "AADSSHLoginForLinux"
  virtual_machine_id         = module.virtual-machines[each.key].vm_id
  publisher                  = "Microsoft.Azure.ActiveDirectory"
  type                       = "AADSSHLoginForLinux"
  type_handler_version       = "1.0"
  auto_upgrade_minor_version = true
  tags                       = module.ctags.common_tags
}
