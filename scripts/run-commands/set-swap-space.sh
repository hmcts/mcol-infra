#!/usr/bin/env bash
set -euo pipefail
# set-swap-space.sh — idempotently configures waagent resource-disk swap on
# the VM's local temporary disk.
#
# Ports the legacy `set-swap-space` Ansible role: write the ResourceDisk.*
# settings into /etc/waagent.conf, unmount the resource disk and restart the
# agent, which then formats the disk, mounts it at /mnt/resource and creates
# the swapfile. Requires a SKU with a local temporary disk — every VM SKU in
# this design (D2ds_v5 / D4ds_v5 / E4-2ds_v5) has one. The agent recreates
# the swapfile at every boot, so nothing is written to /etc/fstab.
#
# Also removes the OS-disk /swapfile and its fstab entry left by the earlier
# swapfile-based version of this script.
#
# Can be executed directly or concatenated with other mcol run-command
# scripts and driven from an entrypoint (set_swap_space_main).
#
# Parameters (exported as environment variables, or passed positionally as
# Azure Run Command does: $1=SWAP_SIZE_MB; exported values win):
#   SWAP_SIZE_MB  ResourceDisk.SwapSizeMB (default 10240, the legacy MCOL
#                 web/app-layer value; the data layer used 16384)

log() { echo "[mcol-run-command] $*"; }
die() { echo "[mcol-run-command] ERROR: $*" >&2; exit 1; }

# Ansible lineinfile semantics: set "key=value", replacing any existing
# "key=..." line or appending at the end of the file. Returns 0 if the file
# changed, 1 if it already held the exact line.
waagent_conf_set() {
  local key="$1" value="$2" path="/etc/waagent.conf"
  grep -qx "${key}=${value}" "$path" && return 1
  if grep -q "^${key}=" "$path"; then
    sed -i "s|^${key}=.*|${key}=${value}|" "$path"
  else
    printf '%s=%s\n' "$key" "$value" >> "$path"
  fi
  log "waagent.conf: set ${key}=${value}"
  return 0
}

set_swap_space_main() {
  local SWAP_SIZE_MB="${SWAP_SIZE_MB:-${1:-10240}}"
  [[ "$SWAP_SIZE_MB" =~ ^[1-9][0-9]{0,8}$ ]] || die "SWAP_SIZE_MB must be a positive integer"

  local mount_point="/mnt/resource"
  local swap_file="${mount_point}/swapfile"

  local changed=0
  if waagent_conf_set "ResourceDisk.Format" "y"; then changed=1; fi
  if waagent_conf_set "ResourceDisk.Filesystem" "ext4"; then changed=1; fi
  if waagent_conf_set "ResourceDisk.MountPoint" "$mount_point"; then changed=1; fi
  if waagent_conf_set "ResourceDisk.EnableSwap" "y"; then changed=1; fi
  if waagent_conf_set "ResourceDisk.SwapSizeMB" "$SWAP_SIZE_MB"; then changed=1; fi

  # Drop the OS-disk swapfile and its fstab entry left by the previous
  # version of this script.
  local old_swap="/swapfile"
  if swapon --noheadings --show=NAME | grep -qxF -- "$old_swap"; then
    swapoff "$old_swap"
    log "disabled swap on $old_swap"
  fi
  if [[ -f "$old_swap" ]]; then
    rm -f "$old_swap"
    log "removed leftover OS-disk swapfile $old_swap"
  fi
  if awk -v f="$old_swap" '$1 !~ /^#/ && $1 == f { found=1 } END { exit !found }' /etc/fstab; then
    local tmp_fstab
    tmp_fstab="$(mktemp)"
    awk -v f="$old_swap" '$1 ~ /^#/ || $1 != f' /etc/fstab > "$tmp_fstab"
    cat "$tmp_fstab" > /etc/fstab
    rm -f "$tmp_fstab"
    log "fstab: removed entry for $old_swap"
  fi

  # The agent only (re)creates the swapfile when it mounts the resource disk,
  # so force the format/mount path as the legacy role did whenever the
  # configuration changed or swap is not currently active.
  if [[ "$changed" -eq 1 ]] || ! swapon --noheadings --show=NAME | grep -qxF -- "$swap_file"; then
    if mountpoint -q /mnt; then umount /mnt; fi
    if mountpoint -q "$mount_point"; then umount "$mount_point"; fi

    local agent_service
    if systemctl list-unit-files 2>/dev/null | awk '{print $1}' | grep -q "^walinuxagent.service"; then
      agent_service="walinuxagent"
    elif systemctl list-unit-files 2>/dev/null | awk '{print $1}' | grep -q "^waagent.service"; then
      agent_service="waagent"
    else
      die "no walinuxagent/waagent systemd unit found"
    fi
    log "restarting ${agent_service} to remount the resource disk and create swap"
    systemctl restart "$agent_service"

    local waited=0
    until swapon --noheadings --show=NAME | grep -qxF -- "$swap_file"; do
      if (( waited >= 120 )); then
        die "swap is not active on $swap_file after ${waited}s"
      fi
      sleep 5
      waited=$((waited + 5))
    done
    log "enabled swap on $swap_file"
  else
    log "$swap_file already active"
  fi

  swapon --show
  log "set-swap-space complete"
}

# Self-execution guard (see mount-drives.sh).
if [[ -z "${MCOL_COMBINED:-}" && "${BASH_SOURCE[0]}" == "$0" ]]; then
  set_swap_space_main "$@"
fi
