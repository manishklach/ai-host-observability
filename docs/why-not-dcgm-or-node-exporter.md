# Why Not Just Use DCGM or node_exporter?

Short answer: you should use them too.

This repo is not trying to replace DCGM or `node_exporter`. It fills a different observability gap:

- DCGM is GPU-focused
- `node_exporter` is generic Linux-host-focused
- `ai-host-observability` focuses on the seam where GPU, RDMA, VFIO, NIC, NUMA, and host memory pressure interact

That seam is where many accelerated-host incidents actually begin.

## The Positioning

### DCGM

DCGM is excellent for:

- GPU utilization
- HBM usage
- thermals
- clocks
- ECC
- some PCIe and NVLink signals

But DCGM may not be the first place you see:

- host reclaim spikes
- memory PSI
- `mlx5` firmware page growth
- cgroup memory pressure
- process `Locked:` growth
- softnet backlog and host interrupt pressure

### node_exporter

`node_exporter` is excellent for:

- generic CPU, memory, filesystem, and network host telemetry
- broad Linux-host coverage
- standard Prometheus integration

But by itself it may miss or not emphasize:

- RDMA-specific counters
- `mlx5` debugfs registration signals
- GPU BAR1
- cgroup-focused pinned-memory correlation
- the AI-host-specific interpretation layer

### This Repo

`ai-host-observability` is a lightweight seam observability layer for accelerated Linux hosts.

It focuses on:

- host pressure caused by GPU/RDMA/VFIO/NIC-heavy workloads
- early warning signals before the failure becomes obvious in apps or GPUs
- textfile-collector-friendly deployment
- low dependency overhead

## Comparison Table

| Layer | Tool | What it sees | What it may miss |
|---|---|---|---|
| GPU device | DCGM | GPU utilization, HBM, thermals, ECC, device-level telemetry | Host reclaim, PSI, cgroup pressure, process locked memory, `mlx5` firmware pages |
| Generic Linux host | node_exporter | Standard CPU, memory, filesystem, and network host metrics | AI-specific seam signals like RDMA registration growth, BAR1 pressure correlation, VFIO-focused context |
| AI host seam layer | ai-host-observability | Host pressure from GPU/RDMA/VFIO/NIC-heavy workloads, including `fw_pages_total`, softirq pressure, BAR1, kernel-event patterns | Deep app/runtime internals, framework-level allocation logic |
| App/runtime layer | framework/runtime metrics | Model throughput, batch size, allocator stats, request latency, runtime decisions | Kernel and host-side pressure outside the application’s visibility |

## The Practical Recommendation

Use all of them together:

- DCGM for GPU truth
- `node_exporter` for baseline Linux truth
- `ai-host-observability` for the host seam
- app/runtime metrics for workload truth

That combination gives you the best chance of catching:

- “GPU looks fine, host is sick”
- host memory collapse before GPU OOM
- RDMA registration growth
- VFIO or IOMMU-related host degradation

