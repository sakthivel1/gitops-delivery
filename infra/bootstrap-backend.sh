#!/usr/bin/env bash
# bootstrap-backend.sh
# Creates the S3 bucket + DynamoDB table that Terraform will use as its backend.
# Run this ONCE before running any terraform commands.
#
# Usage: bash infra/bootstrap-backend.sh

set -euo pipefail

# ── Configuration ─────────────────────────────────────────────────────────────
AWS_REGION="us-east-1"
ACCOUNT_ID="457591021188"
PROJECT="finapp"
ENV="prod"

# Bucket names must be globally unique — prefix with account ID
TF_STATE_BUCKET="${PROJECT}-tfstate-${ACCOUNT_ID}"
TF_LOCK_TABLE="${PROJECT}-tflock"
EVIDENCE_BUCKET="${PROJECT}-evidence-${ACCOUNT_ID}"

KMS_ALIAS="alias/${PROJECT}"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
log() { echo -e "${GREEN}[BOOTSTRAP]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC}    $*"; }

echo "======================================="
echo "  Terraform Backend Bootstrap"
echo "  Account : ${ACCOUNT_ID}"
echo "  Region  : ${AWS_REGION}"
echo "  Buckets : ${TF_STATE_BUCKET}"
echo "            ${EVIDENCE_BUCKET}"
echo "  DynamoDB: ${TF_LOCK_TABLE}"
echo "======================================="
echo ""

# ── 1. Create KMS key for encryption ──────────────────────────────────────────
log "Creating KMS key..."
KMS_KEY_ID=$(aws kms create-key \
  --region "${AWS_REGION}" \
  --description "${PROJECT} Terraform state encryption key" \
  --query 'KeyMetadata.KeyId' \
  --output text 2>/dev/null) || {
    warn "KMS key may already exist — fetching existing key..."
    KMS_KEY_ID=$(aws kms describe-key \
      --key-id "${KMS_ALIAS}" \
      --region "${AWS_REGION}" \
      --query 'KeyMetadata.KeyId' \
      --output text 2>/dev/null || echo "")
  }

if [[ -n "${KMS_KEY_ID}" ]]; then
  log "KMS Key ID: ${KMS_KEY_ID}"
  # Enable auto-rotation
  aws kms enable-key-rotation \
    --key-id "${KMS_KEY_ID}" \
    --region "${AWS_REGION}" 2>/dev/null || true

  # Create alias
  aws kms create-alias \
    --alias-name "${KMS_ALIAS}" \
    --target-key-id "${KMS_KEY_ID}" \
    --region "${AWS_REGION}" 2>/dev/null || {
    warn "KMS alias already exists — skipping"
  }

  KMS_KEY_ARN=$(aws kms describe-key \
    --key-id "${KMS_KEY_ID}" \
    --region "${AWS_REGION}" \
    --query 'KeyMetadata.Arn' \
    --output text)
  log "KMS ARN: ${KMS_KEY_ARN}"
else
  warn "Could not create/find KMS key. Proceeding with SSE-S3 encryption."
  KMS_KEY_ARN=""
fi

# ── 2. Create Terraform state S3 bucket ───────────────────────────────────────
log "Creating Terraform state S3 bucket: ${TF_STATE_BUCKET}..."
aws s3api create-bucket \
  --bucket "${TF_STATE_BUCKET}" \
  --region "${AWS_REGION}" 2>/dev/null || warn "Bucket ${TF_STATE_BUCKET} already exists — continuing"

log "Enabling versioning on state bucket..."
aws s3api put-bucket-versioning \
  --bucket "${TF_STATE_BUCKET}" \
  --versioning-configuration Status=Enabled

log "Blocking all public access on state bucket..."
aws s3api put-public-access-block \
  --bucket "${TF_STATE_BUCKET}" \
  --public-access-block-configuration \
    BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

log "Enabling server-side encryption on state bucket..."
if [[ -n "${KMS_KEY_ARN}" ]]; then
  aws s3api put-bucket-encryption \
    --bucket "${TF_STATE_BUCKET}" \
    --server-side-encryption-configuration "{
      \"Rules\": [{
        \"ApplyServerSideEncryptionByDefault\": {
          \"SSEAlgorithm\": \"aws:kms\",
          \"KMSMasterKeyID\": \"${KMS_KEY_ARN}\"
        },
        \"BucketKeyEnabled\": true
      }]
    }"
else
  aws s3api put-bucket-encryption \
    --bucket "${TF_STATE_BUCKET}" \
    --server-side-encryption-configuration '{
      "Rules": [{"ApplyServerSideEncryptionByDefault": {"SSEAlgorithm": "AES256"}}]
    }'
fi

# ── 3. Create Evidence S3 bucket ──────────────────────────────────────────────
log "Creating evidence S3 bucket: ${EVIDENCE_BUCKET}..."
aws s3api create-bucket \
  --bucket "${EVIDENCE_BUCKET}" \
  --region "${AWS_REGION}" 2>/dev/null || warn "Bucket ${EVIDENCE_BUCKET} already exists — continuing"

