# Open Questions & Code Observations

This document captures ambiguities, architectural constraints, and differences between documentation and code.

## 1. Single API Server Replica Constraint & Distributed Locking

- **Observation:** `src/server/api_server.py` uses in-process `asyncio.Lock` (`owner_locks`) to synchronize session attachment and worker teardown during session reaping.
- **Question:** While `store.py` and `session_registry.py` use Redis for shared state across pods, the in-process `owner_locks` restrict the API server deployment to a single replica (`replicas: 1`). Is a distributed Redis-based locking mechanism planned to allow horizontal scaling of the API server frontend?

## 2. LoRA vs FFT Placement & Time-Slicing Symmetry

- **Observation:** In `scheduler/controller/internal/placement/placement.go`, FFT workloads participate in time-slicing and binpack into shared claims, whereas LoRA workloads receive exclusive claims (waiting for a free GPU if none are available).
- **Question:** While multiple LoRA adapters sharing the same base model reuse a single worker before placement, different base models running LoRA cannot time-slice a GPU under current placement logic. Is cross-base-model LoRA time-slicing intended in a future release?

## 3. vLLM Model Architecture Overrides

- **Observation:** `src/server/worker_manager.py` explicitly injects `VLLM_ARCHITECTURE_OVERRIDE="Gemma4ForCausalLM"` when detecting `gemma-4` or `gemma4` in base model names.
- **Question:** Is this intended as a temporary upstream compatibility shim for vLLM 0.25.x, and will it be superseded by dynamic model registration in newer vLLM releases?

## 4. In-Memory Store vs Multi-Worker Deployments

- **Observation:** `src/server/training_requests_processor.py` strictly raises an error if instantiated with a time slicer without a `REDIS_URL`. Local mode can run entirely with `InMemoryStore`.
- **Question:** For local testing of time-slicing without Kubernetes, is a local Redis server always mandatory, or is an IPC-shared in-memory queue planned for local multi-process testing?

## 5. Filestore StorageClass Default VPC Network Binding

- **Observation:** In `k8s/deploy/lora/storage.yaml` and `k8s/deploy/distributed-shared/01-shared-pvc.yaml`, the PVC references `standard-rwx`, which relies on GKE's managed `GcpFilestoreCsiDriver` binding implicitly to the GCP `default` VPC network.
- **Question:** For non-default VPC networks or VPC Service Controls (VPC-SC) perimeters, will parameterized Kustomize overlays provide custom Filestore `StorageClass` manifests (with explicit `parameters.network`)?

## 6. GPU Node Taints vs DRA Driver DaemonSet Tolerations

- **Observation:** Standard GKE GPU node pools often apply `nvidia.com/gpu=present:NoSchedule` or similar taints to reserve GPU nodes. The NVIDIA DRA driver Helm chart and preloaded GPU driver installer daemonsets need matching tolerations to schedule cleanly on dedicated GPU pools.
- **Question:** Should default Kustomize overlays or Helm values files pin standard tolerations across all runtime DaemonSets (`open-rl-accel-timeslicer`, `snapshot-agent`, `nvidia-dra-driver-gpu`) to avoid manual daemonset patching on tainted pools?

