# PCIe and VFIO Instability

## Symptoms

- AER-related kernel log events
- VFIO or IOMMU errors in logs
- device resets, drops, or disappearing throughput

## Likely Causes

- PCIe link instability
- IOMMU mapping faults
- reset-sensitive passthrough device behavior

## Metrics to Inspect

- `nixl_kernel_log_pattern_total`
- `nixl_pcie_device_info`
- `nixl_vfio_group_devices`
- `nixl_module_loaded`
- `nixl_gpu_pcie_link_width`

## Manual Commands

```bash
journalctl -k -b | grep -Ei 'aer|vfio|iommu|dma fault'
lspci -vv
```

## PromQL

```promql
increase(nixl_kernel_log_pattern_total{pattern="pcie_aer"}[30m])
increase(nixl_kernel_log_pattern_total{pattern=~"vfio|iommu_dma"}[30m])
```

## Correlate

- align kernel log spikes with workload phase changes
- compare GPU PCIe link width against expected topology

## Safe Mitigations

- reduce churn from resets or hot reconfiguration
- isolate unstable devices from production scheduling

## Avoid Early Conclusions

- do not blame VFIO alone before checking broader PCIe health

