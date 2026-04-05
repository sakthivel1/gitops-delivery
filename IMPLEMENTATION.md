# GitOps Delivery Platform — Implementation Document

## Project Overview

**Project Name:** finapp — Financial Application GitOps Delivery Platform  
**Repository:** https://github.com/sakthivel1/gitops-delivery  
**Cloud Provider:** AWS (Account: 457591021188, Region: us-east-1)  
**Methodology:** GitOps — every change to infrastructure and application is driven by Git commits  

---

## Why GitOps?

Traditional deployments rely on manual steps, shell scripts run by individuals, and no audit trail. GitOps solves this by making Git the single source of truth:

- Every infrastructure change is a pull request
- Every deployment is triggered by a commit
- Every environment is reproducible from code
- Every action is logged in Git history (audit trail for compliance)
- Rollback = `git revert`

---

## Architecture Overview

```
Developer → GitHub (git push)
                ↓
         GitHub Actions CI/CD
         ┌─────────────────────────────────────────┐
         │ validate → lint → security → build →    │
         │ test → deploy-dev                        │
         └─────────────────────────────────────────┘
                ↓                        ↓
         GHCR (Docker image)      ArgoCD (GitOps sync)
                                         ↓
                              AWS EKS Cluster
                              ┌────────────────────┐
                              │ finapp-dev          │
                              │ finapp-staging      │
                              │ finapp-prod         │
                              └────────────────────┘
```

---

## Part A — Infrastructure (Terraform Modules)

### Why Terraform?

Terraform manages AWS infrastructure as code. Instead of clicking in the AWS console (error-prone, not repeatable), every resource is declared in `.tf` files, reviewed in PRs, and applied via CI/CD.

### Module Structure

```
infra/
├── main.tf              # Root — composes all modules
├── variables.tf         # Input variables
├── outputs.tf           # Output values
├── backend.tf           # S3 remote state backend
├── compliance.tf        # AWS Config + CloudTrail + Security Hub
├── terraform.tfvars     # Environment values
├── environments/
│   └── dev.tfvars       # Dev-specific overrides
└── modules/
    ├── vpc/             # Networking
    ├── eks/             # Kubernetes cluster
    ├── iam/             # Roles and policies
    └── alb-logging/     # Load balancer access logs
```

---

### Module 1 — VPC (infra/modules/vpc/)

**What it creates:**
- VPC with CIDR `10.0.0.0/16`
- 3 public subnets (one per AZ) — for NAT gateways and load balancers
- 3 private subnets (one per AZ) — for EKS worker nodes (never directly internet-accessible)
- Internet Gateway — allows public subnets to reach the internet
- 3 NAT Gateways — allow private subnet pods to make outbound internet calls (pull images, reach GitHub)
- Route tables — wires subnets to gateways
- VPC Flow Logs → CloudWatch — captures all network traffic for security auditing
- Default Security Group — restricted to no rules (compliance requirement CKV2_AWS_12)

**Why this design:**
- Worker nodes in private subnets = no direct internet exposure
- NAT gateways = pods can pull container images and reach external APIs (GitHub, ECR) without being publicly reachable
- Three AZs = high availability; if one AZ fails, workloads shift to others
- Flow Logs = required for PCI-DSS and CIS compliance (every network packet logged)

**Key outputs:**
```
vpc_id             → used by EKS module
private_subnet_ids → EKS nodes placed here
public_subnet_ids  → ALB placed here
```

---

### Module 2 — EKS (infra/modules/eks/)

**What it creates:**
- EKS control plane (managed by AWS)
- EKS node group — EC2 instances running Kubernetes worker nodes
- Security groups — controls traffic between nodes and control plane
- KMS encryption — Kubernetes secrets encrypted at rest
- CloudWatch log group — control plane logs (API server, audit, scheduler)
- OIDC provider — enables pods to assume IAM roles without stored credentials (IRSA)

**Why this design:**
- Managed control plane = AWS handles etcd, API server patching, HA
- Private endpoint = control plane API not exposed to internet
- OIDC/IRSA = pods get temporary AWS credentials via service account annotations instead of long-lived access keys stored in secrets
- KMS secrets encryption = even if someone gets raw etcd data, secrets are unreadable without the KMS key

**Node group configuration (terraform.tfvars):**
```hcl
node_groups = {
  general = {
    instance_types = ["t3.medium"]
    capacity_type  = "ON_DEMAND"
    desired_size   = 2
    max_size       = 5
    min_size       = 1
    disk_size      = 30
  }
}
```

