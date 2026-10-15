#!/usr/bin/env bash
# entrypoints/db-rhel9.sh — combined run command for the permanent Oracle 19c
# VMs (mcol-db-vm01/02, RHEL 9). Concatenate the component scripts in the
# order given by local.db_rhel9_script_files in components/vm and place this
# file last; do not run it standalone.

mcol_main() {
  # Azure Run Command passes parameters as positional arguments, in the order
  # of the parameter / protected_parameter blocks in
  # components/vm/30-run-commands.tf (public first, then protected); map them
  # to the names the component scripts read. Already-set variables win.
  if [[ -z "${MOUNTS:-}" && $# -ge 1 ]]; then MOUNTS="${1}"; fi
  export MOUNTS
  if [[ -z "${SWAP_SIZE_MB:-}" && $# -ge 2 ]]; then SWAP_SIZE_MB="${2}"; fi
  export SWAP_SIZE_MB
  if [[ -z "${STORAGE_ACCOUNT_NAME:-}" && $# -ge 3 ]]; then STORAGE_ACCOUNT_NAME="${3}"; fi
  export STORAGE_ACCOUNT_NAME
  if [[ -z "${FILE_SHARE:-}" && $# -ge 4 ]]; then FILE_SHARE="${4}"; fi
  export FILE_SHARE
  if [[ -z "${STORAGE_ACCOUNT_KEY:-}" && $# -ge 5 ]]; then STORAGE_ACCOUNT_KEY="${5}"; fi
  export STORAGE_ACCOUNT_KEY
  log "=== mcol db (rhel 9) configuration start ==="
  log "step 1/6: growing LVM volumes for /opt and /var"
  grow_rhel_lvs_main
  log "step 2/6: mounting data disks"
  if [[ -n "${MOUNTS:-}" ]]; then
    mount_drives_main
  else
    log "no data-disk mount paths configured — skipping mount-drives"
  fi
  log "step 3/6: configuring waagent resource-disk swap"
  set_swap_space_main
  log "step 4/6: mounting Azure Files share"
  mount_azure_fileshare_main
  log "step 5/6: applying oracle prerequisites"
  oracle_prereqs_main
  log "step 6/6: disabling host firewall"
  disable_firewall_main
  log "=== mcol db (rhel 9) configuration complete ==="
}

mcol_main "$@"
