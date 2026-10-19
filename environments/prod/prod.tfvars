location      = "uksouth"
cnp_vault_sub = "8999dec3-0104-4a27-94ee-6588559729d1"

subscription_id = "c170c61a-f00f-4295-a718-634e27af1597"

install_azure_monitor = true

install_dynatrace_oneagent = false

web_vms = {
  mcol-web-vm01-prod = {
    availability_zone = 1
    subnet_name       = "web"
    private_ip        = "10.24.248.7"
    install_xdr_agent = true
  }
  mcol-web-vm02-prod = {
    availability_zone = 2
    subnet_name       = "web"
    private_ip        = "10.24.248.8"
    install_xdr_agent = true
  }
}

app_vms = {
  mcol-app-vm01-prod = {
    availability_zone = 1
    subnet_name       = "app"
    private_ip        = "10.24.248.39"
    install_xdr_agent = true
  }
  mcol-app-vm02-prod = {
    availability_zone = 2
    subnet_name       = "app"
    private_ip        = "10.24.248.40"
    install_xdr_agent = true
  }
}

db_vms = {
  mcol-db-vm01-prod = {
    availability_zone = 1
    subnet_name       = "data"
    private_ip        = "10.24.248.70"
    install_xdr_agent = true
    data_disks = {
      lun10 = { lun = 10, disk_size_gb = 128, mount_path = "/opt/moj" }
      lun11 = { lun = 11, disk_size_gb = 512, mount_path = "/u01" }
      lun12 = { lun = 12, disk_size_gb = 32, mount_path = "/u02" }
      lun14 = { lun = 14, disk_size_gb = 512, storage_account_type = "Standard_LRS", mount_path = "/backup" }
    }
  }
  mcol-db-vm02-prod = {
    availability_zone = 2
    subnet_name       = "data"
    private_ip        = "10.24.248.71"
    install_xdr_agent = true
    data_disks = {
      lun10 = { lun = 10, disk_size_gb = 128, mount_path = "/opt/moj" }
      lun11 = { lun = 11, disk_size_gb = 512, mount_path = "/u01" }
      lun12 = { lun = 12, disk_size_gb = 32, mount_path = "/u02" }
      lun14 = { lun = 14, disk_size_gb = 512, storage_account_type = "Standard_LRS", mount_path = "/backup" }
    }
  }
  # Temporary migration VM for the Oracle 12c restore and upgrade. Zone 1 so its upgraded data disk
  # can be detached and attached to the zone 1 primary.
  mcol-dbmig-vm01-prod = {
    availability_zone = 1
    subnet_name       = "data"
    private_ip        = "10.24.248.72"
    install_xdr_agent = true
    image = {
      publisher = "RedHat"
      offer     = "RHEL"
      sku       = "79-gen2"
    }
    data_disks = {
      lun10 = { lun = 10, disk_size_gb = 128, mount_path = "/opt/moj" }
      lun11 = { lun = 11, disk_size_gb = 512, mount_path = "/u01" }
      lun12 = { lun = 12, disk_size_gb = 32, mount_path = "/u02" }
      lun14 = { lun = 14, disk_size_gb = 512, storage_account_type = "Standard_LRS", mount_path = "/backup" }
    }
  }
}

