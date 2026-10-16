#!/usr/bin/env bash
set -euo pipefail
# set-swap-space.sh — idempotently configures swap on the VM's local
# temporary (resource) disk at /mnt/resource/swapfile.
#
# Replaces the legacy `set-swap-space` Ansible role, which delegated this to
# waagent (ResourceDisk.* in /etc/waagent.conf). On the cloud-init based
# marketplace images used here that is unreliable: cloud-init and waagent both
# manage the temp disk, and after a deallocate/redeploy Azure presents a fresh
# NTFS disk that cloud-init reformats and remounts at /mnt, after which
# waagent puts the swapfile at /mnt/swapfile instead of /mnt/resource. It also
# required restarting waagent from inside the Run Command, which can kill the
# Run Command handler itself.
#
# Instead this script installs a small boot-time systemd unit,
# mcol-resource-swap.service, which is the single owner of the temp disk. At
# every boot — after cloud-init has run and before network (CIFS) mounts such
# as /mnt/build — it:
#   * moves the temp disk from /mnt to /mnt/resource if cloud-init mounted it
#     there (and drops cloud-init's /mnt fstab entry);
#   * formats the disk as ext4 if it is fresh (NTFS/unformatted);
#   * (re)creates /mnt/resource/swapfile at the configured size and enables it.
# waagent's own resource-disk handling is disabled (ResourceDisk.Format=n,
# ResourceDisk.EnableSwap=n) so the two never race. The script then runs the
# same helper immediately, so swap is active on the current boot without a
# reboot or an agent restart. Nothing swap-related is written to /etc/fstab.
#
# Requires a SKU with a local temporary disk — every VM SKU in this design
# (D2ds_v5 / D4ds_v5 / E4-2ds_v5) has one.
#
# Also removes the OS-disk /swapfile and its fstab entry left by the earlier
# swapfile-based version of this script.
#
# Can be executed directly or concatenated with other mcol run-command
# scripts and driven from an entrypoint (set_swap_space_main).
#
# Parameters (exported as environment variables, or passed positionally as
# Azure Run Command does: $1=SWAP_SIZE_MB; exported values win):
#   SWAP_SIZE_MB  Swapfile size in MiB (default 10240, the legacy MCOL
#                 web/app-layer value; the data layer used 16384)

log() { echo "[mcol-run-command] $*"; }
die() { echo "[mcol-run-command] ERROR: $*" >&2; exit 1; }

# Ansible lineinfile semantics: set "key=value", replacing any existing
# "key=..." line or appending at the end of the file. No-op if the file does
# not exist (waagent not installed).
waagent_conf_set() {
  local key="$1" value="$2" path="/etc/waagent.conf"
  [[ -f "$path" ]] || return 0
  grep -qx "${key}=${value}" "$path" && return 0
  if grep -q "^${key}=" "$path"; then
    sed -i "s|^${key}=.*|${key}=${value}|" "$path"
  else
    printf '%s=%s\n' "$key" "$value" >> "$path"
  fi
  log "waagent.conf: set ${key}=${value}"
}

# Write $3 to $1 with mode $2 only if the content differs. Returns 0 if the
# file changed, 1 if it was already up to date.
swap_write_if_changed() {
  local path="$1" mode="$2" content="$3"
  if [[ -f "$path" ]] && [[ "$(cat "$path")" == "$content" ]]; then
    chmod "$mode" "$path"
    return 1
  fi
  mkdir -p "$(dirname "$path")"
  printf '%s\n' "$content" > "$path"
  chmod "$mode" "$path"
  log "wrote $path"
  return 0
}

# Boot-time helper installed at /usr/local/sbin/mcol-resource-swap. Kept
# self-contained (it runs outside the Run Command at every boot).
read -r -d '' MCOL_RESOURCE_SWAP_HELPER <<'HELPER' || true
#!/usr/bin/env bash
# mcol-resource-swap — installed by the mcol set-swap-space run command.
# Mounts the Azure temporary disk at /mnt/resource and enables
# /mnt/resource/swapfile. Idempotent; runs at every boot via
# mcol-resource-swap.service. Configuration: /etc/default/mcol-resource-swap.
set -euo pipefail

log() { echo "[mcol-resource-swap] $*"; }
die() { echo "[mcol-resource-swap] ERROR: $*" >&2; exit 1; }

