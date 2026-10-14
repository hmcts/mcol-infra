#!/usr/bin/env bash
set -euo pipefail
# oracle-prereqs-rhel7.sh — idempotent port of the `oracle-config-rhel7`
# Ansible role, for RHEL 7 hosts (e.g. mcol-dbmig-vm01, the temporary Oracle
# 12c restore/upgrade VM).
#
# Installs Oracle prerequisite packages, creates the oinstall/dba groups and
# oracle user, applies Oracle kernel parameters (sysctl), resource limits
# (limits.d), PAM pam_limits and the /etc/profile ulimits block, and opens
# the Oracle ports in firewalld.
#
# Refuses to run on anything other than EL 7 so it cannot be aimed at the
# wrong base image. Safe to re-run: every step is guarded and only changes
# state that differs.
#
# Can be executed directly or concatenated with other mcol run-command
# scripts and driven from an entrypoint (oracle_prereqs_main).
#
# No parameters.

log() { echo "[mcol-run-command] $*"; }
die() { echo "[mcol-run-command] ERROR: $*" >&2; exit 1; }

# --- helpers -----------------------------------------------------------------
o_write_if_changed() {
  local path="$1" tmp
  tmp="$(mktemp)"
  cat > "$tmp"
  if [[ -f "$path" ]] && cmp -s "$tmp" "$path"; then
    log "unchanged: $path"
    rm -f "$tmp"
    return 0
  fi
  cat "$tmp" > "$path"
  rm -f "$tmp"
  log "wrote: $path"
}

o_ensure_line() {
  local file="$1" line="$2"
  if grep -qFx "$line" "$file" 2>/dev/null; then
    log "present: $line"
  else
    printf '%s\n' "$line" >> "$file"
    log "added to $file: $line"
  fi
}

o_ensure_group() {
  local name="$1" gid="$2"
  if getent group "$name" >/dev/null; then
    log "group $name already exists"
  else
    if getent group "$gid" >/dev/null; then
      die "gid $gid already belongs to group $(getent group "$gid" | cut -d: -f1); cannot create $name"
    fi
    groupadd -g "$gid" "$name"
    log "created group $name (gid $gid)"
  fi
}

o_ensure_user() {
  local name="$1" uid="$2" grp
  if ! id "$name" >/dev/null 2>&1; then
    if getent passwd "$uid" >/dev/null; then
      die "uid $uid already belongs to user $(getent passwd "$uid" | cut -d: -f1); cannot create $name"
    fi
    useradd -u "$uid" -s /bin/bash "$name"
    log "created user $name (uid $uid, primary group $name)"
  fi
  for grp in oinstall dba; do
    if ! id -nG "$name" | tr ' ' '\n' | grep -qx "$grp"; then
      usermod -aG "$grp" "$name"
      log "added $name to group $grp"
    fi
  done
}

