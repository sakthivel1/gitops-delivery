terraform {
  backend "s3" {
    # Values are injected via -backend-config in CI/CD
    # Example: terraform init -backend-config=backend-prod.conf
    bucket         = ""  # Override: var.tfstate_bucket
    key            = ""  # Override: "<project>/<env>/terraform.tfstate"
    region         = ""  # Override: var.region
    encrypt        = true
    kms_key_id     = ""  # Override: KMS key ARN
    dynamodb_table = ""  # Override: var.tflock_table
  }
}
