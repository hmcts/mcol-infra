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
| `grow-rhel-lvs.sh` | — (not an Ansible port) | Grows the LVs behind `/opt` and `/var` to the minimum sizes the VM extensions need; mount-driven so it works on both RHEL 7 and RHEL 9 layouts |
| `oracle-prereqs-rhel9.sh` | `oracle-config-rhel9` | Oracle 19c prerequisites for EL 9 (packages, `oinstall`/`dba` groups, `oracle` user, sysctl, limits.d, PAM, `/etc/profile`) |
| `oracle-prereqs-rhel7.sh` | `oracle-config-rhel7` | As above for EL 7, plus the firewalld ICMP/port rules the RHEL 7 role applied |
| `disable-firewall.sh` | `disable-firewall` | Stops and disables `firewalld`; NSGs enforce network policy |
| `mount-drives.sh` | `mount-drives` | Formats (only if unformatted) and persistently mounts data disks |
| `set-swap-space.sh` | `set-swap-space` | Installs `mcol-resource-swap.service`, which keeps the temp disk at `/mnt/resource` with a swapfile on every boot; must run before `mount-azure-fileshare.sh` because the share mounts inside `/mnt`, which the swap step may unmount |
| `mount-azure-fileshare.sh` | `mount-azure-fileshare` | Mounts the legacy `storheritage003/build` share over CIFS on each MCOL VM |

The Oracle scripts refuse to run on the wrong major OS version, so the RHEL 7
and RHEL 9 variants cannot be applied to each other's VMs by mistake.

## Which scripts for which VM

| VM type | Base image | Scripts |
| ------- | ---------- | ------- |
| `mcol-db-vm01/02` (Oracle 19c primary/standby) | RHEL 9.6 | combined `db-rhel9` run command (wired): `grow-rhel-lvs` → `mount-drives` → `set-swap-space` → `mount-azure-fileshare` → `oracle-prereqs-rhel9` → `disable-firewall` |
| `mcol-dbmig-vm01` (temporary 12c restore/upgrade) | RHEL 7.9 | combined `dbmig-rhel7` run command (wired): `grow-rhel-lvs` → `mount-drives` → `set-swap-space` → `mount-azure-fileshare` → `oracle-prereqs-rhel7` |
| `mcol-web/app-vm01/02` (Docker hosts) | Ubuntu 22.04 | combined `docker-host` run command (wired): `set-swap-space` → `mount-azure-fileshare` |

Swap is a swapfile on the local temporary (resource) disk at
`/mnt/resource/swapfile`, as in the legacy estate, but it is no longer
delegated to waagent. On these cloud-init marketplace images cloud-init and
waagent both manage the temp disk; after a deallocate/redeploy Azure presents a
fresh NTFS disk that cloud-init remounts at `/mnt`, and waagent would then put
swap at `/mnt/swapfile`. Instead, `set-swap-space.sh` installs
`mcol-resource-swap.service` (helper `/usr/local/sbin/mcol-resource-swap`,
size in `/etc/default/mcol-resource-swap`) as the single owner of the temp
disk. At every boot — after cloud-init, before network mounts such as
`/mnt/build` — it moves the disk from `/mnt` to `/mnt/resource` (dropping
cloud-init's `/mnt` fstab entry), formats it as ext4 if fresh, and recreates and
enables the swapfile. waagent's handling is disabled (`ResourceDisk.Format=n`,
`ResourceDisk.EnableSwap=n`), and the agent is never restarted from inside the
Run Command; the helper is simply run once immediately for the current boot.
Every SKU in this design has a local temporary disk (`Standard_D2ds_v5`,
`Standard_D4ds_v5`, and the policy-exempted `Standard_E4-2ds_v5` on the
database VMs). The script also removes an OS-disk `/swapfile` left behind by
the earlier swapfile-based version of this script.

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
`grow-rhel-lvs` (RHEL only) + `mount-drives` + `set-swap-space` + `mount-azure-fileshare` + `oracle-prereqs-<rhel>` (+ `disable-firewall`
on RHEL 9) — assembled in Terraform with `file()` + `join()` from
`entrypoints/_prologue.sh`, the step scripts, and a per-type entrypoint last:

| Combined script | VMs | Steps |
| --------------- | --- | ----- |
| `entrypoints/db-rhel9.sh` | `mcol-db-vm01/02` (RHEL 9.6) | grow LVs → mount drives → swap → Azure Files → Oracle prereqs → disable firewall |
| `entrypoints/dbmig-rhel7.sh` | `mcol-dbmig-vm01` (RHEL 7.9) | grow LVs → mount drives → swap → Azure Files → Oracle prereqs |
| `entrypoints/docker-host.sh` | `mcol-web/app-vm01/02` (Ubuntu 22.04) | swap → Azure Files |

