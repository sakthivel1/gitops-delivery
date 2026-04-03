# staging.tfvars — Staging environment overrides
environment = "staging"
owner       = "platform-team"
cost_center = "CC-4521"

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

vpc_cidr             = "10.2.0.0/16"
public_subnet_cidrs  = ["10.2.1.0/24", "10.2.2.0/24", "10.2.3.0/24"]
private_subnet_cidrs = ["10.2.11.0/24", "10.2.12.0/24", "10.2.13.0/24"]
availability_zones   = ["us-east-1a", "us-east-1b", "us-east-1c"]

kubernetes_version = "1.29"
tfstate_bucket     = "finapp-tfstate-457591021188"
tflock_table       = "finapp-tflock"
evidence_bucket    = "finapp-evidence-457591021188"
