#!/usr/bin/env bash
# entrypoints/docker-host.sh — combined run command for the web and
# application Docker hosts (mcol-web-vm01/02, mcol-app-vm01/02, Ubuntu 22.04).
# These VMs need no Oracle or data-disk configuration. The legacy playbook
# mounted the build share and configured waagent resource-disk swap, which
# set-swap-space.sh restores now that the SKUs have a temporary disk.
# Concatenate the component scripts in the order given by
# local.docker_host_script_files in components/vm and place this file last;
# do not run it standalone.

mcol_main() {
  # Azure Managed Run Command passes parameters as positional arguments, in
  # the order of the parameter / protected_parameter blocks in
  # components/vm/30-run-commands.tf (public first, then protected); map them
  # to the names the component scripts read. Already-set variables win.
  if [[ -z "${SWAP_SIZE_MB:-}" && $# -ge 1 ]]; then SWAP_SIZE_MB="${1}"; fi
  export SWAP_SIZE_MB
  if [[ -z "${STORAGE_ACCOUNT_NAME:-}" && $# -ge 2 ]]; then STORAGE_ACCOUNT_NAME="${2}"; fi
  export STORAGE_ACCOUNT_NAME
  if [[ -z "${FILE_SHARE:-}" && $# -ge 3 ]]; then FILE_SHARE="${3}"; fi
  export FILE_SHARE
  if [[ -z "${STORAGE_ACCOUNT_KEY:-}" && $# -ge 4 ]]; then STORAGE_ACCOUNT_KEY="${4}"; fi
  export STORAGE_ACCOUNT_KEY
  log "=== mcol docker host configuration start ==="
  log "step 1/2: mounting Azure Files share"
  mount_azure_fileshare_main
  log "step 2/2: configuring waagent resource-disk swap"
  set_swap_space_main
  log "=== mcol docker host configuration complete ==="
}

mcol_main "$@"
