# Architectural Decision Records

This document records the key engineering decisions made during the design and deployment of the scalable n8n architecture on AKS. Each record follows the same structure: the context that forced a decision, the options considered, the choice made, and — critically — what was accepted as a tradeoff.

---

## ADR-001: Queue Mode Architecture vs. Single-Process Deployment

**Status:** Accepted

### Context

n8n can run as a single container that handles the UI, REST API, webhook receiver, scheduler, and workflow executor simultaneously. This is how most self-hosted deployments work and how every tutorial deploys it.

Under real load, this collapses: a single long-running workflow execution monopolises the Node.js event loop. While it runs, the REST API becomes unresponsive, incoming webhooks time out, and the scheduler misses triggers. There is no way to scale individual concerns independently.

### Decision

Deploy n8n in queue mode with three separate process types: `n8n-main` (UI and API), `n8n-webhook` (HTTP trigger receiver), and `n8n-worker` (workflow executor). Redis acts as the message broker between them.

### Alternatives Considered

- **Single-container deployment:** Operationally simpler, but collapses under execution load. Acceptable for a personal instance with no SLA; not for a platform other people depend on.
- **Two-process split (main + worker only):** Separates execution from the UI but leaves webhook receiving coupled to the main process. Webhook timeouts remain possible during API load spikes.

### Consequences

**Accepted tradeoffs:**
- Three deployments, two StatefulSets, and a Redis broker to operate instead of one container. Operational surface area is meaningfully larger.
- Debugging spans multiple process logs — a failed workflow execution requires correlating logs across main (scheduling), redis (queue), and worker (execution).
- Redis becomes a hard dependency. If Redis is unavailable, no workflows execute regardless of whether main and worker are healthy.
- Minimum viable deployment requires five pods running simultaneously, which increases base compute cost.

---

## ADR-002: Custom Helm Chart vs. Community Chart

**Status:** Accepted

### Context

A community-maintained n8n Helm chart exists. Using it would reduce authoring time significantly. However, the community chart is designed to support many deployment configurations: multiple database backends, multiple ingress options, optional queue mode, and various secret management approaches. This generality adds template complexity and makes security hardening harder to audit.

### Decision

Write a custom, minimal Helm chart from scratch, scoped specifically to this platform's requirements: AKS, Postgres, Redis, queue mode, Key Vault CSI, Calico NetworkPolicies, and kube-prometheus-stack.

### Alternatives Considered

- **Community chart with values overrides:** Faster to start, but security hardening (non-root, capability dropping, read-only filesystems) would require fighting the upstream defaults rather than setting them directly. Any upstream chart update could silently revert hardening choices.
- **Community chart as a subchart dependency:** Provides upstream updates but adds a layer of indirection that makes the manifest hard to audit and own.

### Consequences

**Accepted tradeoffs:**
- Full responsibility for chart correctness. Upstream n8n version upgrades require manual image tag bumps — there is no automated dependency update mechanism.
- More authoring time upfront. Every template (18 total) was written from scratch, including the KEDA ScaledObject, SecretProviderClass, and PrometheusRule — none of which exist in the community chart.
- No community-maintained upgrade path. If the n8n deployment architecture changes significantly in a future version, the chart needs to be updated manually.

---

## ADR-003: ArgoCD OCI Source vs. Git Path Source

**Status:** Accepted

### Context

The most common ArgoCD pattern sources Helm charts directly from a Git repository path. ArgoCD watches the path and syncs on any commit. This is simple and requires no additional infrastructure.

The risk: any commit touching the chart directory — including work-in-progress, a failed refactor, or an accidental push — immediately triggers a sync to the cluster. There is no build step, no lint gate, and no immutable artifact between a Git push and a running cluster change.

### Decision

Package the Helm chart in CI (GitHub Actions), publish it to ACR as a versioned OCI artifact tagged with the Git commit SHA, and configure ArgoCD to source from the OCI registry. The `targetRevision` in `application.yaml` is patched automatically by CI on each merge to main.

### Alternatives Considered

- **Git path source:** Simpler to set up, no ACR dependency for chart delivery. Rejected because it couples every Git commit directly to cluster state with no intermediate validation gate.
- **Separate chart repository:** Common in larger organisations. Adds isolation but introduces cross-repository coordination overhead that isn't justified for a single platform.

### Consequences