---

### Module 3 — IAM (infra/modules/iam/)

**What it creates:**

| Role | Used By | Permissions |
|---|---|---|
| `eks-cluster-role` | EKS control plane | AmazonEKSClusterPolicy |
| `eks-node-role` | EC2 worker nodes | EKS worker + ECR read + SSM |
| `argocd-role` | ArgoCD pod (IRSA) | SecretsManager read |
| `cicd-runner-role` | GitHub Actions | ECR push + S3 + DynamoDB + EKS describe |

**Why IRSA instead of access keys:**
- Access keys are long-lived secrets that can leak
- IRSA grants temporary credentials (15 min TTL) via AWS STS
- Credentials are scoped to the specific pod's service account
- No secrets to rotate or accidentally commit to Git

**S3 buckets created:**
- `finapp-tfstate-457591021188` — Terraform remote state (versioned, KMS encrypted, lifecycle: 90 days)
- `finapp-evidence-457591021188` — CI/CD audit evidence (versioned, KMS encrypted, lifecycle: 7 years for financial compliance)

**DynamoDB table:**
- `finapp-tflock` — Terraform state locking (prevents concurrent applies corrupting state)

---

### Module 4 — Compliance (infra/compliance.tf)

**What it creates:**

| Resource | Purpose |
|---|---|
| AWS Config recorder | Records all resource configuration changes |
| AWS Config rules | Enforces: no public S3, required tags, encrypted EBS, KMS rotation, no public EKS endpoint |
| AWS CloudTrail | Logs every AWS API call — who did what, when, from where |
| Security Hub | Aggregates findings from Config, GuardDuty; checks CIS and PCI-DSS standards |
| KMS key policy | Allows CloudTrail to encrypt logs; root account to manage key |
| CloudWatch log group | CloudTrail logs streamed here for real-time alerting |

**Why this matters:**
- Financial applications require audit trails (PCI-DSS, SOC2)
- Config rules act as continuous compliance gates — any drift is detected automatically
- CloudTrail answers: "Who deleted that S3 bucket at 3am?" 
- Security Hub gives a single dashboard view of compliance posture

---

### Bootstrap Process

Before Terraform can store state, the S3 bucket must exist. Chicken-and-egg problem solved by `bootstrap-backend.sh`:

```
bootstrap-backend.sh runs ONCE manually
    ↓
Creates: KMS key → S3 state bucket → S3 evidence bucket → DynamoDB lock table
    ↓
Writes: backend-prod.conf + terraform.tfvars
    ↓
Now terraform init -backend-config=backend-prod.conf works
    ↓
terraform apply creates everything else
```

---

## Part B — Kubernetes Application (Helm Chart)

### Why Helm?

Helm packages Kubernetes manifests as templated charts. Instead of duplicating YAML for dev/staging/prod, one chart with different `values-<env>.yaml` files covers all environments.

### Chart Structure

```
charts/app/
├── Chart.yaml              # Chart metadata
├── values.yaml             # Default values (all environments)
├── values-dev.yaml         # Dev overrides
├── values-staging.yaml     # Staging overrides
├── values-prod.yaml        # Prod overrides
└── templates/
    ├── deployment.yaml
    ├── service.yaml
    ├── ingress.yaml
    ├── hpa.yaml             # Horizontal Pod Autoscaler
    └── pdb.yaml             # Pod Disruption Budget
```

### Key Design Decisions

**High Availability:**
```yaml
replicaCount: 2

affinity:
  podAntiAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
      # Force pods onto different nodes
      topologyKey: kubernetes.io/hostname

topologySpreadConstraints:
  # Spread across AZs
  - topologyKey: topology.kubernetes.io/zone
```
Pods are forced onto different nodes AND different AZs. If one node or AZ fails, the app stays up.

**Auto-scaling:**
```yaml
autoscaling:
  minReplicas: 2
  maxReplicas: 10
  targetCPUUtilizationPercentage: 70
```
HPA scales pods up under load, down when idle — cost-efficient and resilient.

**Pod Disruption Budget:**
```yaml
podDisruptionBudget:
  minAvailable: 1
```
Kubernetes will never evict pods in a way that leaves zero running — protects during node upgrades.

