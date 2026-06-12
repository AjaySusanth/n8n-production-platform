---
name: kubernetes-networking
description: Load this skill when writing NetworkPolicies, configuring Ingress, explaining Services, or debugging any network connectivity issue in the cluster
activation: manual
---

# Skill: Kubernetes Networking for n8n Platform

## Learner Context
Networking is the learner's self-identified weak spot. Apply maximum scaffolding here. Always draw the communication matrix BEFORE writing any policy. Never skip the curl test after each policy.

## The Three Networking Concepts That Actually Matter for This Project

Teach these three things and everything else follows:

### 1. Services — how pods find each other

A Service gives a stable DNS name and IP to a group of pods. Without it, pods die and restart with new IPs and nothing can find them.

```
Service name: redis          →  DNS: redis.n8n.svc.cluster.local
Service name: postgres       →  DNS: postgres.n8n.svc.cluster.local
Service name: n8n-main       →  DNS: n8n-main.n8n.svc.cluster.local
```

n8n-worker finds Redis by name (`QUEUE_BULL_REDIS_HOST=redis`), not by IP. The Service makes this work.

Three Service types — teach the difference:
- `ClusterIP` (default) — only reachable inside the cluster. Use for postgres, redis, internal services
- `NodePort` — opens a port on every node. Don't use this in production.
- `LoadBalancer` — creates an Azure Load Balancer with a public IP. Use only for the Ingress controller, not individual apps

### 2. Ingress — how traffic gets in from outside

Ingress is NOT a Service type. It's a reverse proxy that routes HTTP/HTTPS traffic to Services based on hostname and path.

```
Internet → Azure Load Balancer → Ingress Controller (nginx) → Service → Pod
```

For n8n specifically, two routing rules:
- `n8n.yourdomain.com/` → n8n-main Service (UI and API)
- `n8n.yourdomain.com/webhook/` → n8n-webhook Service (external webhook traffic)

Why split webhook to a separate backend? Webhook pods can be autoscaled independently from the main UI. A traffic spike from external webhooks doesn't affect the UI response time.

### 3. NetworkPolicies — how pods are isolated from each other

**Critical concept to establish:** By default, ALL pods in a cluster can talk to ALL other pods. NetworkPolicies are opt-in restrictions, not opt-in permissions.

The correct pattern is always:
1. Apply a default-deny-all policy to the namespace first
2. Then add specific allow rules for each communication path

```yaml
# Step 1: deny everything
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
  namespace: n8n
spec:
  podSelector: {}       # {} means "select ALL pods in this namespace"
  policyTypes:
  - Ingress
  - Egress
```

After this, nothing can talk to anything. Then add rules one by one.

## n8n Communication Matrix

Always show this table before writing any NetworkPolicy. Ask the learner to fill in the WHY column themselves first:

```
SOURCE              → DESTINATION    PORT   WHY
──────────────────────────────────────────────────────────────────
n8n-main            → postgres       5432   Store/read workflows and credentials
n8n-main            → redis          6379   Publish execution IDs to queue
n8n-worker          → postgres       5432   Read workflow definitions to execute
n8n-worker          → redis          6379   Pull jobs from queue, publish results
n8n-webhook         → redis          6379   Enqueue incoming webhook executions
ingress-controller  → n8n-main       5678   Serve UI and API
ingress-controller  → n8n-webhook    5678   Receive external webhook traffic
n8n-main            → internet       443    n8n phones home, npm registry for nodes
n8n-worker          → internet       443    Workflow steps call external APIs (Slack, etc.)
kube-dns            ← all pods       53     DNS resolution for service names
```

## NetworkPolicy Patterns for n8n

Teach each one with explanation, not just the YAML:

### Allow n8n-worker to reach Redis (egress from worker)
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-worker-to-redis
  namespace: n8n
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/component: worker    # applies TO worker pods
  policyTypes:
  - Egress
  egress:
  - to:
    - podSelector:
        matchLabels:
          app.kubernetes.io/name: redis      # allows TO redis pods only
    ports:
    - port: 6379
      protocol: TCP
