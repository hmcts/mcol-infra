# Post-deployment configuration of the VMs via Azure Run Command.
#
# Each VM that needs post-deployment setup gets a single
# azurerm_virtual_machine_run_command whose script is the concatenation of
# the idempotent per-step scripts in scripts/run-commands (ported from the
# legacy setup Ansible) plus the per-type entrypoint. The combined script is
# assembled here with file() + join() so the per-step scripts remain the
# single source of truth.
#
# Note: Run Command only executes again when the script or parameters change.
# Re-applying or drift-detecting does not re-run the scripts on the VM; to
# force a re-run, change the script/parameters or use `az vm run-command`.
#
# This is separate from the XDR run command: that one is created inside the
# virtual-machines module by terraform-module-vm-bootstrap (as a
# RunCommandLinux extension) and is unaffected by the resources below.

locals {
  run_command_dir = "${path.module}/../../scripts/run-commands"

  # Concatenation order matters: the prologue marks the combined context,
  # the entrypoint (last) invokes the per-step mains in order.
  db_rhel9_script_files = [
    "entrypoints/_prologue.sh",
    "mount-drives.sh",
    "mount-azure-fileshare.sh",
    "set-swap-space.sh",
    "oracle-prereqs-rhel9.sh",
    "disable-firewall.sh",
    "entrypoints/db-rhel9.sh",
  ]
  dbmig_rhel7_script_files = [
    "entrypoints/_prologue.sh",
    "mount-drives.sh",
    "mount-azure-fileshare.sh",
    "set-swap-space.sh",
    "oracle-prereqs-rhel7.sh",
    "disable-firewall.sh",
    "entrypoints/dbmig-rhel7.sh",
  ]
  # The web/app Docker hosts (Ubuntu 22.04) need no Oracle or data-disk
  # configuration; the legacy setup playbook also mounted the build share on
  # this tier. Swap is waagent resource-disk swap on the local temporary
  # disk, as in the legacy estate — every VM SKU in this design
  # (D2ds_v5 / D4ds_v5 / E4-2ds_v5) has a temporary disk for it.
  docker_host_script_files = [
    "entrypoints/_prologue.sh",
    "mount-azure-fileshare.sh",
    "set-swap-space.sh",
    "entrypoints/docker-host.sh",
  ]
  db_rhel9_script    = join("\n", [for f in local.db_rhel9_script_files : file("${local.run_command_dir}/${f}")])
  dbmig_rhel7_script = join("\n", [for f in local.dbmig_rhel7_script_files : file("${local.run_command_dir}/${f}")])
  docker_host_script = join("\n", [for f in local.docker_host_script_files : file("${local.run_command_dir}/${f}")])

  # Data-disk mounts per VM, built from the data_disks that declare a
  # mount_path (layout mirrors the legacy PMCOL data layer, pending CGI DBA
  # confirmation per the README). LUN-based device paths are used because
  # /dev/sdX letters can be reordered across reboots; sorting by LUN keeps the
  # string (and therefore the run command) stable between plans.
  db_data_disk_mounts = {
    for name, vm in var.db_vms : name => join(";", [
      for disk in sort([for d in vm.data_disks : format("%03d", d.lun) if d.mount_path != null]) :
      "/dev/disk/azure/scsi1/lun${tonumber(disk)}:${[for d in vm.data_disks : d.mount_path if d.lun == tonumber(disk)][0]}"
    ])
  }

  # The migration VM is RHEL 7.9 (image sku 79-gen2); the permanent Oracle
  # servers are RHEL 9.6 (96-gen2).
  db_swap_size_mb = "16384"
  # Legacy MCOL web/app layers both used a 10240MB swapfile.
  docker_host_swap_size_mb = "10240"

  db_run_command_script = { for name, vm in var.db_vms : name => substr(vm.image.sku, 0, 1) == "7" ? local.dbmig_rhel7_script : local.db_rhel9_script }
  db_run_command_name   = { for name, vm in var.db_vms : name => substr(vm.image.sku, 0, 1) == "7" ? "mcol-dbmig-rhel7-config" : "mcol-db-rhel9-config" }
}

resource "azurerm_virtual_machine_run_command" "db_config" {
  for_each = var.db_vms

  name               = local.db_run_command_name[each.key]
  location           = var.location
  virtual_machine_id = module.virtual-machines[each.key].vm_id

  source {
    script = local.db_run_command_script[each.key]
  }

  parameter {
    name  = "MOUNTS"
    value = local.db_data_disk_mounts[each.key]
  }
  parameter {
    name  = "SWAP_SIZE_MB"
    value = local.db_swap_size_mb
  }
  parameter {
    name  = "STORAGE_ACCOUNT_NAME"
    value = "storheritage003"
  }
  parameter {
    name  = "FILE_SHARE"
    value = "build"
  }
  protected_parameter {
    name  = "STORAGE_ACCOUNT_KEY"
    value = var.fileshare_storage_account_key
  }

  # Package installs run one at a time and can be slow on first boot. The
  # provider has no timeout_in_seconds argument; it forwards the Terraform
  # create timeout to Azure as the run command's timeoutInSeconds.
  timeouts {
    create = "60m"
  }

  tags = module.ctags.common_tags

  # Wait for the whole VM module (including data disk attachments, which are
  # created inside it and not reflected in the vm_id output) so the
  # mount-drives step finds its devices on first run. An instance-specific
  # depends_on is not possible, so this waits on every VM.
  depends_on = [module.virtual-machines]
}

resource "azurerm_virtual_machine_run_command" "docker_host_config" {
  for_each = merge(var.web_vms, var.app_vms)

  name               = "mcol-docker-host-config"
  location           = var.location
  virtual_machine_id = module.virtual-machines[each.key].vm_id

  source {
    script = local.docker_host_script
  }

  parameter {
    name  = "SWAP_SIZE_MB"
    value = local.docker_host_swap_size_mb
  }
  parameter {
    name  = "STORAGE_ACCOUNT_NAME"
    value = "storheritage003"
  }
  parameter {
    name  = "FILE_SHARE"
    value = "build"
  }
  protected_parameter {
    name  = "STORAGE_ACCOUNT_KEY"
    value = var.fileshare_storage_account_key
  }

  timeouts {
    create = "30m"
  }

  tags = module.ctags.common_tags

  depends_on = [module.virtual-machines]
}
