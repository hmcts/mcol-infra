# mcol-infra

## Introduction

Money Claim Online (MCOL) tech refresh infrastructure. The refresh replaces the legacy RHEL 7 OHS/WebLogic web and application servers with Ubuntu 22.04 Docker hosts running Apache, MCOL and QAS containers, and upgrades the database tier to Oracle 19c on RHEL 9.

The refreshed estate is built alongside the legacy MCOL hosts in the Heritage External Services spoke VNets (`vnet-{nle,prod}-ext-01`), in new web, app and data subnets created by this repository. The VNets, Front Door and the legacy MCOL estate (including the retained private load balancers) are managed by [hmcts/oracle-azure-infrastructure](https://github.com/hmcts/oracle-azure-infrastructure).

Resource group: `mcol-rg-{env}`
KeyVault: `mcol-kv-{env}` (VM credentials). Application secrets remain in `mcol-{env}-kv`.

## Responsibilities

| Area of Responsibility                        | Responsible Party |
| --------------------------------------------- | ----------------- |
| Azure Infrastructure                          | PlatOps           |
| Docker runtime / host patching                | PlatOps           |
| AADSSHLoginForLinux                           | PlatOps           |
| Container images and Docker Compose releases  | CGI               |
| Oracle install, Data Guard and migration      | CGI DBA team      |

## Components

| Component       | Purpose |
| --------------- | ------- |
| `core`          | Resource group, key vault, recovery services vault, daily backup policy, subnets, route table and NSGs (via `terraform-module-dlrm-core-infra`). |
| `vm`            | Web, application, Oracle and temporary migration VMs, data disks, backup protection and Entra ID SSH login. |
| `load-balancer` | Adds tech-refresh VM NICs to the backend pools of the retained web and application load balancers. |
| `rbac`          | VM login role assignments per tier, Key Vault Secrets User on the application key vault, and AcrPull for the Docker hosts. |

## Network

| Subnet          | Staging            | Production         |
| --------------- | ------------------ | ------------------ |
| mcol-web-{env}  | 10.25.249.96/27    | 10.24.249.96/27    |
| mcol-app-{env}  | 10.25.249.128/27   | 10.24.249.128/27   |
| mcol-data-{env} | 10.25.249.160/27   | 10.24.249.160/27   |

All subnets use the `mcol-rt-{env}` route table, which sends traffic to the hub firewall in the same way as the legacy `{NLE,PROD}-EXTERNAL-NONAT-RT`. Application, CaseMan and SDP access to Oracle is limited to the permanent database servers, which keeps the migration VM isolated from live traffic. NSGs are deny-by-default and only permit the flows defined in the LLD; in production the Oracle primary and standby may reach each other on 1521 for Data Guard.

## VM Details

| VM Name                    | Environments | VM SKU             | Operating System | Zone | Role |
| -------------------------- | ------------ | ------------------ | ---------------- | ---- | ---- |
| mcol-web-vm01-{env}        | stg, prod    | Standard D2s v6    | Ubuntu 22.04     | 1    | Apache container |
| mcol-web-vm02-{env}        | stg, prod    | Standard D2s v6    | Ubuntu 22.04     | 2    | Apache container |
| mcol-app-vm01-{env}        | stg, prod    | Standard D4s v6    | Ubuntu 22.04     | 1    | MCOL + QAS containers |
| mcol-app-vm02-{env}        | stg, prod    | Standard D4s v6    | Ubuntu 22.04     | 2    | MCOL + QAS containers |
| mcol-db-vm01-{env}         | stg, prod    | Standard E4-2s v5  | RHEL 9.6         | 1    | Oracle 19c (prod: Data Guard primary) |
| mcol-db-vm02-prod          | prod         | Standard E4-2s v5  | RHEL 9.6         | 2    | Oracle 19c Data Guard standby |
| mcol-dbmig-vm01-{env}      | stg, prod    | Standard E4-2s v5  | RHEL 7.9         | 1    | Temporary Oracle 12c restore and upgrade |

All VMs have a 64 GiB Premium SSD OS disk. Production Oracle data disks mirror the legacy PMCOL database servers (128, 512 and 32 GiB Premium SSD plus a 512 GiB Standard SSD export volume on each node); Pre-Production uses the same LUN layout sized for the pre-production estate. Final capacity, IOPS and mount points remain subject to CGI DBA team confirmation per the LLD.

## Load balancer cutover

Traffic cutover and rollback are controlled by backend pool membership on the retained load balancers (`{n,p}mcol-pri-lb-01` web, `{n,p}mcol-pri-lb-02` application):

1. Add the new VM names to `load_balancer_backends` in the environment tfvars and apply the `load-balancer` component.
2. Remove the legacy NICs from `nic_names` / `nic_names_web` in oracle-azure-infrastructure.
3. Roll back by reversing these steps.

## Temporary migration VMs

`mcol-dbmig-vm01-{env}` sits in the data subnet in zone 1, so its upgraded data disk can be attached to the zone 1 primary. It accepts SSH and Oracle traffic from the legacy MCOL data subnet for the migration; the matching rule on the legacy `MCOL-DATA-NSG` is in oracle-azure-infrastructure (`mcol-tr-migration-allow-in`). Remove the VM from `db_vms`, and both rules, once migration is complete.

## VM Access

The VMs can be accessed over the HMCTS Jumpboxes or bastions using the az CLI with the SSH extension. They use Azure Entra ID to authenticate, so use `az ssh` rather than plain `ssh`. Local admin credentials are stored in `mcol-kv-{env}`.

Admin login (with sudo) is granted per tier via the `rbac` component to `DTS Platform Operations` (`SC` in prod) and the legacy V1/CGI admin groups carried over from the Ansible sudoers setup (`aadDcAdminsV1`/`aadDcAdminsCGI`): `dcd_heritage_nle_mgmt_admins_v1`/`_cgi` in stg, `DTS Heritage Mgmt Prod V1 Admins`/`DTS Heritage Mgmt Prod CGI Admins` in prod.

## Backup Policy

All VMs are backed up daily at 01:00 UTC to `mcol-rsv-{env}` using the core module's default policy. RTO and RPO targets have not yet been approved by the MCOL service owner. Oracle backup and recovery (RMAN) is owned by the CGI DBA team.

## Additional Software

The following software is installed on the VMs using virtual machine extensions:

- Docker (web and application VMs)
- AAD SSH Login for Linux
- Azure Monitor
- Dynatrace One Agent
- Splunk Universal Forwarder
- Tenable Nessus
- Cortex XDR

## Post-deployment VM configuration

Idempotent Run Command scripts ported from the legacy estate's setup Ansible
(oracle-azure-infrastructure) live in `scripts/run-commands/`. They cover the
per-tier, per-base-image configuration that the legacy Packer images used to
carry — Oracle prerequisites for RHEL 7 and RHEL 9, data-disk mounting,
waagent swap and firewall handling. The `vm` component creates one
`azurerm_virtual_machine_run_command` per VM that needs post-deployment
setup: the full combined script on the database VMs, and a share-mount plus
swap script on the Ubuntu web/app Docker hosts. The legacy Azure Files share
key is passed to each command through a protected parameter sourced from the
secure `TF_VAR_fileshare_storage_account_key` pipeline variable. The separate
XDR run command is created inside the virtual-machines module. See
`scripts/run-commands/README.md` for the per-VM-type matrix and usage.

## Documentation

MCOL Tech Refresh - Infrastructure LLD.
