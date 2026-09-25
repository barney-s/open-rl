# OpenRL Code Map

## Directory Layout

```
open-rl/
├── src/                      # Core Python packages
│   ├── server/               # FastAPI server, request queues, session registry, vLLM engine
│   ├── training/             # PyTorch trainer workers (LoRA / FFT), loss functions, command definitions
│   └── accel_timeslicer/     # Cooperative GPU time-slicing daemon and client for FFT
├── scheduler/                # Kubernetes GPU DRA Scheduler (Go controller & CRDs)
│   ├── controller/           # Controller-runtime manager, placement logic, reconcile loops
│   ├── api/v1alpha1/         # CRD definitions: Workload, ClaimLedger
│   └── deploy/               # Kustomize base & overlay manifests for the scheduler
├── k8s/deploy/               # Deployment manifests (kind, distributed-shared, lustre, lora, fft)
├── dev/                      # Local dev tooling: kind setup, monitoring, dev CLI
├── examples/                 # SFT & RL recipes (Pig Latin, Text-to-SQL, Harvey Labs, Autoresearch)
├── scripts/                  # E2E test runners, VM synchronization, cluster eval scripts
└── tests/                    # Unit and integration test suite
```

## Top 20 Files That Matter Most

| File | Purpose | Criticality & Danger |
| --- | --- | --- |
| `src/server/api_server.py` | Primary FastAPI entry point handling Tinker REST/Protobuf routes and session heartbeats. | ⚠️ **DANGEROUS**: High concurrency surface; bugs in session reaping or async locks can orphan worker pods or leak GPU resources. |
| `src/server/store.py` | `RequestStore` and `StateStore` implementations for in-memory and Redis backends. | Core queueing contract; changes affect command serialization and future retrieval. |
| `src/server/session_registry.py` | Tracks active client sessions and maps them to owner runtimes for 30s auto-reaping. | Critical for multi-tenant cleanup; errors risk premature worker termination. |
| `src/server/worker_manager.py` | Abstract `WorkerManager` protocol and `LocalWorkerManager` for subprocess spawning. | Core worker abstraction decoupling local execution from Kubernetes. |
| `src/server/scheduler_worker_manager.py` | K8s worker manager creating `Workload` CRDs for the cluster scheduler. | Translates API server worker requests into Kubernetes scheduler CRDs. |
| `src/server/training_requests_processor.py` | Background loop in trainer workers draining commands from Redis. | Coordinates training lifecycle and time-slicer registration. |
| `src/server/vllm_sampler.py` | vLLM worker entry point processing generation requests and dynamic weight loading. | Main inference engine; handles sleep/wake states for time-slicing. |
| `src/server/delta_weight_transfer_engine.py` | Custom vLLM `WeightTransferEngine` applying sparse `.safetensors` CPU deltas to GPU. | ⚠️ **DANGEROUS**: Manipulates raw tensor storage in host/device memory; bugs cause silent weight corruption or GPU crashes. |
| `src/server/proto_codec.py` | Encoders and decoders for Tinker Protobuf messages (`tinker_public_pb2`). | Wire-format boundary for Tinker protocol compatibility. |
| `src/server/model_metadata.py` | Pydantic model metadata and weight sync configuration parsers. | Configuration bridge between API server, workers, and env vars. |
| `src/server/estimator.py` | Peak accelerator memory and tier footprint estimation for models and roles. | Direct input to scheduler placement decisions. |
| `src/training/trainer_worker.py` | `BaseTrainerWorker` abstract base defining training operations. | Core interface implemented by all post-training backends. |
| `src/training/lora_trainer_worker.py` | PEFT LoRA training worker managing multi-adapter lifecycles and optimizer states. | ⚠️ **DANGEROUS**: Manages complex PEFT module targeting, tied embeddings, and optimizer state swaps. |
| `src/training/fft_trainer_worker.py` | Full Fine-Tuning worker managing full model state updates and delta diffs. | Implements full-model backprop and diff calculation against base weights. |
| `src/training/losses.py` | Loss function implementations (Cross-Entropy, Importance Sampling, etc.). | Mathematical core of RL and SFT objectives. |
| `src/training/commands.py` | Command dataclasses (`ForwardBackwardCommand`, `OptimStepCommand`, etc.). | Internal wire format between API server and trainer processors. |
| `src/accel_timeslicer/single_node.py` | Single-node time-slicer server managing mutual exclusion over accelerator access. | ⚠️ **DANGEROUS**: Coordinates GPU locks; deadlocks or lease faults freeze training and sampling. |
| `src/accel_timeslicer/time_slicer.py` | Client interface and socket transport for registering and leasing GPUs. | Async context manager interface used across worker loops. |
| `scheduler/controller/internal/controller/workload_controller.go` | Kubernetes controller reconciling `Workload` CRDs and managing DRA claims. | ⚠️ **DANGEROUS**: Manages pod creation and claim binding; race conditions cause GPU double-booking. |
| `scheduler/controller/internal/placement/placement.go` | Pure placement algorithm computing binpack and spread assignments on DRA claims. | ⚠️ **DANGEROUS**: Core scheduling logic; errors cause unschedulable pods or claim exhaustion. |

## Entry Points

- **API Server:** `src/server/api_server.py` (`uvicorn server.api_server:app --port 9003`)
- **Trainer Worker (Standalone/Pod):** `src/server/training_requests_processor.py` (`python -m server.training_requests_processor`)
- **vLLM Sampler Worker:** `src/server/vllm_sampler.py` (`python -m server.vllm_sampler`)
- **Accel Time-Slicer Server:** `src/accel_timeslicer/serve.py` (`python -m accel_timeslicer.serve`)
- **Scheduler Controller Manager:** `scheduler/controller/cmd/manager/main.go`
- **Developer CLI:** `dev/tools/cli.py` (`make cli ...`)
