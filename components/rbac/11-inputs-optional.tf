variable "location" {
  type        = string
  description = "The Azure region to deploy resources to."
  default     = "uksouth"
}

variable "web_users" {
  type = map(object({
    is_group               = optional(bool, false)
    group_security_enabled = optional(bool, false)
    is_user                = optional(bool, false)
    is_service_principal   = optional(bool, false)
    role_type              = string
  }))
  description = "Map of objects describing the users, groups and service principals who should be able to access the web VMs."
  default     = {}
  validation {
    condition = alltrue([
      for user in var.web_users : length([for flag in [user.is_group, user.is_user, user.is_service_principal] : flag if flag]) == 1
      && contains(["admin", "user"], user.role_type)
    ])
    error_message = "Exactly one of is_group, is_user or is_service_principal must be set to true for each user, group or service principal. The valid values for role_type are admin and user (lowercase)."
  }
}

variable "app_users" {
  type = map(object({
    is_group               = optional(bool, false)
    group_security_enabled = optional(bool, false)
    is_user                = optional(bool, false)
    is_service_principal   = optional(bool, false)
    role_type              = string
  }))
  description = "Map of objects describing the users, groups and service principals who should be able to access the application VMs."
  default     = {}
  validation {
    condition = alltrue([
      for user in var.app_users : length([for flag in [user.is_group, user.is_user, user.is_service_principal] : flag if flag]) == 1
      && contains(["admin", "user"], user.role_type)
    ])
    error_message = "Exactly one of is_group, is_user or is_service_principal must be set to true for each user, group or service principal. The valid values for role_type are admin and user (lowercase)."
  }
}

variable "db_users" {
  type = map(object({
    is_group               = optional(bool, false)
    group_security_enabled = optional(bool, false)
    is_user                = optional(bool, false)
    is_service_principal   = optional(bool, false)
    role_type              = string
  }))
  description = "Map of objects describing the users, groups and service principals who should be able to access the database VMs."
  default     = {}
  validation {
    condition = alltrue([
      for user in var.db_users : length([for flag in [user.is_group, user.is_user, user.is_service_principal] : flag if flag]) == 1
      && contains(["admin", "user"], user.role_type)
    ])
    error_message = "Exactly one of is_group, is_user or is_service_principal must be set to true for each user, group or service principal. The valid values for role_type are admin and user (lowercase)."
  }
}

variable "application_key_vault" {
  type = object({
    name                = string
    resource_group_name = string
  })
  description = "The existing MCOL application key vault (RBAC enabled) that the application VMs read secrets from."
  default     = null
}

variable "container_registry_id" {
  type        = string
  description = "Resource ID of the HMCTS ACR the Docker hosts pull MCOL images from. AcrPull is granted to web and application VMs when set."
  default     = null
}
