output "kv_id" {
  value = azurerm_key_vault.kv.id
  description = "The Key Vault resource ID"
}

output "kv_name" {
  value = azurerm_key_vault.kv.name
  description = "The Key Vault name"
}

output "vault_uri" {
  value = azurerm_key_vault.kv.vault_uri
  description = "The Vault URI. The Secrets Store CSI driver in Kubernetes needs this URI to fetch the secrets."
}