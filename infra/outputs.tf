output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "eks_cluster_id" {
  description = "EKS cluster name"
  value       = module.eks.cluster_id
}

output "eks_cluster_endpoint" {
  description = "EKS API server endpoint"
  value       = module.eks.cluster_endpoint
  sensitive   = true
}

output "evidence_bucket" {
  description = "Evidence S3 bucket name"
  value       = module.iam.evidence_bucket_id
}

output "argocd_role_arn" {
  description = "ArgoCD IRSA role ARN"
  value       = module.iam.argocd_role_arn
}
