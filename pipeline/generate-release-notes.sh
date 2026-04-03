#!/usr/bin/env bash
# generate-release-notes.sh — Standalone release notes generator.
#
# Usage:
#   ./generate-release-notes.sh [FROM_REF] [TO_REF] [OUTPUT_FILE]
#
# Defaults:
#   FROM_REF    — last git tag (or first commit if no tags exist)
#   TO_REF      — HEAD
#   OUTPUT_FILE — release-notes.md
#
# Outputs a Markdown file with:
#   - Version / date header
#   - Categorised commits (feat, fix, chore, ci, docs, refactor)
#   - JIRA ticket links (extracted from branch names / commit messages)
#   - Deployment metadata (image tag, deployer, pipeline URL)
#
# Environment variables (injected by GitLab CI or set manually):
#   CI_COMMIT_SHA          — full commit SHA (falls back to `git rev-parse HEAD`)
#   CI_PIPELINE_URL        — GitLab pipeline URL
#   CI_COMMIT_REF_NAME     — branch/tag name
#   GITLAB_USER_LOGIN      — user who triggered the pipeline
#   IMAGE_TAG              — Docker image tag built by CI
#   JIRA_BASE_URL          — e.g. https://yourcompany.atlassian.net/browse

set -euo pipefail

###############################################################################
# Arguments / defaults
###############################################################################
FROM_REF="${1:-}"
TO_REF="${2:-HEAD}"
OUTPUT_FILE="${3:-release-notes.md}"

# If no FROM_REF given, use the most recent tag; fallback to first commit
if [[ -z "$FROM_REF" ]]; then
  FROM_REF=$(git describe --tags --abbrev=0 2>/dev/null || git rev-list --max-parents=0 HEAD)
fi

COMMIT_SHA="${CI_COMMIT_SHA:-$(git rev-parse HEAD)}"
SHORT_SHA="${COMMIT_SHA:0:8}"
BRANCH="${CI_COMMIT_REF_NAME:-$(git rev-parse --abbrev-ref HEAD)}"
DEPLOYER="${GITLAB_USER_LOGIN:-system}"
PIPELINE_URL="${CI_PIPELINE_URL:-N/A}"
IMAGE_TAG="${IMAGE_TAG:-${SHORT_SHA}}"
JIRA_BASE_URL="${JIRA_BASE_URL:-https://yourcompany.atlassian.net/browse}"
GENERATED_AT="$(date -u '+%Y-%m-%d %H:%M UTC')"

###############################################################################
# Collect commits between FROM_REF and TO_REF
###############################################################################
COMMITS=$(git log "${FROM_REF}..${TO_REF}" \
  --no-merges \
  --format="%h %s" \
  2>/dev/null) || true

if [[ -z "$COMMITS" ]]; then
  echo "No commits found between ${FROM_REF} and ${TO_REF}. Generating minimal notes."
fi

###############################################################################
# Categorise commits
###############################################################################
FEATURES=""
FIXES=""
CI_CHANGES=""
DOCS=""
REFACTORS=""
CHORES=""
OTHER=""

while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  hash="${line%% *}"
  msg="${line#* }"

  case "$msg" in
    feat*|feature*)   FEATURES+="- ${msg} (\`${hash}\`)"$'\n' ;;
    fix*|bug*)        FIXES+="- ${msg} (\`${hash}\`)"$'\n' ;;
    ci*|build*)       CI_CHANGES+="- ${msg} (\`${hash}\`)"$'\n' ;;
    docs*)            DOCS+="- ${msg} (\`${hash}\`)"$'\n' ;;
    refactor*)        REFACTORS+="- ${msg} (\`${hash}\`)"$'\n' ;;
    chore*)           CHORES+="- ${msg} (\`${hash}\`)"$'\n' ;;
    *)                OTHER+="- ${msg} (\`${hash}\`)"$'\n' ;;
  esac
done <<< "$COMMITS"

###############################################################################
# Extract JIRA ticket IDs from commit messages and branch name
###############################################################################
ALL_TEXT="${COMMITS} ${BRANCH}"
JIRA_TICKETS=$(echo "$ALL_TEXT" \
  | grep -oE '[A-Z]+-[0-9]+' \
  | sort -u \
  | while read -r ticket; do echo "- [${ticket}](${JIRA_BASE_URL}/${ticket})"; done) || true

###############################################################################
# Write Markdown
###############################################################################
cat > "$OUTPUT_FILE" <<EOF
# Release Notes

**Version:** \`${IMAGE_TAG}\`
**Branch:** \`${BRANCH}\`
**Commit:** \`${COMMIT_SHA}\`
**Generated:** ${GENERATED_AT}
**Deployed by:** ${DEPLOYER}
**Pipeline:** ${PIPELINE_URL}

---

## Changes (${FROM_REF} → ${TO_REF})

EOF

append_section() {
  local title="$1"
  local content="$2"
  if [[ -n "$content" ]]; then
    printf "### %s\n\n%s\n" "$title" "$content" >> "$OUTPUT_FILE"
  fi
}

append_section "Features" "$FEATURES"
append_section "Bug Fixes" "$FIXES"
append_section "CI / Build" "$CI_CHANGES"
append_section "Documentation" "$DOCS"
append_section "Refactoring" "$REFACTORS"
append_section "Chores" "$CHORES"
append_section "Other" "$OTHER"

if [[ -z "$FEATURES$FIXES$CI_CHANGES$DOCS$REFACTORS$CHORES$OTHER" ]]; then
  echo "_No changes recorded for this release._" >> "$OUTPUT_FILE"
fi

###############################################################################
# JIRA ticket summary
###############################################################################
if [[ -n "$JIRA_TICKETS" ]]; then
  cat >> "$OUTPUT_FILE" <<EOF

---

## JIRA Tickets

${JIRA_TICKETS}
EOF
fi

###############################################################################
# Deployment metadata
###############################################################################
cat >> "$OUTPUT_FILE" <<EOF

---

## Deployment Metadata

| Field         | Value                          |
|---------------|--------------------------------|
| Image Tag     | \`${IMAGE_TAG}\`               |
| Commit SHA    | \`${SHORT_SHA}\`               |
| Branch        | \`${BRANCH}\`                  |
| Deployer      | ${DEPLOYER}                    |
| Pipeline URL  | ${PIPELINE_URL}                |
| Timestamp     | ${GENERATED_AT}                |
EOF

echo "Release notes written to: ${OUTPUT_FILE}"
