---
name: terraform-azure
description: Load this skill when writing or explaining any Terraform file — modules, variables, outputs, backend config, or workspace usage
activation: manual
---

# Skill: Terraform on Azure for n8n Platform

## Learner Context
The learner has written Terraform in a previous project (P2) and understands modules and remote state conceptually. The goal here is to go deeper — DRY modules, typed variables, workspace-based environments, and OIDC auth from GitHub Actions.

## Module Structure to Build

```
terraform/
├── backend.tf              # Remote state config — Azure Blob
├── modules/
│   ├── networking/         # VNet, subnets, NSGs
│   ├── aks/                # AKS cluster
│   ├── acr/                # Azure Container Registry
│   └── keyvault/           # Key Vault + access policies
└── envs/
    ├── dev/
    │   ├── main.tf         # calls modules with dev-sized inputs
    │   ├── variables.tf
    │   └── terraform.tfvars
    └── prod/
        ├── main.tf
        ├── variables.tf
        └── terraform.tfvars
```

## Key Concepts to Teach

### Why modules?
Without modules, dev and prod would be two copies of the same 500-line file. Changing the AKS version means editing two files and forgetting one. Modules = define once, instantiate twice with different inputs.

Analogy: a module is like a function. `module "aks" { source = "../modules/aks" node_count = 2 }` is like calling `create_aks(node_count=2)`.

### Variable typing — enforce this
Every variable must have a type. This catches mistakes at `terraform plan` time, not at 3am when something breaks:

```hcl
variable "node_count" {
  type        = number
  description = "Number of nodes in the default node pool"
  default     = 2

  validation {
    condition     = var.node_count >= 1 && var.node_count <= 10
    error_message = "Node count must be between 1 and 10."
  }
}
```

If the learner writes `type = any` or omits type, correct it.

### Remote state — explain the why
Without remote state, the `.tfstate` file lives on your laptop. If you switch machines, lose the file, or work with a team, Terraform doesn't know what it already created and will try to create everything again.

Azure Blob with lease-based locking = two people can't run `terraform apply` simultaneously (prevents state corruption).

```hcl
terraform {
  backend "azurerm" {
    resource_group_name  = "tfstate-rg"
    storage_account_name = "n8ntfstate"
    container_name       = "tfstate"
    key                  = "n8n.tfstate"
    use_oidc             = true    # auth via OIDC, not stored credentials
  }
}
```

### OIDC Auth — teach this, it's impressive
Traditional Terraform CI uses a Service Principal with a client secret stored as a GitHub secret. That secret can leak, expire, or be forgotten.

OIDC federated credentials = GitHub Actions proves its identity to Azure using a JWT token. No secret stored anywhere. Azure trusts GitHub's identity provider directly.

In Terraform provider:
```hcl
provider "azurerm" {
  features {}
  use_oidc = true
  # No client_secret here — Azure accepts GitHub's OIDC token
}
```

In GitHub Actions:
```yaml
permissions:
  id-token: write   # allows the job to request an OIDC token
  contents: read

- uses: azure/login@v2
  with:
    client-id: ${{ vars.AZURE_CLIENT_ID }}
    tenant-id: ${{ vars.AZURE_TENANT_ID }}
    subscription-id: ${{ vars.AZURE_SUBSCRIPTION_ID }}
```

**Interview line:** "We use OIDC federated credentials so there are no long-lived secrets in GitHub at all — Azure trusts GitHub's identity provider directly."

## AKS Module — Key Decisions to Explain

```hcl
resource "azurerm_kubernetes_cluster" "main" {
  name                = var.cluster_name
  location            = var.location
  resource_group_name = var.resource_group_name
  dns_prefix          = var.cluster_name
  kubernetes_version  = var.kubernetes_version

  default_node_pool {
    name                = "system"
    node_count          = var.system_node_count
    vm_size             = var.vm_size
    vnet_subnet_id      = var.subnet_id
    
    # Why upgrade_settings? Without this, node upgrades drain all pods at once
    upgrade_settings {
      max_surge = "33%"
    }
  }

  # Why system-assigned identity over service principal?
  # Azure manages rotation automatically — no credential to expire
  identity {
    type = "SystemAssigned"
  }

  network_profile {
    network_plugin = "azure"   # Azure CNI — pods get VNet IPs
    network_policy = "calico"  # enables NetworkPolicy enforcement
  }

  # Why enable this? Lets Key Vault CSI driver use pod-level managed identities
  key_vault_secrets_provider {
    secret_rotation_enabled = true
  }
}
```

**Decision to explain:** `network_policy = "calico"` is required for NetworkPolicies to actually be enforced. Without this, you can write NetworkPolicy manifests all day and they do nothing.

## Outputs — Always Export What Downstream Needs

```hcl
# In modules/aks/outputs.tf
output "cluster_name" {
  value = azurerm_kubernetes_cluster.main.name
}

output "kubelet_identity_object_id" {
  value = azurerm_kubernetes_cluster.main.kubelet_identity[0].object_id
  description = "Used to grant AKS permission to pull from ACR and read Key Vault"
}
```

Teach: outputs are how modules communicate. The AKS module outputs its identity so the Key Vault module can grant it access.

## Debugging Terraform

```bash
# Always run plan before apply — read every line
terraform plan -var-file=terraform.tfvars

# If state is confused about a resource that already exists
terraform import azurerm_resource_group.main /subscriptions/.../resourceGroups/name

# If a resource is stuck in a broken state
terraform state list          # see everything terraform knows about
terraform state show <resource>  # inspect one resource

# Cost discipline — always destroy after each session
terraform destroy -var-file=terraform.tfvars
```

## Interview Explanation Template

"I structured Terraform as reusable modules — AKS, ACR, Key Vault, and networking are each independent modules that both dev and prod environments call with different inputs. State is stored in Azure Blob with lease-based locking so concurrent runs can't corrupt it. CI/CD authenticates to Azure using OIDC federated credentials, so there are literally no secrets stored in GitHub — Azure trusts GitHub's identity provider directly."
