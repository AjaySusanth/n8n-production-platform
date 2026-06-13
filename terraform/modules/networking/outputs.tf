output "subnet_id" {
  value = azurerm_subnet.subnet.id
  description = "ID of the AKS Node Subnet"
}