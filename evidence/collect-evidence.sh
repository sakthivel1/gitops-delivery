#!/usr/bin/env bash
# collect-evidence.sh — Package a compliance evidence bundle for a pipeline run
#
# Usage:
#   ./evidence/collect-evidence.sh <pipeline-id> [evidence-dir] [s3-bucket]
#
# Environment variables (can also be passed as args):
#   PIPELINE_ID      GitLab pipeline ID
#   EVIDENCE_DIR     Directory containing raw evidence artifacts
#   S3_BUCKET        S3 bucket to upload bundle to (optional)
#
# The script:
#   1. Validates all required artifacts are present
#   2. Generates a manifest.json with checksums
#   3. Zips the bundle
#   4. Optionally uploads to S3

set -euo pipefail

PIPELINE_ID="${1:-${CI_PIPELINE_ID:-local-test}}"
EVIDENCE_DIR="${2:-evidence-bundle}"
S3_BUCKET="${3:-${EVIDENCE_BUCKET:-}}"

BUNDLE_NAME="evidence-${CI_PROJECT_NAME:-finapp}-${PIPELINE_ID}-$(date +%Y%m%d-%H%M%S).zip"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# ---- 1. Validate required artifacts ------------------------------------------
REQUIRED_FILES=(
  "lint-terraform.log"
  "checkov-scan.log"
  "build-info.env"
  "unit-test-results.xml"
  "integration-test-results.xml"
  "helm-diff-prod.log"
  "argocd-sync-prod.log"
  "deploy-info.env"
  "approval-evidence.env"
)

log_info "Validating required evidence artifacts..."
MISSING=()
for f in "${REQUIRED_FILES[@]}"; do
  if [[ ! -f "${EVIDENCE_DIR}/${f}" ]]; then
    MISSING+=("$f")
    log_warn "Missing: ${f}"
  else
    log_info "Found: ${f}"
  fi
done

if [[ ${#MISSING[@]} -gt 0 ]]; then
  log_error "Missing ${#MISSING[@]} required evidence files:"
  printf '  - %s\n' "${MISSING[@]}"
  log_error "Bundle will be created but marked as INCOMPLETE"
  BUNDLE_STATUS="INCOMPLETE"
else
  BUNDLE_STATUS="COMPLETE"
fi

# ---- 2. Generate manifest with checksums ------------------------------------
log_info "Generating manifest.json..."

{
  echo "{"
  echo "  \"pipeline_id\": \"${PIPELINE_ID}\","
  echo "  \"pipeline_url\": \"${CI_PIPELINE_URL:-N/A}\","
  echo "  \"commit_sha\": \"${CI_COMMIT_SHA:-N/A}\","
  echo "  \"commit_branch\": \"${CI_COMMIT_BRANCH:-N/A}\","
  echo "  \"project\": \"${CI_PROJECT_NAME:-finapp}\","
  echo "  \"environment\": \"${DEPLOY_ENV:-N/A}\","
  echo "  \"image_tag\": \"${IMAGE_TAG:-N/A}\","
  echo "  \"deployed_by\": \"${GITLAB_USER_LOGIN:-N/A}\","
  echo "  \"approved_by\": \"${APPROVED_BY:-N/A}\","
  echo "  \"bundle_status\": \"${BUNDLE_STATUS}\","
  echo "  \"generated_at\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\","
  echo "  \"artifacts\": {"

  FIRST=true
  for f in "${EVIDENCE_DIR}"/*; do
    if [[ -f "$f" ]]; then
      FNAME=$(basename "$f")
      CHECKSUM=$(sha256sum "$f" | cut -d' ' -f1)
      SIZE=$(wc -c < "$f")
      if [[ "$FIRST" == "true" ]]; then
        FIRST=false
      else
        echo ","
      fi
      printf '    "%s": { "sha256": "%s", "size_bytes": %s }' "$FNAME" "$CHECKSUM" "$SIZE"
    fi
  done

  echo ""
  echo "  }"
  echo "}"
} > "${EVIDENCE_DIR}/manifest.json"

log_info "Manifest written to ${EVIDENCE_DIR}/manifest.json"

# ---- 3. Generate release notes from git log ----------------------------------
if git rev-parse --git-dir > /dev/null 2>&1; then
  log_info "Generating release notes from git log..."
  {
    echo "# Release Notes — Pipeline ${PIPELINE_ID}"
    echo ""
    echo "**Branch:** ${CI_COMMIT_BRANCH:-N/A}"
    echo "**Commit:** ${CI_COMMIT_SHA:-N/A}"
    echo "**Date:** $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo ""
    echo "## Changes"
    echo ""
    git log --oneline --no-merges \
      "$(git describe --tags --abbrev=0 2>/dev/null || git rev-list --max-parents=0 HEAD)"..HEAD \
      | sed 's/^[a-f0-9]*//' \
      | sed 's/^  *//' \
      | sed 's/^/- /'
  } > "${EVIDENCE_DIR}/release-notes.md"
else
  echo "# Release Notes — Pipeline ${PIPELINE_ID}" > "${EVIDENCE_DIR}/release-notes.md"
  echo "Git history not available in this context." >> "${EVIDENCE_DIR}/release-notes.md"
fi

# ---- 4. Package bundle -------------------------------------------------------
log_info "Creating bundle: ${BUNDLE_NAME}..."
zip -r "${BUNDLE_NAME}" "${EVIDENCE_DIR}/"
BUNDLE_SIZE=$(du -sh "${BUNDLE_NAME}" | cut -f1)
log_info "Bundle created: ${BUNDLE_NAME} (${BUNDLE_SIZE})"

# ---- 5. Upload to S3 (optional) ----------------------------------------------
if [[ -n "${S3_BUCKET}" ]]; then
  S3_KEY="pipelines/${PIPELINE_ID}/${BUNDLE_NAME}"
  log_info "Uploading to s3://${S3_BUCKET}/${S3_KEY}..."
  aws s3 cp "${BUNDLE_NAME}" \
    "s3://${S3_BUCKET}/${S3_KEY}" \
    --sse aws:kms \
    --metadata "pipeline-id=${PIPELINE_ID},commit=${CI_COMMIT_SHA:-N/A},status=${BUNDLE_STATUS}" \
    --no-progress
  log_info "Uploaded: s3://${S3_BUCKET}/${S3_KEY}"
  echo "EVIDENCE_S3_URL=s3://${S3_BUCKET}/${S3_KEY}" > bundle-upload.env
else

  log_warn "No S3_BUCKET set — bundle stored locally only: ${BUNDLE_NAME}"
fi

# ---- 6. Summary --------------------------------------------------------------
echo ""
echo "======================================"
echo " EVIDENCE BUNDLE SUMMARY"
echo "======================================"
echo " Pipeline:   ${PIPELINE_ID}"
echo " Status:     ${BUNDLE_STATUS}"
echo " Bundle:     ${BUNDLE_NAME}"
echo " Size:       ${BUNDLE_SIZE}"
[[ -n "${S3_BUCKET}" ]] && echo " S3 Path:    s3://${S3_BUCKET}/pipelines/${PIPELINE_ID}/${BUNDLE_NAME}"
echo "======================================"

if [[ "${BUNDLE_STATUS}" == "INCOMPLETE" ]]; then
  exit 1
fi
