locals {
  env_map = {
    "stg"  = "nle"
    "prod" = "prod"
  }
}

module "ctags" {
  source = "github.com/hmcts/terraform-module-common-tags"

  builtFrom   = var.builtFrom
  environment = var.env
  product     = var.product
}

data "azurerm_subnet" "subnets" {
  for_each             = toset(["Web", "App", "Data"])
  name                 = "MCOL-${each.key}-${upper(local.env_map[var.env])}"
  virtual_network_name = "vnet-${local.env_map[var.env]}-ext-01"
  resource_group_name  = "ExternalSpoke-rg"
}
