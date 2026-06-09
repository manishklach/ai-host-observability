# AI Host Golden Signals

## Why AI Hosts Fail Differently

GPU servers often fail first at the Linux host seam, not in the most obvious GPU dashboard. HBM can still look healthy while the host is already losing memory headroom, building reclaim stalls, exhausting pinned-memory limits, or accumulating RDMA registration state.

## Hidden Host Memory Pressure

Start with:

- `nixl_host_meminfo_bytes{field="memavailable"}`
- `nixl_host_memory_psi_avg`
- `nixl_host_vmstat`
- `nixl_host_cgroup_memory_current_bytes`
- `nixl_host_cgroup_memory_events`

This is the fastest way to catch the classic pattern where the guest or app looks fine but the host is already degrading.

## RDMA Registration Growth

Watch:

- `nixl_host_fw_pages_sum`
- `nixl_host_fw_pages_total`
- `nixl_infiniband_counter`
- `nixl_host_ulimit{resource="memlock"}`

This is the key host-side signal family for registration-heavy collectives and buffer pinning behavior that can quietly consume host RAM.

## GPU BAR1 / ECC / Clocks / Slowdown

Watch:

- `nixl_gpu_bar1_used_bytes`
- `nixl_gpu_ecc_volatile_total`
- `nixl_gpu_pstate`
- `nixl_gpu_throttle_reason`
- `nixl_gpu_memory_fragmentation_ratio`
- `nixl_gpu_retired_pages_pending`

HBM alone is not enough. BAR1 pressure, ECC activity, throttling, and reserved memory can explain “GPU looks busy but something is still wrong” situations.

## NUMA Locality

Watch:

- `nixl_numa_stat{field="numa_miss"}`
- `nixl_numa_stat{field="other_node"}`
- `nixl_host_sysctl{name="kernel.numa_balancing"}`
- `nixl_host_sysctl{name="vm.zone_reclaim_mode"}`

NUMA locality issues can produce noisy, node-specific performance regressions long before you get a hard failure.

## IRQ / Softirq And NIC Pressure

Watch:

- `nixl_softnet_stat_total`
- `nixl_softirq_total`
- `nixl_irq_total`
- `nixl_netflow_iface_rx_utilization_ratio`
- `nixl_netflow_iface_tx_utilization_ratio`
- `nixl_netflow_tcp_retrans_total`

This is where host networking pressure shows up when collective traffic or storage transfer paths overwhelm the CPU side of the NIC.

## PCIe / VFIO / IOMMU / AER Events

Watch:

- `nixl_kernel_log_pattern_total{pattern="pcie_aer"}`
- `nixl_kernel_log_pattern_total{pattern="vfio"}`
- `nixl_kernel_log_pattern_total{pattern="iommu_dma"}`
- `nixl_pcie_device_info`
- `nixl_iommu_group_total`

These signals help explain host-side instability that people often misattribute to the framework or GPU model alone.

## Disk / Filesystem Pressure

Watch:

- `nixl_diskstat_total{field="ms_io"}`
- `nixl_filesystem_bytes{field="avail"}`
- `nixl_file_nr`
- `nixl_inode_nr`
- `nixl_job_checkpoint_last_write_age_seconds`

Checkpoint freshness is an especially practical signal for training operators because storage trouble often looks like “the job stalled” before it looks like “the disk is unhealthy.”

## Process Locked Memory

Watch:

- `nixl_process_locked_bytes`
- `nixl_process_vm_lck_bytes`
- `nixl_process_pinned_candidates`

This is one of the most useful host-only views for explaining why GPU or RDMA workloads are consuming RAM that app dashboards do not obviously account for.

## How To Use The Triage Script

Run collection, then ask for the operator summary:

```bash
OUT_DIR=/var/lib/node_exporter/textfile_collector bash scripts/collect-all.sh
OUT_DIR=/var/lib/node_exporter/textfile_collector bash scripts/ai-host-triage.sh
```

The script groups available signals into host memory, PSI, RDMA, GPU, NUMA, network, kernel, disk, and locked-memory sections. Missing signal families are reported as `insufficient data` instead of hard-failing.

## Mapping Signals To Runbooks

- Memory pressure -> `docs/runbooks/host-memory-pressure.md`
- RDMA registration growth -> `docs/runbooks/rdma-registration-growth.md`
- GPU looks fine but host is degrading -> `docs/demos/host-oom-before-gpu-oom.md`
- Softirq and network spillover -> `docs/runbooks/softirq-network-pressure.md`
- PCIe / VFIO instability -> `docs/runbooks/pcie-vfio-instability.md`

The goal is not just to expose metrics. It is to move from “something is slow” to a plausible host-side diagnosis before you blame the GPU for the wrong thing.
