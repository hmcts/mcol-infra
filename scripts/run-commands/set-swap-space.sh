#!/usr/bin/env bash
set -euo pipefail
# set-swap-space.sh — idempotent port of the `set-swap-space` Ansible role.
#
# Configures the Azure Linux Agent (waagent) resource-disk swap settings in
# /etc/waagent.conf. The agent is only restarted when the configuration
# actually changes, so re-runs are no-ops.
#
# Can be executed directly or concatenated with other mcol run-command
# scripts and driven from an entrypoint (set_swap_space_main).
#
# Parameters (passed to Azure Run Command as name=value pairs, or exported):
#   SWAP_SIZE_MB          Size of the swapfile in MB (default 10240, the
#                         legacy MCOL web/app-layer value; data layer used 16384)
#   RESOURCE_DISK_FORMAT  y|n (default y)
#   RESOURCE_DISK_FS      Filesystem for the resource disk (default ext4)
#   RESOURCE_DISK_MOUNT   Resource disk mount point (default /mnt/resource)
#   ENABLE_SWAP           y|n (default y)

log() { echo "[mcol-run-command] $*"; }
die() { echo "[mcol-run-command] ERROR: $*" >&2; exit 1; }

# Idempotently set key=value in $ss_conf; sets ss_changed=1 when a write occurs.
ss_set_kv() {
  local key="$1" value="$2"
  if grep -q "^${key}=" "$ss_conf"; then
    if [[ "$(grep "^${key}=" "$ss_conf" | tail -1 | cut -d= -f2- | tr -d '[:space:]')" == "$value" ]]; then
      log "$ss_conf: $key already $value"
      return 0
    fi
    sed -i "s|^${key}=.*|${key}=${value}|" "$ss_conf"
  else
    printf '%s=%s\n' "$key" "$value" >> "$ss_conf"
  fi
  log "$ss_conf: set $key=$value"
  ss_changed=1
}

set_swap_space_main() {
  local SWAP_SIZE_MB="${SWAP_SIZE_MB:-10240}"
  local RESOURCE_DISK_FORMAT="${RESOURCE_DISK_FORMAT:-y}"
  local RESOURCE_DISK_FS="${RESOURCE_DISK_FS:-ext4}"
  local RESOURCE_DISK_MOUNT="${RESOURCE_DISK_MOUNT:-/mnt/resource}"
  local ENABLE_SWAP="${ENABLE_SWAP:-y}"

  ss_conf=/etc/waagent.conf
  [[ -f "$ss_conf" ]] || die "$ss_conf not found — is the Azure Linux Agent installed?"

  local ss_changed=0
  ss_set_kv ResourceDisk.Format     "$RESOURCE_DISK_FORMAT"
  ss_set_kv ResourceDisk.Filesystem "$RESOURCE_DISK_FS"
  ss_set_kv ResourceDisk.MountPoint "$RESOURCE_DISK_MOUNT"
  ss_set_kv ResourceDisk.EnableSwap "$ENABLE_SWAP"
  ss_set_kv ResourceDisk.SwapSizeMB "$SWAP_SIZE_MB"

  if [[ "$ss_changed" -eq 0 ]]; then
    log "no changes — waagent swap already configured (${SWAP_SIZE_MB}MB)"
    return 0
  fi

  # Configuration changed: unmount the resource disk (old and new mount
  # points) and restart the agent so it recreates the swapfile.
  local mp
  for mp in "$RESOURCE_DISK_MOUNT" /mnt; do
    if findmnt -rn -M "$mp" >/dev/null 2>&1; then
      umount "$mp" || log "warning: could not unmount $mp (agent restart will handle it)"
    fi
  done

  local restarted=0 svc
  for svc in waagent walinuxagent; do
    # `systemctl cat` fails for units that do not exist (list-unit-files
    # returns success even for pattern matches nothing, which would pick
    # "waagent" on Ubuntu where only walinuxagent exists).
    if systemctl cat "${svc}.service" >/dev/null 2>&1; then
      systemctl restart "$svc"
      log "restarted $svc"
      restarted=1
      break
    fi
  done
  [[ "$restarted" -eq 1 ]] || die "neither waagent nor walinuxagent systemd unit found"

  sleep 5
  swapon --show || true
  log "set-swap-space complete"
}

# Self-execution guard (see mount-drives.sh).
if [[ -z "${MCOL_COMBINED:-}" && "${BASH_SOURCE[0]}" == "$0" ]]; then
  set_swap_space_main "$@"
fi
