subnets = {
  web = {
    address_prefixes  = ["10.24.249.96/27"]
    service_endpoints = ["Microsoft.KeyVault", "Microsoft.Storage"]
  }
  app = {
    address_prefixes  = ["10.24.249.128/27"]
    service_endpoints = ["Microsoft.KeyVault", "Microsoft.Storage"]
  }
  data = {
    address_prefixes  = ["10.24.249.160/27"]
    service_endpoints = ["Microsoft.KeyVault", "Microsoft.Storage"]
  }
}

route_tables = {
  rt = {
    subnets = ["web", "app", "data"]
    routes = {
      default = {
        address_prefix         = "0.0.0.0/0"
        next_hop_type          = "VirtualAppliance"
        next_hop_in_ip_address = "10.11.8.36"
      }
      bais = {
        address_prefix         = "10.224.251.0/24"
        next_hop_type          = "VirtualAppliance"
        next_hop_in_ip_address = "10.11.8.36"
      }
      hmcts_managed_domain = {
        address_prefix         = "10.128.0.0/24"
        next_hop_type          = "VirtualAppliance"
        next_hop_in_ip_address = "10.11.8.36"
      }
      aad_internet = {
        address_prefix = "AzureActiveDirectory"
        next_hop_type  = "Internet"
      }
    }
  }
}

network_security_groups = {
  web-nsg = {
    subnets = ["web"]
    rules = {
      "deny_vnet_inbound" = {
        priority                   = 4000
        direction                  = "Inbound"
        access                     = "Deny"
        protocol                   = "*"
        source_port_range          = "*"
        destination_port_range     = "*"
        source_address_prefix      = "VirtualNetwork"
        destination_address_prefix = "*"
      }
      "allow_http" = {
        priority                   = 200
        direction                  = "Inbound"
        access                     = "Allow"
        protocol                   = "Tcp"
        source_port_range          = "*"
        destination_port_ranges    = ["8003", "8004", "8025", "8026"]
        source_address_prefixes    = ["10.11.8.6/32", "10.11.72.32/27", "10.49.8.32/27", "10.49.72.32/27", "10.11.8.32/27"]
        destination_address_prefix = "10.24.249.96/27"
      }
      "allow_payment" = {
        priority                   = 201
        direction                  = "Inbound"
        access                     = "Allow"
        protocol                   = "Tcp"
        source_port_range          = "*"
        destination_port_ranges    = ["8004", "8026"]
        source_address_prefix      = "10.11.8.5/32"
        destination_address_prefix = "10.24.249.96/27"
      }
      "allow_mgmt" = {
        priority                   = 202
        direction                  = "Inbound"
        access                     = "Allow"
        protocol                   = "Tcp"
        source_port_range          = "*"
        destination_port_range     = "22"
        source_address_prefixes    = ["10.24.248.96/27", "10.224.249.192/27", "10.24.250.0/24", "10.11.8.37", "10.11.8.38", "10.10.72.0/23", "10.10.74.0/23"]
        destination_address_prefix = "10.24.249.96/27"
      }
      "allow_lb" = {
        priority                   = 203
        direction                  = "Inbound"
        access                     = "Allow"
        protocol                   = "*"
        source_port_range          = "*"
        destination_port_range     = "*"
        source_address_prefix      = "AzureLoadBalancer"
        destination_address_prefix = "10.24.249.96/27"
      }
    }
  }
  app-nsg = {
    subnets = ["app"]
    rules = {
      "deny_vnet_inbound" = {
        priority                   = 4000
        direction                  = "Inbound"
        access                     = "Deny"
        protocol                   = "*"
        source_port_range          = "*"
        destination_port_range     = "*"
        source_address_prefix      = "VirtualNetwork"
        destination_address_prefix = "*"
      }
      "allow_web" = {
        priority                   = 200
        direction                  = "Inbound"
        access                     = "Allow"
        protocol                   = "Tcp"
        source_port_range          = "*"
        destination_port_range     = "8005"
        source_address_prefix      = "10.24.249.96/27"
        destination_address_prefix = "10.24.249.128/27"
      }
      "allow_sdt" = {
        priority                   = 201
        direction                  = "Inbound"
        access                     = "Allow"
        protocol                   = "Tcp"
        source_port_range          = "*"
        destination_port_range     = "8005"
        source_address_prefix      = "10.24.249.32/27"
        destination_address_prefix = "10.24.249.128/27"
      }
      "allow_cft" = {
        priority                   = 202
        direction                  = "Inbound"
        access                     = "Allow"
        protocol                   = "Tcp"
        source_port_range          = "*"
        destination_port_ranges    = ["7779", "8005"]
        source_address_prefixes    = ["10.90.64.0/20", "10.90.80.0/20"]
        destination_address_prefix = "10.24.249.128/27"
      }
      "allow_mgmt" = {
        priority                   = 203
        direction                  = "Inbound"
        access                     = "Allow"
        protocol                   = "Tcp"
        source_port_range          = "*"
        destination_port_range     = "22"
        source_address_prefixes    = ["10.24.248.96/27", "10.224.249.192/27", "10.24.250.0/24", "10.11.8.37", "10.11.8.38", "10.10.72.0/23", "10.10.74.0/23"]
        destination_address_prefix = "10.24.249.128/27"
      }
      "allow_lb" = {
        priority                   = 204
        direction                  = "Inbound"
        access                     = "Allow"
        protocol                   = "*"
        source_port_range          = "*"
        destination_port_range     = "*"
        source_address_prefix      = "AzureLoadBalancer"
        destination_address_prefix = "10.24.249.128/27"
      }
    }
  }
  data-nsg = {
    subnets = ["data"]
    rules = {
      "deny_vnet_inbound" = {
        priority                   = 4000
        direction                  = "Inbound"
        access                     = "Deny"
        protocol                   = "*"
        source_port_range          = "*"
        destination_port_range     = "*"
        source_address_prefix      = "VirtualNetwork"
        destination_address_prefix = "*"
      }
      # Application, CaseMan and SDP access is limited to the permanent Oracle servers so the
      # migration VM stays isolated from live traffic.
      "allow_oracle_app" = {
        priority                     = 200
        direction                    = "Inbound"
        access                       = "Allow"
        protocol                     = "Tcp"
        source_port_range            = "*"
        destination_port_range       = "1521"
        source_address_prefix        = "10.24.249.128/27"
        destination_address_prefixes = ["10.24.249.166/32", "10.24.249.167/32"]
      }
      "allow_oracle_caseman" = {
        priority                     = 201
        direction                    = "Inbound"
        access                       = "Allow"
        protocol                     = "Tcp"
        source_port_range            = "*"
        destination_port_range       = "1521"
        source_address_prefix        = "10.24.242.32/27"
        destination_address_prefixes = ["10.24.249.166/32", "10.24.249.167/32"]
      }
      "allow_oracle_sdp" = {
        priority                     = 202
        direction                    = "Inbound"
        access                       = "Allow"
        protocol                     = "Tcp"
        source_port_range            = "*"
        destination_port_range       = "1521"
        source_address_prefixes      = ["10.148.0.0/20", "10.148.16.0/20", "10.144.0.0/20", "10.144.16.0/20", "10.24.33.0/27", "10.24.33.32/27"]
        destination_address_prefixes = ["10.24.249.166/32", "10.24.249.167/32"]
      }
      "allow_mgmt" = {
        priority                   = 203
        direction                  = "Inbound"
        access                     = "Allow"
        protocol                   = "Tcp"
        source_port_range          = "*"
        destination_port_ranges    = ["22", "1521"]
        source_address_prefixes    = ["10.24.248.96/27", "10.224.249.192/27", "10.24.250.0/24", "10.11.8.37", "10.11.8.38", "10.10.72.0/23", "10.10.74.0/23"]
        destination_address_prefix = "10.24.249.160/27"
      }
      "allow_legacy_migration" = {
        priority                   = 204
        direction                  = "Inbound"
        access                     = "Allow"
        protocol                   = "Tcp"
        source_port_range          = "*"
        destination_port_ranges    = ["22", "1521"]
        source_address_prefix      = "10.24.248.64/27"
        destination_address_prefix = "10.24.249.168/32"
      }
      "allow_data_guard" = {
        priority                     = 205
        direction                    = "Inbound"
        access                       = "Allow"
        protocol                     = "Tcp"
        source_port_range            = "*"
        destination_port_range       = "1521"
        source_address_prefixes      = ["10.24.249.166/32", "10.24.249.167/32"]
        destination_address_prefixes = ["10.24.249.166/32", "10.24.249.167/32"]
        description                  = "Oracle Data Guard redo transport between primary and standby."
      }
      "allow_legacy_migration_source" = {
        priority                   = 206
        direction                  = "Inbound"
        access                     = "Allow"
        protocol                   = "Tcp"
        source_port_range          = "*"
        destination_port_ranges    = ["22", "1521"]
        source_address_prefix      = "62.208.147.2"
        destination_address_prefix = "10.24.249.168/32"
        description                = "Temporary legacy migration source. Remove after migration acceptance."
      }
    }
  }
}

