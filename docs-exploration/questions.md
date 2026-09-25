# OpenRL Questions & Ambiguities

This document records open technical questions and architectural ambiguities identified during codebase exploration.

## Unresolved Questions

### 1. Multi-GPU & Distributed Training Support
- **Observation:** `scheduler/controller` assigns a single accelerator device per `Workload` claim (`accelerator.memory`), and `describe_worker` in `src/server/scheduler_worker_manager.py` requests single-worker allocations.
- **Question:** How will multi-GPU data/tensor parallel training (e.g. FSDP/DeepSpeed or tensor-parallel vLLM) integrate into the `Workload` CRD and DRA Claim allocations? Is multi-node worker gang scheduling planned via Kueue or directly inside the OpenRL scheduler?

### 2. Time-Slicing Backend Selection (`accel_timeslicer` vs `llmd`)
- **Observation:** `src/accel_timeslicer/` includes both an internal `SingleNodeTimeSlicer` (Unix/TCP socket daemon) and an `llmd.py` adapter connecting to `timeslice` / `llm-d-rl-time-slicing`.
- **Question:** Under what conditions should clusters use the standalone `SingleNodeTimeSlicer` DaemonSet versus the external `llm-d-rl-time-slicing` snapshot agent daemon?

### 3. LoRA Worker Instance Scaling & Capacity Accounting
- **Observation:** In `src/server/scheduler_worker_manager.py`, `workload_name` hardcodes instance index `0` for LoRA workloads (`lora-{owner}-0-{role}`), with a comment noting "The instance index stays 0 until adapter capacity accounting exists."
- **Question:** When adapter memory footprint on a single GPU reaches saturation, how will the API server and scheduler shard incoming adapter requests across multiple LoRA worker instances?

### 4. Protobuf Wire Encoding vs REST JSON Dual Path
- **Observation:** `src/server/api_server.py` handles both JSON-encoded requests and raw Protobuf payloads (`application/x-protobuf`) for endpoints like `/forward_backward` and `/sample`.
- **Question:** Is the JSON path intended solely for local debugging/testing fixtures, or is full bidirectional JSON parity intended to be maintained indefinitely alongside Tinker protobuf serialization?
