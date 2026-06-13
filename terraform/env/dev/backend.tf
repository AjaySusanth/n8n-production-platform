terraform {
  backend "azurerm" {
    resource_group_name  = "n8n-tfstate-rg"
    storage_account_name = "n8ntfstateajay789" 
    container_name = "tfstate"
    key = "dev.n8n.tfstate"
  }
}