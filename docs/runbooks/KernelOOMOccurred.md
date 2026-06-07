## Meaning

The kernel log is recording OOM behavior rather than only trending toward it.

## Impact

Processes may already be getting killed, service quality is likely degraded, and the node may be unsafe for continued workload placement.

## Diagnosis

Run these PromQL queries:

```promql
rate(nixl_kernel_log_pattern_total{pattern="oom"}[5m])
```

```promql
increase(nixl_host_cgroup_memory_events{event="oom_kill"}[10m])
```

```promql
topk(10, nixl_process_locked_bytes)
```

## Remediation

Identify the killed process or offending cgroup, stabilize the node, and decide whether to restart, drain, or isolate the workload causing host memory exhaustion.
