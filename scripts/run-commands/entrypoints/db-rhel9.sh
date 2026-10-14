#!/usr/bin/env bash
# entrypoints/db-rhel9.sh — combined run command for the permanent Oracle 19c
# VMs (mcol-db-vm01/02, RHEL 9). Concatenate the component scripts in the
# order given by local.db_rhel9_script_files in components/vm and place this
# file last; do not run it standalone.

mcol_main() {
  log "=== mcol db (rhel 9) configuration start ==="
  log "step 1/5: mounting data disks"
  mount_drives_main
  log "step 2/5: mounting Azure Files share"
  mount_azure_fileshare_main
  log "step 3/5: configuring waagent swap"
  set_swap_space_main
  log "step 4/5: applying oracle prerequisites"
  oracle_prereqs_main
  log "step 5/5: disabling host firewall"
  disable_firewall_main
  log "=== mcol db (rhel 9) configuration complete ==="
}

mcol_main
