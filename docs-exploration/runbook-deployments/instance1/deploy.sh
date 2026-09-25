#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

# Source instance parameters
# shellcheck source=docs-exploration/runbook-deployments/instance1/params.env
source "${SCRIPT_DIR}/params.env"

echo "=== Deploying OpenRL on GKE (Instance: ${RESOURCE_PREFIX}) ==="
echo "Project: ${PROJECT_ID}"
echo "Cluster: ${CLUSTER_NAME} (${REGION}/${ZONE})"

# 1. Enable Required GCP APIs
echo "--> Enabling GCP APIs..."
gcloud config set project "${PROJECT_ID}"
gcloud services enable \
  compute.googleapis.com \
  container.googleapis.com \
  file.googleapis.com

# 2. Create GKE Standard Cluster with Filestore CSI
echo "--> Creating GKE cluster ${CLUSTER_NAME}..."
gcloud container clusters create "${CLUSTER_NAME}" \
  --project="${PROJECT_ID}" \
  --location="${REGION}" \
  --node-locations="${ZONE}" \
  --release-channel=regular \
  --machine-type=e2-standard-4 \
  --num-nodes=1 \
  --disk-size=100 \
  --addons=GcpFilestoreCsiDriver \
  --labels="repo-agent-instance=${RESOURCE_PREFIX}"

# 3. Create GPU DRA Node Pool
echo "--> Creating GPU DRA node pool ${NODE_POOL_NAME}..."
gcloud container node-pools create "${NODE_POOL_NAME}" \
  --project="${PROJECT_ID}" \
  --cluster="${CLUSTER_NAME}" \
  --location="${REGION}" \
  --node-locations="${ZONE}" \
  --machine-type=g2-standard-24 \
  --accelerator="type=nvidia-l4,count=2,gpu-driver-version=disabled" \
  --node-labels="openrl.io/enabled=true,openrl.io/trainer=true,openrl.io/sampler=true,gke-no-default-nvidia-gpu-device-plugin=true,nvidia.com/gpu.present=true" \
  --node-taints="nvidia.com/gpu=present:NoSchedule" \
  --image-type=COS_CONTAINERD \
  --num-nodes=1 \
  --disk-size=200

# 4. Fetch Credentials and Install NVIDIA Drivers
echo "--> Fetching cluster credentials..."
gcloud container clusters get-credentials "${CLUSTER_NAME}" --location="${REGION}" --project="${PROJECT_ID}"

echo "--> Installing host NVIDIA drivers daemonset..."
kubectl apply -f https://raw.githubusercontent.com/GoogleCloudPlatform/container-engine-accelerators/master/nvidia-driver-installer/cos/daemonset-preloaded-latest.yaml

echo "--> Installing NVIDIA DRA GPU driver via Helm..."
helm repo add nvidia https://helm.ngc.nvidia.com/nvidia
helm repo update
helm install nvidia-dra-driver-gpu nvidia/nvidia-dra-driver-gpu \
  --version="25.8.0" \
  --create-namespace \
  --namespace "${NVIDIA_DRA_NAMESPACE}" \
  --set nvidiaDriverRoot="/home/kubernetes/bin/nvidia/"

# 5. Deploy OpenRL Stack
echo "--> Applying OpenRL LoRA manifests..."
kubectl apply --server-side -k "${PROJECT_ROOT}/k8s/deploy/lora"

echo "=== Deployment complete ==="
