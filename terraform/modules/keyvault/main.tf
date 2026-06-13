data "azurerm_client_config" "current" {}

resource "azurerm_key_vault" "kv" {
  name = var.kv_name
  resource_group_name = var.resource_group_name
  location = var.location
  sku_name = var.sku_name
  tenant_id = var.tenant_id
  purge_protection_enabled = false
  soft_delete_retention_days = 7
}

resource "azurerm_key_vault_access_policy" "terraform" {
  key_vault_id = azurerm_key_vault.kv.id
  tenant_id = var.tenant_id
  object_id = data.azurerm_client_config.current.object_id
  secret_permissions =  ["Get", "List", "Set", "Delete", "Purge", "Recover"]
}

resource "azurerm_key_vault_access_policy" "readers" {
  key_vault_id = azurerm_key_vault.kv.id
  tenant_id = var.tenant_id
  secret_permissions =  ["Get", "List"]
  for_each = var.reader_object_ids
  object_id = each.value
}