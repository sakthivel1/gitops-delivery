# dev.tfvars — Development environment overrides
environment = "dev"
owner       = "platform-team"
cost_center = "CC-4521"

# Smaller nodes to reduce dev costs
node_groups = {
  general = {
    instance_types = ["t3.small"]
    capacity_type  = "SPOT"
    desired_size   = 1
    max_size       = 3
    min_size       = 1
    disk_size      = 20
  }
}

# Tighter CIDR — smaller dev VPC
vpc_cidr             = "10.1.0.0/16"
public_subnet_cidrs  = ["10.1.1.0/24", "10.1.2.0/24"]
private_subnet_cidrs = ["10.1.11.0/24", "10.1.12.0/24"]
availability_zones   = ["us-east-1a", "us-east-1b"]

kubernetes_version = "1.29"
tfstate_bucket     = "finapp-tfstate-457591021188"
tflock_table       = "finapp-tflock"
evidence_bucket    = "finapp-evidence-457591021188"
