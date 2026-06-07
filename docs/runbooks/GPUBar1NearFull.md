## Meaning

BAR1 aperture usage is close to full for one or more GPUs.

## Impact

Transfers and mappings between the host and GPU may become constrained, and this can correlate with broader host-side pressure or PCIe instability.

## Diagnosis

Run these PromQL queries:

```promql
nixl_gpu_bar1_used_bytes / nixl_gpu_bar1_total_bytes
```

```promql
nixl_gpu_memory_used_bytes / nixl_gpu_memory_total_bytes
```

```promql
nixl_gpu_pcie_link_width
```

## Remediation

Reduce the mapping footprint, inspect the workload’s host-device transfer pattern, and correlate BAR1 pressure with pinned memory or PCIe-side warnings.
