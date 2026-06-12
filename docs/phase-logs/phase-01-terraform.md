# Phase 1: Terraform — AKS & Supporting Infrastructure

## Architecture Overview

> Fill this in as you build. Describe what this phase provisions and why each component exists.

- **Resource Group**: Groups all Azure resources under a single lifecycle boundary. Deleting the RG tears down everything cleanly.
- **VNet + Subnet**: Private network boundaries. No resource is directly internet-accessible. All pod IPs are drawn from the AKS subnet CIDR.
- **AKS Cluster**: The managed Kubernetes control plane. Azure manages the control plane nodes; we manage the worker node pools.
- **ACR (Azure Container Registry)**: Private image registry. Our Helm chart will pull n8n (and any custom images) from here, not Docker Hub directly.
- **ACR Pull Role Assignment**: Grants the AKS kubelet identity the `AcrPull` role so nodes can pull images from ACR without stored credentials.
- **Azure Key Vault**: Stores all secrets (DB passwords, n8n encryption key, etc.). Never written to a file. Mounted into pods at runtime via the CSI driver.
- **Log Analytics Workspace**: Required by AKS for cluster diagnostics, container insights, and later Prometheus integration.
- **Storage Account + Blob Container**: Remote backend for Terraform state. Enables team collaboration and state locking.

---

## Implementation Notes

> Fill this in as you write each module. Note decisions you made and why.

### Module: networking
- *Created the variables.tf file with rg-name, location, vnet and subnet name and their address spaces. Also created files for main.tf and outputs.tf. => feat(terraform): scaffold networking module*

- *Created a vnet and subnet in the main.tf and defined subnet id as the output*

- **Subnet id tells K8s in which subnet the nodes should be placed**

### Module: acr
- *Created the vars file with acr name, rg-name and loc and the sku*

- *Defined the resource in main.tf with admin_enabled = false. **It disables the admin user controls, allowing to enforce least privelege usig Azure RBAC, explicitly define exact permissions that are required like AcrPush and AcrPull***

- *Outputs: acr_id => used to assign AcrPull role to AKS,
            login_server => used for acr login in CI/CD pipeline*

### Module: keyvault
- 

### Module: aks
- 

### Backend Config
- 

---

## Key Learnings

### Conceptual
> What did you understand about Terraform, Azure, or Kubernetes architecture from this phase?

- 

### Project-Specific
> What does this specific Terraform setup enable for the n8n platform?

- 

---

## Mistakes, Challenges & How You Overcame Them

> Be honest. This is the most valuable section for interview prep.

| Mistake / Challenge | What Went Wrong | How You Fixed It |
|---|---|---|
| | | |

---

## Interview Questions From This Phase

> After completing the phase, answer these in your own words.

1. Why do you use a remote backend for Terraform state instead of storing it locally?
2. Why does AKS need an explicit role assignment to pull from ACR? Why doesn't it just work?
3. What is the difference between a subnet and a VNet? Why does the AKS subnet CIDR size matter?
4. Why store secrets in Key Vault instead of Kubernetes Secrets?
