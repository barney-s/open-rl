# Deploy OpenRL Latest Release on GKE (DRA + Filestore)

## What this needs

Requires real cloud infrastructure on Google Cloud Platform (GKE Standard cluster with NVIDIA GPUs, Filestore CSI driver, and node-level DRA drivers).

**Why real infrastructure is forced:**
- **Dynamic Resource Allocation (DRA):** OpenRL scheduler binds `gpu.nvidia.com` ResourceClaims and requires node-level kubelet plugin sockets and custom ResourceSlices.
- **Node-level drivers:** Requires privileged host daemonsets (`nvidia-dra-driver-gpu`, host `/home/kubernetes/bin/nvidia`).
- **Shared RWX Storage:** Multi-process weight synchronization and model caching require Google Cloud Filestore (`standard-rwx` StorageClass via GCP Filestore CSI driver).
- **Release Bundles:** Deploys official prebuilt release bundles (`openrl-lora.yaml`, `openrl-distributed-shared.yaml`, or `openrl-fft.yaml`) from GitHub Releases with images pinned to the release tag on `ghcr.io/gke-labs/open-rl/*`.

**Teardown cost:**
Runs G2 VMs (`g2-standard-24` with 2x L4 GPUs) and 1TiB Filestore. Prompt deletion after verification avoids recurring GPU and storage hourly billing.

### Verified Feasibility Checklist
- [x] GCP IAM permissions for cluster and node pool management (`roles/container.admin`)
- [x] GCP IAM permissions for Filestore instance creation (`roles/file.editor` / `file.googleapis.com`)
- [x] GCP IAM service account user permission (`roles/iam.serviceAccountUser`)
- [x] `gcloud` CLI (Google Cloud SDK 586.0.0+)
- [x] `kubectl` CLI (v1.35.8+ with server-side apply support)
- [x] `curl` CLI (for asset fetching and API verification)
- [x] `gh` CLI (v2.82.1+ for querying release tags)
- [ ] `helm` CLI v3 (for NVIDIA DRA driver installation) — ✗ MISSING: `curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash`
- [ ] `uv` CLI (optional for running host test clients) — ✗ MISSING: `curl -LsSf https://astral.sh/uv/install.sh | sh`

## Preconditions

Set instance parameters for GCP project, location, release bundle, and unique cluster identifier:

```bash
export PROJECT_ID="${PROJECT_ID:-$(gcloud config get-value project)}"
export REGION="${REGION:-us-central1}"
export ZONE="${ZONE:-us-central1-a}"
export CLUSTER_NAME="${RESOURCE_PREFIX:-openrl}-gke-rel"
export OPENRL_VERSION="${OPENRL_VERSION:-latest}"
export RELEASE_BUNDLE="${RELEASE_BUNDLE:-openrl-lora.yaml}"
gcloud config set project "${PROJECT_ID}"
```

## Steps

### 1. Enable Required GCP APIs
```bash
gcloud services enable \
  compute.googleapis.com \
  container.googleapis.com \
  file.googleapis.com
```

### 2. Create GKE Standard Cluster with Filestore CSI
```bash
gcloud container clusters create "${CLUSTER_NAME}" \
  --location="${REGION}" \
  --node-locations="${ZONE}" \
  --release-channel=regular \
  --machine-type=e2-standard-4 \
  --num-nodes=1 \
  --disk-size=100 \
  --addons=GcpFilestoreCsiDriver
```

### 3. Create GPU DRA Node Pool
```bash
gcloud container node-pools create gpu-dra \
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
```

### 4. Fetch Credentials and Install NVIDIA Drivers
```bash
gcloud container clusters get-credentials "${CLUSTER_NAME}" --location="${REGION}"

# Install host NVIDIA drivers
kubectl apply -f https://raw.githubusercontent.com/GoogleCloudPlatform/container-engine-accelerators/master/nvidia-driver-installer/cos/daemonset-preloaded-latest.yaml

# Install NVIDIA DRA GPU driver via Helm
helm repo add nvidia https://helm.ngc.nvidia.com/nvidia
helm repo update
helm install nvidia-dra-driver-gpu nvidia/nvidia-dra-driver-gpu \
  --version="25.8.0" \
  --create-namespace \
  --namespace nvidia-dra-driver-gpu \
  --set nvidiaDriverRoot="/home/kubernetes/bin/nvidia/"
```

### 5. Deploy Official OpenRL Release Bundle
Apply the rendered release manifest via server-side apply (required because the Workload CRD exceeds the client-side annotation size limit):
```bash
RELEASE_URL="https://github.com/gke-labs/open-rl/releases/${OPENRL_VERSION}/download/${RELEASE_BUNDLE}"
if [ "${OPENRL_VERSION}" = "latest" ]; then
  RELEASE_URL="https://github.com/gke-labs/open-rl/releases/latest/download/${RELEASE_BUNDLE}"
fi

kubectl apply --server-side -f "${RELEASE_URL}"
```

## Verify

### 1. Verify Storage, Pods, and DRA Slices
```bash
# Wait for Filestore 1TiB PVC to bind
kubectl wait --for=jsonpath='{.status.phase}'=Bound pvc/open-rl-shared-pvc -n openrl-system --timeout=5m

# Confirm deployments are rolled out
kubectl -n openrl-system rollout status deployment/redis-store --timeout=3m
kubectl -n openrl-system rollout status deployment/open-rl-scheduler --timeout=3m
kubectl -n openrl-system rollout status deployment/open-rl-api-server --timeout=3m

# Verify DRA resource slices published by NVIDIA driver
kubectl get resourceslices,resourceclaims -n openrl-system
```

### 2. Verify Release Image Tags
Confirm all OpenRL workloads run pinned release images from `ghcr.io/gke-labs/open-rl/*` and none run `:latest`:
```bash
kubectl get pods -n openrl-system -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{range .spec.containers[*]}{.image}{" "}{end}{"\n"}{end}'
```

### 3. Smoke Test API Server
```bash
kubectl -n openrl-system port-forward svc/open-rl-api-server-service 8000:8000 &
PF_PID=$!
sleep 2

curl -s http://127.0.0.1:8000/api/v1/healthz
curl -s http://127.0.0.1:8000/api/v1/get_server_capabilities

kill "${PF_PID}"
```

## Teardown

```bash
# 1. Remove active workloads and claims
kubectl -n openrl-system delete workloads,resourceclaims --all --ignore-not-found

# 2. Delete the GKE Cluster and associated Filestore storage
gcloud container clusters delete "${CLUSTER_NAME}" --location="${REGION}" --quiet
```
