variable "resource_group_name" {
    type  = string
    description  = "Name of the resource group"
}

variable "location" {
  type = string
  description = "Azure region to deploy the resources"
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

variable "acr_name" {
  type = string
  description = "Name of the Azure Container Registry"
}

variable "acr_sku" {
  type = string
  description = "Tier of ACR"
}


variable "cluster_name" {
  type  = string
  description = "Name of the AKS Cluster"
}
variable "dns_prefix" {
  type  = string
  description = "DNS prefix for the AKS Cluster"
}
variable "kubernetes_version" {
  type  = string
  description = "Version of Kubernetes to use"
}

variable "node_count" {
  type  = number
  description = "Number of worker nodes in the default node pool"
  default  = 1
}
variable "vm_size" {
  type  = string
  description = "VM size of the worker nodes"
  default  = "Standard_B2s_v2"
}


variable "kv_name" {
  type = string
  description = "Name of the Azure Key Vault"
}

variable "kv_sku" {
  type = string
  description = "Tier of AKV"
  default = "standard"
}

variable "github_repository" {
  type = string
  description = "The Github username and repo name"
  default     = "AjaySusanth/n8n-production-platform"
}