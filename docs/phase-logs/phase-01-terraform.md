# Phase 1: Terraform — AKS & Supporting Infrastructure

## Architecture Overview

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

### Module: networking
- *Scaffolded variables, resources, and outputs. Created the VNet and AKS subnet inside `main.tf`.*
- *Outputted the `subnet_id` to allow the AKS cluster module to know exactly which network boundary to deploy its worker nodes into.*

### Module: acr
- *Defined the registry resource with the `sku` variable and disabled the admin user (`admin_enabled = false`).*
- *Disabling admin controls enforces the **Principle of Least Privilege**, forcing us to use Azure RBAC (Managed Identities) rather than shared static credentials.*
- *Outputted the `acr_id` (for role assignment) and `login_server` (for image registry logins in the CI/CD pipeline).*

### Module: keyvault
- *Set `purge_protection_enabled = false` for the dev environment to allow easy deletion and recreation without waiting for Azure's default retention lock.*
- *Created an access policy for the Terraform deploying identity (`azurerm_client_config.current.object_id`) to manage and seed secrets.*
- *Created an access policy loop for reader identities to grant read-only (`Get`, `List`) secrets access to the AKS cluster.*
- *Outputted the `vault_uri` and `kv_name` for the Secrets Store CSI driver configuration.*

### Module: aks
- *Configured the cluster with a DNS prefix, system-assigned managed identity, and a cost-efficient single node pool running `Standard_B2s_v2`.*
- *Enabled Calico network policies (`network_policy = "calico"`) and Azure CNI (`network_plugin = "azure"`) to establish secure pod-to-pod networking boundaries.*
- *Enabled the CSI secrets provider integration to mount Key Vault secrets into Kubernetes.*
- *Configured `upgrade_settings { max_surge = "33%" }` inside the node pool block to ensure nodes are upgraded incrementally without causing application downtime.*
- *Outputted `kubelet_identity_object_id` (the node identity) to authorize container image pulls and Key Vault reading.*

### Backend Config
- *Bootstrapped a remote backend storage architecture using Azure CLI.*
- *Placed the state storage account in a completely separate Resource Group (`n8n-tfstate-rg`) so that running `terraform destroy` on the dev cluster doesn't delete the state file currently tracking the destruction.*
- *Created `backend.tf` to configure the `azurerm` backend with Locally Redundant Storage (`Standard_LRS`) for maximum credit savings.*

---

## Key Learnings

### Conceptual
- **Environment Isolation**: In development, namespaces are fine for isolating workloads on a shared cluster, but production systems require separate folder structures, separate states, and separate resource groups to ensure zero blast radius between dev, staging, and prod.
- **Key Vault CSI Mechanics**: Learned how the Secrets Store CSI driver acts as an agent on AKS nodes, leveraging the node's Kubelet Identity to securely mount secrets as virtual volumes rather than storing credentials in the Kubernetes database.

### Project-Specific
- **Decoupled Module Structure**: Learned how to construct DRY, reusable Terraform modules that communicate purely via inputs and outputs, keeping modules completely unaware of each other (e.g. the Key Vault module doesn't hardcode AKS variables).
- **Cost Discipline**: Understood how to downscale a production-ready architecture (single node, burstable VM, basic ACR SKU, and LRS storage) to fit student credit budgets without compromising on the underlying infrastructure design.

---

## Mistakes, Challenges & How You Overcame Them

| Mistake / Challenge | What Went Wrong | How You Fixed It |
|---|---|---|
| **Dynamic `for_each` Keys** | Used `toset(var.reader_object_ids)` in Key Vault policies. Because the AKS Kubelet ID is generated at apply time, the set values were unknown at plan time. Terraform requires loop keys to be known during `plan` to address resources. | Changed `reader_object_ids` to a `map(string)` where keys are static strings (e.g., `"aks"`) and values are the dynamic IDs. Terraform maps the loop to static keys at plan time, resolving values at apply. |
| **LTS Version Restrictions** | Tried to deploy K8s `1.30` and `1.32`. Azure rejected this because those families are in LTS, which is restricted to Premium tier tiers. | Ran `az aks get-versions` via CLI to inspect the region's support plans. Upgraded the version to `1.33` which is active and fully supported on the Free/Standard tiers. |

---

## Interview Questions From This Phase

### 1. Why do you use a remote backend for Terraform state instead of storing it locally?
Storing state locally is a single point of failure and makes team collaboration impossible. A remote backend (like Azure Blob Storage) ensures:
- **Single Source of Truth**: Everyone in the team works with the same infrastructure state.
- **State Locking**: Prevents concurrent runs from executing `apply` simultaneously, which would corrupt the state.
- **Security**: The state file (which can contain sensitive plain-text parameters) is stored securely in encrypted cloud storage rather than on developer laptops.

### 2. Why does AKS need an explicit role assignment to pull from ACR? Why doesn't it just work?
For security and isolation, AKS and ACR are completely separate services. By default, Azure enforces a zero-trust model. We also disabled the insecure ACR admin username and password. 
To pull private container images, we must explicitly grant the AKS cluster's **Kubelet identity** (the identity managing the VM scale set nodes) the `AcrPull` role on the scope of the ACR. This maps authorization to the node's active Managed Identity, completely eliminating the need for stored or rotated registry secrets.

### 3. What is the difference between a subnet and a VNet? Why does the AKS subnet CIDR size matter?
A VNet is a private logical network in Azure. A subnet is a partitioned range of IP addresses within that VNet.
In AKS, we use **Azure CNI**, which assigns a real VNet IP address to every single pod. Because AKS pre-allocates pod IP ranges per node at startup (e.g., 30 IPs per node) and Azure reserves 5 IPs per subnet, a small subnet (like `/24` with 251 usable IPs) will rapidly run out of addresses as the cluster scales. We provisioned a `/22` subnet (1,024 IPs) to ensure healthy headroom for scaling our n8n workers and webhooks.

### 4. Why store secrets in Key Vault instead of Kubernetes Secrets?
By default, Kubernetes Secrets are stored in `etcd` as plain base64-encoded strings, not strongly encrypted. Anyone with read access to the namespace can easily decode them.
Azure Key Vault provides:
- **Cloud-Grade Security**: Secrets are encrypted using HSMs (Hardware Security Modules) with robust audit logging and access policies.
- **Mount-on-Demand**: Using the Secret Store CSI driver, secrets are fetched dynamically and mounted as memory-backed files (tmpfs) directly into pods. They never touch persistent storage or `etcd`, reducing the cluster's security attack surface.
