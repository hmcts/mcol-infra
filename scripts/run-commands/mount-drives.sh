#!/usr/bin/env bash
set -euo pipefail
# mount-drives.sh — idempotent port of the `mount-drives` Ansible role.
#
# Formats (only if unformatted), creates mount points and persistently mounts
# data disks. Safe to re-run: filesystems are probed with blkid before any
# mkfs, so existing data is never touched.
#
# Can be executed directly (via Azure Run Command on its own) or concatenated
# with other mcol run-command scripts and driven from an entrypoint — the
# work happens in mount_drives_main, invoked by the self-execution guard at
# the bottom of this file when run standalone.
#
# Parameters (passed to Azure Run Command as name=value pairs, or exported):
#   MOUNTS    Required. Semicolon-separated list of
#             <device>:<mount-path>[:<fstype>[:<opts>]]
#             Defaults when omitted: fstype=ext4, opts=defaults,nofail
#             Legacy MCOL data layer example:
#             MOUNTS="/dev/sdc:/opt/moj;/dev/sdd:/u01;/dev/sde:/u02;/dev/sdf:/backup"
#   DIR_MODE  Mode for created mount-point directories (default 0777, matching
#             the Ansible role's ugo+rwx).
#
# Devices under /dev/disk/azure/scsi1/lun<N> are recommended over /dev/sdX
# letters, which can change across reboots.

log() { echo "[mcol-run-command] $*"; }
die() { echo "[mcol-run-command] ERROR: $*" >&2; exit 1; }

# Idempotently ensure <device> <path> <fstype> <opts> 0 0 is the only fstab
# entry for <path>. Sets md_fstab_changed=1 when fstab was rewritten.
md_ensure_fstab_entry() {
  local src="$1" path="$2" fstype="$3" opts="$4"
  md_fstab_changed=0
  local tmp
  tmp="$(mktemp)"
  # Drop any existing (commented or not) entry whose mount point is $path,
  # then append the desired entry.
  awk -v mp="$path" '$1 ~ /^#/ || $2 != mp' /etc/fstab > "$tmp"
  printf '%s %s %s %s 0 0\n' "$src" "$path" "$fstype" "$opts" >> "$tmp"
  if ! cmp -s "$tmp" /etc/fstab; then
    cat "$tmp" > /etc/fstab
    md_fstab_changed=1
    log "fstab: updated entry for $path ($src)"
  else
    log "fstab: entry for $path already correct"
  fi
  rm -f "$tmp"
}

mount_drives_main() {
  local MOUNTS="${MOUNTS:-}"
  local DIR_MODE="${DIR_MODE:-0777}"
  # stat reports modes without the leading zero (0777 -> "777")
  local DIR_MODE_OCTAL="${DIR_MODE#0}"

  [[ -n "$MOUNTS" ]] || die "MOUNTS is not set"

  local entry src path fstype opts current_mode current_src existing
  local -a md_specs
  IFS=';' read -ra md_specs <<< "$MOUNTS"
  for entry in "${md_specs[@]}"; do
    [[ -n "$entry" ]] || continue
    IFS=':' read -r src path fstype opts <<< "$entry"
    [[ -n "${src:-}" && -n "${path:-}" ]] || die "bad MOUNTS entry '$entry' (need at least device:path)"
    fstype="${fstype:-ext4}"
    opts="${opts:-defaults,nofail}"

    [[ -b "$src" ]] || die "$src is not a block device on this VM"

    if findmnt -rn -M "$path" >/dev/null 2>&1; then
      # On a rerun this path is the mounted filesystem's root, not the hidden
      # mount-point directory. Leave the filesystem's permissions untouched.
      log "$path is already a mount point; leaving filesystem permissions unchanged"
    else
      if [[ ! -d "$path" ]]; then
        mkdir -p "$path"
        chmod "$DIR_MODE" "$path"
        log "created mount point $path (mode $DIR_MODE)"
      else
        current_mode="$(stat -c '%a' "$path")"
        if [[ "$current_mode" != "$DIR_MODE_OCTAL" ]]; then
          chmod "$DIR_MODE" "$path"
          log "adjusted mode of $path to $DIR_MODE"
        fi
      fi
    fi

    if ! blkid "$src" >/dev/null 2>&1; then
      log "no filesystem on $src — creating $fstype"
      mkfs -t "$fstype" "$src"
    else
      existing="$(blkid -o value -s TYPE "$src")"
      [[ "$existing" == "$fstype" ]] || die "$src already has a $existing filesystem, refusing to create $fstype"
      log "$src already formatted as $fstype"
    fi

    md_ensure_fstab_entry "$src" "$path" "$fstype" "$opts"

    current_src="$(findmnt -rn -M "$path" -o SOURCE 2>/dev/null || true)"
    # findmnt reports the resolved device (/dev/sdX), not the
    # /dev/disk/azure/... symlink we were given, so compare resolved paths.
    if [[ -n "$current_src" && "$(readlink -f "$current_src")" == "$(readlink -f "$src")" ]]; then
      if [[ "$md_fstab_changed" -eq 1 ]]; then
        # fstab options changed; apply them to the live mount.
        mount -o remount "$path" || die "failed to remount $path with updated options"
        log "$path remounted to apply updated fstab options"
      else
        log "$path already mounted from $src"
      fi
    else
      if [[ -n "$current_src" ]]; then
        log "$path mounted from unexpected source $current_src — remounting from $src"
        umount "$path" || die "failed to unmount $path"
      fi
      mount "$path"
      log "mounted $src on $path"
    fi
  done

  log "mount-drives complete"
}

# Self-execution guard: when this file is run directly (Azure Run Command on
# its own) execute the main function; when concatenated ahead of an
# entrypoint the entrypoint calls mount_drives_main instead.
if [[ -z "${MCOL_COMBINED:-}" && "${BASH_SOURCE[0]}" == "$0" ]]; then
  mount_drives_main "$@"
fi
