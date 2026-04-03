# Cloud-Native GitOps Delivery + Observability
## How This Pipeline Supports Secure, Compliant, and Observable Delivery in Regulated Environments

---

## Overview

This repository implements a production-grade delivery platform for a financial services company. Every change is automatically traced from a Git commit through infrastructure provisioning, container build, security scanning, deployment, and observability — with immutable compliance evidence captured at every stage.

---

## Architecture Diagram

```
Developer Push (feature/JIRA-ID-*)
        │
        ▼
┌──────────────────────────────────────────────────────────────┐
│                    GitLab CI/CD Pipeline                     │
│                                                              │
│  [validate] → [lint] → [security] → [build] → [test]        │
│      │           │         │           │          │          │
│   Branch       fmt+     Checkov     Docker    Unit +         │
│   naming      tflint    tfsec      image     Integration     │
│   check       helm      Trivy     + tf plan    tests         │
│              lint      Secret                                │
│                        detect                                │
│                                                              │
│  → [deploy-dev] → [deploy-staging] → [MANUAL GATE]          │
│                                           │                  │
│                                    [deploy-prod]             │
│                                    [tf apply]                │
│                                           │                  │
│                                    [evidence package]        │
└──────────────────────────────────────────────────────────────┘
        │                                   │
        ▼                                   ▼
┌─────────────┐                   ┌──────────────────┐
│  AWS EKS    │                   │  S3 Evidence     │
│  Cluster    │                   │  Bucket          │
│             │                   │  (7yr retention) │
│  ArgoCD     │                   └──────────────────┘
│  ────────   │
│  finapp-dev │
│  finapp-    │
│  staging    │
│  finapp-prod│
└─────────────┘
        │
        ▼
┌───────────────────────┐
│  Prometheus + Grafana │
│  ─────────────────── │
│  Cluster health       │
│  App latency/errors   │
│  CI/CD trends (DORA)  │
│  ArgoCD sync status   │
└───────────────────────┘
```

---

## Part A — Infrastructure Provisioning

### What was built
- **VPC module**: Multi-AZ VPC with public/private subnets, NAT gateways, VPC Flow Logs to CloudWatch (90-day retention).
- **EKS module**: Private-endpoint-only cluster, audit logging (all 5 log types), KMS-encrypted secrets, IMDSv2-enforced nodes, encrypted EBS volumes.
- **IAM module**: Least-privilege roles for the EKS cluster, node groups, ArgoCD (IRSA), and the CI/CD runner. State backend (S3 + DynamoDB) with KMS encryption and versioning.

### How compliance is enforced
| Control | Implementation |
|---|---|
| Mandatory tags | `var.common_tags` with `Owner`, `Environment`, `CostCenter` applied to all resources via provider `default_tags` |
| No public S3 | `aws_s3_bucket_public_access_block` on every bucket + AWS Config rule `S3_BUCKET_LEVEL_PUBLIC_ACCESS_PROHIBITED` |
| No SSH/RDP from internet | Security groups have no `0.0.0.0/0` ingress on port 22/3389; enforced by Checkov (`CKV_AWS_24`, `CKV_AWS_25`) |
| CloudWatch logging | EKS: all control plane log types enabled. VPC: Flow Logs. ALB: access logging to S3. CloudTrail: multi-region, log file validation, KMS-encrypted |
| Encryption at rest | KMS CMK with auto-rotation for S3, DynamoDB, EBS, EKS secrets |

---

## Part B — CI/CD Pipeline

### Stage-by-stage breakdown

