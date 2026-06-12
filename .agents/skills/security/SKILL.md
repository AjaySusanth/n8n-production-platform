---
name: kubernetes-security
description: Load this skill when configuring Key Vault CSI, writing securityContext, setting up ServiceAccounts, or adding OPA Gatekeeper policies
activation: manual
---

# Skill: Security Hardening for n8n Platform

## Learner Context
The learner has seen RBAC and Key Vault CSI in their learning path but hasn't applied them to a real multi-service app. n8n is a high-value security target — it holds API keys for every service it integrates with. This context makes security concrete, not theoretical.

## Why Security Matters Specifically for n8n

n8n stores credentials for every external service it connects to: Slack tokens, GitHub PATs, database passwords, API keys. If the n8n pod is compromised and credentials are stored in Kubernetes Secrets (which are base64 in etcd, not encrypted by default), an attacker gets everything.

Use this framing whenever explaining a security control — "what does an attacker gain if this is missing?"

## The Security Checklist for This Project

Work through these in order:

### 1. Non-root containers (do this first — easiest win)

```yaml
# In every Deployment's pod spec
securityContext:
  runAsNonRoot: true
  runAsUser: 1000
  runAsGroup: 1000
  fsGroup: 1000           # files created in volumes owned by this group
  seccompProfile:
    type: RuntimeDefault  # restricts syscalls to a safe default set

containers:
- name: n8n
  securityContext:
    allowPrivilegeEscalation: false    # cannot gain more privileges than parent
    readOnlyRootFilesystem: true       # can't write to container filesystem
    capabilities:
      drop:
      - ALL                            # drop ALL linux capabilities
```

After showing this, ask: "Why do we drop ALL capabilities? What's a Linux capability?" 
Answer: capabilities are fine-grained root powers (like `CAP_NET_BIND_SERVICE` to bind port <1024, `CAP_SYS_PTRACE` to debug processes). By default containers get several. Dropping all means even if exploited, the attacker can't do most privileged operations.

Note for n8n: `readOnlyRootFilesystem: true` requires mounting a writable volume for n8n's temp directory:
```yaml
volumeMounts:
- name: tmp
  mountPath: /tmp
volumes:
- name: tmp
  emptyDir: {}
```

### 2. ServiceAccounts — one per component

Never use the `default` ServiceAccount. Create specific ones:

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: n8n-main
  namespace: n8n
  annotations:
    # Workload Identity — allows this SA to access Azure resources
    azure.workload.identity/client-id: {{ .Values.keyvault.clientId }}
automountServiceAccountToken: false  # don't mount API token unless needed
```

Why separate ServiceAccounts? So you can give n8n-worker access to Key Vault secrets without giving the same access to the webhook pods. Least privilege.

### 3. Azure Key Vault CSI Driver — replace all secrets

**The problem with Kubernetes Secrets:**
```bash
# Anyone with kubectl get secret can see your "encrypted" secret
kubectl get secret n8n-postgres-password -n n8n -o jsonpath='{.data.password}' | base64 -d
# → mysecretpassword123
```

Kubernetes Secrets are base64 encoded, not encrypted. Anyone with cluster access can read them.

**Key Vault CSI Driver instead:**
```
Azure Key Vault (encrypted, access-controlled)
     ↓ CSI driver mounts secret as a file
Pod reads /mnt/secrets/postgres-password
     ↓ 
n8n reads it as an environment variable
```

```yaml
apiVersion: secrets-store.csi.x-k8s.io/v1
kind: SecretProviderClass
metadata:
  name: n8n-secrets
  namespace: n8n
spec:
  provider: azure
  parameters:
    usePodIdentity: "false"
    useVMManagedIdentity: "false"
    clientID: {{ .Values.keyvault.clientId }}
    keyvaultName: {{ .Values.keyvault.name }}
    tenantID: {{ .Values.keyvault.tenantId }}
    objects: |
      array:
        - |
          objectName: postgres-password
          objectType: secret
        - |
          objectName: n8n-encryption-key
          objectType: secret
  secretObjects:               # also creates a K8s Secret synced from Key Vault
  - secretName: n8n-secrets
    type: Opaque
    data:
    - objectName: postgres-password
      key: postgres-password
    - objectName: n8n-encryption-key
      key: encryption-key
```

Then in the Deployment:
```yaml
volumes:
- name: secrets
  csi:
    driver: secrets-store.csi.k8s.io
    readOnly: true
    volumeAttributes:
      secretProviderClass: n8n-secrets

volumeMounts:
- name: secrets
  mountPath: /mnt/secrets
  readOnly: true

env:
- name: DB_POSTGRESDB_PASSWORD
  valueFrom:
    secretKeyRef:
      name: n8n-secrets        # the synced K8s Secret
      key: postgres-password
```

**Important n8n-specific secret:** n8n uses an `N8N_ENCRYPTION_KEY` to encrypt all stored credentials. If this key is lost or rotated without migrating, all credentials become unreadable. Store it in Key Vault, never rotate it accidentally.

### 4. OPA Gatekeeper — enforce policies cluster-wide

Three constraints to implement:

**Block :latest tags:**
```yaml
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sDisallowedTags
metadata:
  name: block-latest-tag
spec:
  match:
    kinds:
    - apiGroups: ["apps"]
      kinds: ["Deployment", "StatefulSet"]
  parameters:
    tags: ["latest"]
```

**Require resource limits:**
```yaml
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sRequiredResources
metadata:
  name: require-resource-limits
spec:
  match:
    kinds:
    - apiGroups: ["apps"]
      kinds: ["Deployment"]
  parameters:
    limits: ["cpu", "memory"]
    requests: ["cpu", "memory"]
```

After each constraint, try to violate it:
```bash
# Try to apply a Deployment with :latest — should be rejected
kubectl apply -f test-latest-deployment.yaml
# → Error: [block-latest-tag] container "n8n" has disallowed image tag "latest"
```

## Verification Commands

```bash
# Check no pod uses default SA
kubectl get pods -n n8n \
  -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.serviceAccountName}{"\n"}{end}'

# Check no secrets in git history
git log -p | grep -i "password\|secret\|key\|token" | head -20

# Verify Key Vault secret is mounted
kubectl exec -it deployment/n8n-main -n n8n -- cat /mnt/secrets/postgres-password

# Check RBAC — can n8n-worker read secrets?
kubectl auth can-i get secrets -n n8n --as=system:serviceaccount:n8n:n8n-worker
# Should return "no" — workers don't need secret access
```

## Interview Explanation Template

"n8n is a high-value security target because it stores API credentials for every service it integrates with. I replaced Kubernetes Secrets with Azure Key Vault CSI driver mounts so credentials are encrypted at rest in Key Vault and never stored in etcd. I also enforced least-privilege ServiceAccounts — each of the three n8n process types has its own ServiceAccount with only the permissions it needs, and none of them use the default account. OPA Gatekeeper blocks `:latest` image tags and missing resource limits at the admission controller level, so these policies can't be bypassed even accidentally."
