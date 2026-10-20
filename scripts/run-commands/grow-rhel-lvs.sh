#!/usr/bin/env bash
set -euo pipefail
# grow-rhel-lvs.sh — grow the LVM volumes behind the mount points that the VM
# extensions (Dynatrace OneAgent in particular) need space on.
#
# Why this exists: the Azure RHEL 7.9 and 9.6 marketplace images ship a fixed
# rootvg layout (RHEL 7: 2 GiB optlv for /opt, 8 GiB varlv for /var; RHEL 9:
# no optlv at all — /opt sits on the 2 GiB rootlv, 10 GiB varlv). When the OS
# disk is created larger (64 GiB here) cloud-init grows the partition and the
# PV but never the LVs, so the VG ends up with tens of GiB of free extents
# while /opt still has only ~1.6 GiB free. The OneAgent installer requires
# 1.72 GiB just to start and aborts with exit code 6 ("Not enough free
# space"), which surfaces in Terraform as VMExtensionProvisioningError.
# Ubuntu images have no separate /opt volume and a full-size root, which is
# why only the RHEL VMs were affected.
#
# The script is mount-driven rather than name-driven so one code path works
# on both layouts: for each mount point, `df --output=source` resolves the
# single filesystem backing that exact path (optlv on RHEL 7, rootlv on RHEL
# 9), lvextend -r grows it to the minimum size and resizes the XFS filesystem
# online (XFS never shrinks, so this is safe on live mounts). findmnt is not
# used because `--target` also lists submounts such as /opt/moj. Filesystems
# not backed by LVM — e.g. a data disk, or a non-LVM image — are skipped with
# a log line.
#
# Can be executed directly (az vm run-command invoke --scripts
# @scripts/run-commands/grow-rhel-lvs.sh — this is how to unblock a VM whose
# Dynatrace extension failed before the combined run commands were created)
# or concatenated with the other mcol run-command scripts and driven from an
# entrypoint (grow_rhel_lvs_main), where it is the first step of both RHEL
# chains.
#
# Parameters (exported as environment variables, or passed positionally as
# Azure Run Command does: $1=OPT_MIN_SIZE_GIB, $2=VAR_MIN_SIZE_GIB; exported
# values win):
#   OPT_MIN_SIZE_GIB  Minimum size of the LV backing /opt (default 10).
#                     Covers OneAgent's 1.72 GiB install check, ~1.3 GiB
#                     installed size and ~2.6 GiB of auto-update temp space.
#   VAR_MIN_SIZE_GIB  Minimum size of the LV backing /var (default 16).
#                     OneAgent keeps runtime and datastorage under
#                     /var/lib/dynatrace (~5 GiB steady state) and this tier
#                     also writes Nessus, Splunk UF and Cortex XDR data there.

log() { echo "[mcol-run-command] $*"; }
die() { echo "[mcol-run-command] ERROR: $*" >&2; exit 1; }

# Idempotently grow the LV backing mount point $1 to at least $2 GiB.
gl_ensure_lv_min_size() {
  local mp="$1" min_gib="$2" src lv size_mib target_mib delta
  # df reports exactly the filesystem backing this path (not submounts),
  # whether or not $mp is itself a mount point: /opt/moj mounted on top of
  # /opt does not obscure it.
  src="$( { df --output=source "$mp" 2>/dev/null | tail -n1 | tr -d '[:space:]'; } || true)"
  if [[ -z "$src" ]]; then
    log "could not resolve the filesystem backing $mp — nothing to grow"
    return 0
  fi
  # Non-LVM sources make lvs exit non-zero; treat an empty result as
  # "not LVM-backed". lvs pads --noheadings output with spaces, so trim.
  lv="$( { lvs --noheadings -o lv_path "$src" 2>/dev/null | head -n1 | tr -d '[:space:]'; } || true)"
  if [[ -z "$lv" ]]; then
    log "$mp backed by $src, which is not an LVM volume — skipping"
    return 0
  fi
  # Output form varies by lvm2 version ("2048.00" or "2048 m"); the first
  # digit run is the integer part of the size in the requested units.
  size_mib="$(lvs --noheadings --nosuffix --units m -o lv_size "$lv" 2>/dev/null | grep -oE '[0-9]+' | head -n1)"
  [[ "$size_mib" =~ ^[0-9]+$ ]] || die "could not read current size of $lv"
  target_mib=$(( min_gib * 1024 ))
  if (( size_mib >= target_mib )); then
    log "$lv (backing $mp) already ${size_mib} MiB (>= ${target_mib} MiB) — no change"
    return 0
  fi
  delta=$(( target_mib - size_mib ))
  log "growing $lv (backing $mp) by ${delta} MiB to reach at least ${min_gib} GiB"
  # -r resizes the (XFS) filesystem online in the same step.
  lvextend -r -L "+${delta}m" "$lv"
}

grow_rhel_lvs_main() {
  local OPT_MIN_SIZE_GIB="${OPT_MIN_SIZE_GIB:-${1:-10}}"
  local VAR_MIN_SIZE_GIB="${VAR_MIN_SIZE_GIB:-${2:-16}}"
  [[ "$OPT_MIN_SIZE_GIB" =~ ^[1-9][0-9]{0,6}$ ]] || die "OPT_MIN_SIZE_GIB must be a positive integer (GiB)"
  [[ "$VAR_MIN_SIZE_GIB" =~ ^[1-9][0-9]{0,6}$ ]] || die "VAR_MIN_SIZE_GIB must be a positive integer (GiB)"

  command -v df >/dev/null || die "df not available"
  command -v lvs >/dev/null || die "lvs not available — is LVM2 installed?"
  command -v lvextend >/dev/null || die "lvextend not available — is LVM2 installed?"

  gl_ensure_lv_min_size /opt "$OPT_MIN_SIZE_GIB"
  gl_ensure_lv_min_size /var "$VAR_MIN_SIZE_GIB"

  log "grow-rhel-lvs complete"
}

# Self-execution guard (see mount-drives.sh).
if [[ -z "${MCOL_COMBINED:-}" && "${BASH_SOURCE[0]}" == "$0" ]]; then
  grow_rhel_lvs_main "$@"
fi
