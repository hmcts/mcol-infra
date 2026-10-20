#!/usr/bin/env bash
# entrypoints/docker-host.sh — combined run command for the web and
# application Docker hosts (mcol-web-vm01/02, mcol-app-vm01/02, Ubuntu 22.04).
# These VMs need no Oracle or data-disk configuration. The legacy playbook
# mounted the build share and configured resource-disk swap, which
# set-swap-space.sh restores now that the SKUs have a temporary disk.
# Concatenate the component scripts in the order given by
# local.docker_host_script_files in components/vm and place this file last;
# do not run it standalone.

mcol_main() {
  # Azure Managed Run Command sets named parameter / protected_parameter
  # blocks in components/vm/30-run-commands.tf as environment variables of the
  # same name, while az vm run-command invoke --parameters passes positional
  # arguments (in block order: public first, then protected). Support both;
  # already-set environment variables win.
  if [[ -z "${SWAP_SIZE_MB:-}" && $# -ge 1 ]]; then SWAP_SIZE_MB="${1}"; fi
  export SWAP_SIZE_MB
  if [[ -z "${STORAGE_ACCOUNT_NAME:-}" && $# -ge 2 ]]; then STORAGE_ACCOUNT_NAME="${2}"; fi
  export STORAGE_ACCOUNT_NAME
  if [[ -z "${FILE_SHARE:-}" && $# -ge 3 ]]; then FILE_SHARE="${3}"; fi
  export FILE_SHARE
  if [[ -z "${STORAGE_ACCOUNT_KEY:-}" && $# -ge 4 ]]; then STORAGE_ACCOUNT_KEY="${4}"; fi
  export STORAGE_ACCOUNT_KEY
  log "=== mcol docker host configuration start ==="
  log "step 1/2: configuring resource-disk swap (mcol-resource-swap.service)"
  set_swap_space_main
  log "step 2/2: mounting Azure Files share"
  mount_azure_fileshare_main
  log "=== mcol docker host configuration complete ==="
}

mcol_main "$@"