SWAP_SIZE_MB=10240
# shellcheck disable=SC1091
[[ -f /etc/default/mcol-resource-swap ]] && . /etc/default/mcol-resource-swap
[[ "$SWAP_SIZE_MB" =~ ^[1-9][0-9]{0,8}$ ]] || die "SWAP_SIZE_MB must be a positive integer"

MOUNT_POINT=/mnt/resource
SWAP_FILE="${MOUNT_POINT}/swapfile"

swap_active() { swapon --noheadings --show=NAME | grep -qxF -- "$1"; }

resolve_resource_partition() {
  local candidate src
  # udev symlinks from WALinuxAgent (/dev/disk/azure) and cloud-init
  # (/dev/disk/cloud) identify the temp disk unambiguously.
  for candidate in \
    /dev/disk/azure/resource-part1 \
    /dev/disk/cloud/azure_resource-part1; do
    if [[ -b "$candidate" ]]; then readlink -f "$candidate"; return 0; fi
  done
  # Fall back to wherever it is currently mounted.
  for candidate in "$MOUNT_POINT" /mnt; do
    src="$(findmnt -rn -M "$candidate" -o SOURCE 2>/dev/null || true)"
    if [[ -n "$src" && -b "$src" ]]; then readlink -f "$src"; return 0; fi
  done
  # Unpartitioned temp disk: use the whole device.
  for candidate in /dev/disk/azure/resource /dev/disk/cloud/azure_resource; do
    if [[ -b "$candidate" ]]; then readlink -f "$candidate"; return 0; fi
  done
  return 1
}

# Wait briefly for udev to publish the temp disk symlinks at early boot.
res_part=""
for _ in $(seq 1 30); do
  if res_part="$(resolve_resource_partition)"; then break; fi
  sleep 2
done
[[ -n "$res_part" ]] || die "unable to locate the Azure temporary resource disk"
log "temporary resource disk partition: $res_part"

# Drop cloud-init's fstab entry mounting the temp disk at /mnt (cloud-init
# rewrites it after a redeploy presents a fresh disk).
if awk '$1 !~ /^#/ && $2 == "/mnt" { found=1 } END { exit !found }' /etc/fstab; then
  tmp_fstab="$(mktemp)"
  awk '$1 ~ /^#/ || $2 != "/mnt"' /etc/fstab > "$tmp_fstab"
  cat "$tmp_fstab" > /etc/fstab
  rm -f "$tmp_fstab"
  systemctl daemon-reload 2>/dev/null || true
  log "fstab: removed /mnt entry for the temporary disk"
fi

# Move the temp disk off /mnt if cloud-init (or anything else) mounted it
# there. Only touch /mnt if it really is the temp disk.
mnt_src="$(findmnt -rn -M /mnt -o SOURCE 2>/dev/null || true)"
submounts=()
if [[ -n "$mnt_src" && "$(readlink -f "$mnt_src")" == "$res_part" ]]; then
  if swap_active /mnt/swapfile; then swapoff /mnt/swapfile; fi
  # Recursive: a share mounted at /mnt/build on top of the temp disk would
  # otherwise keep /mnt busy. Those submounts are remounted from fstab below.
  mapfile -t submounts < <(findmnt -rn -R -o TARGET /mnt | tail -n +2)
  umount -R /mnt
  log "unmounted temporary disk from /mnt"
fi

mkdir -p "$MOUNT_POINT"
if ! mountpoint -q "$MOUNT_POINT"; then
  fstype="$(blkid -p -s TYPE -o value "$res_part" 2>/dev/null || true)"
  # Azure delivers the temp disk NTFS-formatted. It is ephemeral by
  # definition, so anything other than ext4/xfs is safe to reformat.
  if [[ "$fstype" != "ext4" && "$fstype" != "xfs" ]]; then
    log "formatting $res_part as ext4 (was: ${fstype:-none})"
    mkfs.ext4 -F -q "$res_part"
  fi
  mount -o defaults,nofail "$res_part" "$MOUNT_POINT"
  log "mounted $res_part at $MOUNT_POINT"
fi

want_bytes=$(( SWAP_SIZE_MB * 1024 * 1024 ))
have_bytes="$(stat -c %s "$SWAP_FILE" 2>/dev/null || echo 0)"
if swap_active "$SWAP_FILE" && [[ "$have_bytes" -eq "$want_bytes" ]]; then
  log "$SWAP_FILE already active (${SWAP_SIZE_MB}M)"