**ALB Ingress (production):**
```yaml
alb.ingress.kubernetes.io/scheme: internet-facing
alb.ingress.kubernetes.io/listen-ports: '[{"HTTPS":443}]'
alb.ingress.kubernetes.io/ssl-policy: ELBSecurityPolicy-TLS13-1-2-2021-06
alb.ingress.kubernetes.io/access-logs.enabled: "true"
```
TLS 1.3 only, access logs for compliance, HTTPS-only.

---

## Part C — Application Code

### Why Flask?

The application is a Python Flask financial transaction API. Flask was chosen for simplicity — the focus of this project is the platform, not the app itself.

### Application Structure

```
src/
├── __init__.py
├── app.py       # Flask app factory, routes
└── database.py  # PostgreSQL connection, schema init

tests/
├── unit/
│   └── test_app.py         # 7 unit tests, no DB required
└── integration/
    └── test_transactions.py # Integration tests with real PostgreSQL
```

### API Endpoints

| Method | Path | Purpose |
|---|---|---|
| GET | `/healthz` | Liveness probe — is the app running? |
| GET | `/ready` | Readiness probe — can the app serve traffic? |
| GET | `/metrics` | Prometheus metrics scraping |
| GET | `/api/v1/transactions` | List last 100 transactions |
| POST | `/api/v1/transactions` | Create a transaction |

### Why separate /healthz and /ready?

- **Liveness** (`/healthz`): If this fails, Kubernetes restarts the pod. Should only fail if the app is truly broken.
- **Readiness** (`/ready`): If this fails, Kubernetes stops sending traffic but doesn't restart. Used during startup and DB connection issues.

This prevents the thundering herd problem: if the DB is down, pods become unready (traffic stops) but don't restart in a loop.

### Prometheus Metrics

```python
REQUEST_COUNT = Counter("http_requests_total", ...)
REQUEST_LATENCY = Histogram("http_request_duration_seconds", ...)
```

Every request is counted and timed. Grafana dashboards (in `observability/`) visualise these metrics. Alerts fire when latency or error rates exceed thresholds.

---

## Part D — Docker Build

### Why Multi-stage Build?

```dockerfile
FROM python:3.12-alpine AS deps    # Build stage — has gcc, headers
  pip install -r requirements.txt

FROM python:3.12-alpine AS runtime # Runtime stage — minimal
  COPY --from=deps site-packages/
  USER finapp                      # Non-root
```

Two-stage build means:
- Build tools (gcc, headers) are NOT in the final image → smaller attack surface
- Final image is ~80MB vs ~400MB for a single-stage build
- Alpine base has far fewer CVEs than Debian (`python:3.12-slim`)

### Security Hardening

```dockerfile
RUN addgroup -S finapp && adduser -S -G finapp
USER finapp          # Never run as root
EXPOSE 8080
HEALTHCHECK ...      # Docker-level health check
```

Running as non-root prevents container escapes from escalating to host root.

---

## Part E — GitHub Actions CI/CD Pipeline

### Why GitHub Actions?

GitHub Actions is native to GitHub — no separate CI server to maintain. Workflows are YAML files in `.github/workflows/`, versioned alongside the code they build.

### Pipeline Flow

```
git push (feature branch)
        ↓
┌──────────────────────────────────────────────────────┐
│ STAGE 1: validate                                    │
│ • Enforce branch naming: feature/JIRA-ID-description │
│ • Extract Jira ticket ID                             │
└──────────────────────────────────────────────────────┘
        ↓
┌──────────────────────────────────────────────────────┐
│ STAGE 2: lint (parallel jobs)                        │
│ • terraform fmt + validate (-backend=false)          │
│ • tflint — Terraform best practices                  │
│ • helm lint — chart validity for all envs            │
│ • yamllint — YAML syntax                             │
└──────────────────────────────────────────────────────┘
        ↓
┌──────────────────────────────────────────────────────┐
│ STAGE 3: security (parallel jobs)                    │
│ • Checkov — IaC security scanning (hard fail: HIGH)  │
│ • tfsec — Terraform security scanning                │
│ • Gitleaks — secret detection in git history         │
└──────────────────────────────────────────────────────┘
        ↓
┌──────────────────────────────────────────────────────┐
│ STAGE 4: build                                       │
│ • Docker build → push to GHCR                        │
│ • Trivy — container vulnerability scan               │
└──────────────────────────────────────────────────────┘
        ↓
┌──────────────────────────────────────────────────────┐
│ STAGE 5: test (parallel)                             │
│ • pytest unit tests + coverage report                │
│ • pytest integration tests (real PostgreSQL)         │
└──────────────────────────────────────────────────────┘
        ↓
┌──────────────────────────────────────────────────────┐
│ STAGE 6: deploy-dev (feature branches only)          │
│ • aws eks update-kubeconfig                          │
│ • argocd app set (update image tag)                  │
│ • argocd app sync + wait                             │
└──────────────────────────────────────────────────────┘
```

