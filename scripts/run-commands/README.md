# Run Command scripts

Idempotent shell scripts ported from the VM-setup Ansible in
[hmcts/oracle-azure-infrastructure](https://github.com/hmcts/oracle-azure-infrastructure)
(`ansible/roles/*`), for configuring the MCOL VMs via
[Azure VM Run Command](https://learn.microsoft.com/en-us/azure/virtual-machines/linux/run-command).
They replace the post-deployment Ansible steps that the legacy estate ran
from DevOps servers; the tech-refresh repo has no Ansible control plane, and
these VMs are built from marketplace images rather than the legacy Packer
base images, so this configuration is applied at run time instead.

Every script is self-contained (no shared libraries, no external downloads),
safe to re-run, and only changes state that differs from the desired end
state. Each script prints `[mcol-run-command]` log lines and exits non-zero
on failure.

## Script inventory and source mapping

| Script | Ports | Notes |
| ------ | ----- | ----- |
| `oracle-prereqs-rhel9.sh` | `oracle-config-rhel9` | Oracle 19c prerequisites for EL 9 (packages, `oinstall`/`dba` groups, `oracle` user, sysctl, limits.d, PAM, `/etc/profile`) |
| `oracle-prereqs-rhel7.sh` | `oracle-config-rhel7` | As above for EL 7, plus the firewalld ICMP/port rules the RHEL 7 role applied |
| `disable-firewall.sh` | `disable-firewall` | Stops and disables `firewalld`; NSGs enforce network policy |
| `mount-drives.sh` | `mount-drives` | Formats (only if unformatted) and persistently mounts data disks |
| `set-swap-space.sh` | `set-swap-space` | Creates and enables a swapfile on the OS disk (the LLD SKUs have no temporary disk for waagent swap) |
| `mount-azure-fileshare.sh` | `mount-azure-fileshare` | Mounts the legacy `storheritage003/build` share over CIFS on each MCOL VM |

The Oracle scripts refuse to run on the wrong major OS version, so the RHEL 7
and RHEL 9 variants cannot be applied to each other's VMs by mistake.

## Which scripts for which VM

| VM type | Base image | Scripts |
| ------- | ---------- | ------- |
| `mcol-db-vm01/02` (Oracle 19c primary/standby) | RHEL 9.6 | combined `db-rhel9` run command (wired): `mount-drives` → `mount-azure-fileshare` → `set-swap-space` → `oracle-prereqs-rhel9` → `disable-firewall` |
| `mcol-dbmig-vm01` (temporary 12c restore/upgrade) | RHEL 7.9 | combined `dbmig-rhel7` run command (wired): `mount-drives` → `mount-azure-fileshare` → `set-swap-space` → `oracle-prereqs-rhel7` |
| `mcol-web/app-vm01/02` (Docker hosts) | Ubuntu 22.04 | combined `docker-host` run command (wired): `mount-azure-fileshare` → `set-swap-space` |

Swap is a swapfile on the OS disk, not waagent resource-disk swap: the SKUs
specified by the LLD (`Standard_D2s_v6`, `Standard_D4s_v6`, `Standard_E4-2s_v5`)
have no local temporary disk. The 64 GiB OS disk must have headroom for it
(10 GiB on Docker hosts, 16 GiB on database VMs).

For the DB VMs, mount points and swap sizes remain subject to CGI DBA
confirmation per the LLD (see the main README). The legacy PMCOL data-layer
layout these scripts were ported from is a useful starting reference:

```text
/dev/sdc -> /opt/moj
/dev/sdd -> /u01
/dev/sde -> /u02
/dev/sdf -> /backup
```

## Running the scripts

### Wired in this repo (DB VMs)

`components/vm/30-run-commands.tf` creates **one**
`azurerm_virtual_machine_run_command` per database VM. Each run command's
script is the per-OS-type combination of the per-step scripts above —
`mount-drives` + `mount-azure-fileshare` + `set-swap-space` + `oracle-prereqs-<rhel>` (+ `disable-firewall`
on RHEL 9) — assembled in Terraform with `file()` + `join()` from
`entrypoints/_prologue.sh`, the step scripts, and a per-type entrypoint last:

| Combined script | VMs | Steps |
| --------------- | --- | ----- |
| `entrypoints/db-rhel9.sh` | `mcol-db-vm01/02` (RHEL 9.6) | mount drives → Azure Files → swap → Oracle prereqs → disable firewall |
| `entrypoints/dbmig-rhel7.sh` | `mcol-dbmig-vm01` (RHEL 7.9) | mount drives → Azure Files → swap → Oracle prereqs |
| `entrypoints/docker-host.sh` | `mcol-web/app-vm01/02` (Ubuntu 22.04) | Azure Files → swap |

The scripts are function-based: each defines a `*_main` and only self-executes
when run directly (the `_prologue.sh` marker suppresses that in the combined
context), so concatenation runs each step exactly once, in entrypoint order.

The DB run commands receive `MOUNTS` (lun-based, derived from each VM's
`data_disks` `mount_path`s, mirroring the legacy PMCOL data layer, pending CGI
DBA confirmation) and `SWAP_SIZE_MB=16384` as parameters. All run commands
receive the legacy share name and share path as public parameters and the
storage account key as a protected parameter. The key must be supplied to
Terraform as the secure Azure DevOps variable `TF_VAR_fileshare_storage_account_key`;
do not put it in tfvars or source control. The commands depend on the whole VM
module so data disks are attached before the mount step runs. The XDR run command is created separately inside
the virtual-machines module (`terraform-module-vm-bootstrap`) and is
unaffected. Removing a VM from `db_vms` removes its run command with it.

Because every step is idempotent, re-running against an already-configured VM
changes nothing. Note, however, that Azure only re-executes a managed run
command when its script or parameters change, so pipeline re-applies and
nightly drift detection do **not** re-run the scripts or correct drift on the
VM. To force a re-run, change the script/parameters or use the one-off
`az vm run-command invoke` flow below.

Mounts are built per VM from the `data_disks` entries in tfvars that set
`mount_path`; disks without a `mount_path` are attached but not mounted. Each
run command has a `timeout_in_seconds` (3600 for DB VMs, 1800 for Docker hosts).
The Oracle prerequisite scripts enable the CRB (RHEL 9) / optional (RHEL 7)
repos for the package installs only. The `depends_on` waits on every VM in the
module (data-disk attachments live inside it), which is coarse but safe.

### One-off via the Azure CLI

```bash
az vm run-command invoke \
  --resource-group mcol-rg-prod \
  --name mcol-db-vm01-prod \
  --command-id RunShellScript \
  --scripts @scripts/run-commands/oracle-prereqs-rhel9.sh
```

Azure Run Command passes `--parameters` values to the script as positional
arguments (`$1`, `$2`, …), not as environment variables. The standalone scripts
accept either: export the named variables, or pass values in this order
(exported variables win):

| Script | Positional order |
| ------ | ---------------- |
| `mount-drives.sh` | `MOUNTS`, `DIR_MODE` |
| `mount-azure-fileshare.sh` | `STORAGE_ACCOUNT_NAME`, `STORAGE_ACCOUNT_KEY`, `FILE_SHARE` |
| `set-swap-space.sh` | `SWAP_SIZE_MB`, `SWAP_FILE` |

The combined entrypoints used by Terraform map their own positional order (see
`entrypoints/*.sh`).

## Parameters

### `mount-drives.sh`

| Parameter | Default | Purpose |
| --------- | ------- | ------- |
| `MOUNTS` | — (required) | `device:path[:fstype[:opts]]` entries separated by `;`. Defaults: `fstype=ext4`, `opts=defaults,nofail` |
| `DIR_MODE` | `0777` | Mode for created mount points (matches the Ansible role) |

Existing filesystems are never reformatted — `blkid` is checked first and a
mismatch between the existing and requested filesystem is a hard error.

Prefer stable device paths such as `/dev/disk/azure/scsi1/lun10` over
`/dev/sdX` letters, which can be reordered across reboots.

Example (legacy PMCOL data-layer layout):

```bash
MOUNTS="/dev/disk/azure/scsi1/lun10:/opt/moj;/dev/disk/azure/scsi1/lun11:/u01;/dev/disk/azure/scsi1/lun12:/u02;/dev/disk/azure/scsi1/lun14:/backup"
```

### `set-swap-space.sh`

| Parameter | Default | Purpose |
| --------- | ------- | ------- |
| `SWAP_SIZE_MB` | `10240` | Swapfile size in MB (legacy data layer used `16384`) |
| `SWAP_FILE` | `/swapfile` | Swapfile path on the OS disk |

### `mount-azure-fileshare.sh`

| Parameter | Default | Purpose |
| --------- | ------- | ------- |
| `STORAGE_ACCOUNT_NAME` | — (required) | Storage account name |
| `STORAGE_ACCOUNT_KEY` | — (required) | Storage account key — pass via `protected_parameter`, never as a public Run Command parameter |
| `FILE_SHARE` | `build` | File share name |

## Deliberately not ported

The following Ansible content has no Run Command equivalent here, by design:

- **CIS hardening** (`cis-rhel7`, `cis-rhel7-create-partitions`,
  `ansible-lockdown.RHEL9-CIS`) — image-build-time concerns. These VMs use
  marketplace images; if CIS is required it should be a Packer/orchestrated
  image build, not a run-time script.
- **ClamAV** (`geerlingguy.clamav`, `clamav-db-download.yml`,
  `push-clamav-db.yml`, `cron-job.yml`) — antivirus is covered by the Cortex
  XDR agents installed on every VM by the VM module. The download-and-push
  master-host pattern also does not translate to per-VM Run Commands.
- **`create-users.yml` / `delete-users.yml`** — local user lifecycle is
  replaced by Entra ID SSH login (`AADSSHLoginForLinux` + the `rbac`
  component's Virtual Machine Administrator/User assignments). The legacy
  `v1admin`-driven model is retired.
- **`join-domain-rhel`** — domain join is replaced by Entra ID authentication.
  The one generally useful fragment in that role, the chrony PTP reference
  clock, is already the default on Azure RHEL marketplace images.
- **`hmcts-base-rhel7.yml` / `hmcts-base-rhel9.yml`** — Packer build
  playbooks for the legacy golden images; the equivalent per-tier run-time
  pieces are the `oracle-prereqs-*` and `disable-firewall` scripts above.
