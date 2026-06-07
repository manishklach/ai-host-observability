## Meaning

The host is in a severe memory-pressure state where a large fraction of time is being lost to stalls on memory allocation and reclaim.

## Impact

This often precedes host OOMs, cgroup kills, or major tail-latency spikes across AI inference and data-plane workloads.

## Diagnosis

Run these PromQL queries:

```promql
nixl_host_memory_psi_avg{scope="full",window="60s"}
```

```promql
increase(nixl_host_cgroup_memory_events{event="oom_kill"}[15m])
```

```promql
rate(nixl_host_fw_pages_sum[5m])
```

## Remediation

Escalate quickly: drain or cordon the node if needed, identify the top growing cgroup or process, and reduce or stop the workload driving host memory expansion.