### AWS Authentication — OIDC (No Stored Keys)

**Old way (insecure):**
```
AWS_ACCESS_KEY_ID = AKIA...  ← stored in GitHub secrets, long-lived, can leak
AWS_SECRET_ACCESS_KEY = ...
```

**Our way (OIDC):**
```
GitHub Actions generates a signed JWT token for each run
    ↓
AWS STS validates the token against the OIDC provider
    ↓
AWS returns temporary credentials (15 min TTL)
    ↓
Pipeline uses credentials → they expire automatically
```

No secret to rotate, no secret to leak. Even if someone intercepts the token, it expires in 15 minutes.

### Evidence Collection

Every job uploads artifacts to GitHub:
```
evidence-bundle/
├── lint-terraform.log
├── tflint.log
├── helm-lint-dev.log
├── checkov-results.xml
├── tfsec-results.json
├── trivy-scan.sarif
├── unit-test-results.xml
├── coverage.xml
├── terraform-plan.json
├── build-info.env
└── deploy-info.env
```

Retained for 365 days. For financial compliance audits, you can prove exactly what was deployed, when, by whom, with what test results.

---

## Part F — ArgoCD GitOps

### Why ArgoCD?

Without GitOps, deployments work like this:
```
CI pipeline → kubectl apply → cluster   ← no one is watching for drift
```

With ArgoCD:
```
Git (desired state) ←→ ArgoCD ←→ EKS cluster (actual state)
                          ↑
                    continuously reconciles
                    alerts on drift
                    auto-heals if selfHeal=true
```

If someone manually changes a deployment in the cluster, ArgoCD detects the drift and reverts it to match Git. Git is always the truth.

### Application Configuration

```yaml
# charts/argocd/application-dev.yaml
spec:
  source:
    repoURL: https://github.com/sakthivel1/gitops-delivery.git
    path: charts/app
    helm:
      valueFiles:
        - values.yaml
        - values-dev.yaml

  syncPolicy:
    automated:
      prune: true      # Delete resources removed from Git
      selfHeal: true   # Revert manual changes in cluster
```

**Production is different — no automated sync:**
```yaml
# charts/argocd/application-prod.yaml
syncPolicy: {}   # Manual sync required — human approval needed
```

Production requires a deliberate `argocd app sync finapp-prod` — no accidental deploys.

### ArgoCD Bootstrap

```
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/v2.10.4/manifests/install.yaml
kubectl apply -f charts/argocd/bootstrap.yaml    ← creates AppProject + enables apiKey
kubectl apply -f charts/argocd/application-dev.yaml
kubectl apply -f charts/argocd/application-staging.yaml
kubectl apply -f charts/argocd/application-prod.yaml
```

---

## Part G — Observability

### Stack

```
Prometheus → scrapes /metrics from all pods
Grafana    → visualises Prometheus data
```

### Dashboard ConfigMaps

```
observability/grafana/dashboards/configmap.yaml
```

Grafana's sidecar automatically discovers ConfigMaps labelled `grafana_dashboard: "1"` and loads them — no manual dashboard import needed.

### What is monitored:

| Metric | Alert Threshold |
|---|---|
| HTTP request rate | Baseline + 2σ |
| HTTP error rate | > 1% for 5 min |
| P99 latency | > 2 seconds |
| Pod restarts | > 3 in 15 min |
| CPU utilisation | > 80% (triggers HPA) |
| Memory utilisation | > 80% |

---

## Problems Encountered and How They Were Solved

### 1. Checkov skip comments not working
**Problem:** `checkov:skip` placed before resource blocks had no effect.  
**Root cause:** Checkov only reads skip annotations INSIDE the resource block.  
**Fix:** Moved all skip comments inside their respective resource blocks.

### 2. Terraform backend chicken-and-egg
**Problem:** Terraform needs S3 to store state, but S3 is created by Terraform.  
**Fix:** `bootstrap-backend.sh` creates the S3 bucket manually before any Terraform runs.

### 3. Docker build failed — no Dockerfile
**Problem:** Pipeline tried to build a Docker image but no app code or Dockerfile existed.  
**Fix:** Created the Flask app (`src/`), Dockerfile (multi-stage Alpine), and test suite.

