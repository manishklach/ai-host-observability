# THPFallbackRateHigh

## Meaning

Transparent hugepage allocations are frequently falling back to small pages.

## Impact

The host can show less predictable memory performance, higher CPU overhead, and more unstable transport behavior during registration-heavy GPU or RDMA activity.

## Diagnosis

- `rate(nixl_thp_fault_fallback_total[5m]) / (rate(nixl_thp_fault_alloc_total[5m]) + rate(nixl_thp_fault_fallback_total[5m]) + 1)`
- `nixl_thp_enabled_info`
- `nixl_hugepages_free`

## Remediation

Review THP mode, fragmentation, and hugepage pool sizing. If the workload depends on large pages, reduce memory fragmentation or provision explicit hugepages.
