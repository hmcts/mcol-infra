#!/usr/bin/env bash
# entrypoints/dbmig-rhel7.sh — combined run command for the temporary Oracle
# migration VM (mcol-dbmig-vm01, RHEL 7.9). Concatenate the component scripts
# in the order given by local.dbmig_rhel7_script_files in components/vm and
# place this file last; do not run it standalone.

mcol_main() {
  # Azure Managed Run Command passes parameters as positional arguments, in
  # the order of the parameter / protected_parameter blocks in
  # components/vm/30-run-commands.tf (public first, then protected); map them
  # to the names the component scripts read. Already-set variables win.
  if [[ -z "${MOUNTS:-}" && $# -ge 1 ]]; then MOUNTS="${1}"; fi
  export MOUNTS
  if [[ -z "${STORAGE_ACCOUNT_NAME:-}" && $# -ge 2 ]]; then STORAGE_ACCOUNT_NAME="${2}"; fi
  export STORAGE_ACCOUNT_NAME
  if [[ -z "${FILE_SHARE:-}" && $# -ge 3 ]]; then FILE_SHARE="${3}"; fi
  export FILE_SHARE
  if [[ -z "${STORAGE_ACCOUNT_KEY:-}" && $# -ge 4 ]]; then STORAGE_ACCOUNT_KEY="${4}"; fi
  export STORAGE_ACCOUNT_KEY
  log "=== mcol migration db (rhel 7) configuration start ==="
  log "step 1/3: mounting data disks"
  mount_drives_main
  log "step 2/3: mounting Azure Files share"
  mount_azure_fileshare_main
  log "step 3/3: applying oracle prerequisites"
  oracle_prereqs_main
  log "=== mcol migration db (rhel 7) configuration complete ==="
}

mcol_main "$@"