else
  if swap_active "$SWAP_FILE"; then swapoff "$SWAP_FILE"; fi
  make_swapfile() {
    rm -f "$SWAP_FILE"
    if [[ "${1:-}" == "dd" ]] || ! fallocate -l "${SWAP_SIZE_MB}M" "$SWAP_FILE" 2>/dev/null; then
      dd if=/dev/zero of="$SWAP_FILE" bs=1M count="$SWAP_SIZE_MB" status=none
    fi
    chmod 0600 "$SWAP_FILE"
    mkswap -f "$SWAP_FILE" >/dev/null
  }
  log "creating ${SWAP_SIZE_MB}M swapfile at $SWAP_FILE"
  make_swapfile
  if ! swapon "$SWAP_FILE" 2>/dev/null; then
    log "swapon rejected the fallocate'd file; recreating with dd"
    make_swapfile dd
    swapon "$SWAP_FILE"
  fi
  log "enabled swap on $SWAP_FILE"
fi

# Re-mount (from fstab) any submounts, e.g. the /mnt/build share, that the
# recursive unmount above took down. Mount points are recreated on the root
# filesystem now that /mnt is no longer the temp disk.
for target in ${submounts[@]+"${submounts[@]}"}; do
  mkdir -p "$target"
  if mount "$target"; then
    log "remounted $target"
  else
    log "WARNING: failed to remount $target"
  fi
done
HELPER

read -r -d '' MCOL_RESOURCE_SWAP_UNIT <<'UNIT' || true
[Unit]
Description=MCOL: mount Azure temporary disk at /mnt/resource and enable swap
# Early-boot unit: after local filesystems and cloud-init (which may have
# reformatted/mounted a fresh temp disk at /mnt), and before network
# filesystems such as the /mnt/build CIFS share. DefaultDependencies=no keeps
# it out of basic.target/sysinit.target ordering so no cycles can form.
# mnt.mount is listed explicitly because cloud-init's /mnt entry is nofail, so
# local-fs.target does not wait for it (ordering only; no-op if absent).
DefaultDependencies=no
After=local-fs.target cloud-init.service mnt.mount
Before=remote-fs-pre.target shutdown.target
Wants=remote-fs-pre.target
Conflicts=shutdown.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/sbin/mcol-resource-swap

[Install]
WantedBy=multi-user.target
UNIT

set_swap_space_main() {
  local SWAP_SIZE_MB="${SWAP_SIZE_MB:-${1:-10240}}"
  [[ "$SWAP_SIZE_MB" =~ ^[1-9][0-9]{0,8}$ ]] || die "SWAP_SIZE_MB must be a positive integer"

  # Hand the temp disk exclusively to mcol-resource-swap.service: stop waagent
  # from formatting/mounting it or creating swap at boot. waagent reads this
  # at its next start, so no restart is needed (or wanted — restarting the
  # agent from inside a Run Command can kill the Run Command handler).
  waagent_conf_set "ResourceDisk.Format" "n"
  waagent_conf_set "ResourceDisk.EnableSwap" "n"

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

  # Install the boot-time helper, its configuration and the systemd unit.
  local unit_changed=0
  swap_write_if_changed /etc/default/mcol-resource-swap 0644 "SWAP_SIZE_MB=${SWAP_SIZE_MB}" || true
  swap_write_if_changed /usr/local/sbin/mcol-resource-swap 0755 "$MCOL_RESOURCE_SWAP_HELPER" || true
  if swap_write_if_changed /etc/systemd/system/mcol-resource-swap.service 0644 "$MCOL_RESOURCE_SWAP_UNIT"; then
    unit_changed=1
  fi
  if [[ "$unit_changed" -eq 1 ]]; then systemctl daemon-reload; fi
  if ! systemctl is-enabled --quiet mcol-resource-swap.service 2>/dev/null; then
    systemctl enable mcol-resource-swap.service
    log "enabled mcol-resource-swap.service"
  fi

  # Apply now for the current boot. Run the helper directly (rather than via
  # systemctl start) so its output lands in the Run Command log. This step
  # runs before the Azure Files share is mounted (see the entrypoints).
  /usr/local/sbin/mcol-resource-swap

  swapon --show
  log "set-swap-space complete"
}

# Self-execution guard (see mount-drives.sh).
if [[ -z "${MCOL_COMBINED:-}" && "${BASH_SOURCE[0]}" == "$0" ]]; then
  set_swap_space_main "$@"
fi
