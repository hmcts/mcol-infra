#!/usr/bin/env bash
set -euo pipefail
# set-swap-space.sh — idempotently configures a swapfile on the OS disk.
#
# Replaces the legacy `set-swap-space` Ansible role, which configured waagent
# resource-disk swap. The LLD SKUs (Dsv6 / Esv5) have no local temporary disk
# for waagent to use, so the swapfile lives on the root filesystem instead.
# waagent is not touched. Ensure the OS disk has headroom for SWAP_SIZE_MB.
#
# Can be executed directly or concatenated with other mcol run-command
# scripts and driven from an entrypoint (set_swap_space_main).
#
# Parameters (exported as environment variables, or passed positionally as
# Azure Run Command does: $1=SWAP_SIZE_MB, $2=SWAP_FILE; exported values win):
#   SWAP_SIZE_MB  Size of the swapfile in MB (default 10240, the legacy MCOL
#                 web/app-layer value; the data layer used 16384)
#   SWAP_FILE     Swapfile path (default /swapfile)

log() { echo "[mcol-run-command] $*"; }
die() { echo "[mcol-run-command] ERROR: $*" >&2; exit 1; }

set_swap_space_main() {
  local SWAP_SIZE_MB="${SWAP_SIZE_MB:-${1:-10240}}"
  local SWAP_FILE="${SWAP_FILE:-${2:-/swapfile}}"

  [[ "$SWAP_SIZE_MB" =~ ^[1-9][0-9]{0,8}$ ]] || die "SWAP_SIZE_MB must be a positive integer"
  local want_bytes=$((SWAP_SIZE_MB * 1024 * 1024))

  # swapfile size is the file size minus the 4KiB swap header page.
  local active=0
  if swapon --noheadings --show=NAME | grep -qxF -- "$SWAP_FILE"; then active=1; fi

  if [[ -f "$SWAP_FILE" && "$(stat -c %s "$SWAP_FILE")" -eq "$want_bytes" ]]; then
    log "$SWAP_FILE already ${SWAP_SIZE_MB}MB"
  else
    if [[ "$active" -eq 1 ]]; then swapoff "$SWAP_FILE"; active=0; fi
    rm -f "$SWAP_FILE"
    log "creating ${SWAP_SIZE_MB}MB swapfile $SWAP_FILE"
    (umask 077
     fallocate -l "${SWAP_SIZE_MB}M" "$SWAP_FILE" 2>/dev/null \
       || dd if=/dev/zero of="$SWAP_FILE" bs=1M count="$SWAP_SIZE_MB" status=none)
  fi
  chmod 600 "$SWAP_FILE"

  if [[ "$active" -eq 0 ]]; then
    # An inactive file may be uninitialised (e.g. an interrupted earlier run),
    # so always (re)write the swap signature before enabling it.
    mkswap "$SWAP_FILE" >/dev/null
    swapon "$SWAP_FILE"
    log "enabled swap on $SWAP_FILE"
  fi

  local fstab_line="${SWAP_FILE} none swap sw 0 0"
  # Enforce the exact line: drop any existing entry for this swapfile (which
  # might carry e.g. noauto), then append the desired one if it differs.
  if [[ "$(awk -v f="$SWAP_FILE" '$1 !~ /^#/ && $1 == f' /etc/fstab)" != "$fstab_line" ]]; then
    local tmp_fstab
    tmp_fstab="$(mktemp)"
    awk -v f="$SWAP_FILE" '$1 ~ /^#/ || $1 != f' /etc/fstab > "$tmp_fstab"
    printf '%s\n' "$fstab_line" >> "$tmp_fstab"
    cat "$tmp_fstab" > /etc/fstab
    rm -f "$tmp_fstab"
    log "fstab: set entry for $SWAP_FILE"
  fi

  swapon --noheadings --show=NAME | grep -qxF -- "$SWAP_FILE" || die "swap is not active on $SWAP_FILE"
  swapon --show
  log "set-swap-space complete"
}

# Self-execution guard (see mount-drives.sh).
if [[ -z "${MCOL_COMBINED:-}" && "${BASH_SOURCE[0]}" == "$0" ]]; then
  set_swap_space_main "$@"
fi