**Accepted tradeoffs:**
- The CI pipeline is now in the critical path for every deployment. If GitHub Actions is unavailable, no chart updates can reach the cluster through the normal flow.
- ACR becomes a dependency for both image pulls and chart delivery. An ACR outage blocks both.
- The GitOps loop is one step removed from Git — the source of truth for what's running in the cluster is the OCI artifact version, not the Git commit directly. These are kept in sync by CI, but divergence is possible if CI fails mid-run.
- Slightly more complex setup: scoped ACR token for ArgoCD (`argocd-helm-pull`), OCI push step in CI, and `targetRevision` patching logic all need to be maintained.

---

## ADR-004: KEDA Redis Trigger vs. Standard HPA

**Status:** Accepted

### Context

Kubernetes HPA scales pods based on CPU and memory utilisation. For n8n workers, this is a lagging indicator: a workflow waits in the Redis queue consuming zero CPU until a worker picks it up and begins execution. By the time worker CPU spikes, the queue backlog has already accumulated and latency has already increased.

### Decision

Use KEDA with a Redis list length trigger (`bull:jobs:wait`) to scale `n8n-worker`. Workers scale out when queue depth exceeds 5 jobs and scale back to 1 replica after a 300-second cooldown.

### Alternatives Considered

- **Standard HPA on CPU:** Would work eventually but responds to resource consumption rather than work waiting to be done. Queue latency would spike before autoscaling fires.
- **Static replica count:** Simple, predictable, but wastes compute at idle and may be insufficient at peak. Eliminates the operational benefit of running queue mode at all.
- **HPA on custom metrics via Prometheus Adapter:** Achieves similar queue-depth scaling but requires deploying and maintaining the Prometheus Adapter alongside KEDA. KEDA has native Redis support requiring no adapter layer.

### Consequences

**Accepted tradeoffs:**
- KEDA is an additional cluster component to install, maintain, and upgrade. It runs its own operator and metrics server.
- The `TriggerAuthentication` object adds a layer of credential management specifically for KEDA's Redis connection — separate from the application's own Redis credentials.
- Cooldown period (300s) means workers scale down slowly after a burst. During cooldown, over-provisioned workers sit idle consuming resources.
- KEDA's `ignoreDifferences` exception on `Deployment.spec.replicas` is required in the ArgoCD application to prevent ArgoCD from fighting KEDA's live replica management. This is a non-obvious configuration coupling that must be maintained.

---

## ADR-005: Azure Key Vault CSI Driver vs. Kubernetes Secrets

**Status:** Accepted

### Context

Kubernetes Secrets are base64-encoded and stored in etcd. Base64 is not encryption — any principal with `kubectl get secret` access, or direct etcd access, can read the values. Committing Secret manifests to Git exposes credentials to anyone with repository access.

### Decision

Store all runtime credentials (`postgres-password`, `redis-password`, `n8n-encryption-key`) in Azure Key Vault. Mount them into pods at runtime via the Secrets Store CSI Driver using the AKS kubelet's managed identity. No secret values exist anywhere in this repository.

### Alternatives Considered

- **Sealed Secrets (Bitnami):** Encrypts secrets for Git storage. Keeps secrets in the GitOps flow but introduces a cluster-side decryption key that must be backed up and managed carefully. Key rotation requires re-encrypting all sealed secrets.
- **External Secrets Operator:** Similar to CSI Driver but syncs Key Vault values into standard Kubernetes Secrets on a schedule. Credentials exist as standard Kubernetes Secrets between sync cycles, which is the problem being solved.
- **Plain Kubernetes Secrets (not committed):** Applied manually or via CI. Removes Git exposure but introduces manual operational steps and makes secret state invisible to GitOps.

### Consequences

**Accepted tradeoffs:**
- Pods fail to start if Key Vault is unreachable at mount time. The CSI Driver is in the critical path for pod scheduling — an Azure Key Vault outage prevents pod restarts and new deployments.
- The `SecretProviderClass` resource and managed identity configuration are Azure-specific. Migrating to a different cloud or on-premises environment requires replacing the secret management layer entirely.
- Secret rotation requires either a pod restart (for file-mounted secrets) or relies on the CSI Driver's rotation polling interval. There is no zero-downtime hot rotation without application-level support.
- Two identity objects to manage: the GitHub Actions OIDC service principal (write access for provisioning) and the kubelet managed identity (read-only for runtime). These must be kept in sync with Key Vault access policies as the platform evolves.
