#!/usr/bin/env bash
# Changed: Explicitly delete PVCs before cluster deletion to allow Filestore CSI driver to cleanly remove GCP Filestore instances, and ensure any orphaned Filestore instances are deleted.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source instance parameters
# shellcheck source=docs-exploration/runbook-deployments/instance1/params.env
source "${SCRIPT_DIR}/params.env"

echo "=== Tearing down OpenRL on GKE (Instance: ${RESOURCE_PREFIX}) ==="
echo "Project: ${PROJECT_ID}"
echo "Cluster: ${CLUSTER_NAME} (${REGION})"

# 1. Fetch credentials and remove active workloads, claims, and PVCs (if cluster is accessible)
if gcloud container clusters get-credentials "${CLUSTER_NAME}" --location="${REGION}" --project="${PROJECT_ID}" >/dev/null 2>&1; then
  echo "--> Deleting active workloads and resourceclaims in ${OPENRL_NAMESPACE}..."
  kubectl -n "${OPENRL_NAMESPACE}" delete workloads,resourceclaims --all --ignore-not-found || true

  echo "--> Deleting persistent volume claims in ${OPENRL_NAMESPACE}..."
  kubectl -n "${OPENRL_NAMESPACE}" delete pvc --all --ignore-not-found || true
fi

# 2. Delete the GKE Cluster
if gcloud container clusters describe "${CLUSTER_NAME}" --location="${REGION}" --project="${PROJECT_ID}" >/dev/null 2>&1; then
  echo "--> Deleting GKE cluster ${CLUSTER_NAME}..."
  gcloud container clusters delete "${CLUSTER_NAME}" \
    --project="${PROJECT_ID}" \
    --location="${REGION}" \
    --quiet
fi

# 3. Clean up any remaining Filestore instances created for this namespace/PVC if orphaned
echo "--> Checking for orphaned Filestore instances..."
orphaned_instances=$(gcloud filestore instances list --project="${PROJECT_ID}" --zone="${ZONE}" --format="value(name)" --filter="labels.kubernetes_io_created-for_pvc_namespace=${OPENRL_NAMESPACE}" 2>/dev/null || true)
if [[ -n "${orphaned_instances}" ]]; then
  for inst in ${orphaned_instances}; do
    echo "--> Deleting orphaned Filestore instance: ${inst}..."
    gcloud filestore instances delete "${inst}" --project="${PROJECT_ID}" --zone="${ZONE}" --quiet
  done
fi

echo "=== Teardown complete ==="
