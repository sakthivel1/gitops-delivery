################################################################################
# Root — Composes VPC + EKS + IAM modules
################################################################################

terraform {
  required_version = ">= 1.6"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = local.common_tags
  }
}

locals {
  common_tags = {
    Owner       = var.owner
    Environment = var.environment
    CostCenter  = var.cost_center
    ManagedBy   = "Terraform"
    Project     = var.project_name
  }
}

# KMS key used for encrypting EKS secrets, S3, and DynamoDB
resource "aws_kms_key" "main" {
  description             = "${var.project_name} encryption key"
  deletion_window_in_days = 30
  enable_key_rotation     = true

  tags = local.common_tags
}

resource "aws_kms_alias" "main" {
  name          = "alias/${var.project_name}"
  target_key_id = aws_kms_key.main.key_id
}

module "vpc" {
  source = "./modules/vpc"

  name                 = "${var.project_name}-${var.environment}"
  vpc_cidr             = var.vpc_cidr
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  availability_zones   = var.availability_zones
  common_tags          = local.common_tags
}

module "iam" {
  source = "./modules/iam"

  name              = "${var.project_name}-${var.environment}"
  region            = var.region
  account_id        = data.aws_caller_identity.current.account_id
  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_provider_url = replace(module.eks.oidc_provider_url, "https://", "")
  kms_key_arn       = aws_kms_key.main.arn
  tfstate_bucket    = var.tfstate_bucket
  tflock_table      = var.tflock_table
  evidence_bucket   = var.evidence_bucket
  common_tags       = local.common_tags
}

module "eks" {
  source = "./modules/eks"

  cluster_name       = "${var.project_name}-${var.environment}"
  kubernetes_version = var.kubernetes_version
  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids
  cluster_role_arn   = module.iam.eks_cluster_role_arn
  node_role_arn      = module.iam.eks_node_role_arn
  kms_key_arn        = aws_kms_key.main.arn
  node_groups        = var.node_groups
  common_tags        = local.common_tags
}

module "alb_logging" {
  source = "./modules/alb-logging"

  name          = "${var.project_name}-${var.environment}"
  log_bucket_id = module.iam.evidence_bucket_id
  account_id    = data.aws_caller_identity.current.account_id
  common_tags   = local.common_tags
}

data "aws_caller_identity" "current" {}
