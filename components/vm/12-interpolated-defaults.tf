locals {
  env_map = {
    "stg"  = "nle"
    "prod" = "prod"
  }

  xdr_tag_map = {
    activityName = "heritage"
    application  = "mcol"
    env          = var.env == "stg" ? "nonprod" : var.env
  }

  xdr_tags = join(",", values(local.xdr_tag_map))

  ubuntu_image = {
    publisher = "canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  docker_vms = {
    for key, value in merge(var.web_vms, var.app_vms) : key => {
      availability_zone     = value.availability_zone
      subnet_name           = value.subnet_name
      private_ip            = value.private_ip
      size                  = value.size
      install_xdr_agent     = value.install_xdr_agent
      install_xdr_collector = value.install_xdr_collector
      install_docker        = value.install_docker
      image                 = local.ubuntu_image
    }
  }
  db_vms = {
    for key, value in var.db_vms : key => {
      availability_zone     = value.availability_zone
      subnet_name           = value.subnet_name
      private_ip            = value.private_ip
      size                  = value.size
      install_xdr_agent     = value.install_xdr_agent
      install_xdr_collector = value.install_xdr_collector
      install_docker        = false
      image                 = value.image
    }
  }

  resource_group_name = "mcol-rg-${var.env}"
  virtual_machines    = merge(local.docker_vms, local.db_vms)

  managed_disks = {
    for vm_key, vm in var.db_vms : vm_key => {
      for disk_key, disk in vm.data_disks : disk_key => {
        name                     = "${vm_key}-datadisk-${disk_key}"
        location                 = var.location
        resource_group_name      = local.resource_group_name
        storage_account_type     = disk.storage_account_type
        disk_create_option       = "Empty"
        disk_size_gb             = tostring(disk.disk_size_gb)
        disk_tier                = null
        disk_zone                = vm.availability_zone
        source_resource_id       = null
        storage_account_id       = null
        hyper_v_generation       = null
        os_type                  = null
        disk_lun                 = tostring(disk.lun)
        disk_caching             = disk.caching
        attachment_create_option = "Attach"
      }
    }
  }
}

module "ctags" {
  source = "github.com/hmcts/terraform-module-common-tags"

  builtFrom   = var.builtFrom
  environment = var.env
  product     = var.product
}

data "azurerm_subnet" "subnets" {
  for_each             = local.virtual_machines
  name                 = "mcol-${each.value.subnet_name}-${var.env}"
  virtual_network_name = "vnet-${local.env_map[var.env]}-ext-01"
  resource_group_name  = "ExternalSpoke-rg"
}

data "azurerm_key_vault" "vault" {
  name                = "mcol-kv-${var.env}"
  resource_group_name = local.resource_group_name
}

data "azurerm_backup_policy_vm" "policy" {
  name                = "mcol-daily-bp-${var.env}"
  recovery_vault_name = "mcol-rsv-${var.env}"
  resource_group_name = local.resource_group_name
}

data "azurerm_storage_account" "xdr_storage" {
  provider            = azurerm.DTS-CFTPTL-INTSVC
  name                = "cftptlintsvc"
  resource_group_name = "core-infra-intsvc-rg"
}