# --- main ---------------------------------------------------------------------
oracle_prereqs_main() {
  # OS guard: refuse anything other than EL 7.
  [[ -r /etc/os-release ]] || die "cannot read /etc/os-release"
  local ID VERSION_ID el_major
  # shellcheck disable=SC1091
  source /etc/os-release
  el_major="${VERSION_ID%%.*}"
  if [[ "$ID" != "rhel" && "$ID" != "centos" ]] || [[ "$el_major" != "7" ]]; then
    die "this script is for RHEL/CentOS 7 (ID=$ID VERSION_ID=${VERSION_ID:-unknown}); use oracle-prereqs-rhel9.sh for EL 9"
  fi
  log "target OS: $ID $VERSION_ID"

  # Packages (mirrors the role's yum loop). Installed individually so one
  # unavailable package does not mask the rest; failures are collected and
  # reported at the end.
  local packages=(
    binutils
    compat-libcap1
    compat-libstdc++-33-3.2.3
    gcc
    gcc-c++
    glibc-2.17
    glibc-devel
    libaio
    libaio-devel
    libgcc
    libstdc++
    libstdc++-devel
    ksh
    make
    sysstat
    numactl
    numactl-devel
    motif
    motif-devel
    redhat-lsb
    redhat-lsb-core
    xorg-x11-server-Xorg
    xorg-x11-xauth
    xorg-x11-apps
    cpp
    glibc-headers
    mpfr
    glibc
    libXi
    libXtst
    compat-libstdc++-33.i686
    glibc.i686
    libgcc.i686
    libstdc++.i686
    cifs-utils
    glibc-devel.i686
    libaio.i686
    libaio-devel.i686
    libstdc++-devel.i686
    libXi.i686
    libXtst.i686
    realmd
    adcli
    sssd
    samba-common-tools
    krb5-workstation
    sssd-libwbclient
  )

  # Some packages (e.g. compat-libcap1, motif-devel) live in the optional
  # repo, which is disabled by default on Azure RHUI images. Enable it for these
  # installs only (a glob that matches no repo is not an error).
  log "installing ${#packages[@]} packages (yum, optional repo enabled for this run)"
  local pkg
  local -a failed=()
  for pkg in "${packages[@]}"; do
    if ! yum -y --enablerepo='*optional-rpms' install "$pkg" >/dev/null 2>&1; then
      failed+=("$pkg")
      log "warning: failed to install $pkg"
    fi
  done
  if [[ "${#failed[@]}" -gt 0 ]]; then
    die "package installation failed for: ${failed[*]} (check enabled repos, e.g. rhel-7-server-optional-rpms)"
  fi

  # Oracle groups and user
  o_ensure_group oinstall 1050
  o_ensure_group dba 1075
  o_ensure_user oracle 1100

  # Kernel parameters (role: ansible.posix.sysctl items). Delivered as a
  # sysctl.d drop-in (equivalent to the role writing /etc/sysctl.conf) so it
  # is self-contained and easy to audit.
  o_write_if_changed /etc/sysctl.d/99-mcol-oracle.conf <<'EOF'
# Oracle database kernel parameters (ported from oracle-config-rhel7)
kernel.shmmni = 4096
kernel.sem = 250 32000 100 128
kernel.shmall = 8388608
kernel.shmmax = 4294967295
fs.file-max = 6815744
fs.aio-max-nr = 1048576
net.ipv4.ip_local_port_range = 9000 65500
net.core.rmem_default = 262144
net.core.rmem_max = 4194304
net.core.wmem_default = 262144
net.core.wmem_max = 1048576
EOF

  sysctl --system >/dev/null 2>&1 || log "warning: sysctl --system reported errors (continuing; the Ansible role ignored these too)"
  log "sysctl parameters applied"

  # Resource limits (role: pam_limits items). Delivered as a limits.d drop-in,
  # equivalent to the role editing /etc/security/limits.conf.
  o_write_if_changed /etc/security/limits.d/99-mcol-oracle.conf <<'EOF'
# Oracle database resource limits (ported from oracle-config-rhel7)
oracle   soft   nofile    4096
oracle   hard   nofile    65536
oracle   soft   nproc     2047
oracle   hard   nproc     16384
oracle   soft   memlock   15099494
oracle   hard   memlock   15099494
oracle   soft   stack     10240
EOF

  o_ensure_line /etc/pam.d/login "session required pam_limits.so"

  # /etc/profile ulimits block (role: blockinfile)
  local profile=/etc/profile
  local begin="# BEGIN mcol oracle ulimits"
  local end="# END mcol oracle ulimits"
  local block_file current_block
  block_file="$(mktemp)"
  cat > "$block_file" <<EOF
$begin
if [ "\$USER" = "oracle" ]; then
    if [ "\$SHELL" = "/bin/ksh" ]; then
        ulimit -u 16384
        ulimit -n 65536
    else
        ulimit -u 16384
        ulimit -n 65536
    fi
fi
$end
EOF
  current_block="$(sed -n "/^$begin\$/,/^$end\$/p" "$profile" 2>/dev/null || true)"
  if [[ -n "$current_block" ]] && cmp -s <(printf '%s\n' "$current_block") "$block_file"; then
    log "unchanged: $profile oracle ulimits block"
  else
    sed -i "/^$begin\$/,/^$end\$/d" "$profile"
    cat "$block_file" >> "$profile"
    log "wrote: $profile oracle ulimits block"
  fi
  rm -f "$block_file"

  # Firewall (role: icmp + firewalld port tasks)
  if systemctl cat firewalld.service >/dev/null 2>&1; then
    local changed=0 port
    # Allow ICMP echo-request (requested by the oracle team for troubleshooting)
    if firewall-cmd --permanent --query-icmp-block=echo-request >/dev/null 2>&1; then
      firewall-cmd --permanent --remove-icmp-block=echo-request
      changed=1
    fi
    # Oracle-specific ports
    for port in 1159 1521 3872 4889 7788 7799 9788 9851; do
      if ! firewall-cmd --permanent --zone=public --query-port="${port}/tcp" >/dev/null 2>&1; then
        firewall-cmd --permanent --zone=public --add-port="${port}/tcp"
        changed=1
      fi
    done
    if [[ "$changed" -eq 1 ]]; then
      firewall-cmd --reload
      log "firewalld rules applied and reloaded"
    else
      log "firewalld rules already present"
    fi
  else
    log "firewalld not installed — skipping firewall configuration"
  fi

  log "oracle-prereqs-rhel7 complete"
}

# Self-execution guard (see mount-drives.sh).
if [[ -z "${MCOL_COMBINED:-}" && "${BASH_SOURCE[0]}" == "$0" ]]; then
  oracle_prereqs_main "$@"
fi
