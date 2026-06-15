resource "azurerm_user_assigned_identity" "github_actions" {
  name = "n8n-dev-github-actions-identity"
  resource_group_name = azurerm_resource_group.rg.name
  location = azurerm_resource_group.rg.location
}

resource "azurerm_federated_identity_credential" "github_actions_oidc" {
  name = "n8n-github-actions-oidc"
  resource_group_name = azurerm_resource_group.rg.name
  audience = [ "api://AzureADTokenExchange" ]
  issuer =  "https://token.actions.githubusercontent.com"
  parent_id = azurerm_user_assigned_identity.github_actions.id
  subject = "repo:${var.github_repository}:ref:refs/heads/main"
}

resource "azurerm_role_assignment" "github_actions_rg_contributor" {
  scope = azurerm_resource_group.rg.id
  role_definition_name = "Contributor"
  principal_id = azurerm_user_assigned_identity.github_actions.principal_id

}

resource "azurerm_role_assignment" "github_actions_acr_push" {
  scope = module.acr.acr_id
  role_definition_name = "AcrPush"
  principal_id = azurerm_user_assigned_identity.github_actions.principal_id

}

# Values to be set as Github repository variables for CI
output "azure_client_id" {
  value = azurerm_user_assigned_identity.github_actions.client_id
  description = "Azure Client id"  
}

output "azure_tenant_id" {
  value = data.azurerm_client_config.current.tenant_id
  description = "Tenant ID"
}

output "azure_subscription_id" {
  value = data.azurerm_client_config.current.subscription_id
  description = "Subscription ID"
}