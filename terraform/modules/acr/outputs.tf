output "login_server" {
  value = azurerm_container_registry.acr.login_server
  description = "Login server url of ACR"
}

output "acr_id" {
  value = azurerm_container_registry.acr.id
  description = "ID of the ACR"
}