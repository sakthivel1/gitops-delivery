#!/usr/bin/env bash
# Rollback strategy: ArgoCD sync history or Helm rollback
# Usage:
#   ./rollback.sh <env> <revision>        # ArgoCD history rollback
#   ./rollback.sh <env> helm <revision>   # Helm rollback (emergency)
#
# Examples:
#   ./rollback.sh prod 42
#   ./rollback.sh prod helm 5

set -euo pipefail

ENV="${1:-}"
MODE="${2:-argocd}"
REVISION="${3:-}"

if [[ -z "$ENV" ]]; then
  echo "Usage: $0 <env> [argocd|helm] [revision]"
  exit 1
fi

APP_NAME="finapp-${ENV}"
NAMESPACE="finapp-${ENV}"
HELM_RELEASE="finapp"

case "$MODE" in
  argocd)
    REVISION="${2:-}"
    if [[ -z "$REVISION" ]]; then
      echo "Listing ArgoCD history for ${APP_NAME}..."
      argocd app history "$APP_NAME"
      read -rp "Enter revision to roll back to: " REVISION
    fi
    echo "Rolling back ${APP_NAME} to revision ${REVISION}..."
    argocd app rollback "$APP_NAME" "$REVISION"
    argocd app wait "$APP_NAME" --health --timeout 300
    echo "Rollback complete. Current state:"
    argocd app get "$APP_NAME"
    ;;

  helm)
    REVISION="${3:-}"
    if [[ -z "$REVISION" ]]; then
      echo "Listing Helm history for ${HELM_RELEASE} in ${NAMESPACE}..."
      helm history "$HELM_RELEASE" -n "$NAMESPACE"
      read -rp "Enter Helm revision to roll back to: " REVISION
    fi
    echo "[EMERGENCY] Rolling back Helm release ${HELM_RELEASE} to revision ${REVISION}..."
    helm rollback "$HELM_RELEASE" "$REVISION" -n "$NAMESPACE" --wait --timeout 5m
    echo "Helm rollback complete. Syncing ArgoCD state..."
    # Force ArgoCD to recognize the rolled-back state
    argocd app sync "$APP_NAME" --force
    echo "Done."
    ;;

  *)
    echo "Unknown mode: $MODE (use 'argocd' or 'helm')"
    exit 1
    ;;
esac