location      = "uksouth"
cnp_vault_sub = "8999dec3-0104-4a27-94ee-6588559729d1"

subscription_id            = "c170c61a-f00f-4295-a718-634e27af1597"
legacy_resource_group_name = "PMCOL-RG"

install_azure_monitor = true

web_vms = {
  mcol-web-vm01-prod = {
    availability_zone = 1
    subnet_name       = "web"
    private_ip        = "10.24.249.103"
    install_xdr_agent = true
  }
  mcol-web-vm02-prod = {
    availability_zone = 2
    subnet_name       = "web"
    private_ip        = "10.24.249.104"
    install_xdr_agent = true
  }
}

app_vms = {
  mcol-app-vm01-prod = {
    availability_zone = 1
    subnet_name       = "app"
    private_ip        = "10.24.249.135"
    install_xdr_agent = true
  }
  mcol-app-vm02-prod = {
    availability_zone = 2
    subnet_name       = "app"
    private_ip        = "10.24.249.136"
    install_xdr_agent = true
  }
}

db_vms = {
  mcol-db-vm01-prod = {
    availability_zone = 1
    subnet_name       = "data"
    private_ip        = "10.24.249.166"
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
    private_ip        = "10.24.249.167"
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
    private_ip        = "10.24.249.168"
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

load_balancer_backends = {
  web = {
    load_balancer_name    = "pmcol-pri-lb-01"
    virtual_machine_names = []
  }
  app = {
    load_balancer_name    = "pmcol-pri-lb-02"
    virtual_machine_names = []
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
