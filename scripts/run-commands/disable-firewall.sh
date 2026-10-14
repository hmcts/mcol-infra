#!/usr/bin/env bash
set -euo pipefail
# disable-firewall.sh — idempotent port of the `disable-firewall` Ansible role.
#
# Stops and disables firewalld. Network-level access control on the MCOL
# estate is enforced by Azure NSGs instead, so the host firewall is not
# needed. Safe to re-run; exits cleanly if firewalld is not installed.
#
# Can be executed directly or concatenated with other mcol run-command
# scripts and driven from an entrypoint (disable_firewall_main).
#
# No parameters.

log() { echo "[mcol-run-command] $*"; }

disable_firewall_main() {
  if ! systemctl list-unit-files firewalld.service >/dev/null 2>&1; then
    log "firewalld is not installed — nothing to do"
    return 0
  fi

  if systemctl is-active --quiet firewalld; then
    systemctl stop firewalld
    log "firewalld stopped"
  else
    log "firewalld already stopped"
  fi

  if systemctl is-enabled --quiet firewalld; then
    systemctl disable firewalld
    log "firewalld disabled"
  else
    log "firewalld already disabled"
  fi

  log "disable-firewall complete"
}

# Self-execution guard (see mount-drives.sh).
if [[ -z "${MCOL_COMBINED:-}" && "${BASH_SOURCE[0]}" == "$0" ]]; then
  disable_firewall_main "$@"
fi