The scripts are function-based: each defines a `*_main` and only self-executes
when run directly (the `_prologue.sh` marker suppresses that in the combined
context), so concatenation runs each step exactly once, in entrypoint order.

### RHEL LVM sizing and the Dynatrace extension

The Azure RHEL 7.9 and 9.6 marketplace images ship a small fixed rootvg
layout. When the OS disk is created larger (64 GiB in this design),
cloud-init grows the partition and the PV but **not** the LVs, so the VG ends
up with tens of GiB free while `/opt` (RHEL 7's `optlv`, 2 GiB; on RHEL 9
`/opt` lives on the 2 GiB `rootlv` — that image has no `optlv`) has only
~1.6 GiB. The Dynatrace OneAgent installer needs 1.72 GiB free on `/opt` just
to start and aborts with installer exit code 6, which surfaces as
`VMExtensionProvisioningError` in Terraform. Ubuntu images have no separate
`/opt` volume and a full-size root, so only the RHEL VMs are affected.

`grow-rhel-lvs.sh` fixes this: it resolves the LV backing `/opt` and `/var`
with `findmnt` (so one code path covers both image layouts), skips anything
not LVM-backed, and grows undersized volumes with `lvextend -r` (XFS resizes
online; it never shrinks). It is the first step of both RHEL chains.

Ordering caveat: run commands only execute after the whole VM module — and
hence the Dynatrace extension — has been applied, so on a **fresh RHEL VM the
extension would fail on the first apply**, the run command would then grow the
volumes, and re-applying the `vm` component would converge. To avoid that
chicken-and-egg failure, the OneAgent extension is gated behind the
`install_dynatrace_oneagent` flag (default `false` in
`components/vm/11-inputs-optional.tf`). A from-scratch first deploy runs with
the flag off (set `install_dynatrace_oneagent = false` in the environment
tfvars), lets the run commands grow `/opt`, then flips the flag back to true
and re-applies — the extension then installs cleanly on its first attempt.
Alternatively, a VM whose `/opt` has already been grown (or one you pre-grow
with a one-off before or while the VM component is applied) can simply keep
the flag set to true:

```bash
az vm run-command invoke --subscription DTS-HERITAGE-EXTSVC-STG \
  -g mcol-rg-stg -n mcol-dbmig-vm01-stg \
  --command-id RunShellScript \
  --scripts @scripts/run-commands/grow-rhel-lvs.sh
```

The DB run commands receive `MOUNTS` (lun-based, derived from each VM's
`data_disks` `mount_path`s, mirroring the legacy PMCOL data layer, pending CGI
DBA confirmation) and `SWAP_SIZE_MB=16384` as parameters. All run commands
receive the legacy share name and share path as public parameters and the
storage account key as a protected parameter. The key must be supplied to
Terraform as the secure variable `TF_VAR_storheritage003_build_share_key` in
the per-environment variable group (named after the service connection, e.g.
`DTS-HERITAGE-EXTSVC-STG`);
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

The yum-based CIFS install and RHEL 7 Oracle prerequisite installs exclude
`rhui-rhel-7-server-dotnet-rhui-rpms` for those transactions only. This unrelated
.NET repository can return HTTP 400 for its metadata and block the migration
VM setup before the Azure Files share is mounted. Required package/repository
failures still fail setup; the VM's persistent repository configuration is
unchanged. If other RHUI repositories also fail, check the image's RHUI client
configuration using [Microsoft's RHUI troubleshooting guide](https://learn.microsoft.com/en-us/troubleshoot/azure/virtual-machines/linux/troubleshoot-linux-rhui-certificate-issues).

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
| `set-swap-space.sh` | `SWAP_SIZE_MB` |
| `grow-rhel-lvs.sh` | `OPT_MIN_SIZE_GIB`, `VAR_MIN_SIZE_GIB` |

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
| `SWAP_SIZE_MB` | `10240` | Size of `/mnt/resource/swapfile` in MiB, persisted to `/etc/default/mcol-resource-swap` (legacy data layer used `16384`) |

### `mount-azure-fileshare.sh`

| Parameter | Default | Purpose |
| --------- | ------- | ------- |
| `STORAGE_ACCOUNT_NAME` | — (required) | Storage account name |
| `STORAGE_ACCOUNT_KEY` | — (required) | Storage account key — pass via `protected_parameter`, never as a public Run Command parameter |
| `FILE_SHARE` | `build` | File share name |

### `grow-rhel-lvs.sh`

| Parameter | Default | Purpose |
| --------- | ------- | ------- |
| `OPT_MIN_SIZE_GIB` | `10` | Minimum size of the LV backing `/opt` (OneAgent install + auto-update temp space) |
| `VAR_MIN_SIZE_GIB` | `16` | Minimum size of the LV backing `/var` (OneAgent runtime/datastorage, Nessus, Splunk UF, XDR) |

Volumes already at or above the minimum are left untouched; mounts not
backed by LVM are skipped with a log line.

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
