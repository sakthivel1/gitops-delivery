variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name (used as prefix for all resources)"
  type        = string
}

variable "environment" {
  description = "Deployment environment (dev, staging, prod)"
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be dev, staging, or prod."
  }
}

# ---- Mandatory compliance tags -----------------------------------------------
variable "owner" {
  description = "Team or person responsible for the resources"
  type        = string
}

variable "cost_center" {
  description = "Cost center code for billing allocation"
  type        = string
}

# ---- Networking --------------------------------------------------------------
variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets"
  type        = list(string)
  default     = ["10.0.11.0/24", "10.0.12.0/24", "10.0.13.0/24"]
}

variable "availability_zones" {
  description = "List of availability zones"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b", "us-east-1c"]
}

# ---- EKS ---------------------------------------------------------------------
variable "kubernetes_version" {
  description = "Kubernetes version for EKS cluster"
  type        = string
  default     = "1.29"
}

variable "node_groups" {
  description = "EKS node group configurations"
  type = map(object({
    instance_types = list(string)
    capacity_type  = string
    desired_size   = number
    max_size       = number
    min_size       = number
    disk_size      = number
  }))
  default = {
    general = {
      instance_types = ["m5.xlarge"]
      capacity_type  = "ON_DEMAND"
      desired_size   = 3
      max_size       = 10
      min_size       = 2
      disk_size      = 50
    }
    spot = {
      instance_types = ["m5.xlarge", "m5a.xlarge"]
      capacity_type  = "SPOT"
      desired_size   = 2
      max_size       = 20
      min_size       = 0
      disk_size      = 50
    }
  }
}

# ---- State Backend -----------------------------------------------------------
variable "tfstate_bucket" {
  description = "S3 bucket for Terraform state"
  type        = string
}

variable "tflock_table" {
  description = "DynamoDB table for Terraform state locking"
  type        = string
  default     = "terraform-state-lock"
}

variable "evidence_bucket" {
  description = "S3 bucket for pipeline compliance evidence"
  type        = string
}
