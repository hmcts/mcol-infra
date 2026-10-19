location      = "uksouth"
cnp_vault_sub = "1c4f0704-a29e-403d-b719-b90c34ef14c9"

subscription_id = "9c604868-4643-43b8-9eb1-4c348c739a3e"

install_azure_monitor = true

install_dynatrace_oneagent = false

web_vms = {
  mcol-web-vm01-stg = {
    availability_zone = 1
    subnet_name       = "web"
    private_ip        = "10.25.248.7"
    install_xdr_agent = true
  }
  mcol-web-vm02-stg = {
    availability_zone = 2
    subnet_name       = "web"
    private_ip        = "10.25.248.8"
    install_xdr_agent = true
  }
}

app_vms = {
  mcol-app-vm01-stg = {
    availability_zone = 1
    subnet_name       = "app"
    private_ip        = "10.25.248.39"
    install_xdr_agent = true
  }
  mcol-app-vm02-stg = {
    availability_zone = 2
    subnet_name       = "app"
    private_ip        = "10.25.248.40"
    install_xdr_agent = true
  }
}

db_vms = {
  mcol-db-vm01-stg = {
    availability_zone = 1
    subnet_name       = "data"
    private_ip        = "10.25.248.70"
    install_xdr_agent = true
    data_disks = {
      lun10 = { lun = 10, disk_size_gb = 128, storage_account_type = "Standard_LRS", mount_path = "/opt/moj" }
      lun11 = { lun = 11, disk_size_gb = 32, storage_account_type = "Standard_LRS", mount_path = "/u01" }
      lun12 = { lun = 12, disk_size_gb = 32, storage_account_type = "Standard_LRS", mount_path = "/u02" }
      lun13 = { lun = 13, disk_size_gb = 32, storage_account_type = "Standard_LRS", mount_path = "/backup" }
    }
  }
  # Temporary migration VM for the Oracle 12c restore and upgrade. Zone 1 so its upgraded data disk
  # can be detached and attached to the zone 1 primary.
  mcol-dbmig-vm01-stg = {
    availability_zone = 1
    subnet_name       = "data"
    private_ip        = "10.25.248.72"
    install_xdr_agent = true
    image = {
      publisher = "RedHat"
      offer     = "RHEL"
      sku       = "79-gen2"
    }
    data_disks = {
      lun10 = { lun = 10, disk_size_gb = 128, storage_account_type = "Standard_LRS", mount_path = "/opt/moj" }
      lun11 = { lun = 11, disk_size_gb = 32, storage_account_type = "Standard_LRS", mount_path = "/u01" }
      lun12 = { lun = 12, disk_size_gb = 32, storage_account_type = "Standard_LRS", mount_path = "/u02" }
      lun13 = { lun = 13, disk_size_gb = 32, storage_account_type = "Standard_LRS", mount_path = "/backup" }
    }
  }
}

