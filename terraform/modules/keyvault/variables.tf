variable "resource_group_name" {
  type = string
  description = "Name of the resource group"
}
variable "location" {
  type = string
  description = "Location of the resource group"
}

variable "kv_name" {
  type = string
  description = "Name of the Azure Key Vault"
}

variable "sku_name" {
  type = string
  description = "Tier of AKV"
  default = "standard"
}

variable "tenant_id" {
  type = string
  description = "ID of the Azure Active Directory"
}

variable "reader_object_ids" {
  type  = list(string)
  description = "List of Azure AD Object IDs that need to read secrets"
  default = [] 
}