| Stage | Jobs | Gate behaviour |
|---|---|---|
| `validate` | Branch name check | Blocks non-conforming branches (`feature/JIRA-ID-description` required) |
| `lint` | `terraform fmt`, `tflint`, `helm lint`, `yamllint` | Hard fail — format errors block the pipeline |
| `security` | Checkov, tfsec, Trivy, GitLab Secret Detection | **Compliance gate**: pipeline fails on any HIGH or CRITICAL violation |
| `build` | Docker image + Terraform plan | Image tagged with commit SHA (never `latest` in prod); plan saved as artifact |
| `test` | Unit + Integration (real DB) | JUnit reports archived; coverage tracked |
| `deploy-*` | ArgoCD sync per environment | Helm diff logged before every sync |
| `deploy-prod` | **Manual approval gate** | Requires explicit human approval; approver identity recorded in evidence |
| `evidence` | Bundle + S3 upload | All artifacts zipped with SHA-256 checksums and uploaded |

### Branch convention enforcement
The `workflow:rules` block rejects any push from a branch that does not match `feature/JIRA-ID-description` or `hotfix/JIRA-ID-description`, ensuring every change is traceable to a Jira ticket before a single CI job runs.

### Release notes
The evidence stage extracts Jira IDs and commit messages (`git log --oneline --no-merges`) between the last tag and HEAD, producing a machine-readable `release-notes.md` inside every evidence bundle.

---

## Part C — GitOps Delivery

### ArgoCD application model
- **AppProject `finapp`** whitelists only the GitOps repo and the three target namespaces, preventing lateral movement.
- **Dev/Staging**: automated sync with `selfHeal: true` — the cluster always converges to Git truth.
- **Production**: automated sync is **disabled**. Deployment is triggered by the pipeline after the manual gate, and ArgoCD enforces the Helm values.

### Helm values hierarchy
```
charts/app/values.yaml        ← shared defaults (security context, probes, etc.)
       └── values-dev.yaml    ← minimal replicas, debug logging
       └── values-staging.yaml← production-like sizing
       └── values-prod.yaml   ← WAF ARN, PDB, strict HPA
```

### Rollback
`charts/argocd/rollback.sh` supports two modes:
- **ArgoCD history rollback** (preferred): `argocd app rollback finapp-prod <revision>` — re-applies a previously synced Helm revision without touching Git.
- **Emergency Helm rollback**: `helm rollback finapp <revision>` — for cases where ArgoCD is unavailable; the script then forces ArgoCD to re-sync to reconcile state.

---

## Part D — Observability

### Metrics collection
- **kube-state-metrics**: Kubernetes object state (replica counts, pod phases, HPA saturation).
- **node-exporter**: Physical node metrics (CPU, memory, disk, network).
- **Application scraping**: Pods annotated with `prometheus.io/scrape: "true"` are auto-discovered per namespace via additional scrape configs.

### Alerting rules (PrometheusRule)
| Alert | Condition | Severity |
|---|---|---|
| `NodeHighCPU` | >80% for 5m | warning |
| `NodeHighCPUCritical` | >95% for 2m | critical → PagerDuty |
| `PodCrashLooping` | >3 restarts / 15m | critical |
| `HighErrorRate` | >5% HTTP 5xx for 3m | critical |
| `HighLatencyP99` | P99 >2s for 5m | warning |
| `ArgoCDAppDegraded` | Health=Degraded for 5m | critical |

### Grafana dashboards
| Dashboard | Key panels |
|---|---|
| Cluster Health | CPU/memory per node, pod restarts, node count, pending pods |
| Application Metrics | Request rate, error %, P50/P95/P99 latency, replica count, HTTP status breakdown |
| CI/CD Trends | DORA metrics (deployment frequency, MTTR, change failure rate), security scan failures, ArgoCD sync events |

---

## Part E — Evidence & Compliance

### What is captured per pipeline run

