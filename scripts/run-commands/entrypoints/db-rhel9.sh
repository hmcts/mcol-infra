#!/usr/bin/env bash
# entrypoints/db-rhel9.sh — combined run command for the permanent Oracle 19c
# VMs (mcol-db-vm01/02, RHEL 9). Concatenate the component scripts in the
# order given by local.db_rhel9_script_files in components/vm and place this
# file last; do not run it standalone.

mcol_main() {
  # Azure Managed Run Command passes parameters as positional arguments, in
  # the order of the parameter / protected_parameter blocks in
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

mcol_main "$@"
