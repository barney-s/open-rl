#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source instance parameters
# shellcheck source=docs-exploration/runbook-deployments/instance1/params.env
source "${SCRIPT_DIR}/params.env"

echo "=== Tearing down OpenRL on GKE (Instance: ${RESOURCE_PREFIX}) ==="
echo "Project: ${PROJECT_ID}"
echo "Cluster: ${CLUSTER_NAME} (${REGION})"

# 1. Fetch credentials and remove active workloads and claims (if cluster is accessible)
if gcloud container clusters get-credentials "${CLUSTER_NAME}" --location="${REGION}" --project="${PROJECT_ID}" >/dev/null 2>&1; then
  echo "--> Deleting active workloads and resourceclaims in ${OPENRL_NAMESPACE}..."
  kubectl -n "${OPENRL_NAMESPACE}" delete workloads,resourceclaims --all --ignore-not-found || true
fi

# 2. Delete the GKE Cluster and associated Filestore storage
echo "--> Deleting GKE cluster ${CLUSTER_NAME}..."
gcloud container clusters delete "${CLUSTER_NAME}" \
  --project="${PROJECT_ID}" \
  --location="${REGION}" \
  --quiet

echo "=== Teardown complete ==="
