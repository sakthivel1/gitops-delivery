output "eks_cluster_role_arn" {
  description = "EKS cluster IAM role ARN"
  value       = aws_iam_role.eks_cluster.arn
}

output "eks_node_role_arn" {
  description = "EKS node group IAM role ARN"
  value       = aws_iam_role.eks_nodes.arn
}

output "argocd_role_arn" {
  description = "ArgoCD IRSA role ARN"
  value       = aws_iam_role.argocd.arn
}

output "cicd_runner_role_arn" {
  description = "CI/CD runner IRSA role ARN"
  value       = aws_iam_role.cicd_runner.arn
}

output "tfstate_bucket_id" {
  description = "Terraform state S3 bucket name"
  value       = aws_s3_bucket.tfstate.id
}

output "tflock_table_name" {
  description = "DynamoDB lock table name"
  value       = aws_dynamodb_table.tflock.name
}

output "evidence_bucket_id" {
  description = "Evidence S3 bucket name"
  value       = aws_s3_bucket.evidence.id
}