### 4. Trivy scan failing on Debian CVEs
**Problem:** `python:3.12-slim` (Debian) has many unfixed HIGH/CRITICAL CVEs.  
**Fix:** Switched to `python:3.12-alpine` — far smaller attack surface.

### 5. ArgoCD can't reach GitHub (DNS broken)
**Problem:** CoreDNS was forwarding to `/etc/resolv.conf` which pointed back to itself — a loop.  
**Root cause:** The `loop` plugin detected this and silently shut down DNS forwarding.  
**Fix:** Changed CoreDNS forwarder from `/etc/resolv.conf` to `10.0.0.2` (VPC DNS resolver).

### 6. Cross-node ClusterIP routing broken
**Problem:** Pods on node `10.0.12.x` couldn't reach ClusterIP `172.20.0.10` (CoreDNS on node `10.0.13.x`).  
**Fix:** Patched ArgoCD deployments with direct CoreDNS pod IPs as nameservers.

### 7. ArgoCD CLI failing — classic ELB doesn't support HTTP/2
**Problem:** gRPC requires HTTP/2; classic ELB only supports HTTP/1.1.  
**Fix:** Switched pipeline to `argocd --port-forward --port-forward-namespace argocd` which uses kubectl tunnel directly — no LB needed.

### 8. aws-auth missing cicd-runner-role
**Problem:** GitHub Actions runner assumed the CICD role but it wasn't in `aws-auth` — got 401 from EKS API.  
**Fix:** Added `finapp-prod-cicd-runner-role` to `aws-auth` ConfigMap with `cicd-deployers` group + created ClusterRoleBinding.

---

## Security Controls Summary

| Control | Implementation |
|---|---|
| No stored AWS credentials | GitHub OIDC → AWS STS temporary credentials |
| No public EKS endpoint | Private cluster, VPN/bastion required |
| No public S3 buckets | `block_public_acls = true` on all buckets |
| Secrets encrypted at rest | KMS encryption on EKS, S3, DynamoDB, CloudWatch |
| Container non-root | `USER finapp` in Dockerfile, `runAsNonRoot: true` |
| Image vulnerability scanning | Trivy on every build |
| IaC security scanning | Checkov + tfsec on every push |
| Secret detection | Gitleaks scans full git history |
| Audit logging | CloudTrail logs all AWS API calls |
| Compliance monitoring | AWS Config rules + Security Hub (CIS + PCI-DSS) |
| Network segmentation | Pods in private subnets, NAT for egress only |
| Key rotation | KMS automatic annual rotation enabled |

---

## Repository Structure

```
gitops-delivery/
├── .github/workflows/
│   ├── ci.yml              # Feature branch pipeline
│   └── deploy.yml          # Main branch deploy pipeline
├── charts/
│   ├── app/                # Application Helm chart
│   └── argocd/             # ArgoCD Application manifests
├── infra/
│   ├── modules/
│   │   ├── vpc/
│   │   ├── eks/
│   │   ├── iam/
│   │   └── alb-logging/
│   ├── main.tf
│   ├── compliance.tf
│   └── bootstrap-backend.sh
├── observability/
│   └── grafana/dashboards/
├── pipeline/
│   └── generate-release-notes.sh
├── src/                    # Flask application
├── tests/                  # Unit + integration tests
├── Dockerfile
├── requirements.txt
└── .trivyignore
```

---

## Flow Summary — From Code to Production

```
1. Developer creates branch: feature/APP-123-add-payment
2. Writes code, commits, pushes to GitHub
3. CI pipeline triggers automatically:
   a. Branch name validated
   b. Terraform linted and validated
   c. Helm chart linted
   d. Checkov + tfsec security scan
   e. Gitleaks secret scan
   f. Docker image built and pushed to GHCR
   g. Trivy scans the image
   h. Unit tests run (pytest)
   i. Integration tests run (pytest + PostgreSQL)
   j. ArgoCD syncs finapp-dev automatically
4. Developer opens PR to main
5. PR requires all CI checks green
6. Reviewer approves
7. Merge to main triggers deploy pipeline:
   a. Deploy to staging (automated)
   b. Terraform plan generated
   c. Manual approval gate for production
   d. Terraform apply (if infra changed)
   e. ArgoCD sync finapp-prod (manual trigger)
   f. Evidence bundle packaged and archived
```

Every step produces evidence. Every decision is in Git. Every secret is temporary. Every deployment is reproducible.
