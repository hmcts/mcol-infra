#!/usr/bin/env bash
# mount-azure-fileshare.sh — idempotent port of the `mount-azure-fileshare`
# Ansible role.
#
# Mounts an Azure Storage Account file share over CIFS/SMB with credentials
# in /etc/smbcredentials/ and a nofail fstab entry.
#
# The legacy setup playbook mounted this share on every MCOL VM. Keep it in
# the combined setup for the full migration and coexistence path.
#
# Parameters (exported as environment variables, or passed positionally as
# Azure Run Command does: $1=STORAGE_ACCOUNT_NAME, $2=STORAGE_ACCOUNT_KEY,
# $3=FILE_SHARE; exported values win):
#   STORAGE_ACCOUNT_NAME  Required. Storage account name.
#   STORAGE_ACCOUNT_KEY   Required. Storage account key (pass via the
#                         `protected_parameter` block of
#                         azurerm_virtual_machine_run_command, not as a public
#                         run-command parameter.
#   FILE_SHARE            Share name (default "build", matching the legacy role).
#
# On re-run the credentials file is rewritten if the key has rotated (the
# Ansible role only created it when missing, so rotated keys never
# propagated), and the mount is only remounted if the fstab entry changed.

set -euo pipefail

log() { echo "[mcol-run-command] $*"; }
die() { echo "[mcol-run-command] ERROR: $*" >&2; exit 1; }

ensure_cifs_utils() {
  if command -v mount.cifs >/dev/null 2>&1; then
    log "cifs-utils already installed"
    return 0
  fi

  if command -v apt-get >/dev/null 2>&1; then
    DEBIAN_FRONTEND=noninteractive apt-get -o DPkg::Lock::Timeout=300 update -y
    DEBIAN_FRONTEND=noninteractive apt-get -o DPkg::Lock::Timeout=300 install -y cifs-utils
  elif command -v dnf >/dev/null 2>&1; then
    dnf -y install cifs-utils
  elif command -v yum >/dev/null 2>&1; then
    # The Azure RHEL 7 .NET RHUI repo can fail metadata requests with HTTP
    # 400. CIFS needs no .NET packages; exclude it for this transaction only.
    # A glob also tolerates images where this repo is absent.
    yum -y --disablerepo='rhui-rhel-7-server-dotnet-rhui-rpms*' install cifs-utils
  else
    die "cannot install cifs-utils: no supported package manager found"
  fi
}

mount_azure_fileshare_main() {
STORAGE_ACCOUNT_NAME="${STORAGE_ACCOUNT_NAME:-${1:-}}"
STORAGE_ACCOUNT_KEY="${STORAGE_ACCOUNT_KEY:-${2:-}}"
FILE_SHARE="${FILE_SHARE:-${3:-build}}"

[[ -n "$STORAGE_ACCOUNT_NAME" ]] || die "STORAGE_ACCOUNT_NAME is not set"
[[ -n "$STORAGE_ACCOUNT_KEY" ]]  || die "STORAGE_ACCOUNT_KEY is not set"
  ensure_cifs_utils

MOUNT_DIR="/mnt/${FILE_SHARE}"
CRED_DIR=/etc/smbcredentials
CRED_FILE="${CRED_DIR}/${STORAGE_ACCOUNT_NAME}.cred"
REMOTE="//${STORAGE_ACCOUNT_NAME}.file.core.windows.net/${FILE_SHARE}"
CIFS_OPTS="vers=3.0,credentials=${CRED_FILE},dir_mode=0777,file_mode=0777,serverino"

mkdir -p "$MOUNT_DIR" "$CRED_DIR"
local needs_remount=0

cred_content=$'username='"${STORAGE_ACCOUNT_NAME}"$'\npassword='"${STORAGE_ACCOUNT_KEY}"
if [[ -f "$CRED_FILE" ]] && [[ "$(cat "$CRED_FILE")" == "$cred_content" ]]; then
  log "credentials file $CRED_FILE already up to date"
else
  (umask 077; printf '%s\n' "$cred_content" > "$CRED_FILE")
  needs_remount=1
  log "wrote credentials file $CRED_FILE"
fi
# Always enforce the mode, even when the content already matched.
chmod 600 "$CRED_FILE"

fstab_line="${REMOTE} ${MOUNT_DIR} cifs nofail,${CIFS_OPTS} 0 0"
# Correct only if exactly one non-comment entry references this share or mount
# point and it is the desired line (duplicates/stale entries force a rewrite).
fstab_matches="$(awk -v remote="$REMOTE" -v mp="$MOUNT_DIR" '$1 !~ /^#/ && ($1 == remote || $2 == mp)' /etc/fstab)"
if [[ "$fstab_matches" == "$fstab_line" ]]; then
  log "fstab entry already correct"
else
  # Remove any stale entry for this share or mount point (e.g. a previous
  # storage account), keeping comments, then add the desired one.
  tmp_fstab="$(mktemp)"
  awk -v remote="$REMOTE" -v mp="$MOUNT_DIR" '$1 ~ /^#/ || ($1 != remote && $2 != mp)' /etc/fstab > "$tmp_fstab"
  cat "$tmp_fstab" > /etc/fstab
  rm -f "$tmp_fstab"
  printf '%s\n' "$fstab_line" >> /etc/fstab
  needs_remount=1
  log "fstab: updated entry for $REMOTE on $MOUNT_DIR"
fi

# A pending marker survives a failed unmount/mount so the next run retries
# applying the new credentials/options even though the files now look current.
PENDING_DIR=/var/lib/mcol-run-command
PENDING_MARKER="${PENDING_DIR}/remount-fileshare-${FILE_SHARE}"
mkdir -p "$PENDING_DIR"
if [[ "$needs_remount" -eq 1 ]]; then touch "$PENDING_MARKER"; fi
[[ ! -e "$PENDING_MARKER" ]] || needs_remount=1

current_src=""
if mountpoint -q "$MOUNT_DIR"; then
  current_src="$(findmnt -rn -o SOURCE --target "$MOUNT_DIR" 2>/dev/null || awk -v mp="$MOUNT_DIR" '$2 == mp { print $1; exit }' /proc/mounts 2>/dev/null || true)"
fi
if [[ "$current_src" == "$REMOTE" && "$needs_remount" -eq 0 ]]; then
  log "$MOUNT_DIR already mounted"
else
  [[ -z "$current_src" ]] || umount "$MOUNT_DIR" || die "failed to unmount $MOUNT_DIR (will retry on next run)"
  mount "$MOUNT_DIR"
  rm -f "$PENDING_MARKER"
  log "mounted $REMOTE on $MOUNT_DIR"
fi

log "mount-azure-fileshare complete"
}

# Self-execution guard (see mount-drives.sh).
if [[ -z "${MCOL_COMBINED:-}" && "${BASH_SOURCE[0]}" == "$0" ]]; then
  mount_azure_fileshare_main "$@"
fi
