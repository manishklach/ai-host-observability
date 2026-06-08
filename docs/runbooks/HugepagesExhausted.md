# HugepagesExhausted

## Meaning

The 2MB hugepage pool is fully allocated while a configured pool still exists.

## Impact

RDMA registrations, GPU BAR mappings, and some userspace allocators can fall back to small pages, which increases TLB pressure and can create throughput cliffs.

## Diagnosis

- `nixl_hugepages_free{size="2048kB"}`
- `nixl_hugepages_total{size="2048kB"}`
- `rate(nixl_thp_fault_fallback_total[5m])`

## Remediation

Increase the hugepage pool if the workload expects it, reclaim abandoned consumers, or rebalance workloads away from the node before new allocations start falling back heavily.
