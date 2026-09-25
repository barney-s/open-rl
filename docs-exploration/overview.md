# OpenRL Overview

OpenRL is a self-hosted post-training API and runtime that decouples reinforcement learning (RL) and fine-tuning algorithms from underlying accelerator infrastructure. It implements the Thinking Machines Lab [Tinker API](https://tinker-docs.thinkingmachines.ai/) specification over HTTP/JSON and Protocol Buffers.

## For Whom

- **AI/RL Researchers:** Write standard Python RL/SFT loops (GRPO, PPO, Reinforce, SFT) against clean SDK primitives (`create_model`, `forward_backward`, `optim_step`, `sample`) without managing CUDA environments, distributed tensors, or cluster orchestration.
- **Infrastructure & Platform Engineers:** Manage GPU utilization, dynamic scheduling, multi-tenant packing, and accelerator time-slicing on self-hosted Kubernetes (GKE, kind) or VM clusters independently of training code.

## Why It Exists

1. **Hardware Utilization in Agentic RL:** Traditional RL training loops operate sequentially: training processes idle while sampling runs, and sampling idles while external environments score rewards. OpenRL multiplexes training and sampling across workloads, allowing dense GPU sharing.
2. **Infrastructure Decoupling:** Training loops run locally (e.g. on a developer laptop or local workstation) while directing computation to remote GPU nodes or clusters via standard APIs.
3. **Multi-Tenancy & Resource Efficiency:**
   - **LoRA Workloads:** Multiple fine-tuning jobs share a single in-memory base model instance with isolated adapters and optimizer states.
   - **Full Fine-Tuning (FFT):** Dedicated worker instances share physical GPUs via accelerator time-slicing (e.g. via llm-d snapshotting or CUDA checkpointing) and Dynamic Resource Allocation (DRA).
   - **Zero-Downtime Weight Synchronization:** Fast sparse delta weight patching into vLLM engines via native in-memory transfer engines without engine restarts.

## Key Operating Modes

- **Local / Development Mode:** Single-machine execution with local subprocess management and optional in-memory stores for fast prototyping.
- **Kubernetes / DRA Mode:** Production deployment utilizing an in-tree Go Kubernetes controller (`openrl.io/v1alpha1` `Workload`), Redis-backed request queues, DRA resource claims, and node-local time-slicing daemons.
