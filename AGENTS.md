# n8n Production Platform on AKS — Project Context

## What This Project Is

A production-grade Kubernetes platform for self-hosting n8n (workflow automation) on Azure Kubernetes Service. This is a **pure DevOps project** — zero application code. Everything here is infrastructure, configuration, pipelines, and operations.

The learner has previously used n8n as a user. This project is about running it properly in production — the way a DevOps team at a real company would.

## Why n8n Needs a Proper Architecture

Most self-hosted n8n deployments run as a single container. That breaks under real load because one process handles the UI, scheduling, webhook receiving, AND workflow execution simultaneously.

Production n8n uses **queue mode** — three separate process types:

| Process | Role | Scales based on |
|---|---|---|
| `n8n-main` | Serves UI, REST API, schedules workflows | API request rate |
| `n8n-webhook` | Receives incoming HTTP webhook triggers | Webhook traffic volume |
| `n8n-worker` | Executes actual workflows | Queue depth in Redis |

Redis is the message broker between them. Postgres is the persistent store for workflows, credentials, and execution history.

## Repository Structure

```
n8n-k8s-platform/
├── terraform/                  # IaC — AKS, ACR, Key Vault, VNet
│   ├── modules/
│   │   ├── aks/
│   │   ├── acr/
│   │   ├── keyvault/
│   │   └── networking/
│   ├── envs/
│   │   ├── dev/
│   │   └── prod/
│   └── backend.tf
├── helm/
│   └── n8n/                    # Custom Helm chart (written from scratch)
│       ├── Chart.yaml
│       ├── values.yaml
│       ├── values-prod.yaml
│       └── templates/
│           ├── _helpers.tpl
│           ├── deployment-main.yaml
│           ├── deployment-worker.yaml
│           ├── deployment-webhook.yaml
│           ├── statefulset-postgres.yaml
│           ├── statefulset-redis.yaml
│           ├── services.yaml
│           ├── ingress.yaml
│           ├── networkpolicies.yaml
│           ├── serviceaccounts.yaml
│           ├── hpa-worker.yaml         # KEDA ScaledObject
│           └── secretproviderclass.yaml
├── gitops/
│   └── argocd/
│       ├── application.yaml
│       └── project.yaml
├── .github/
│   └── workflows/
│       ├── ci.yaml             # lint, helm package, push to ACR
│       └── infra.yaml          # terraform plan/apply
├── monitoring/
│   ├── dashboards/             # Grafana dashboard JSON
│   └── alerts/                 # AlertManager rules
└── .agents/
    ├── rules/
    │   └── teaching-guide.md   # Always-on agent instructions
    └── skills/
        ├── helm/SKILL.md
        ├── terraform/SKILL.md
        ├── observability/SKILL.md
        ├── networking/SKILL.md
        └── security/SKILL.md
```

## Technology Stack

- **Cloud**: Azure (AKS, ACR, Azure Key Vault, Azure Blob for tfstate)
- **IaC**: Terraform with remote state + workspace-based environments
- **Kubernetes**: AKS, Helm (custom chart), ArgoCD, KEDA, cert-manager
- **CI/CD**: GitHub Actions with OIDC (no stored secrets)
- **Observability**: kube-prometheus-stack, custom Grafana dashboards, AlertManager
- **Security**: Azure Key Vault CSI driver, NetworkPolicies, non-root containers, OPA Gatekeeper

## Non-Negotiables

These rules apply to every file in this project. Never violate them:

1. No secrets in any file. No exceptions. All credentials via Key Vault CSI.
2. No `:latest` image tags. Pin every image to a specific digest or semver tag.
3. Every container has resource requests AND limits.
4. Every Deployment has liveness and readiness probes.
5. No pod uses the `default` ServiceAccount.
6. NetworkPolicies: default-deny namespace, then whitelist per service.
7. All changes to the cluster go through Git → ArgoCD. No manual `kubectl apply` to prod.

## Current Phase

Track progress here as each phase completes:

- [x] Phase 1: Terraform — AKS + supporting infra
- [x] Phase 2: Helm chart — write from scratch, deploy manually first
- [x] Phase 3: CI/CD — GitHub Actions + OIDC + ArgoCD
- [x] Phase 4: Observability — Prometheus, Grafana, AlertManager, KEDA
- [ ] Phase 5: Security — Key Vault CSI, NetworkPolicies, OPA Gatekeeper
- [ ] Phase 6: README + architecture diagram + interview prep
