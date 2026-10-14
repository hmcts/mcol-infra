#!/usr/bin/env bash
# entrypoints/dbmig-rhel7.sh — combined run command for the temporary Oracle
# migration VM (mcol-dbmig-vm01, RHEL 7.9). Concatenate the component scripts
# in the order given by local.dbmig_rhel7_script_files in components/vm and
# place this file last; do not run it standalone.

mcol_main() {
  log "=== mcol migration db (rhel 7) configuration start ==="
  log "step 1/4: mounting data disks"
  mount_drives_main
  log "step 2/4: mounting Azure Files share"
  mount_azure_fileshare_main
  log "step 3/4: configuring waagent swap"
  set_swap_space_main
  log "step 4/4: applying oracle prerequisites"
  oracle_prereqs_main
  log "=== mcol migration db (rhel 7) configuration complete ==="
}

mcol_main
