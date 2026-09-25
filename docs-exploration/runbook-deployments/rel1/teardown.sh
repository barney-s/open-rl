#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/params.env"

echo "=== Tearing down OpenRL Release Instance: ${RESOURCE_PREFIX} ==="
echo "Project: ${PROJECT_ID}"
echo "Cluster: ${CLUSTER_NAME}"
echo "Region:  ${REGION}"

gcloud config set project "${PROJECT_ID}"

# Try getting credentials to cleanly delete workloads and claims first if cluster is reachable
if gcloud container clusters get-credentials "${CLUSTER_NAME}" --location="${REGION}" 2>/dev/null; then
  echo "Deleting active OpenRL workloads and ResourceClaims..."
  kubectl -n openrl-system delete workloads,resourceclaims --all --ignore-not-found || true
fi

# Delete the GKE cluster (and any associated Filestore storage provisioned by CSI)
echo "Deleting GKE cluster ${CLUSTER_NAME}..."
gcloud container clusters delete "${CLUSTER_NAME}" --location="${REGION}" --quiet

echo "=== Teardown completed ==="
