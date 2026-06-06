# GPU Looks Fine, Host Is Dying: Catching Host OOM Before It Happens

This walkthrough covers a failure mode that shows up on accelerated AI servers running GPU- and RDMA-heavy workloads:

- GPU HBM graphs look stable
- GPU utilization looks normal
- application logs may not show the first warning
- but the host starts losing memory headroom, reclaim rises, and the node eventually OOMs

This is exactly the kind of seam-level issue `ai-host-observability` is built to make visible.

## The Scenario

Imagine a multi-GPU host serving inference or training with:

- a high-throughput runtime
- heavy pinned-memory or buffer-registration behavior
- one or more RDMA or NIC data paths
- cgroup isolation for jobs or services

The workload begins normally:

- GPU utilization is high but expected
- GPU memory used is stable
- latency is acceptable

Then host-only pressure starts building:

- `MemAvailable` falls
- memory PSI rises
- reclaim counters increase
- cgroup memory usage grows
- `mlx5` firmware pages grow
- process locked memory grows

If nobody is watching those host-side signals, the first obvious symptom may be:

- host OOM killer activity
- cgroup OOM kills
- application failures that appear unrelated to GPU memory

## Symptoms

Typical early symptoms:

- minor latency spikes before throughput visibly drops
- host free memory slowly falling despite “healthy” GPU dashboards
- pressure concentrated on one node or cgroup
- rising softirq, RDMA, or NIC-side counters in parallel

Late symptoms:

- direct reclaim spikes
- swap activity
- OOM killer events
- cgroup `oom_kill` counters increasing
- workloads restarting or hanging

## Timeline

### T0: Workload Starts

- `nixl_gpu_utilization_percent` rises to expected steady-state
- `nixl_gpu_memory_used_bytes` rises, then stabilizes
- `nixl_host_meminfo_bytes{field="memavailable"}` starts healthy
- PSI is near zero

Interpretation:

- the GPU is busy, but nothing looks pathological yet

### T+10 Minutes: Hidden Host Pressure Begins

- `nixl_host_meminfo_bytes{field="memavailable"}` trends down
- `nixl_host_fw_pages_sum` starts rising
- `nixl_process_locked_bytes` shows one or more pinned-memory-heavy processes

Interpretation:

- the first warning is host-side allocation pressure, not GPU HBM exhaustion

### T+20 Minutes: Pressure Becomes Visible

- `nixl_host_memory_psi_avg{scope="some",window="60s"}` rises
- `rate(nixl_host_vmstat{field="pgscan_direct"}[10m])` increases
- `nixl_host_cgroup_memory_current_bytes` continues growing
- `increase(nixl_host_cgroup_memory_events{event="high"}[10m])` may appear

Interpretation:

- the kernel is now spending real time stalled on memory pressure
- reclaim is active and likely user-visible

### T+30 Minutes: Transport/Seam Signals Join In

- `rate(nixl_host_fw_pages_sum[15m])` remains elevated
- `increase(nixl_infiniband_counter{counter="port_rcv_errors"}[10m])` may begin to move
- `increase(nixl_net_ethtool_stat{stat="link_down_events_phy"}[30m])` might remain zero, which is useful

Interpretation:

- if RDMA/NIC errors remain low while firmware pages keep rising, the root problem is likely still memory registration pressure, not a bad link

### T+40 Minutes: Failure Threshold

- `nixl_host_meminfo_bytes{field="memavailable"}` gets critically low
- `nixl_host_memory_psi_avg{scope="some",window="60s"}` stays elevated
- `increase(nixl_host_cgroup_memory_events{event="oom_kill"}[15m]) > 0` or
- `increase(nixl_kernel_log_pattern_total{pattern="oom"}[30m]) > 0`

Interpretation:

- the node has crossed from degraded to actively failing

## PromQL Queries

Start with these:

```promql
nixl_host_meminfo_bytes{field="memavailable"}
```

```promql
nixl_host_memory_psi_avg{scope="some",window="60s"}
```

```promql
rate(nixl_host_vmstat{field="pgscan_direct"}[10m])
```

```promql
nixl_host_cgroup_memory_current_bytes
```

```promql
rate(nixl_host_fw_pages_sum[15m])
```

```promql
topk(10, nixl_process_locked_bytes)
```

```promql
increase(nixl_host_cgroup_memory_events{event="oom_kill"}[15m])
```

```promql
increase(nixl_kernel_log_pattern_total{pattern="oom"}[30m])
```

Correlate against GPU-side metrics:

```promql
nixl_gpu_utilization_percent
```

```promql
nixl_gpu_memory_used_bytes
```

```promql
nixl_gpu_bar1_used_bytes / nixl_gpu_bar1_total_bytes
```

## Manual Linux Commands

Check host memory directly:

```bash
grep -E 'MemAvailable|MemFree|SwapFree|Buffers|Cached' /proc/meminfo
cat /proc/pressure/memory
grep -E 'pgscan|pgsteal|pswp' /proc/vmstat
```

Check firmware-page growth:

```bash
find /sys/kernel/debug/mlx5 -name fw_pages_total -exec sh -c 'printf "%s " "$1"; cat "$1"' _ {} \;
```

Check cgroup memory:

```bash
cat /sys/fs/cgroup/<path>/memory.current
cat /sys/fs/cgroup/<path>/memory.events
cat /sys/fs/cgroup/<path>/memory.pressure
```

Check locked memory per process:

```bash
grep -E '^VmLck:' /proc/<pid>/status
grep -E '^Locked:' /proc/<pid>/smaps_rollup
```

Check kernel log evidence:

```bash
journalctl -k -b | grep -Ei 'oom|out of memory|vfio|iommu|mlx5|rdma|aer'
```

## Metrics to Watch From This Repo

- `nixl_host_meminfo_bytes`
- `nixl_host_memory_psi_avg`
- `nixl_host_vmstat`
- `nixl_host_cgroup_memory_current_bytes`
- `nixl_host_cgroup_memory_events`
- `nixl_host_fw_pages_total`
- `nixl_host_fw_pages_sum`
- `nixl_process_locked_bytes`
- `nixl_process_vm_lck_bytes`
- `nixl_kernel_log_pattern_total`
- `nixl_gpu_memory_used_bytes`
- `nixl_gpu_bar1_used_bytes`

## How to Interpret the Pattern

If these are true at the same time:

- GPU memory is stable
- GPU utilization is normal
- host `MemAvailable` is falling
- memory PSI is rising
- direct reclaim is increasing
- `fw_pages_total` is growing
- locked memory is growing

then the best hypothesis is:

- the host is being squeezed by pinned or registered memory, not by classic GPU HBM exhaustion

That is exactly the seam that generic GPU dashboards often miss.

## Safe Mitigations

- reduce workload density per host
- reduce registration fan-out or buffer registration churn
- reduce per-job pinned memory footprint
- isolate the offender cgroup or process
- increase host memory headroom if operationally acceptable
- roll back a recent UCX, runtime, or NIC-configuration change if it correlates

## What Not to Conclude Too Early

- do not assume “GPU memory is fine” means the node is healthy
- do not assume the problem is a Linux kernel bug before measuring registration growth
- do not blame PCIe or NIC links first if firmware-page growth is the leading signal
- do not jump straight to driver debugging if reclaim and locked memory already explain the behavior

## Why This Demo Matters

This repo is most valuable when the first warning lives between layers:

- not just on the GPU
- not just in generic host metrics
- not just in app logs

It is built to make that hidden host seam visible before the node reaches OOM.

