resource "azurerm_kubernetes_cluster" "aks" {
    name = var.cluster_name
    resource_group_name = var.resource_group_name
    location = var.location
    dns_prefix = var.dns_prefix
    kubernetes_version = var.kubernetes_version
    default_node_pool {
      name = "system"
      node_count = var.node_count
      vm_size = var.vm_size
      vnet_subnet_id = var.subnet_id

      upgrade_settings {
        max_surge = "33%"
      }
    }
    identity {
      type = "SystemAssigned"
    }

    network_profile {
      network_policy = "calico"
      network_plugin = "azure"
    }
    key_vault_secrets_provider {
      secret_rotation_enabled = true
    }
  
}