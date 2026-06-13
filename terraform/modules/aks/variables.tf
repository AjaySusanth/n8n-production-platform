variable "resource_group_name" {
  type  = string
  description = "Name of the resource group"
}

variable "location" {
  type  = string
  description = "Location of the resource group"
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
variable "subnet_id" {
  type  = string
  description = "ID of the subnet where the cluster should reside"
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