load_balancers = {
  web = {
    name = "mcol-web-lb"
    sku  = "Standard"
    frontend_ip_configurations = {
      mcol-web-feip01-stg = {
        subnet_name                   = "web"
        private_ip_address_allocation = "Static"
        private_ip_address            = "10.25.248.9"
        zones                         = ["1", "2"]
      }
    }
    backend_address_pools = {
      mcol-web-bap01-stg = {
        virtual_machine_names = ["mcol-web-vm01-stg", "mcol-web-vm02-stg"]
      }
    }
    probes = {
      mcol-web-probe01-stg = {
        protocol = "Tcp"
        port     = 8003
      }
      mcol-web-probe02-stg = {
        protocol = "Tcp"
        port     = 8004
      }
    }
    rules = {
      mcol-web-rule01-stg = {
        protocol                       = "Tcp"
        frontend_port                  = 8025
        backend_port                   = 8003
        frontend_ip_configuration_name = "mcol-web-feip01-stg"
        backend_address_pool_names     = ["mcol-web-bap01-stg"]
        probe_name                     = "mcol-web-probe01-stg"
        load_distribution              = "SourceIP"
        idle_timeout_in_minutes        = 4
        disable_outbound_snat          = true
      }
      mcol-web-rule02-stg = {
        protocol                       = "Tcp"
        frontend_port                  = 8026
        backend_port                   = 8004
        frontend_ip_configuration_name = "mcol-web-feip01-stg"
        backend_address_pool_names     = ["mcol-web-bap01-stg"]
        probe_name                     = "mcol-web-probe02-stg"
        load_distribution              = "SourceIP"
        idle_timeout_in_minutes        = 4
        disable_outbound_snat          = true
      }
    }
  }
  app = {
    name = "mcol-app-lb"
    sku  = "Standard"
    frontend_ip_configurations = {
      mcol-app-feip01-stg = {
        subnet_name                   = "app"
        private_ip_address_allocation = "Static"
        private_ip_address            = "10.25.248.41"
        zones                         = ["1", "2"]
      }
    }
    backend_address_pools = {
      mcol-app-bap01-stg = {
        virtual_machine_names = ["mcol-app-vm01-stg", "mcol-app-vm02-stg"]
      }
    }
    probes = {
      mcol-app-probe01-stg = {
        protocol = "Tcp"
        port     = 8005
      }
    }
    rules = {
      mcol-app-rule01-stg = {
        protocol                       = "Tcp"
        frontend_port                  = 8005
        backend_port                   = 8005
        frontend_ip_configuration_name = "mcol-app-feip01-stg"
        backend_address_pool_names     = ["mcol-app-bap01-stg"]
        probe_name                     = "mcol-app-probe01-stg"
        load_distribution              = "SourceIP"
        idle_timeout_in_minutes        = 4
        disable_outbound_snat          = true
      }
    }
  }
}

application_key_vault = {
  name                = "mcol-stg-kv"
  resource_group_name = "NMCOL-RG"
}

container_registry_id = "/subscriptions/5ca62022-6aa2-4cee-aaa7-e7536c8d566c/resourceGroups/sds-acr-rg/providers/Microsoft.ContainerRegistry/registries/sdshmctspublic"

web_users = {
  "DTS Platform Operations" = {
    is_group               = true
    group_security_enabled = true
    role_type              = "admin"
  }
  # Legacy V1/CGI admin groups (aadDcAdminsV1/aadDcAdminsCGI), granted sudo via
  # Virtual Machine Administrator Login — the Entra ID equivalent of the legacy
  # sudoers entries.
  "dcd_heritage_nle_mgmt_admins_v1" = {
    is_group               = true
    group_security_enabled = true
    role_type              = "admin"
  }
  "dcd_heritage_nle_mgmt_admins_cgi" = {
    is_group               = true
    group_security_enabled = true
    role_type              = "admin"
  }
}

app_users = {
  "DTS Platform Operations" = {
    is_group               = true
    group_security_enabled = true
    role_type              = "admin"
  }
  # Legacy V1/CGI admin groups (aadDcAdminsV1/aadDcAdminsCGI), granted sudo via
  # Virtual Machine Administrator Login — the Entra ID equivalent of the legacy
  # sudoers entries.
  "dcd_heritage_nle_mgmt_admins_v1" = {
    is_group               = true
    group_security_enabled = true
    role_type              = "admin"
  }
  "dcd_heritage_nle_mgmt_admins_cgi" = {
    is_group               = true
    group_security_enabled = true
    role_type              = "admin"
  }
}

db_users = {
  "DTS Platform Operations" = {
    is_group               = true
    group_security_enabled = true
    role_type              = "admin"
  }
  # Legacy V1/CGI admin groups (aadDcAdminsV1/aadDcAdminsCGI), granted sudo via
  # Virtual Machine Administrator Login — the Entra ID equivalent of the legacy
  # sudoers entries.
  "dcd_heritage_nle_mgmt_admins_v1" = {
    is_group               = true
    group_security_enabled = true
    role_type              = "admin"
  }
  "dcd_heritage_nle_mgmt_admins_cgi" = {
    is_group               = true
    group_security_enabled = true
    role_type              = "admin"
  }
}