aws s3api put-bucket-versioning \
  --bucket "${EVIDENCE_BUCKET}" \
  --versioning-configuration Status=Enabled

aws s3api put-public-access-block \
  --bucket "${EVIDENCE_BUCKET}" \
  --public-access-block-configuration \
    BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

if [[ -n "${KMS_KEY_ARN}" ]]; then
  aws s3api put-bucket-encryption \
    --bucket "${EVIDENCE_BUCKET}" \
    --server-side-encryption-configuration "{
      \"Rules\": [{
        \"ApplyServerSideEncryptionByDefault\": {
          \"SSEAlgorithm\": \"aws:kms\",
          \"KMSMasterKeyID\": \"${KMS_KEY_ARN}\"
        }
      }]
    }"
fi

# 7-year lifecycle for compliance
log "Configuring 7-year lifecycle on evidence bucket..."
aws s3api put-bucket-lifecycle-configuration \
  --bucket "${EVIDENCE_BUCKET}" \
  --lifecycle-configuration '{
    "Rules": [{
      "ID": "retain-7-years",
      "Status": "Enabled",
      "Transitions": [
        {"Days": 90,  "StorageClass": "STANDARD_IA"},
        {"Days": 365, "StorageClass": "GLACIER"}
      ],
      "Expiration": {"Days": 2555}
    }]
  }'

# ── 4. Create DynamoDB lock table ─────────────────────────────────────────────
log "Creating DynamoDB lock table: ${TF_LOCK_TABLE}..."
aws dynamodb create-table \
  --region "${AWS_REGION}" \
  --table-name "${TF_LOCK_TABLE}" \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --table-class STANDARD 2>/dev/null || warn "DynamoDB table ${TF_LOCK_TABLE} already exists — continuing"

log "Waiting for DynamoDB table to become active..."
aws dynamodb wait table-exists \
  --region "${AWS_REGION}" \
  --table-name "${TF_LOCK_TABLE}"

if [[ -n "${KMS_KEY_ARN}" ]]; then
  aws dynamodb update-table \
    --region "${AWS_REGION}" \
    --table-name "${TF_LOCK_TABLE}" \
    --sse-specification "Enabled=true,SSEType=KMS,KMSMasterKeyId=${KMS_KEY_ARN}" 2>/dev/null || true
fi

# ── 5. Write backend config file ──────────────────────────────────────────────
log "Writing backend config: infra/backend-prod.conf..."
cat > "$(dirname "$0")/backend-prod.conf" <<EOF
bucket         = "${TF_STATE_BUCKET}"
key            = "${PROJECT}/prod/terraform.tfstate"
region         = "${AWS_REGION}"
dynamodb_table = "${TF_LOCK_TABLE}"
encrypt        = true
EOF

if [[ -n "${KMS_KEY_ARN}" ]]; then
  echo "kms_key_id     = \"${KMS_KEY_ARN}\"" >> "$(dirname "$0")/backend-prod.conf"
fi

log "Writing terraform.tfvars..."
cat > "$(dirname "$0")/terraform.tfvars" <<EOF
# Auto-generated by bootstrap-backend.sh
# Edit values as needed before running terraform plan

region          = "${AWS_REGION}"
project_name    = "${PROJECT}"
environment     = "prod"

# Mandatory compliance tags
owner       = "platform-team"
cost_center = "CC-4521"

# Networking
vpc_cidr             = "10.0.0.0/16"
public_subnet_cidrs  = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
private_subnet_cidrs = ["10.0.11.0/24", "10.0.12.0/24", "10.0.13.0/24"]
availability_zones   = ["us-east-1a", "us-east-1b", "us-east-1c"]

# EKS
kubernetes_version = "1.29"
node_groups = {
  general = {
    instance_types = ["t3.medium"]   # Use smaller instances for cost control
    capacity_type  = "ON_DEMAND"
    desired_size   = 2
    max_size       = 5
    min_size       = 1
    disk_size      = 30
  }
}

# State backend (created by bootstrap)
tfstate_bucket  = "${TF_STATE_BUCKET}"
tflock_table    = "${TF_LOCK_TABLE}"
evidence_bucket = "${EVIDENCE_BUCKET}"
EOF

echo ""
echo "======================================="
echo "  Bootstrap COMPLETE"
echo "======================================="
echo ""
echo "  State bucket  : ${TF_STATE_BUCKET}"
echo "  Evidence bucket: ${EVIDENCE_BUCKET}"
echo "  DynamoDB table: ${TF_LOCK_TABLE}"
[[ -n "${KMS_KEY_ARN}" ]] && echo "  KMS key       : ${KMS_KEY_ARN}"
echo ""
echo "  Next step:"
echo "    cd infra"
echo "    terraform init -backend-config=backend-prod.conf"
echo ""
