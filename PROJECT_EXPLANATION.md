# GitOps Delivery Platform — Complete Project Explanation

**Project:** finapp — Financial Application GitOps Delivery Platform
**Repository:** https://github.com/sakthivel1/gitops-delivery
**Cloud:** AWS (Account: 457591021188, Region: us-east-1)
**Author:** sakthivel1
**Date:** April 2026

---

## Table of Contents

1. [What Problem Are We Solving?](#1-what-problem-are-we-solving)
2. [The Core Principle: GitOps](#2-the-core-principle-gitops)
3. [How Everything Connects](#3-how-everything-connects)
4. [Component 1 — AWS Infrastructure (Terraform)](#4-component-1--aws-infrastructure-terraform)
5. [Component 2 — Helm Chart (Application Packaging)](#5-component-2--helm-chart-application-packaging)
6. [Component 3 — The Application (Flask API)](#6-component-3--the-application-flask-api)
7. [Component 4 — Docker (Packaging the Application)](#7-component-4--docker-packaging-the-application)
8. [Component 5 — GitHub Actions CI/CD Pipeline](#8-component-5--github-actions-cicd-pipeline)
9. [Component 6 — ArgoCD (GitOps Deployment)](#9-component-6--argocd-gitops-deployment)
10. [Component 7 — Observability (Prometheus + Grafana)](#10-component-7--observability-prometheus--grafana)
11. [Evidence Collection](#11-evidence-collection)
12. [Problems Encountered and How They Were Solved](#12-problems-encountered-and-how-they-were-solved)
13. [End-to-End Flow — One Feature From Idea to Production](#13-end-to-end-flow--one-feature-from-idea-to-production)

---

## 1. What Problem Are We Solving?

Imagine a financial application team that deploys software like this:

- Developer finishes code → sends zip file to ops team
- Ops team manually SSHs into servers → runs scripts
- No one knows what version is running where
- A bug in production? No one knows what changed or when
- Rollback? Someone manually reverts files, hoping they remember what state things were in
- Compliance audit? "Uh... we have some notes somewhere..."

This is how most companies worked 5–10 years ago. It causes outages, security breaches,
failed audits, and slow delivery.

**Our platform solves all of this** by making Git the single source of truth for
everything — infrastructure, application code, and deployments. Every change is a commit.
Every deployment is automated. Every action is logged.

---

## 2. The Core Principle: GitOps

GitOps means:

- **What is in Git = What should be running in production**
- No manual server access for deployments
- No "it works on my machine" — everything runs from the same tested code
- Rollback = `git revert` (one command, 30 seconds)
- Audit trail = `git log` (who changed what, when, why)

### Traditional Deployment vs GitOps

| | Traditional | GitOps (Our Platform) |
|---|---|---|
| How to deploy | SSH + run script manually | git push → automated pipeline |
| Who deployed last? | Ask around the team | `git log` shows you |
| What version is prod running? | Check server manually | Git tag = image tag = running version |
| Rollback | Manual file restoration | `git revert` + pipeline re-runs |
| Compliance proof | Hope someone took notes | Full artifact trail, 365 days |
| Dev/Prod consistency | "Works on my machine" | Same Helm chart, same Docker image |

---

## 3. How Everything Connects

```
Developer writes code
        |
        v
git push to GitHub
        |
        v
GitHub Actions runs automatically (CI Pipeline)
  |-- Validates the code is safe and correct
  |-- Builds a Docker container image
  |-- Runs all tests
  |-- Deploys to AWS Kubernetes cluster via ArgoCD
        |
        v
AWS EKS Kubernetes Cluster
  |-- finapp-dev      (auto-deploy on every feature branch)
  |-- finapp-staging  (auto-deploy on main branch)
  |-- finapp-prod     (manual approval required)
        |
        v
Grafana + Prometheus
        |-- Monitor the running application 24/7
        |-- Alert when something goes wrong
```

---

## 4. Component 1 — AWS Infrastructure (Terraform)

### What is Terraform?

Terraform is "Infrastructure as Code." Instead of clicking around the AWS console to
create servers and networks, you write code that describes what you want, and Terraform
creates it automatically and consistently.

**Without Terraform:**
```
Engineer A clicks -> creates VPC
Engineer B clicks -> creates slightly different VPC
Production != Staging != Dev -> bugs only appear in prod
```

**With Terraform:**
```
Everyone uses the same .tf files
Dev = Staging = Prod (same structure, different sizes)
Changes reviewed in Pull Requests before applying
```

---

### 4.1 VPC (Virtual Private Cloud) — The Network

**File:** `infra/modules/vpc/main.tf`

Think of a VPC as a private office building in AWS. Inside it, you control all
the networking.

**Architecture:**
```
Internet
    |
    v
Public Subnets (3, one per availability zone)
    |-- NAT Gateways   (let private resources call out, but not receive inbound)
    |-- Load Balancers (receive web traffic, forward to pods)
    |
    v
Private Subnets (3, one per availability zone)
    |-- EKS Worker Nodes (pods run here — NEVER directly internet-accessible)
```

**Why private subnets for worker nodes?**

If a pod gets compromised, an attacker cannot directly SSH into it from the internet.
They would need to first get through the load balancer, then the application, then find
a way to reach the node — multiple layers of defense.

**Why 3 availability zones?**

AWS data centers are grouped into "availability zones" (AZs). Each AZ is a physically
separate building with its own power and networking. If us-east-1a has an outage,
us-east-1b and us-east-1c keep running. Our application stays up.

**Why NAT Gateways?**

Private subnet pods need to call out to the internet (pull Docker images, send metrics,
reach GitHub) but should NEVER receive unsolicited connections from the internet. NAT
gateways allow outbound-only internet access — like a one-way mirror.

**Why VPC Flow Logs?**

Every network packet in and out of the VPC is logged to CloudWatch. For a financial
application, this is mandatory — if there is ever a security incident, you can trace
exactly what traffic occurred, when, and between which IP addresses.

**Resources Created:**

| Resource | Count | Purpose |
|---|---|---|
| VPC | 1 | Private network (10.0.0.0/16) |
| Public Subnets | 3 | Load balancers, NAT gateways |
| Private Subnets | 3 | EKS worker nodes |
| Internet Gateway | 1 | Public subnet internet access |
| NAT Gateways | 3 | Private subnet outbound internet |
| Route Tables | 4 | Traffic routing rules |
| VPC Flow Logs | 1 | Network audit trail |
| Default SG (restricted) | 1 | Compliance: no default rules |

---

### 4.2 EKS (Elastic Kubernetes Service) — The Container Platform

**File:** `infra/modules/eks/main.tf`

**What is Kubernetes?**

Think of Kubernetes as an operating system for running containers across multiple servers.
Instead of managing "Server 1" and "Server 2," you tell Kubernetes:
"I want 3 copies of this container running at all times, with 512MB of RAM each."
Kubernetes figures out which servers to use, restarts crashed containers, and scales up
under load automatically.

**Why managed EKS instead of self-managed Kubernetes?**

Running Kubernetes yourself means managing etcd (the database), the API server,
certificate rotation, and upgrades. EKS means AWS handles all of that. You manage
only your applications.

**Key Design Decisions:**

| Decision | Reason |
|---|---|
| Private API endpoint | Kubernetes API not accessible from internet |
| KMS secrets encryption | Even raw etcd data is unreadable without the key |
| OIDC provider | Pods get AWS credentials without stored passwords |
| CloudWatch logging | Every cluster action logged permanently |
| Multi-AZ nodes | Node failure in one AZ doesn't take down the app |

---

### 4.3 IAM (Identity and Access Management) — Who Can Do What

**File:** `infra/modules/iam/main.tf`

**The Principle of Least Privilege:**

Every piece of software gets ONLY the permissions it absolutely needs. Nothing more.
If ArgoCD only needs to read secrets, it gets only `secretsmanager:GetSecretValue`.
It cannot delete EC2 instances, modify S3 buckets, or do anything else.

**Four Roles Created:**

**Role 1 — EKS Cluster Role**
Used by the Kubernetes control plane to make AWS API calls (describe EC2 instances,
create load balancers, manage network interfaces).

**Role 2 — EKS Node Role**
Used by EC2 worker nodes to:
- Pull container images from ECR
- Register themselves with the cluster
- Receive SSM sessions (secure shell without SSH keys)

**Role 3 — ArgoCD Role (IRSA)**
Used by the ArgoCD pod to read application secrets from AWS Secrets Manager.

**Role 4 — CI/CD Runner Role (GitHub Actions)**
Used by the GitHub Actions pipeline to:
- Push Docker images to ECR
- Read/write Terraform state to S3
- Lock state in DynamoDB
- Describe EKS cluster to configure kubectl

**Why IRSA (IAM Roles for Service Accounts) instead of Access Keys?**

```
Old way (insecure):
  Store AWS_ACCESS_KEY_ID in GitHub secrets
  -> Long-lived credential, can leak, must rotate manually
  -> If leaked, attacker has permanent AWS access

IRSA way (our approach):
  GitHub generates a signed JWT token for each workflow run
  -> AWS STS verifies the token via OIDC
  -> Returns temporary credentials (valid 15 minutes only)
  -> Even if intercepted, they expire before an attacker can use them
  -> No secret to rotate, no secret to leak
```

**S3 Buckets Created:**

| Bucket | Purpose | Retention |
|---|---|---|
| finapp-tfstate-457591021188 | Terraform remote state | 90 days old versions |
| finapp-evidence-457591021188 | CI/CD audit evidence | 7 years (financial compliance) |

**Why 7 years for evidence?**

Financial regulations (PCI-DSS, SOX) require audit evidence to be retained for
7 years. Every test result, security scan, and deployment record is stored here.

---

### 4.4 Compliance — AWS Config + CloudTrail + Security Hub

**File:** `infra/compliance.tf`

For a financial application, you need to prove to auditors that security controls
work continuously — not just when someone manually checks.

**AWS Config — Continuous Compliance Monitoring**

Continuously checks every AWS resource against rules:
- "Are all S3 buckets blocking public access?" — checked every change
- "Are all EBS volumes encrypted?" — checked on every change
- "Do all resources have required tags?" — checked continuously
- "Is EKS endpoint private?" — checked continuously
- "Is KMS key rotation enabled?" — checked continuously

If something drifts (someone accidentally makes an S3 bucket public), Config
detects it within minutes and flags it as non-compliant.

**AWS CloudTrail — Complete API Audit Log**

Every AWS API call is permanently logged:
```
2026-04-03 14:23:11  User: sakthivel1  Action: DeleteS3Bucket  Bucket: finapp-prod
2026-04-03 14:25:03  User: github-actions  Action: PutObject  Bucket: finapp-tfstate
```

If something bad happens, you have a complete record of who did what, from which IP,
at what time. This is legally required for financial applications.

**AWS Security Hub — Compliance Dashboard**

Aggregates findings from Config, GuardDuty (threat detection), and Inspector
(vulnerability scanning) into one dashboard. Checks against:
- **CIS AWS Foundations Benchmark** — security best practices
- **PCI-DSS v3.2.1** — required for applications handling payment data

**Terraform State Backend — S3 + DynamoDB**

Terraform stores its state in S3 so multiple team members can work together.
DynamoDB provides distributed locking — preventing two engineers from running
`terraform apply` simultaneously and corrupting the state.

```
bootstrap-backend.sh (runs ONCE manually)
    |
    v
Creates: KMS key + S3 state bucket + S3 evidence bucket + DynamoDB lock table
    |
    v
terraform init -backend-config=backend-prod.conf
terraform apply  <- creates everything else
```

---

## 5. Component 2 — Helm Chart (Application Packaging)

**Directory:** `charts/app/`

### What is Helm?

Helm is a package manager for Kubernetes. Instead of writing separate Kubernetes
YAML files for dev, staging, and production (which drift apart over time), you write
one template and supply different values per environment.

**Without Helm:**
```
deployment-dev.yaml     (300 lines)
deployment-staging.yaml (300 lines, 90% identical)
deployment-prod.yaml    (300 lines, 90% identical)
-> Someone updates dev, forgets staging -> environments drift -> prod surprises
```

**With Helm:**
```
templates/deployment.yaml  (one template)
values.yaml                (defaults)
values-dev.yaml            (1 replica, small resources)
values-staging.yaml        (2 replicas, medium resources)
values-prod.yaml           (3 replicas, large resources, stricter security)
```

### Key Design Decisions

**High Availability — Never Go Down:**
```yaml
affinity:
  podAntiAffinity:
    required: true
    topologyKey: kubernetes.io/hostname    # Never 2 pods on same node

topologySpreadConstraints:
  topologyKey: topology.kubernetes.io/zone # Spread across AZs
```

If a node crashes, only ONE pod dies. The other is on a different node. App stays up.
If an AZ goes down, only ONE pod dies. The other is in a different AZ. App stays up.

**Auto-scaling:**
```yaml
autoscaling:
  minReplicas: 2    # Always at least 2 running
  maxReplicas: 10   # Can scale to 10 under heavy load
  targetCPU: 70%    # Scale up before CPU is maxed out
```

Black Friday traffic spike? Kubernetes automatically adds more pods.
Traffic drops at night? Pods scale back down. You pay for what you actually use.

**Pod Disruption Budget:**
```yaml
podDisruptionBudget:
  minAvailable: 1
```

When Kubernetes upgrades a node, it drains pods off it first. PDB tells Kubernetes:
"Never drain pods in a way that leaves zero running." This guarantees zero-downtime
node maintenance.

**Production ALB Configuration:**
```yaml
alb.ingress.kubernetes.io/scheme: internet-facing
alb.ingress.kubernetes.io/listen-ports: '[{"HTTPS":443}]'
alb.ingress.kubernetes.io/ssl-policy: ELBSecurityPolicy-TLS13-1-2-2021-06
alb.ingress.kubernetes.io/access-logs.enabled: "true"
```

TLS 1.3 only (most secure), HTTPS-only (no plain HTTP), access logs stored to S3
for compliance.

---

## 6. Component 3 — The Application (Flask API)

**Directory:** `src/`

### Why Flask?

Flask is a lightweight Python web framework. The application itself is kept simple
because the focus of this project is the platform infrastructure. The same platform
would work for any application.

### API Endpoints and Why Each Exists

| Endpoint | Method | Purpose |
|---|---|---|
| /healthz | GET | Liveness probe — is the app process alive? |
| /ready | GET | Readiness probe — can the app serve traffic? |
| /metrics | GET | Prometheus metrics scraping |
| /api/v1/transactions | GET | List last 100 transactions |
| /api/v1/transactions | POST | Create a new transaction |

**Why Two Separate Health Endpoints?**

```
Database goes down:
  /healthz -> 200  (app process is running fine)
  /ready   -> 503  (cannot serve requests without database)

Kubernetes behaviour:
  -> Stops sending traffic to this pod (readiness fails)
  -> Does NOT restart the pod (liveness still passes)
  -> When DB recovers, /ready returns 200, traffic resumes

Without separate probes:
  -> App would restart in a loop every time the database is temporarily down
  -> Each restart takes 10+ seconds -> unnecessary downtime
```

**Why /metrics?**

The Flask app exposes Prometheus metrics:
```python
REQUEST_COUNT = Counter("http_requests_total", ...)      # Count every request
REQUEST_LATENCY = Histogram("http_request_duration_seconds", ...)  # Time every request
```

Grafana reads these metrics and shows graphs. Alerts fire when:
- Error rate exceeds 1%
- P99 latency exceeds 2 seconds
- Request rate drops suddenly (possible outage)

### Test Suite

**Unit Tests** (`tests/unit/test_app.py`):
- 7 tests covering all endpoints
- No database required — runs in milliseconds
- Tests error cases: missing amount, invalid amount type

**Integration Tests** (`tests/integration/test_transactions.py`):
- Tests against real PostgreSQL database
- Verifies the complete create -> list flow
- Skipped if DATABASE_URL is not set (safe to run anywhere)

---

## 7. Component 4 — Docker (Packaging the Application)

**File:** `Dockerfile`

### What is Docker?

Docker packages your application and ALL its dependencies into a single image.
The image runs identically on a developer laptop, in CI, in staging, and in production.
No more "it works on my machine."

### Why Multi-Stage Build?

```dockerfile
# Stage 1 — BUILD (has compilers, build tools, headers)
FROM python:3.12-alpine AS deps
RUN apk add gcc musl-dev libpq-dev    # Build tools needed to compile psycopg2
RUN pip install -r requirements.txt   # Compiles Python packages

# Stage 2 — RUNTIME (tiny, only what the app needs to RUN)
FROM python:3.12-alpine AS runtime
COPY --from=deps site-packages/       # Copy only the compiled packages
# Compilers, headers, build tools are NOT in the final image
RUN addgroup -S finapp && adduser -S -G finapp
USER finapp                           # Run as non-root user
```

**Benefits:**
- Final image is ~120MB instead of ~400MB (smaller = faster to deploy, less to scan)
- No build tools in final image = fewer attack vectors
- Non-root user = container escape cannot escalate to host root

### Why Alpine Instead of Debian?

```
python:3.12-slim (Debian):
  -> 87 OS packages installed
  -> Many packages with unfixed CVEs (glibc, openssl, etc.)
  -> Trivy security scanner was FAILING the pipeline on these

python:3.12-alpine:
  -> 39 OS packages installed
  -> Minimal CVEs, fast security patches from Alpine team
  -> Trivy scanner PASSES
```

Switching the base image from Debian to Alpine eliminated all HIGH/CRITICAL
container CVEs from our Trivy scan results.

---

## 8. Component 5 — GitHub Actions CI/CD Pipeline

**File:** `.github/workflows/ci.yml`

### What is CI/CD?

**CI (Continuous Integration):**
Every code change is automatically built, tested, and scanned. Problems are found in
minutes, not weeks later when someone notices something is broken in production.

**CD (Continuous Delivery):**
Every code change that passes CI is automatically deployable. Deployment is either
automatic (dev/staging) or a single button press with full audit trail (production).

### Pipeline Stages — Why Each Exists

---

#### Stage 1 — Branch Validation

```
Branch must match: feature/JIRA-ID-description
                   hotfix/JIRA-ID-description
Examples:
  feature/APP-123-add-payment-export    VALID
  hotfix/APP-456-fix-null-pointer       VALID
  my-changes                            INVALID -> pipeline fails immediately
```

**Why we enforce this:**

Every change is linked to a Jira ticket. You cannot push code without a business
requirement attached. This makes git history readable and traceable:

```
git log --oneline
abc123  feat: add payment export (APP-123)
def456  fix: handle null pointer in auth (APP-456)
```

In 6 months, when someone asks "why was this added?", you look up APP-123 in Jira.

---

#### Stage 2 — Linting (Code Quality Gates)

**Terraform fmt + validate:**
Checks that Terraform code is properly formatted and syntactically valid.
Fails fast on obvious errors before spending time on expensive security scans.

**tflint:**
Checks Terraform for deprecated syntax, incorrect variable types, and AWS-specific
best practices that `terraform validate` misses (like invalid instance types, missing
required fields, etc.)

**Helm lint:**
Validates the Kubernetes chart against all three environment value files (dev, staging,
prod). Catches template rendering errors that would only appear at deployment time.

**yamllint:**
Enforces consistent YAML formatting across all YAML files. YAML is whitespace-sensitive
and easy to break subtly. yamllint catches these before they reach the cluster.

---

#### Stage 3 — Security Scanning

**Checkov (Infrastructure Security):**

Scans all Terraform code against 1000+ security rules:
- "Is S3 bucket encryption enabled?"
- "Is CloudWatch log group encrypted with KMS?"
- "Does this IAM policy follow least privilege?"
- "Is EKS API endpoint private?"

Hard-fails on HIGH and CRITICAL findings. The pipeline cannot proceed unless all
high-severity security issues are resolved or explicitly documented with `checkov:skip`.

Example of a justified skip:
```hcl
resource "aws_iam_role_policy" "cicd_runner" {
  # checkov:skip=CKV_AWS_355: ECR GetAuthorizationToken requires Resource="*"
  # by AWS API design — no resource-level restriction is supported
```

The skip is documented with a reason inside the resource block (not before it —
Checkov only reads annotations inside the block).

**tfsec:**
Second opinion on Terraform security with a different ruleset. Catches different
issues from Checkov. Defense in depth.

**Gitleaks (Secret Detection):**
Scans the ENTIRE git history for accidentally committed secrets (passwords, API keys,
private keys, connection strings).

Why scan history?
```
Developer accidentally commits: password = "supersecret123"
Developer notices, deletes the line, commits again
-> The password is STILL in git history, forever visible
-> Gitleaks catches this
```

---

#### Stage 4 — Build

**Docker Build + Push to GHCR:**

Builds the Docker image and pushes to GitHub Container Registry. The image is tagged
with the git commit SHA:

```
ghcr.io/sakthivel1/gitops-delivery:a9eb01d
                                      ^
                              This IS the git commit
```

You always know exactly which code version is running in any environment. No ambiguity.

**Trivy Container Scan:**

Scans the built image for CVEs in OS packages and Python dependencies.

```
ignore-unfixed: true
```

We only fail on CVEs that HAVE an available fix. There is no point blocking a deploy
for a vulnerability that has no upstream patch — you cannot fix it until the patch exists.

Unfixed CVEs are still reported and visible in the GitHub Security tab — tracked but
not blocking.

---

#### Stage 5 — Tests

**Unit Tests (no dependencies):**
```
pytest tests/unit/ --cov=src --cov-report=xml
```
Tests individual functions in isolation. No database, no network calls.
Runs in under 10 seconds.
Covers: all API endpoints, error handling, edge cases (missing fields, invalid types).

**Integration Tests (real PostgreSQL):**
```
pytest tests/integration/
```
GitHub Actions spins up a real PostgreSQL container as a service. Tests verify the
complete create -> list flow with actual SQL queries.

Why both?

```
Unit tests find:   Logic errors, wrong status codes, missing validation
Integration tests: SQL errors, database schema issues, real transaction behaviour
Both together:     High confidence the code works in the real world
```

**Test Results as Evidence:**
Both test runs produce JUnit XML reports uploaded as artifacts. Proves to auditors
that testing happened before every deployment.

---

#### Stage 6 — Deploy to Dev

Runs only on feature branches. Automatically deploys to the dev environment after
all tests pass.

```bash
# Configure kubectl to talk to the EKS cluster
aws eks update-kubeconfig --name finapp-prod --region us-east-1

# Download ArgoCD CLI
curl -o argocd https://github.com/argoproj/argo-cd/releases/download/v2.10.4/argocd-linux-amd64

# Update the image tag in the ArgoCD application
argocd app set finapp-dev --helm-set image.tag=abc123 --port-forward --insecure

# Trigger sync and wait for healthy
argocd app sync finapp-dev --timeout 300
argocd app wait finapp-dev --health --timeout 120
```

Why `--port-forward`?
Classic AWS ELBs only support HTTP/1.1. ArgoCD CLI uses gRPC which requires HTTP/2.
`--port-forward` creates a direct kubectl tunnel to the ArgoCD server pod, bypassing
the load balancer entirely. No external LB needed.

---

## 9. Component 6 — ArgoCD (GitOps Deployment)

**Directory:** `charts/argocd/`

### The Problem ArgoCD Solves

**Without ArgoCD:**
```
CI pipeline runs: kubectl apply -f deployment.yaml
-> Deployment happens
-> Someone manually edits the deployment in the cluster (changes env vars, scales)
-> Now cluster state != Git state
-> Next deployment might revert their change unexpectedly
-> "Why does staging behave differently from dev?" -> mystery config, unknown origin
```

**With ArgoCD:**
```
ArgoCD continuously watches BOTH Git AND the live cluster
If cluster drifts from Git -> ArgoCD detects it immediately
                           -> Alerts in Slack/PagerDuty
                           -> Auto-reverts if selfHeal=true
Git is ALWAYS the source of truth. Always.
```

### Application Configuration

**Dev — Fully Automated:**
```yaml
# charts/argocd/application-dev.yaml
syncPolicy:
  automated:
    prune: true      # Delete resources removed from Git automatically
    selfHeal: true   # Revert any manual changes made in the cluster
```

Any commit to the repo immediately deploys to dev. Fast feedback loop for developers.

**Production — Manual Only:**
```yaml
# charts/argocd/application-prod.yaml
syncPolicy: {}  # Empty - NO automated sync
```

Production requires a human to explicitly run `argocd app sync finapp-prod`.
No accidental production deployments. Deliberate, reviewed, approved action only.

### ArgoCD AppProject — Security Boundary

```yaml
kind: AppProject
spec:
  sourceRepos:
    - https://github.com/sakthivel1/gitops-delivery.git  # ONLY our repo
  destinations:
    - namespace: finapp-dev      # Can ONLY deploy to these namespaces
    - namespace: finapp-staging
    - namespace: finapp-prod
```

Even if someone gets ArgoCD admin credentials, they cannot:
- Deploy from a malicious repository
- Deploy into kube-system or any other namespace
- Affect infrastructure outside the finapp namespaces

### ArgoCD Bootstrap Process

```bash
# 1. Install ArgoCD into cluster
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/v2.10.4/manifests/install.yaml

# 2. Apply our configuration (AppProject + enable apiKey for CI auth)
kubectl apply -f charts/argocd/bootstrap.yaml

# 3. Create Application objects
kubectl apply -f charts/argocd/application-dev.yaml
kubectl apply -f charts/argocd/application-staging.yaml
kubectl apply -f charts/argocd/application-prod.yaml

# 4. ArgoCD immediately syncs dev and staging from Git
# Production waits for manual sync trigger
```

---

## 10. Component 7 — Observability (Prometheus + Grafana)

**Directory:** `observability/`

### Why Monitor?

```
Without monitoring:  Users call support -> support alerts team -> team investigates
                     -> 30+ minutes before anyone knows there is a problem

With monitoring:     Alert fires at 99th percentile latency > 2s
                     -> On-call engineer paged within 60 seconds
                     -> Problem identified and fixed before most users notice
```

### How It Works

```
Flask app code
  -> Exposes /metrics endpoint (Prometheus format)
       |
       v
Prometheus
  -> Scrapes /metrics from every pod every 15 seconds
  -> Stores time-series data
  -> Evaluates alert rules
       |
       v
Grafana
  -> Reads from Prometheus
  -> Shows dashboards (graphs, charts)
  -> Sends alerts (Slack, PagerDuty)
```

### Metrics Collected

**Application Metrics (from our Flask code):**

| Metric | Type | What it tells you |
|---|---|---|
| http_requests_total | Counter | Request rate by endpoint and status code |
| http_request_duration_seconds | Histogram | Latency (P50, P90, P99) per endpoint |

**Infrastructure Metrics (from Kubernetes):**

| Metric | Alert Threshold |
|---|---|
| Pod CPU utilisation | > 80% triggers HPA scale-up |
| Pod memory utilisation | > 80% triggers HPA scale-up |
| Pod restart count | > 3 in 15 minutes = alert |
| P99 request latency | > 2 seconds = alert |
| HTTP error rate | > 1% for 5 minutes = alert |

### Auto-Provisioned Dashboards

```yaml
# observability/grafana/dashboards/configmap.yaml
metadata:
  labels:
    grafana_dashboard: "1"    # Magic label
```

Grafana's sidecar container watches for ConfigMaps with this label and automatically
loads them as dashboards. No manual dashboard importing needed after deployments.
Dashboards are code — versioned in Git, deployed with the application.

---

## 11. Evidence Collection

### Why Collect Evidence?

Financial regulations require proof that testing and security scanning occurred
before every production deployment. Without automated evidence collection, this
means someone manually writing reports — error-prone, incomplete, and slow.

Our pipeline automatically collects and uploads evidence for every run:

```
evidence-bundle/
|-- lint-terraform.log       "Terraform code was valid before deployment"
|-- tflint.log               "No deprecated syntax or best practice violations"
|-- helm-lint-dev.log        "Helm chart renders correctly for dev environment"
|-- checkov-results.xml      "No HIGH/CRITICAL security issues in infrastructure code"
|-- tfsec-results.json       "Second security scan passed"
|-- trivy-scan.sarif         "Container image had no fixable CVEs"
|-- unit-test-results.xml    "All 7 unit tests passed"
|-- coverage.xml             "Code coverage: 94%"
|-- integration-test-results.xml  "Integration tests passed against real database"
|-- terraform-plan.json      "Exactly these infrastructure changes would be made"
|-- build-info.env           "Image abc123 built at 14:23 by github-user"
|-- deploy-info.env          "Deployed to dev at 14:31, image abc123, commit abc123"
```

All artifacts retained for **365 days** in GitHub Actions.
Evidence bucket on S3 retains for **7 years** (financial compliance).

When an auditor asks: "Prove that version 2.1.4 was tested before going to production."
You download the artifact from GitHub. Done. 30 seconds. Not 3 days of searching emails.

---

## 12. Problems Encountered and How They Were Solved

### Problem 1 — Checkov skip comments not working

**Symptom:** `checkov:skip` annotations were being ignored, checks kept failing.

**Root Cause:** Checkov only reads skip annotations INSIDE the resource block.
Comments placed BEFORE the opening `resource` keyword are ignored.

**Wrong (before fix):**
```hcl
# checkov:skip=CKV_AWS_130: Public subnets need this for ALB
resource "aws_subnet" "public" {
  map_public_ip_on_launch = true
```

**Correct (after fix):**
```hcl
resource "aws_subnet" "public" {
  # checkov:skip=CKV_AWS_130: Public subnets need this for ALB
  map_public_ip_on_launch = true
```

**Lesson:** Always read tool documentation for exact annotation placement requirements.

---

### Problem 2 — Terraform backend chicken-and-egg

**Symptom:** `terraform init` failed because S3 bucket doesn't exist yet.
The S3 bucket is what Terraform uses to store state. But Terraform creates it.

**Fix:** `bootstrap-backend.sh` creates the S3 bucket, DynamoDB table, and KMS key
manually using AWS CLI before any Terraform runs. This script runs ONCE per environment.

---

### Problem 3 — No Dockerfile or application code

**Symptom:** Pipeline failed trying to build a Docker image that did not exist.

**Fix:** Created the complete application:
- `src/app.py` — Flask API with all required endpoints
- `src/database.py` — PostgreSQL connection and schema management
- `tests/unit/` — 7 unit tests
- `tests/integration/` — Integration tests
- `Dockerfile` — Multi-stage Alpine build
- `requirements.txt` — Pinned Python dependencies

---

### Problem 4 — Trivy failing on Debian CVEs

**Symptom:** Trivy scan found HIGH/CRITICAL CVEs in the base Docker image.

**Root Cause:** `python:3.12-slim` is based on Debian, which ships ~87 OS packages
with many unfixed CVEs in glibc, openssl, and other system libraries.

**Fix:** Switched base image to `python:3.12-alpine` — only 39 packages,
minimal attack surface, fast security patches. All HIGH/CRITICAL CVEs eliminated.

---

### Problem 5 — Classic ELB does not support HTTP/2 (ArgoCD gRPC failure)

**Symptom:** `argocd login` kept timing out with "gRPC connection not ready."

**Root Cause:** ArgoCD CLI uses gRPC which requires HTTP/2. Classic AWS ELBs
only support HTTP/1.1. The connection was being downgraded and failing.

**Fix:** Switched all ArgoCD CLI commands to use `--port-forward` flag:
```bash
argocd app set finapp-dev --port-forward --port-forward-namespace argocd
```
This creates a direct kubectl tunnel to the ArgoCD server pod, completely bypassing
the load balancer. No HTTP/2 negotiation issue.

---

### Problem 6 — CoreDNS forwarding loop (DNS broken for all pods)

**Symptom:** All pods in the cluster could not resolve external domain names
(github.com, etc.). Internal cluster DNS also intermittently failing.

**Root Cause:** CoreDNS was configured to forward external queries to
`/etc/resolv.conf`. Inside Kubernetes, `/etc/resolv.conf` points to the CoreDNS
ClusterIP (`172.20.0.10`) — which is CoreDNS itself. A forwarding loop.
The `loop` plugin detected this and silently shut down external DNS forwarding.

**Fix:**
```yaml
# Changed from:
forward . /etc/resolv.conf

# Changed to:
forward . 10.0.0.2  # VPC DNS resolver (VPC CIDR base + 2, always available)
```

The VPC DNS resolver at `10.0.0.2` is a real AWS IP, always routable from any
EC2 instance or pod, and handles both internal and external DNS queries.

---

### Problem 7 — Cross-node ClusterIP routing broken

**Symptom:** Pods in the `argocd` namespace could not reach CoreDNS (ClusterIP
`172.20.0.10`). DNS worked in `default` namespace but not in `argocd` namespace.

**Root Cause:** Both CoreDNS pods were scheduled on node `ip-10-0-13-83`.
ArgoCD pods were on node `ip-10-0-12-125`. The iptables rules routing ClusterIP
traffic across nodes were not working (kube-proxy issue after node recycle).

**Fix:** Patched all ArgoCD deployments with direct CoreDNS pod IPs as nameservers:
```json
{
  "dnsPolicy": "None",
  "dnsConfig": {
    "nameservers": ["10.0.13.22", "10.0.13.230"]
  }
}
```
This bypasses the broken ClusterIP path and talks directly to the CoreDNS pods.

---

### Problem 8 — GitHub Actions got 401 from EKS API

**Symptom:** `kubectl` commands from the GitHub Actions runner failed with
"the server has asked for the client to provide credentials."

**Root Cause:** EKS maps IAM roles to Kubernetes users via the `aws-auth` ConfigMap.
The `finapp-prod-cicd-runner-role` was not in this ConfigMap. Any request from that
role was rejected with a 401.

**Fix:** Added the role to aws-auth:
```yaml
- rolearn: arn:aws:iam::457591021188:role/finapp-prod-cicd-runner-role
  username: cicd-runner
  groups:
    - cicd-deployers
```

And created a ClusterRoleBinding granting `cicd-deployers` permission to patch
ArgoCD Application objects.

---

### Problem 9 — ArgoCD app pointing at wrong repository

**Symptom:** ArgoCD reported "repository not accessible" for
`argoproj/argocd-example-apps.git`.

**Root Cause:** The ArgoCD Application manifests still had the old GitLab URL
from before the project was migrated to GitHub.

**Fix:** Updated all three Application manifests:
```yaml
# Before:
repoURL: https://gitlab.company.com/platform/gitops.git

# After:
repoURL: https://github.com/sakthivel1/gitops-delivery.git
```

---

## 13. End-to-End Flow — One Feature From Idea to Production

```
STEP 1 — Requirement
  Product manager creates Jira ticket: APP-123 "Add transaction history export"

STEP 2 — Development
  git checkout -b feature/APP-123-transaction-export
  # Developer writes code in src/
  # Developer writes tests in tests/
  git add . && git commit -m "feat: add transaction export endpoint"
  git push origin feature/APP-123-transaction-export

STEP 3 — CI Pipeline triggers automatically (~8 minutes total)

  validate-branch    [30s]
    PASS  Branch name matches: feature/APP-123-transaction-export
    PASS  Jira ID extracted: APP-123

  lint-terraform     [1m]
    PASS  terraform fmt check passed
    PASS  terraform validate passed

  lint-helm          [30s]
    PASS  helm lint values-dev.yaml passed
    PASS  helm lint values-staging.yaml passed
    PASS  helm lint values-prod.yaml passed

  lint-yaml          [20s]
    PASS  yamllint passed for all YAML files

  security-checkov   [2m]
    PASS  No HIGH or CRITICAL IaC security issues

  security-tfsec     [1m]
    PASS  No HIGH security findings in Terraform

  security-gitleaks  [30s]
    PASS  No secrets found in git history

  build-docker       [2m]
    PASS  Image built: ghcr.io/sakthivel1/gitops-delivery:abc123
    PASS  Image pushed to GHCR

  security-trivy     [1m]
    PASS  No fixable HIGH/CRITICAL CVEs in image abc123

  test-unit          [30s]
    PASS  7/7 unit tests passed
    PASS  Code coverage: 94%

  test-integration   [1m]
    PASS  3/3 integration tests passed against PostgreSQL

  deploy-dev         [2m]
    PASS  kubectl configured for finapp-prod cluster
    PASS  ArgoCD updated finapp-dev: image.tag=abc123
    PASS  ArgoCD sync completed
    PASS  App health check passed
    INFO  Evidence bundle uploaded (12 files, 365-day retention)

STEP 4 — Developer Testing
  Developer visits dev URL, tests the new export feature
  Feature works as expected

STEP 5 — Pull Request
  Developer opens PR: "feat: add transaction export (APP-123)"
  GitHub shows: All 11 checks passed
  Team lead reviews code, approves PR

STEP 6 — Merge to Main
  PR merged to main branch
  Deploy pipeline triggers automatically

  deploy-staging     [auto]
    PASS  ArgoCD syncs finapp-staging with image abc123
    PASS  QA team tests staging

  terraform-plan     [3m]
    INFO  Plan shows: 0 infrastructure changes (code-only change)
    PASS  Plan artifact uploaded for review

  Manual Approval Gate — "Deploy to Production"
    Tech lead reviews the plan
    Tech lead clicks "Approve" in GitHub Environments
    [approval logged with tech lead's GitHub username + timestamp]

  deploy-prod        [3m]
    PASS  ArgoCD syncs finapp-prod with image abc123
    PASS  Rolling deploy: old pods replaced one by one
    PASS  PDB ensures minimum 1 pod running throughout
    PASS  Health checks pass after deployment

  evidence-package   [1m]
    PASS  Complete evidence bundle archived to S3 (7-year retention)

STEP 7 — Complete Audit Trail

  Git log shows:
    abc123  feat: add transaction export endpoint  [sakthivel1]

  PR shows:
    Author: sakthivel1
    Reviewer/Approver: tech-lead-name
    All checks: PASSED

  GitHub Environments shows:
    Production approval: tech-lead-name  2026-04-05 14:23:11 UTC

  Evidence bundle shows:
    - Checkov scan: PASSED (no HIGH issues)
    - Unit tests: 7/7 PASSED
    - Integration tests: 3/3 PASSED
    - Image built: abc123 at 14:15:03
    - Deployed to prod: abc123 at 14:31:47
    - Deployed by: github-actions (approved by tech-lead-name)

  If auditor asks in 2028:
    "Prove that APP-123 was tested before going to production in April 2026."
    -> Download evidence artifact from S3
    -> Show Jira ticket APP-123
    -> Done. 2 minutes. Not 2 days.
```

---

## Security Controls Summary

| Control | What it does | Why it matters |
|---|---|---|
| No stored AWS credentials | GitHub OIDC -> temporary STS tokens | Leaked credentials expire in 15 min |
| Private EKS endpoint | Kubernetes API not on internet | No remote API attacks |
| Private worker nodes | Pods not directly reachable | Attacker must get through app first |
| KMS encryption everywhere | S3, DynamoDB, CloudWatch, EKS secrets | Data useless without KMS key access |
| Non-root container | USER finapp in Dockerfile | Container escape cannot escalate |
| Image scanning (Trivy) | Scans every build for CVEs | Catch vulnerabilities before deploy |
| IaC scanning (Checkov+tfsec) | Scans Terraform for misconfigs | Catch security mistakes before apply |
| Secret scanning (Gitleaks) | Scans full git history | Catch accidentally committed secrets |
| CloudTrail | Logs every AWS API call | Complete audit trail of all actions |
| AWS Config | Continuous compliance checks | Catch drift within minutes |
| Security Hub CIS + PCI-DSS | Compliance framework validation | Prove compliance to auditors |
| Pod anti-affinity | Pods spread across nodes/AZs | Single failure does not take down app |
| Network segmentation | Private subnets, NAT only | No unsolicited inbound internet traffic |
| TLS 1.3 only (production) | Strict SSL policy on ALB | No weak cipher attacks |
| Key rotation | KMS annual auto-rotation | Limits blast radius of key compromise |

---

## Repository Structure

```
gitops-delivery/
|
|-- .github/workflows/
|   |-- ci.yml              GitHub Actions CI pipeline (feature branches)
|   |-- deploy.yml          GitHub Actions deploy pipeline (main branch)
|
|-- charts/
|   |-- app/                Helm chart for the finapp application
|   |   |-- templates/      Kubernetes resource templates
|   |   |-- values.yaml     Default values
|   |   |-- values-dev.yaml     Dev environment overrides
|   |   |-- values-staging.yaml Staging environment overrides
|   |   |-- values-prod.yaml    Production environment overrides
|   |
|   |-- argocd/             ArgoCD configuration
|       |-- bootstrap.yaml          AppProject + argocd-cm setup
|       |-- application-dev.yaml    Dev Application (auto-sync)
|       |-- application-staging.yaml Staging Application (auto-sync)
|       |-- application-prod.yaml   Prod Application (manual sync)
|       |-- cicd-rbac.yaml          ClusterRole for GitHub Actions
|       |-- netpol-egress.yaml      Allow-all egress NetworkPolicy
|
|-- infra/
|   |-- modules/
|   |   |-- vpc/            Network module
|   |   |-- eks/            Kubernetes cluster module
|   |   |-- iam/            Roles and policies module
|   |   |-- alb-logging/    Load balancer logging module
|   |
|   |-- main.tf             Root module (composes all modules)
|   |-- compliance.tf       AWS Config + CloudTrail + Security Hub
|   |-- variables.tf        Input variable definitions
|   |-- outputs.tf          Output value definitions
|   |-- backend.tf          S3 remote state backend config
|   |-- terraform.tfvars    Environment configuration values
|   |-- bootstrap-backend.sh One-time backend setup script
|
|-- observability/
|   |-- grafana/dashboards/ Grafana dashboard ConfigMaps
|
|-- pipeline/
|   |-- generate-release-notes.sh  Automated release notes generator
|
|-- src/                    Flask application source code
|   |-- __init__.py
|   |-- app.py              Flask app factory and API routes
|   |-- database.py         PostgreSQL connection and schema
|
|-- tests/
|   |-- unit/               Unit tests (no external dependencies)
|   |-- integration/        Integration tests (requires PostgreSQL)
|
|-- Dockerfile              Multi-stage Alpine container build
|-- requirements.txt        Python production dependencies
|-- requirements-test.txt   Python test dependencies
|-- .trivyignore            Documented CVE exceptions
|-- .yamllint.yml           YAML linting configuration
|-- IMPLEMENTATION.md       Technical implementation details
|-- PROJECT_EXPLANATION.md  This document
```
