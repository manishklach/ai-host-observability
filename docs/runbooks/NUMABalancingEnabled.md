# NUMABalancingEnabled

## Meaning
Automatic NUMA balancing is enabled on a host where predictable memory locality is usually preferred.

## Impact
Page migration activity can add latency variance, churn memory mappings, and create noisy performance differences across ostensibly identical GPU nodes.

## Diagnosis
Check `nixl_host_sysctl{name="kernel.numa_balancing"}` and compare with job throughput, page-fault behavior, and cross-node consistency. Confirm whether the setting is intentionally enabled for this host class.

## Remediation
Disable NUMA balancing on dedicated GPU training nodes unless there is a specific reason to keep it enabled. Reapply the policy across the fleet to remove drift.
