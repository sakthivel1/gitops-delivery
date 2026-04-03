variable "name" {
  description = "Name prefix for ALB log resources"
  type        = string
}

variable "log_bucket_id" {
  description = "S3 bucket ID for ALB access logs"
  type        = string
}

variable "account_id" {
  description = "AWS account ID"
  type        = string
}

variable "elb_account_id" {
  description = "AWS ELB service account ID for the region (us-east-1 = 127311923021)"
  type        = string
  default     = "127311923021"  # us-east-1 ELB account
}

variable "common_tags" {
  description = "Compliance tags"
  type        = map(string)
}