```

Explanation to give: "This says: pods labelled `component: worker` are allowed to send traffic OUT to pods labelled `name: redis` on port 6379. Everything else is still blocked by the default-deny."

### Allow DNS (always needed, always forgotten)
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-dns
  namespace: n8n
spec:
  podSelector: {}    # applies to ALL pods
  policyTypes:
  - Egress
  egress:
  - ports:
    - port: 53
      protocol: UDP
    - port: 53
      protocol: TCP
```

**This is the most commonly forgotten policy.** Without it, pods can't resolve `redis` to an IP and everything breaks in a confusing way. Teach this early.

### Allow worker internet egress (for calling external APIs)
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-worker-egress-internet
  namespace: n8n
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/component: worker
  policyTypes:
  - Egress
  egress:
  - to:
    - ipBlock:
        cidr: 0.0.0.0/0
        except:
        - 10.0.0.0/8      # block access back to internal cluster IPs
        - 172.16.0.0/12
        - 192.168.0.0/16
    ports:
    - port: 443
      protocol: TCP
```

Explanation: "Workers need to call external APIs like Slack or GitHub. We allow outbound HTTPS to the internet but explicitly block access to private IP ranges so a compromised worker can't pivot to attack internal services."

## Testing Every Policy

After EACH NetworkPolicy, test it before moving on. Show the learner this pattern:

```bash
# Get a shell inside n8n-worker
kubectl exec -it deployment/n8n-worker -n n8n -- sh

# Test Redis connectivity (should succeed)
nc -zv redis 6379

# Test Postgres connectivity (should succeed)
nc -zv postgres 5432

# Test that worker can't reach main (should fail — they don't need to talk)
nc -zv n8n-main 5678

# Test internet access
curl -s https://api.ipify.org   # returns your external IP
```

When a connection fails unexpectedly:
```bash
# Check if a NetworkPolicy is blocking it
kubectl describe networkpolicy -n n8n

# Check pod labels (policies match on labels — wrong label = policy doesn't apply)
kubectl get pod <name> -n n8n --show-labels
```

## Ingress + TLS with cert-manager

Teach the full flow:

```
cert-manager watches for Certificate resources
→ requests a certificate from Let's Encrypt
→ Let's Encrypt sends an HTTP challenge to your domain
→ cert-manager creates a temporary pod to answer the challenge
→ Let's Encrypt issues the certificate
→ cert-manager stores it as a Kubernetes Secret
→ Ingress controller reads the Secret and serves HTTPS
```

The learner should be able to draw this flow without looking it up after completing this section.

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: n8n
  namespace: n8n
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
    nginx.ingress.kubernetes.io/proxy-body-size: "50m"  # n8n webhooks can be large
spec:
  ingressClassName: nginx
  tls:
  - hosts:
    - n8n.yourdomain.com
    secretName: n8n-tls    # cert-manager creates this Secret automatically
  rules:
  - host: n8n.yourdomain.com
    http:
      paths:
      - path: /webhook
        pathType: Prefix
        backend:
          service:
            name: n8n-webhook
            port:
              number: 5678
      - path: /
        pathType: Prefix
        backend:
          service:
            name: n8n-main
            port:
              number: 5678
```

Note: `/webhook` rule must come BEFORE `/` — Ingress matches top-to-bottom.

## Interview Explanation Template

"I implemented a default-deny NetworkPolicy for the entire n8n namespace, then whitelisted only the specific paths the application needs — workers to Redis and Postgres, webhooks to Redis, ingress to main and webhook pods. I tested every policy with kubectl exec curl commands so I know the policies are actually enforced, not just written. The Ingress routes external webhook traffic to a separate Deployment from the UI, so we can autoscale them independently."
