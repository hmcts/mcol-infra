module "core-infra" {
  source      = "git::https://github.com/hmcts/terraform-module-dlrm-core-infra.git?ref=main"
  env         = var.env
  project     = var.product
  common_tags = module.ctags.common_tags

  storage_account_firewall_subnet_ids = [for subnet in data.azurerm_subnet.subnets : subnet.id]
}
