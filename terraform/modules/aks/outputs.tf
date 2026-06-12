output "cluster_name" {
  value = azurerm_kubernetes_cluster.aks.name
  description = "Name of the AKS Cluster"
}

output "kubelet_identity_object_id" {
  value = azurerm_kubernetes_cluster.aks.kubelet_identity[0].object_id
  description = "The Active Directory Object ID of the system-assigned Kubelet identity"
}