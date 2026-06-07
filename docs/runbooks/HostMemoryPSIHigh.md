## Meaning

The host is spending a sustained amount of time stalled on memory pressure, but the node may still be recoverable before it reaches host OOM conditions.

## Impact

Expect higher latency, reclaim churn, and potentially degraded GPU or RDMA workload behavior even if GPU utilization still looks normal.

## Diagnosis

Run these PromQL queries:

```promql
nixl_host_memory_psi_avg{scope="full",window="60s"}
```

```promql
nixl_host_meminfo_bytes{field=~"memavailable|memfree"}
```

```promql
rate(nixl_host_vmstat{field=~"pgscan_direct|pgmajfault"}[5m])
```

## Remediation

Reduce memory pressure by shedding nonessential workloads, checking cgroup growth, and investigating whether RDMA registration or pinned memory has started to climb.
