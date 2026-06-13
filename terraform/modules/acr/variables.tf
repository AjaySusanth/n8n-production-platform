variable "resource_group_name" {
  type = string
  description = "Name of the resource group"
}
variable "location" {
  type = string
  description = "Location of the resource group"
}

variable "acr_name" {
  type = string
  description = "Name of the Azure Container Registry"
}

variable "sku" {
  type = string
  description = "Tier of ACR"
}