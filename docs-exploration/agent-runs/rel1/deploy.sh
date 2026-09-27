#!/usr/bin/env bash
# Fix: configure nvidia-dra-driver-gpu helm values (gpuResourcesEnabledOverride, tolerations, priorityClassName, affinity) and handle gateway rollout
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/params.env"

echo "=== Deploying OpenRL Release Instance: ${RESOURCE_PREFIX} ==="
echo "Project:        ${PROJECT_ID}"
echo "Region / Zone:  ${REGION} / ${ZONE}"
echo "Cluster:        ${CLUSTER_NAME}"
echo "Release Bundle: ${RELEASE_BUNDLE} (${OPENRL_VERSION})"

# Configure active GCP project
gcloud config set project "${PROJECT_ID}"

# Step 1: Enable Required GCP APIs
echo "Enabling GCP APIs..."
gcloud services enable \
  compute.googleapis.com \
  container.googleapis.com \
  file.googleapis.com

# Step 2: Create GKE Standard Cluster with Filestore CSI
if ! gcloud container clusters describe "${CLUSTER_NAME}" --location="${REGION}" >/dev/null 2>&1; then
  echo "Creating GKE Standard Cluster ${CLUSTER_NAME}..."
  gcloud container clusters create "${CLUSTER_NAME}" \
    --location="${REGION}" \
    --node-locations="${ZONE}" \
    --release-channel=regular \
    --machine-type=e2-standard-4 \
    --num-nodes=1 \
    --disk-size=100 \
    --addons=GcpFilestoreCsiDriver \
    --labels="repo-agent-instance=${RESOURCE_PREFIX}" \
    --async
fi

echo "Waiting for cluster ${CLUSTER_NAME} to become RUNNING..."
while true; do
  C_STATUS="$(gcloud container clusters describe "${CLUSTER_NAME}" --location="${REGION}" --format="value(status)" 2>/dev/null || echo "UNKNOWN")"
  echo "Cluster status: ${C_STATUS}..."
  if [ "${C_STATUS}" = "RUNNING" ]; then
    break
  fi
  sleep 10
done
echo "Cluster is RUNNING."

# Step 3: Create GPU DRA Node Pool
if ! gcloud container node-pools describe "${NODE_POOL_NAME}" --cluster="${CLUSTER_NAME}" --location="${REGION}" >/dev/null 2>&1; then
  echo "Creating GPU DRA Node Pool..."
  gcloud container node-pools create "${NODE_POOL_NAME}" \
    --cluster="${CLUSTER_NAME}" \
    --location="${REGION}" \
    --node-locations="${ZONE}" \
    --machine-type=g2-standard-24 \
    --accelerator="type=nvidia-l4,count=2,gpu-driver-version=disabled" \
    --node-labels="openrl.io/enabled=true,openrl.io/trainer=true,openrl.io/sampler=true,gke-no-default-nvidia-gpu-device-plugin=true,nvidia.com/gpu.present=true" \
    --node-taints="nvidia.com/gpu=present:NoSchedule" \
    --image-type=COS_CONTAINERD \
    --num-nodes=1 \
    --disk-size=200 \
    --async
fi

echo "Waiting for node pool ${NODE_POOL_NAME} to become RUNNING..."
while true; do
  NP_STATUS="$(gcloud container node-pools describe "${NODE_POOL_NAME}" --cluster="${CLUSTER_NAME}" --location="${REGION}" --format="value(status)" 2>/dev/null || echo "UNKNOWN")"
  echo "Node pool status: ${NP_STATUS}..."
  if [ "${NP_STATUS}" = "RUNNING" ]; then
    break
  fi
  sleep 10
done
echo "Node pool is RUNNING."

# Step 4: Fetch Credentials and Install NVIDIA Drivers
echo "Fetching cluster credentials..."
gcloud container clusters get-credentials "${CLUSTER_NAME}" --location="${REGION}"

echo "Installing host NVIDIA drivers..."
kubectl apply -f https://raw.githubusercontent.com/GoogleCloudPlatform/container-engine-accelerators/master/nvidia-driver-installer/cos/daemonset-preloaded-latest.yaml

echo "Installing NVIDIA DRA GPU driver via Helm..."
helm repo add nvidia https://helm.ngc.nvidia.com/nvidia
helm repo update
helm upgrade --install nvidia-dra-driver-gpu nvidia/nvidia-dra-driver-gpu \
  --version="25.8.0" \
  --create-namespace \
  --namespace nvidia-dra-driver-gpu \
  --set nvidiaDriverRoot="/home/kubernetes/bin/nvidia/" \
  --set gpuResourcesEnabledOverride=true \
  --set "kubeletPlugin.tolerations[0].key=nvidia.com/gpu,kubeletPlugin.tolerations[0].operator=Exists,kubeletPlugin.tolerations[0].effect=NoSchedule" \
  --set controller.priorityClassName="" \
  --set kubeletPlugin.priorityClassName="" \
  --set controller.affinity=null

# Step 5: Deploy Official OpenRL Release Bundle
echo "Deploying OpenRL release bundle ${RELEASE_BUNDLE}..."
RELEASE_URL="https://github.com/gke-labs/open-rl/releases/${OPENRL_VERSION}/download/${RELEASE_BUNDLE}"
if [ "${OPENRL_VERSION}" = "latest" ]; then
  RELEASE_URL="https://github.com/gke-labs/open-rl/releases/latest/download/${RELEASE_BUNDLE}"
fi

kubectl apply --server-side -f "${RELEASE_URL}"

# Verification
echo "Waiting for Filestore 1TiB PVC to bind..."
kubectl wait --for=jsonpath='{.status.phase}'=Bound pvc/open-rl-shared-pvc -n openrl-system --timeout=5m

echo "Confirming deployments rollout..."
kubectl -n openrl-system rollout status deployment/redis-store --timeout=3m
kubectl -n openrl-system rollout status deployment/open-rl-scheduler --timeout=3m
if kubectl -n openrl-system get deployment open-rl-gateway >/dev/null 2>&1; then
  kubectl -n openrl-system rollout status deployment/open-rl-gateway --timeout=3m
else
  kubectl -n openrl-system rollout status deployment/open-rl-api-server --timeout=3m
fi

echo "Published DRA ResourceSlices and Claims:"
kubectl get resourceslices,resourceclaims -A

echo "Workload pod images:"
kubectl get pods -n openrl-system -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{range .spec.containers[*]}{.image}{" "}{end}{"\n"}{end}'

echo "Smoke testing Gateway API service..."
GATEWAY_SVC="open-rl-gateway-service"
if ! kubectl -n openrl-system get svc "${GATEWAY_SVC}" >/dev/null 2>&1; then
  GATEWAY_SVC="open-rl-api-server-service"
fi
kubectl -n openrl-system port-forward "svc/${GATEWAY_SVC}" 18000:8000 >/dev/null 2>&1 &
PF_PID=$!
trap "kill ${PF_PID} 2>/dev/null || true" EXIT
sleep 3

echo "Probing /api/v1/healthz..."
curl -fsS http://127.0.0.1:18000/api/v1/healthz || curl -fsS http://127.0.0.1:18000/healthz
echo ""
echo "Probing /api/v1/get_server_capabilities..."
curl -fsS http://127.0.0.1:18000/api/v1/get_server_capabilities
echo ""

kill "${PF_PID}" || true
trap - EXIT

echo "=== Deployment finished successfully ==="
