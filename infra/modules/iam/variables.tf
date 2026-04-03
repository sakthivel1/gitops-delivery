variable "name" {
  description = "Project name prefix"
  type        = string
}

variable "region" {
  description = "AWS region"
  type        = string
}

variable "account_id" {
  description = "AWS account ID"
  type        = string
}

variable "oidc_provider_arn" {
  description = "EKS OIDC provider ARN"
  type        = string
}

variable "oidc_provider_url" {
  description = "EKS OIDC provider URL (without https://)"
  type        = string
}

variable "kms_key_arn" {
  description = "KMS key ARN for encryption"
  type        = string
}

variable "tfstate_bucket" {
  description = "S3 bucket name for Terraform state"
  type        = string
}

variable "tflock_table" {
  description = "DynamoDB table name for Terraform locking"
  type        = string
}

variable "evidence_bucket" {
  description = "S3 bucket name for pipeline evidence"
  type        = string
}

variable "common_tags" {
  description = "Mandatory compliance tags"
  type        = map(string)
}