| Artifact | Content |
|---|---|
| `terraform-plan.log` | Full `terraform plan` output showing what will change |
| `terraform-apply.log` | Apply result with resource state |
| `checkov-scan.log` + `results_junitxml.xml` | All checks, pass/fail, severity |
| `tfsec-results.json` | tfsec findings in machine-readable format |
| `trivy-scan.log` | Container CVE scan results |
| `unit-test-results.xml` | JUnit test report |
| `integration-test-results.xml` | Integration test report (real DB) |
| `helm-diff-prod.log` | Exact diff of what changed in the Helm release |
| `argocd-sync-prod.log` | Sync timeline, resource-by-resource |
| `deploy-info.env` | Environment, timestamp, deployed-by, image tag |
| `approval-evidence.env` | Approver identity, timestamp |
| `release-notes.md` | Commit messages + Jira IDs since last tag |
| `manifest.json` | SHA-256 checksums of every artifact |

### Chain of custody
The manifest's SHA-256 checksums allow auditors to verify that no artifact was modified after collection. The bundle is uploaded to S3 with KMS encryption and a 7-year lifecycle policy (STANDARD → STANDARD_IA → GLACIER → expire), matching typical financial regulatory retention requirements (SOX, PCI-DSS).

### Who approved what
The manual approval gate in GitLab records `GITLAB_USER_LOGIN` at the moment of approval. This identity, the timestamp, the pipeline URL, and the commit SHA are all written into `approval-evidence.env` inside the bundle — providing a non-repudiable record of who authorised each production change.

---

## Security Posture Summary

| Area | Control |
|---|---|
| Network | Private EKS endpoint, no public ingress on 22/3389, VPC Flow Logs |
| Identity | IRSA (no long-lived keys on nodes), IMDSv2 enforced |
| Secrets | AWS Secrets Manager + KMS; no secrets in Git (detected by Secret Detection job) |
| Images | Trivy scan in CI; ECR image scanning enabled; no `latest` tag in prod |
| IaC | Checkov + tfsec gate blocks HIGH/CRITICAL violations before apply |
| Audit | CloudTrail (multi-region, validated), AWS Config rules, Security Hub (CIS + PCI-DSS) |
| Compliance evidence | Immutable S3 bundle per pipeline run, 7-year retention |

---

## Repository Structure

```
gitops-delivery/
├── infra/                    # Terraform — AWS infrastructure
│   ├── modules/
│   │   ├── vpc/              # VPC, subnets, flow logs
│   │   ├── eks/              # EKS cluster, node groups, OIDC
│   │   └── iam/              # Roles, S3 state/evidence buckets, DynamoDB
│   ├── main.tf               # Root module composition
│   ├── variables.tf          # Input variables with validation
│   ├── outputs.tf
│   ├── backend.tf            # S3 + DynamoDB remote state
│   └── compliance.tf         # AWS Config, Security Hub, CloudTrail
├── charts/
│   ├── app/                  # Application Helm chart
│   │   ├── templates/        # Deployment, Service, HPA, PDB, SA
│   │   ├── values.yaml       # Shared defaults
│   │   ├── values-dev.yaml
│   │   ├── values-staging.yaml
│   │   └── values-prod.yaml
│   └── argocd/               # ArgoCD AppProject + Application manifests
│       ├── bootstrap.yaml
│       ├── application-dev.yaml
│       ├── application-staging.yaml
│       ├── application-prod.yaml
│       └── rollback.sh
├── pipeline/
│   └── .gitlab-ci.yml        # Full pipeline: lint→security→build→test→deploy→evidence
├── observability/
│   ├── prometheus/
│   │   ├── values.yaml       # kube-prometheus-stack Helm values
│   │   └── alert-rules.yaml  # PrometheusRule CRD
│   └── grafana/
│       ├── values.yaml       # Grafana Helm values
│       └── dashboards/
│           ├── cluster-health.json
│           ├── app-metrics.json
│           └── cicd-trends.json
└── evidence/
    ├── collect-evidence.sh   # Bundle packaging + S3 upload script
    └── sample/               # Sample evidence bundle for reference
        ├── terraform-plan.log
        ├── security-scan.log
        ├── helm-diff.log
        └── manifest.json
```
