# OpenRL Code Map

## Directory Layout

```
open-rl/
├── src/
│   ├── server/           # FastAPI API server, store backends, proto codec, vLLM engine
│   ├── training/         # PyTorch trainer workers (LoRA & FFT), commands, loss functions
│   └── accel_timeslicer/ # Node-local GPU lease coordinator (TCP/Unix socket)
├── scheduler/
│   └── controller/       # Go Kubernetes controller for Workload CRDs and DRA placement
├── k8s/                  # Kustomize base & overlay manifests (kind-dra, gke, lora, fft)
├── dev/                  # Cluster scripts (kind/GCP), monitoring dashboards, tools
├── examples/             # Tutorials & recipes (autoresearch, harvey_labs, text-to-sql, SFT)
├── tests/                # Unit, integration, compatibility, and mock tests
└── scripts/              # Helper scripts (Tinker proto sync, VM setup, cluster e2e)
```

## Entry Points

- **API Server:** `uvicorn server.api_server:app --host <host> --port <port>` (invoked via `make server` or `Dockerfile.api_server`).
- **Trainer Worker Daemon:** `python -m server.training_requests_processor` (invoked per model or active tenant set).
- **vLLM Sampler:** `python -m server.vllm_sampler` (invoked via `make vllm` or `Dockerfile`).
- **Time-Slicer Daemon:** `python -m accel_timeslicer.serve` (runs as a node-level DaemonSet or local daemon).
- **K8s Scheduler Controller:** `scheduler/controller/cmd/manager/main.go` (deployed via `scheduler/deploy/`).
- **CLI / Tools:** `dev/tools/cli.py` (invoked via `make cli <command>`).

## 20 Files That Matter Most

| File | Purpose |
|---|---|
| `src/server/api_server.py` | FastAPI application serving Tinker endpoints and managing async long-polling futures. |
| `src/server/training_requests_processor.py` | Queue consumer loop draining batched tenant commands into trainer instances. |
| `src/server/store.py` | `RequestStore` (queue + futures) and `StateStore` (metadata) for in-memory and Redis. |
| `src/server/proto_codec.py` | Zero-copy byte packer converting between Tinker SDK Protobuf messages and internal dicts. |
| `src/server/worker_manager.py` | Abstract worker manager interface and local process launcher. |
| `src/server/scheduler_worker_manager.py` | Kubernetes worker manager translating runtime requirements into `Workload` CRDs. |
| `src/server/delta_weight_transfer_engine.py` | Native vLLM `WeightTransferEngine` implementing in-place CPU snapshot delta updates. |
| `src/server/vllm_sampler.py` | vLLM sampling daemon handling weight synchronization and generation requests. |
| `src/server/session_registry.py` | Tinker session heartbeat monitor and idle runtime garbage collector. |
| `src/server/estimator.py` | Mathematical model memory footprint estimation for DRA GPU device allocations. |
| `src/training/trainer_worker.py` | Base PyTorch execution worker abstraction handling training loops and checkpointing. |
| `src/training/lora_trainer_worker.py` | Multi-tenant LoRA execution worker with per-adapter states on a shared base model. |
| `src/training/fft_trainer_worker.py` | Dedicated Full Fine-Tuning worker managing full-weight backprop and weight diffing. |
| `src/training/commands.py` | Internal Pydantic command schemas dispatched through the request queue. |
| `src/accel_timeslicer/single_node.py` | Node-local lease state machine managing active/checkpointed GPU access. |
| `src/accel_timeslicer/time_slicer.py` | Time-slicer client protocol and IPC socket communication. |
| `scheduler/controller/internal/placement/placement.go` | Pure scheduling algorithms (binpack vs spread) mapping workloads to DRA resource slices. |
| `scheduler/controller/internal/controller/workload_controller.go` | Kubernetes controller-runtime reconciler managing Workload and ClaimLedger lifecycles. |
| `scheduler/controller/api/v1alpha1/workload_types.go` | Go struct definitions for `Workload` and `ClaimLedger` CRDs. |
| `Makefile` | Root orchestration for testing, building containers, running servers, and rendering manifests. |

## Dangerous Files to Modify

- **`src/server/proto_codec.py`:** Directly unpacks binary buffers using Python's `array` module with strict endianness and typecode assumptions matching upstream Tinker Protobufs. Any subtle field misalignment or incorrect type conversion causes silent payload corruption or failures in Tinker SDK client polling.
- **`src/server/delta_weight_transfer_engine.py`:** Operates inside vLLM's internal weight loading hooks to perform in-place sparse tensor patching in CPU RAM. Incorrect tensor indexing or safetensors loading logic leads to silent weight corruption during live sampling rollouts.
- **`scheduler/controller/internal/placement/placement.go`:** Contains concurrency-sensitive capacity arithmetic for GPU memory tiers and claim ledgers. Flaws here cause scheduler race conditions, GPU double-booking, or unschedulable pod deadlocks under high load.
- **`src/server/session_registry.py` & `src/server/api_server.py` (`owner_locks`):** In-process mutual exclusion locks protect the critical window between session teardown and worker reclamation. Modifications could cause orphaned GPU worker pods or race conditions where active sessions attach to reaped workers.
