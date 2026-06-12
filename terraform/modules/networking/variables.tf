variable "resource_group_name" {
  type = string
  description = "Name of the resource group"
}

variable "location" {
  type = string
  description = "Location of the resource group"
}

variable "vnet_name" {
  type = string
  description = "Name of the virtual network"
}

variable "subnet_name" {
  type = string
  description = "Name of the subnet"
}

variable "vnet_address_space" {
  type = list(string)
  description = "Address space range of Vnet"
}

variable "subnet_address_space" {
  type = list(string)
  description = "Address space range of SubNet"
}
