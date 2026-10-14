# mcol-infra Review — Terraform and Azure DevOps Pipeline Implementation

**Date:** 2026-10-10
**Scope:** The `mcol-infra` repository — four Terraform components (`core`, `vm`, `load-balancer`, `rbac`), environment tfvars, `azure-pipelines.yaml`, README, and repo housekeeping files.

**Reviewed against:**

- hmcts `sdrs-infra` and `crime-portal-infra` (the stated reference patterns)
- hmcts `oracle-azure-infrastructure` (legacy MCOL estate and Heritage External Services spokes, including the `mcol-tr-migration-allow-in` NSG rules added 2026-10-10)
- `terraform-module-virtual-machine`, `terraform-module-dlrm-core-infra`, `terraform-module-azure-virtual-networking` (actual module sources)
- hmcts `cnp-azuredevops-libraries` (pipeline templates)
- The MCOL Infrastructure LLD (v0.2 draft), with the agreed deviation that the estate deploys into **new subnets** rather than the LLD's "re-use existing subnets" wording.

## Verdict

The implementation is in good shape. It is a faithful mirror of the sdrs-infra / crime-portal-infra patterns and lines up with the LLD. Two issues were found and fixed (left uncommitted in the working copy); a small number of items are flagged for awareness but deliberately not changed.

## Fixes applied (uncommitted in working copy)

1. **`azure-pipelines.yaml` — added the nightly drift-detection schedule.** Both reference repos run the pipeline at 18:00 on weekdays with `always: true` so drift gets surfaced by a plan. MCOL was the only one without it. Added the identical `schedules` block (cron `0 18 * * 1-5`).
2. **`README.md` — corrected the data-disk claim.** It said Oracle data disks "match the legacy MCOL database servers in each environment". That is true for prod (lun10 128 GiB / lun11 512 GiB / lun12 32 GiB Premium, lun14 512 GiB Standard — exactly the legacy PMCOL set), but the legacy stg DB has a single 128 GiB disk while the new stg build has four. Reworded to state the prod mirroring explicitly and that final capacity remains subject to CGI DBA confirmation per the LLD.

A local git repo was initialised and the implementation committed as a baseline before these edits; the two fixes are the only uncommitted changes.

## Verified correct (no action needed)

**Plumbing end-to-end**

- The core module's `subscription_vnet_map` covers both external-services subscriptions: `9c604868-4643-43b8-9eb1-4c348c739a3e` → `vnet-nle-ext-01` and `c170c61a-f00f-4295-a718-634e27af1597` → `vnet-prod-ext-01`, both in `ExternalSpoke-rg`.
- The dlrm core module creates `mcol-rg-{env}`, `mcol-kv-{env}`, `mcol-rsv-{env}`, `mcol-daily-bp-{env}` and subnets `mcol-{web,app,data}-{env}`, matching every data-source lookup in the `vm` and `rbac` components; route-table/NSG subnet associations key correctly through the networking module.

**Network placement**

- The new subnets (`10.25.249.96/27`, `10.25.249.128/27`, `10.25.249.160/27` stg; `10.24.249.96/27`, `10.24.249.128/27`, `10.24.249.160/27` prod) do not overlap any of the 13 existing subnets in either spoke VNet.
- All static IPs (web .103/.104, app .135/.136, data .166/.167/.168) are inside their /27s and avoid Azure-reserved addresses.
- The route table mirrors the legacy `NLE/PROD-EXTERNAL-NONAT-RT` baseline (default → firewall 10.11.72.36 / 10.11.8.36, `bais`, `hmcts-managed-domain`), plus an intentional `AzureActiveDirectory → Internet` route (see flagged items).
- The reciprocal migration NSG rules match oracle-azure-infrastructure's `mcol-tr-migration-allow-in` (new data subnet → legacy data subnet, 22/1521).

**Terraform modules**

- VM module usage verified against the real module source: NIC/ipconfig names (`{vm}-nic`, `{vm}-ipconfig`) match what the load-balancer component references; the `managed_disks` object shape, `vm_availabilty_zones` (string-coerced), XDR run-command wiring, and `vm_id`/`xdr_tags` outputs all check out.
- `identity[0].principal_id` on `data.azurerm_virtual_machine` is valid for azurerm 4.22 (confirmed in the provider schema: TypeList, MaxItems 1).

**RBAC**

- `ops-approval-gate-{stg,prod}-envs` service connections and the provider block match crime-portal-infra exactly.
- `mcol-{stg,prod}-kv` are confirmed RBAC-enabled in oracle-azure-infrastructure, so `Key Vault Secrets User` is the correct grant for the app VMs' system-assigned identities; the AcrPull target (`sdshmctspublic`) matches the LLD's "reuse the HMCTS ACR used by Crime Portal".

**NSG rules**

- Rules match the LLD baseline: web 8003/8004/8025/8026 from shared-ingress sources (plus prod-only payment source 10.11.8.5/32 and 10.11.8.32/27), app 8005/7779 from the new web subnet + SDT + CFT ranges (AAT values in stg, prod values in prod), data 1521 from the new app subnet to the permanent DBs only (migration VM excluded), prod Data Guard 1521 between .166/.167, and time-bound legacy migration rules — with legacy WebLogic-era rules correctly retired.

**Validation**

- All four components pass `terraform validate` (the `vm` component validated against the real remote module with its `1.9.5` pin relaxed only in a throwaway copy — the pin itself matches crime-portal and is intentional).
- `terraform fmt -check` and YAML parse are clean.
- tflint warnings are all inherited house patterns (unpinned `terraform-module-common-tags`, untyped `install_azure_monitor`) or pipeline-required boilerplate: the shared `cnp-azuredevops-libraries` template always injects `-var builtFrom -var product`, so those variables must be declared even when unused. The shared template resolves the var-file as `environments/<env>/<env>.tfvars`, matching the repo's file naming.

## Flagged for awareness (not changed)

- **OEM monitoring.** The LLD says retain the OEM rules (10.24.247.32/27 / 10.25.247.37 → 1521/3872) "only if OEM remains approved for the target estate". The new data NSGs omit them — worth confirming with the CGI DBA team that this is the agreed call before prod.
- **No intra-subnet allow rule.** Legacy NSGs had `Intra-Subnet-in` at priority 3900; the new NSGs are deny-by-default (the core module adds `DenyAllInbound` at 4096) and DB↔DB (Data Guard) traffic is explicitly covered. If the DBAs need same-subnet flows beyond 1521 between the two prod DB nodes, a rule will need adding.
- **Stg mgmt source `10.25.248.96/27`.** This CIDR is not declared as a subnet in the stg vnet tfvars (the stg management subnet is in the 10.225 space), but the legacy MCOL stg NSGs reference the same CIDR, so mcol-infra is consistent with the legacy baseline. It is a legacy quirk, not a bug here.
- **AAD route addition.** The new route table adds `AzureActiveDirectory → Internet`, which the legacy NONAT tables do not have. This is deliberate and needed for Entra ID SSH login from non-NAT'd subnets (same as sdrs), but it is an intentional addition worth knowing about.
- **RTO/RPO** remain unapproved by the MCOL service owner (documented in the README, per the LLD).
