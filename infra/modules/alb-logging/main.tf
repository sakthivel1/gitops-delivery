################################################################################
# ALB Logging Module
# Enables CloudWatch + S3 access logging for Application Load Balancers
# Required by: Part A compliance — "CloudWatch logging enabled for EKS and ALB"
################################################################################

# S3 bucket policy that allows ALB to write access logs
resource "aws_s3_bucket_policy" "alb_logs" {
  bucket = var.log_bucket_id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ALBAccessLogDelivery"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${var.elb_account_id}:root"
        }
        Action   = "s3:PutObject"
        Resource = "arn:aws:s3:::${var.log_bucket_id}/alb-logs/AWSLogs/${var.account_id}/*"
      },
      {
        Sid    = "ALBLogDeliveryAclCheck"
        Effect = "Allow"
        Principal = { Service = "delivery.logs.amazonaws.com" }
        Action   = "s3:GetBucketAcl"
        Resource = "arn:aws:s3:::${var.log_bucket_id}"
      },
      {
        Sid    = "ALBLogDeliveryWrite"
        Effect = "Allow"
        Principal = { Service = "delivery.logs.amazonaws.com" }
        Action   = "s3:PutObject"
        Resource = "arn:aws:s3:::${var.log_bucket_id}/alb-logs/AWSLogs/${var.account_id}/*"
        Condition = {
          StringEquals = { "s3:x-amz-acl" = "bucket-owner-full-control" }
        }
      }
    ]
  })
}

# CloudWatch Log Group for ALB logs (via subscription)
resource "aws_cloudwatch_log_group" "alb" {
  name              = "/aws/alb/${var.name}"
  retention_in_days = 90

  tags = var.common_tags
}

# WAF association placeholder — attach WAF WebACL to ALB
# Actual ALB is created by AWS Load Balancer Controller via Ingress annotations
# The following annotation on Ingress enables access logging:
#   alb.ingress.kubernetes.io/load-balancer-attributes: access_logs.s3.enabled=true,access_logs.s3.bucket=<bucket>,access_logs.s3.prefix=alb-logs

output "alb_log_prefix" {
  value = "alb-logs"
}

output "cloudwatch_log_group" {
  value = aws_cloudwatch_log_group.alb.name
}
