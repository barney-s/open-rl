# OpenRL Architecture

OpenRL exposes the Tinker API via FastAPI, queues training work across models, delegates execution to dedicated or shared GPU workers, and synchronizes updated weights to sampling engines with minimal overhead.

```mermaid
flowchart TB
    subgraph Client["Client (Researcher Workflow)"]
        Loop["Training Loop (Tinker SDK / Python)"]
    end

    subgraph ControlPlane["API & State Plane"]
        API["FastAPI API Server<br/>(src/server/api_server.py)"]
        Registry["Session Registry & Reaper<br/>(src/server/session_registry.py)"]
        Codec["Proto Codec<br/>(src/server/proto_codec.py)"]
        Store[("Request & State Store<br/>(Redis / InMemory)")]
        Mgr["Worker Manager<br/>(Local / Scheduler K8s)"]
    end

    subgraph TrainingPlane["Training Plane"]
        Processor["Training Requests Processor<br/>(src/server/training_requests_processor.py)"]
        LoraWorker["LoRA Trainer Worker<br/>(src/training/lora_trainer_worker.py)"]
        FFTWorker["FFT Trainer Worker<br/>(src/training/fft_trainer_worker.py)"]
    end

    subgraph InferencePlane["Inference / Sampling Plane"]
        VLLM["vLLM Sampler<br/>(src/server/vllm_sampler.py)"]
        WeightEngine["Delta Snapshot Weight Transfer Engine<br/>(src/server/delta_weight_transfer_engine.py)"]
        LoraSampler["PyTorch / PEFT Sampler<br/>(src/server/lora_sampler.py)"]
    end

    subgraph Coordination["GPU Orchestration & Time Slicing"]
        TimeSlicer["Accel Time-Slicer Daemon<br/>(src/accel_timeslicer/)"]
        K8sSched["Go GPU Scheduler Controller<br/>(scheduler/controller/)"]
    end

    Loop -->|1. HTTP JSON/Protobuf| API
    API --> Codec
    API --> Registry
    API -->|2. Enqueue Work & Futures| Store
    API -->|Ensure Workers| Mgr
    Mgr -->|Create Workload CRDs| K8sSched
    Store -.->|3. Drain Commands| Processor
    Processor --> LoraWorker
    Processor --> FFTWorker
    FFTWorker <-->|Acquire/Release GPU Lease| TimeSlicer
    VLLM <-->|Acquire/Release GPU Lease| TimeSlicer
    LoraWorker -->|4. Save Deltas / Checkpoints| WeightEngine
    FFTWorker -->|4. Save Deltas / Checkpoints| WeightEngine
    WeightEngine -->|5. In-Place Delta Patch| VLLM
    API -->|Forward Sample Requests| VLLM
    API -->|Forward Sample Requests| LoraSampler
```

## Key Abstractions

| Abstraction | File Location | Responsibility |
|---|---|---|
| `api_server.py` | `src/server/api_server.py` | FastAPI application exposing Tinker API (`/api/v1/create_model`, `/api/v1/forward_backward`, `/api/v1/optim_step`, `/api/v1/sample`, `/api/v1/retrieve_future`). Manages async future polling and session heartbeats. |
| `proto_codec.py` | `src/server/proto_codec.py` | Zero-copy byte manipulation converting Protobuf wire formats (used by Tinker SDK >= 0.25) to internal command structures without requiring NumPy in API edge pods. |
| `RequestStore` / `StateStore` | `src/server/store.py` | Queue abstraction for per-model command streams and futures. Backed by `InMemoryStore` (local dev) or `RedisStore` (cluster/multi-process). |
| `WorkerManager` | `src/server/worker_manager.py` | Factory protocol for spinning up model runtimes. `LocalWorkerManager` spawns subprocesses; `SchedulerWorkerManager` creates Kubernetes `Workload` CRDs. |
| `TrainingRequestsProcessor` | `src/server/training_requests_processor.py` | Background daemon polling `RequestStore` for batched tenant training commands and executing them against worker backends. |
| `LoraTrainingWorker` / `FFTTrainingWorker` | `src/training/` | Underlying PyTorch execution engines. LoRA worker maintains multi-tenant adapters over a frozen base model; FFT worker runs full-weight backpropagation and optimizer steps. |
| `DeltaSnapshotWeightTransferEngine` | `src/server/delta_weight_transfer_engine.py` | Pull-based delta weight sync for vLLM. Applies sparse safetensors patches into CPU snapshot memory and loads updated tensors directly into GPU memory without process restarts. |
| `SingleNodeTimeSlicer` | `src/accel_timeslicer/` | IPC socket/TCP daemon managing GPU residency leases between training and sampling workloads on shared accelerators via `llm-d` or `cuda-checkpoint`. |
| `Workload Controller` | `scheduler/controller/` | Go controller reconciling `openrl.io/v1alpha1` `Workload` and `ClaimLedger` resources against Kubernetes Dynamic Resource Allocation (DRA) `ResourceSlice` objects. |
| `estimator.py` | `src/server/estimator.py` | Memory footprint calculation for base models, LoRA ranks, optimizer states, and context lengths used to size worker device allocations. |

## Data & Request Lifecycle

```mermaid
sequenceDiagram
    autonumber
    actor Client as Tinker Client SDK
    participant API as API Server
    participant Redis as Redis / RequestStore
    participant Trainer as Trainer Worker
    participant Storage as Shared Volume / Memory
    participant Sampler as vLLM Sampler

    Client->>API: POST /api/v1/forward_backward (Protobuf/JSON)
    API->>Redis: Enqueue command & initialize future
    API-->>Client: Return request_id immediately
    Redis->>Trainer: Drain command batch
    Trainer->>Trainer: Forward pass, backward pass, accumulate gradients
    Trainer->>Redis: Mark future completed
    Client->>API: POST /api/v1/retrieve_future (Long Poll)
    API->>Redis: Check future status
    API-->>Client: Return ForwardBackwardOutput

    Client->>API: POST /api/v1/save_weights_for_sampler
    API->>Redis: Enqueue save command
    Trainer->>Storage: Write sparse delta safetensors
    API->>Sampler: POST /v1/weight_transfer/update
    Sampler->>Storage: Read delta patch
    Sampler->>Sampler: In-memory CPU patch & load_weights callback
```
