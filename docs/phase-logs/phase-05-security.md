# Phase 5: Security — Container Hardening, Key Vault CSI, NetworkPolicies & OPA Gatekeeper

## Architecture Overview

- **Least-Privilege Pod Security**: Containers run as non-root users (`runAsNonRoot: true`) with specific UIDs matching their base image definitions (UID `1000` for n8n/Redis, `999` for Postgres). All Linux kernel capabilities are dropped (`drop: ["ALL"]`) to restrict privileges.
- **Read-Only Root Filesystems**: Container filesystems are set to `readOnlyRootFilesystem: true` to prevent attackers from writing malware or executing unauthorized binaries. Writable storage is restricted to memory-backed `emptyDir` volumes mounted on `/tmp` and `/home/node`.
- **System Call Restriction**: Enabled `seccompProfile: RuntimeDefault` to restrict the system calls a container can make to the Linux kernel, minimizing kernel exploit surface area.
- **ServiceAccount Token Disabling**: Set `automountServiceAccountToken: false` across all workload ServiceAccounts to prevent automatic projection of Kubernetes API tokens into pods, limiting credentials available to potential attackers.
- **Azure Key Vault CSI Integration**: Secrets (database passwords and encryption keys) are stored in Key Vault, retrieved dynamically at startup, and mounted as ephemeral volumes.
- **OPA Gatekeeper**: Validates and enforces security policies at the API level. We implement two core admission policies: blocking images using the `:latest` tag and requiring CPU/Memory requests and limits on all containers inside the `dev` namespace.
- **Calico NetworkPolicies**: A default-deny egress/ingress network boundary that isolates the `dev` namespace and whitelists only necessary communications (e.g., DNS, Redis access for KEDA/monitoring, and Postgres access for n8n).

---

## Implementation Notes

### Workload Hardening
- *Modified `main.yaml`, `webhook.yaml`, `worker.yaml`, `postgres.yaml`, and `redis.yaml` templates.*
- *Injected `securityContext` at both the Pod level (defining user, group, fsGroup) and Container level (enforcing read-only root filesystems, dropping capabilities, and setting seccomp profiles).*

### Ephemeral Storage Volume Mounts
- *Added a `tmp` volume (`emptyDir: {}`) mounted to `/tmp` in n8n workloads to support temporary write actions.*
- *Added an `n8n-home` volume (`emptyDir: {}`) mounted to `/home/node` to give the node user write access to its configurations, caches, and custom nodes without compromising the OS directories.*

### ServiceAccount Remediation
- *Updated `serviceaccounts.yaml` to explicitly disable token automounting on all three component ServiceAccounts (`main`, `webhook`, `worker`).*

### OPA Gatekeeper Deployments & Rules
- *Bootstrapped the Gatekeeper operator using an ArgoCD Application pointing to the official charts.*
- *Created policy templates and constraints under `gitops/argocd/gatekeeper/` to enforce `:latest` tag blocks and mandatory resource specs in the `dev` namespace.*

---

## Testing & Verification Process

### 1. Gatekeeper Validation Test (Disallowed Tags)
- **Action**: Attempted to run a pod with the `latest` tag in the `dev` namespace:
  ```powershell
  kubectl run test-latest --image=nginx:latest -n dev
  ```
- **Result**: The admission webhook rejected the request immediately with the message:
  `Error from server (Forbidden): admission webhook "validation.gatekeeper.sh" denied the request: container <test-latest> uses a disallowed tag <nginx:latest>; disallowed tags are ["latest"]`
- **Action**: Ran the same command in the `default` namespace:
  ```powershell
  kubectl run test-latest --image=nginx:latest -n default
  ```
- **Result**: The pod ran successfully (confirming namespace scoping is functional). Cleaned it up via `kubectl delete pod test-latest -n default`.

### 2. Gatekeeper Validation Test (Required Resources)
- **Action**: Attempted to run a pod without resource requests/limits in the `dev` namespace:
  ```powershell
  kubectl run test-resources --image=nginx:1.25.3 -n dev
  ```
- **Result**: Rejected immediately with the message:
  `Error from server (Forbidden): admission webhook "validation.gatekeeper.sh" denied the request: container <test-resources> does not have resource <requests.cpu> specified`

