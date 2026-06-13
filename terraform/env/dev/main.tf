terraform {
  required_version = ">=1.0.0"

  required_providers {
    azurerm = {
        source = "hashicorp/azurerm"
        version = "~>3.0"
    }
  }
}

provider "azurerm" {
  features {}
}


data "azurerm_client_config" "current" {}

resource "azurerm_resource_group" "rg" {
    name = var.resource_group_name
    location = var.location
}

module "networking" {
  source = "../../modules/networking"
  resource_group_name = azurerm_resource_group.rg.name
  location = azurerm_resource_group.rg.location
  vnet_name = var.vnet_name
  subnet_name = var.subnet_name
  vnet_address_space = var.vnet_address_space
  subnet_address_space = var.subnet_address_space
}

module "acr" {
    source = "../../modules/acr"
    resource_group_name = azurerm_resource_group.rg.name
    location = azurerm_resource_group.rg.location
    acr_name = var.acr_name
    sku = var.acr_sku
}
module "aks" {
    source = "../../modules/aks"
    cluster_name = var.cluster_name
    kubernetes_version = var.kubernetes_version
    resource_group_name = azurerm_resource_group.rg.name
    location = azurerm_resource_group.rg.location
    subnet_id = module.networking.subnet_id
    node_count = var.node_count
    vm_size = var.vm_size
    dns_prefix = var.dns_prefix
}


module "keyvault" {
  source = "../../modules/keyvault"
  kv_name = var.kv_name
  resource_group_name = azurerm_resource_group.rg.name
  location = azurerm_resource_group.rg.location
  sku_name = var.kv_sku
  tenant_id = data.azurerm_client_config.current.tenant_id
  reader_object_ids = [module.aks.kubelet_identity_object_id]
}

resource "azurerm_role_assignment" "acr_pull" {
  scope = module.acr.acr_id
  role_definition_name = "AcrPull"
  principal_id = module.aks.kubelet_identity_object_id
}