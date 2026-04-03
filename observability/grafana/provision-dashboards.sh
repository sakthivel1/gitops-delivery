#!/usr/bin/env bash
# provision-dashboards.sh — Creates Grafana dashboard ConfigMaps in the cluster.
# Run once after kube-prometheus-stack is installed, or via CI as part of observability setup.
# The Grafana sidecar picks up any ConfigMap in the monitoring namespace with label grafana_dashboard=1.

set -euo pipefail

NAMESPACE="monitoring"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DASHBOARDS_DIR="${SCRIPT_DIR}/dashboards"

declare -A DASHBOARDS=(
  ["cluster-health"]="cluster-health.json"
  ["app-metrics"]="app-metrics.json"
  ["cicd-trends"]="cicd-trends.json"
)

for name in "${!DASHBOARDS[@]}"; do
  file="${DASHBOARDS[$name]}"
  json_path="${DASHBOARDS_DIR}/${file}"

  if [[ ! -f "$json_path" ]]; then
    echo "ERROR: dashboard file not found: $json_path"
    exit 1
  fi

  echo "Provisioning dashboard: $name ($file)"

  # Build the ConfigMap with kubectl --dry-run then apply
  kubectl create configmap "grafana-dashboard-${name}" \
    --namespace="${NAMESPACE}" \
    --from-file="${file}=${json_path}" \
    --dry-run=client -o yaml \
  | kubectl label --local -f - grafana_dashboard=1 --dry-run=client -o yaml \
  | kubectl apply -f -

done

echo "All dashboards provisioned successfully."