### 3. Read-Only Filesystem Verification & Troubleshooting
- **Observation**: After enforcing `readOnlyRootFilesystem`, the n8n-main and n8n-worker pods entered `CrashLoopBackOff`.
- **Diagnosis**: 
  - Checked logs: `EROFS: read-only file system, open '/home/node/.n8n/config'` followed by `Error: command start not found`. The underlying CLI framework (Oclif) failed to initialize due to writing restrictions.
  - Resolved by mounting an `emptyDir` volume at `/home/node/.n8n`.
  - Next, the `main` instance crashed with `Error: ENOENT: no such file or directory, mkdir '/home/node/.cache'` due to static asset compilation write actions.
- **Result**: Changed the volume mount path from `/home/node/.n8n` to `/home/node` entirely. All pods successfully restarted and reached `1/1 READY` with `0` restarts.

---

## Mistakes, Challenges & How You Overcame Them

| Mistake / Challenge | What Went Wrong | How You Fixed It |
|---|---|---|
| **Oclif Read-Only FS Failure** | Oclif CLI framework tries to write CLI configurations dynamically to `/home/node/.n8n/config` at startup. Under read-only FS, this failed, causing initialization crashes. | Mounted a writeable `emptyDir` volume at `/home/node/.n8n`. |
| **Static Asset Cache Failure** | The `main` instance serves the UI and attempts to write compiled assets to `/home/node/.cache`. This threw an `ENOENT` folder creation error. | Expanded the volume mount path from `/home/node/.n8n` to `/home/node` so that the entire user home directory is writable. |
| **ArgoCD OutOfSync for Gatekeeper** | ArgoCD flagged OPA Gatekeeper as `OutOfSync` on several CRDs and Webhook configs. | Identified this as normal behavior: the Gatekeeper operator uses a post-install hook to dynamically insert certificates and upgrade CRDs, causing a drift between Git and live cluster states. |
| **Gatekeeper Parameter Indentation** | In `required-resources-constraint.yaml`, `parameters` was nested inside `match`. This caused parameters to be ignored by the validation controller. | Corrected the indentation by backing `parameters` out by 2 spaces to align directly under `spec`. |

---

## Interview Questions From This Phase

### 1. Why is `readOnlyRootFilesystem: true` considered a critical security practice?
If an attacker exploits a remote code execution vulnerability (RCE) in an application, the first thing they try to do is download malicious scripts, write cron jobs, or download scanning tools onto the host container. Enforcing a read-only filesystem locks the door. The attacker cannot write any files, download utilities, or execute binary modifications, rendering standard post-exploitation vectors useless.

### 2. What are Linux capabilities, and why do we set `capabilities { drop ["ALL"] }`?
By default, the Linux kernel divides system privileges into distinct units called "capabilities" (e.g., binding to low ports, changing file owners, modifying system time). Standard Docker containers grant about 14 of these capabilities by default. Dropping "ALL" capabilities strips the container container process of any root privilege actions, preventing an attacker from escalating privileges or interacting maliciously with the host node kernel.

### 3. What is the risk of keeping `automountServiceAccountToken: true` on ServiceAccounts?
When a pod starts with a ServiceAccount, Kubernetes automatically mounts a JWT token containing the account's API credentials at `/var/run/secrets/kubernetes.io/serviceaccount/token`. If an attacker compromises a pod, they can read this token and use it to query the Kubernetes API server. If the ServiceAccount has administrative permissions (or if we use the default ServiceAccount), the attacker can scale, edit, or compromise the entire cluster. Disabling token automounting limits the blast radius.

### 4. Why enforce policies via OPA Gatekeeper at admission time instead of just checking them in CI/CD?
Static analysis in CI/CD (like Helm linting or Kubeval) is a shift-left best practice, but it only validates code that goes through the git pipeline. It does not protect the cluster if an engineer runs a direct `kubectl run`, patches a resource manually, or if a third-party operator creates an insecure resource dynamically. OPA Gatekeeper acts as a gatekeeper at the API server admission webhook level, ensuring policies are enforced regardless of *how* the resource request was initiated.
