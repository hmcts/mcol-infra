output "XDR_TAGS" {
  value = { for k, v in local.virtual_machines : k => module.virtual-machines[k].xdr_tags if v.install_xdr_agent || v.install_xdr_collector }
}