load_balancers = {
  web = {
    name = "mcol-web-lb"
    sku  = "Standard"
    frontend_ip_configurations = {
      mcol-web-feip01-prod = {
        subnet_name                   = "web"
        private_ip_address_allocation = "Static"
        private_ip_address            = "10.24.248.9"
        zones                         = ["1", "2"]
      }
    }
    backend_address_pools = {
      mcol-web-bap01-prod = {
        virtual_machine_names = ["mcol-web-vm01-prod", "mcol-web-vm02-prod"]
      }
    }
    probes = {
      mcol-web-probe01-prod = {
        protocol = "Tcp"
        port     = 8003
      }
      mcol-web-probe02-prod = {
        protocol = "Tcp"
        port     = 8004
      }
    }
    rules = {
      mcol-web-rule01-prod = {
        protocol                       = "Tcp"
        frontend_port                  = 8025
        backend_port                   = 8003
        frontend_ip_configuration_name = "mcol-web-feip01-prod"
        backend_address_pool_names     = ["mcol-web-bap01-prod"]
        probe_name                     = "mcol-web-probe01-prod"
        load_distribution              = "SourceIP"
        enable_tcp_reset               = true
        idle_timeout_in_minutes        = 4
      }
      mcol-web-rule02-prod = {
        protocol                       = "Tcp"
        frontend_port                  = 8026
        backend_port                   = 8004
        frontend_ip_configuration_name = "mcol-web-feip01-prod"
        backend_address_pool_names     = ["mcol-web-bap01-prod"]
        probe_name                     = "mcol-web-probe02-prod"
        load_distribution              = "SourceIP"
        enable_tcp_reset               = true
        idle_timeout_in_minutes        = 4
      }
    }
  }
  app = {
    name = "mcol-app-lb"
    sku  = "Standard"
    frontend_ip_configurations = {
      mcol-app-feip01-prod = {
        subnet_name                   = "app"
        private_ip_address_allocation = "Static"
        private_ip_address            = "10.24.248.41"
        zones                         = ["1", "2"]
      }
    }
    backend_address_pools = {
      mcol-app-bap01-prod = {
        virtual_machine_names = ["mcol-app-vm01-prod", "mcol-app-vm02-prod"]
      }
    }
    probes = {
      mcol-app-probe01-prod = {
        protocol = "Tcp"
        port     = 8005
      }
    }
    rules = {
      mcol-app-rule01-prod = {
        protocol                       = "Tcp"
        frontend_port                  = 8005
        backend_port                   = 8005
        frontend_ip_configuration_name = "mcol-app-feip01-prod"
        backend_address_pool_names     = ["mcol-app-bap01-prod"]
        probe_name                     = "mcol-app-probe01-prod"
        load_distribution              = "SourceIP"
        idle_timeout_in_minutes        = 5
        disable_outbound_snat          = true
      }
    }
  }
}

application_key_vault = {
  name                = "mcol-prod-kv"
  resource_group_name = "PMCOL-RG"
}

container_registry_id = "/subscriptions/5ca62022-6aa2-4cee-aaa7-e7536c8d566c/resourceGroups/sds-acr-rg/providers/Microsoft.ContainerRegistry/registries/sdshmctspublic"

web_users = {
  "DTS Platform Operations SC" = {
    is_group               = true
    group_security_enabled = true
    role_type              = "admin"
  }
  # Legacy V1/CGI admin groups (aadDcAdminsV1/aadDcAdminsCGI), granted sudo via
  # Virtual Machine Administrator Login — the Entra ID equivalent of the legacy
  # sudoers entries. (@HMCTS.NET suffix and sudoers space-escaping from the
  # Ansible vars are not part of the Entra display names.)
  "DTS Heritage Mgmt Prod V1 Admins" = {
    is_group               = true
    group_security_enabled = true
    role_type              = "admin"
  }
  "DTS Heritage Mgmt Prod CGI Admins" = {
    is_group               = true
    group_security_enabled = true
    role_type              = "admin"
  }
}

app_users = {
  "DTS Platform Operations SC" = {
    is_group               = true
    group_security_enabled = true
    role_type              = "admin"
  }
  # Legacy V1/CGI admin groups (aadDcAdminsV1/aadDcAdminsCGI), granted sudo via
  # Virtual Machine Administrator Login — the Entra ID equivalent of the legacy
  # sudoers entries. (@HMCTS.NET suffix and sudoers space-escaping from the
  # Ansible vars are not part of the Entra display names.)
  "DTS Heritage Mgmt Prod V1 Admins" = {
    is_group               = true
    group_security_enabled = true
    role_type              = "admin"
  }
  "DTS Heritage Mgmt Prod CGI Admins" = {
    is_group               = true
    group_security_enabled = true
    role_type              = "admin"
  }
}

db_users = {
  "DTS Platform Operations SC" = {
    is_group               = true
    group_security_enabled = true
    role_type              = "admin"
  }
  # Legacy V1/CGI admin groups (aadDcAdminsV1/aadDcAdminsCGI), granted sudo via
  # Virtual Machine Administrator Login — the Entra ID equivalent of the legacy
  # sudoers entries. (@HMCTS.NET suffix and sudoers space-escaping from the
  # Ansible vars are not part of the Entra display names.)
  "DTS Heritage Mgmt Prod V1 Admins" = {
    is_group               = true
    group_security_enabled = true
    role_type              = "admin"
  }
  "DTS Heritage Mgmt Prod CGI Admins" = {
    is_group               = true
    group_security_enabled = true
    role_type              = "admin"
  }
}
