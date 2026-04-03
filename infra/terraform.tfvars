# terraform.tfvars — Generated for account 457591021188
# Edit before applying to a different environment.

region       = "us-east-1"
project_name = "finapp"
environment  = "prod"

# Mandatory compliance tags (enforced by AWS Config rule)
owner       = "platform-team"
cost_center = "CC-4521"

# Networking
vpc_cidr             = "10.0.0.0/16"
public_subnet_cidrs  = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
private_subnet_cidrs = ["10.0.11.0/24", "10.0.12.0/24", "10.0.13.0/24"]
availability_zones   = ["us-east-1a", "us-east-1b", "us-east-1c"]

# EKS — using t3.medium (cost-effective for this walkthrough)
kubernetes_version = "1.29"
node_groups = {
  general = {
    instance_types = ["t3.medium"]
    capacity_type  = "ON_DEMAND"
    desired_size   = 2
    max_size       = 4
    min_size       = 1
    disk_size      = 30
  }
}

# State backend (created in Step 1)
tfstate_bucket  = "finapp-tfstate-457591021188"
tflock_table    = "finapp-tflock"
evidence_bucket = "finapp-evidence-457591021188"
