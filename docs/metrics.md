# Metrics

This document is the metric contract for `ai-host-observability`.

## Stability Policy

- Metric names are considered stable after `v0.1`.
- Labels may be added, but existing labels should not be removed without a changelog note.
- Missing hardware should emit exporter scrape success and zero or absent hardware-specific metrics rather than hard-fail the exporter.

## Wrapper Metrics

### `ai_host_exporter_last_run_success`

- Type: `gauge`
- Labels: `exporter`
- Unit: boolean `0/1`
- Source: `scripts/collect-all.sh`
- When absent: only if the wrapper itself never ran
- Interpretation: whether the wrapper successfully ran the named exporter
- Example alert: `ai_host_exporter_last_run_success == 0`

### `ai_host_exporter_last_run_error`

- Type: `gauge`
- Labels: `exporter`, `error`
- Unit: boolean `0/1`
- Source: `scripts/collect-all.sh`
- When absent: exporter succeeded
- Interpretation: wrapper-recorded exporter failure marker
- Example alert: `ai_host_exporter_last_run_error == 1`

## Host Memory Exporter

### `nixl_host_scrape_success`

- Type: `gauge`
- Labels: none
- Unit: boolean `0/1`
- Source: `scripts/nixl-host-mem-exporter.sh`
- When absent: exporter failed before emitting output
- Interpretation: exporter completed

### `nixl_host_fw_pages_total`

- Type: `gauge`
- Labels: `device`
- Unit: firmware pages
- Source: `${DEBUGFS_ROOT}/mlx5/*/pages/fw_pages_total`
- When absent: no visible `mlx5` debugfs counters
- Interpretation: host-side RDMA registration footprint per device
- Example alert: `rate(nixl_host_fw_pages_total[15m]) > 0`

### `nixl_host_fw_pages_devices`

- Type: `gauge`
- Labels: none
- Unit: count
- Source: derived from `fw_pages_total` files
- When absent: exporter failed
- Interpretation: number of devices contributing firmware-page counters

### `nixl_host_fw_pages_sum`

- Type: `gauge`
- Labels: none
- Unit: firmware pages
- Source: sum of `fw_pages_total`
- When absent: exporter failed
- Interpretation: total host-side firmware page footprint

### `nixl_host_meminfo_bytes`

- Type: `gauge`
- Labels: `field`
- Unit: bytes
- Source: `${PROC_ROOT}/meminfo`
- When absent: meminfo missing
- Interpretation: selected host free-memory components
- Example alert: `nixl_host_meminfo_bytes{field="memavailable"} < 8e9`

### `nixl_host_memory_psi_avg`

- Type: `gauge`
- Labels: `scope`, `window`
- Unit: percent
- Source: `${PROC_ROOT}/pressure/memory`
- When absent: PSI unavailable
- Interpretation: rolling memory stall fraction
- Example alert: `nixl_host_memory_psi_avg{scope="some",window="60s"} > 5`

### `nixl_host_memory_psi_total`

- Type: `counter`
- Labels: `scope`
- Unit: microseconds
- Source: `${PROC_ROOT}/pressure/memory`
- When absent: PSI unavailable
- Interpretation: cumulative memory stall time

### `nixl_host_vmstat`

- Type: `counter`
- Labels: `field`
- Unit: events
- Source: `${PROC_ROOT}/vmstat`
- When absent: vmstat unavailable
- Interpretation: reclaim and swap pressure
- Example alert: `rate(nixl_host_vmstat{field="pgscan_direct"}[5m]) > 100`

### `nixl_host_cgroup_memory_current_bytes`

- Type: `gauge`
- Labels: `path`
- Unit: bytes
- Source: `${CGROUP_PATH}/memory.current`
- When absent: `CGROUP_PATH` unset or file missing
- Interpretation: cgroup memory footprint

### `nixl_host_cgroup_memory_events`

- Type: `counter`
- Labels: `path`, `event`
- Unit: events
- Source: `${CGROUP_PATH}/memory.events`
- When absent: `CGROUP_PATH` unset or file missing
- Interpretation: cgroup low/high/max/oom activity
- Example alert: `increase(nixl_host_cgroup_memory_events{event="oom_kill"}[10m]) > 0`

### `nixl_host_cgroup_memory_pressure_avg`

- Type: `gauge`
- Labels: `path`, `scope`, `window`
- Unit: percent
- Source: `${CGROUP_PATH}/memory.pressure`
- When absent: `CGROUP_PATH` unset or file missing
- Interpretation: cgroup-specific memory pressure

### `nixl_host_cgroup_memory_pressure_total`

- Type: `counter`
- Labels: `path`, `scope`
- Unit: microseconds
- Source: `${CGROUP_PATH}/memory.pressure`
- When absent: `CGROUP_PATH` unset or file missing
- Interpretation: cumulative cgroup memory stall time

## RDMA and NIC Exporter

### `nixl_rdma_scrape_success`

- Type: `gauge`
- Labels: none
- Unit: boolean `0/1`
- Source: `scripts/rdma-link-exporter.sh`
- When absent: exporter failed
- Interpretation: exporter completed

### `nixl_net_up`

- Type: `gauge`
- Labels: `iface`
- Unit: boolean `0/1`
- Source: `${SYS_ROOT}/class/net/*/operstate`
- When absent: interface missing
- Interpretation: link state by interface

### `nixl_net_speed_mbps`

- Type: `gauge`
- Labels: `iface`
- Unit: megabits per second
- Source: `${SYS_ROOT}/class/net/*/speed`
- When absent: speed unavailable
- Interpretation: current reported interface speed

### `nixl_net_carrier`

- Type: `gauge`
- Labels: `iface`
- Unit: boolean `0/1`
- Source: `${SYS_ROOT}/class/net/*/carrier`
- When absent: carrier unavailable
- Interpretation: physical carrier status

### `nixl_net_ethtool_stat`

- Type: `counter`
- Labels: `iface`, `stat`
- Unit: events
- Source: `${ETHTOOL} -S`
- When absent: `ethtool` unavailable or stat not supported
- Interpretation: NIC-side error and discard counters
- Example alert: `increase(nixl_net_ethtool_stat{stat="link_down_events_phy"}[10m]) > 0`

### `nixl_infiniband_port_state`

- Type: `gauge`
- Labels: `device`, `port`
- Unit: numeric state code
- Source: `${SYS_ROOT}/class/infiniband/*/ports/*/state`
- When absent: no InfiniBand device
- Interpretation: IB port state

### `nixl_infiniband_rate_gbps`

- Type: `gauge`
- Labels: `device`, `port`
- Unit: Gbps
- Source: `${SYS_ROOT}/class/infiniband/*/ports/*/rate`
- When absent: no InfiniBand device or rate unavailable
- Interpretation: current IB link rate

### `nixl_infiniband_counter`

- Type: `counter`
- Labels: `device`, `port`, `counter`
- Unit: events or hardware counter units
- Source: `${SYS_ROOT}/class/infiniband/*/ports/*/counters/*`
- When absent: no InfiniBand device or counter missing
- Interpretation: RDMA transport health
- Example alert: `increase(nixl_infiniband_counter{counter="port_rcv_errors"}[10m]) > 0`

## CPU and IRQ Exporter

### `nixl_cpu_scrape_success`

- Type: `gauge`
- Labels: none
- Unit: boolean `0/1`
- Source: `scripts/cpu-irq-exporter.sh`

### `nixl_cpu_psi_avg`

- Type: `gauge`
- Labels: `scope`, `window`
- Unit: percent
- Source: `${PROC_ROOT}/pressure/cpu`
- When absent: PSI unavailable
- Interpretation: CPU pressure

### `nixl_cpu_psi_total`

- Type: `counter`
- Labels: `scope`
- Unit: microseconds
- Source: `${PROC_ROOT}/pressure/cpu`
- When absent: PSI unavailable

### `nixl_softirq_total`

- Type: `counter`
- Labels: `type`
- Unit: events
- Source: `${PROC_ROOT}/softirqs`
- When absent: softirqs unavailable
- Interpretation: host softirq work by class

### `nixl_irq_total`

- Type: `counter`
- Labels: `irq`, `source`
- Unit: events
- Source: `${PROC_ROOT}/interrupts`
- When absent: interrupts unavailable or no selected devices
- Interpretation: selected IRQ load for PCIe/networking devices

### `nixl_loadavg`

- Type: `gauge`
- Labels: `window`
- Unit: runnable tasks
- Source: `${PROC_ROOT}/loadavg`
- When absent: loadavg unavailable
- Interpretation: classic host load average

## NUMA Exporter

### `nixl_numa_scrape_success`

- Type: `gauge`
- Labels: none
- Unit: boolean `0/1`
- Source: `scripts/numa-exporter.sh`

### `nixl_numa_meminfo_bytes`

- Type: `gauge`
- Labels: `node`, `field`
- Unit: bytes
- Source: `${SYS_ROOT}/devices/system/node/node*/meminfo`
- When absent: no NUMA topology or field unavailable
- Interpretation: per-node free/used/file-page memory

### `nixl_numa_hugepages`

- Type: `gauge`
- Labels: `node`, `field`
- Unit: pages
- Source: `${SYS_ROOT}/devices/system/node/node*/meminfo`
- When absent: hugepage fields unavailable
- Interpretation: per-node hugepage inventory

### `nixl_numa_stat`

- Type: `counter`
- Labels: `node`, `field`
- Unit: events
- Source: `${SYS_ROOT}/devices/system/node/node*/numastat`
- When absent: NUMA stats unavailable
- Interpretation: local-vs-remote NUMA effectiveness

## Kernel Log Exporter

### `nixl_kernel_log_scan_success`

- Type: `gauge`
- Labels: none
- Unit: boolean `0/1`
- Source: `scripts/kernel-log-scan-exporter.sh`

### `nixl_kernel_log_pattern_total`

- Type: `counter`
- Labels: `pattern`
- Unit: matching log lines
- Source: `${JOURNALCTL} -k -b --no-pager` or `dmesg`
- When absent: kernel logs unavailable
- Interpretation: boot-window pattern counts for OOM, AER, VFIO, IOMMU, RDMA, GPU driver events

## GPU Exporter

### `nixl_gpu_scrape_success`

- Type: `gauge`
- Labels: none
- Unit: boolean `0/1`
- Source: `scripts/gpu-exporter.sh`

### `nixl_gpu_info`

- Type: `gauge`
- Labels: `index`, `uuid`, `name`, `pci_bus`
- Unit: constant `1`
- Source: `${NVIDIA_SMI}`
- When absent: `nvidia-smi` missing or no visible GPU
- Interpretation: inventory anchor for joins in dashboards

### `nixl_gpu_utilization_percent`

- Type: `gauge`
- Labels: `index`, `uuid`
- Unit: percent
- Source: `${NVIDIA_SMI}`
- When absent: GPU metrics unavailable
- Interpretation: SM utilization

### `nixl_gpu_memory_used_bytes`

- Type: `gauge`
- Labels: `index`, `uuid`
- Unit: bytes
- Source: `${NVIDIA_SMI}`
- When absent: GPU metrics unavailable
- Interpretation: device memory in use

### `nixl_gpu_memory_total_bytes`

- Type: `gauge`
- Labels: `index`, `uuid`
- Unit: bytes
- Source: `${NVIDIA_SMI}`
- When absent: GPU metrics unavailable

### `nixl_gpu_temperature_celsius`

- Type: `gauge`
- Labels: `index`, `uuid`
- Unit: Celsius
- Source: `${NVIDIA_SMI}`
- When absent: GPU metrics unavailable

### `nixl_gpu_power_draw_watts`

- Type: `gauge`
- Labels: `index`, `uuid`
- Unit: watts
- Source: `${NVIDIA_SMI}`
- When absent: GPU metrics unavailable

### `nixl_gpu_pcie_link_gen`

- Type: `gauge`
- Labels: `index`, `uuid`
- Unit: PCIe generation
- Source: `${NVIDIA_SMI}`
- When absent: GPU metrics unavailable
- Interpretation: current negotiated PCIe generation

### `nixl_gpu_pcie_link_width`

- Type: `gauge`
- Labels: `index`, `uuid`
- Unit: lanes
- Source: `${NVIDIA_SMI}`
- When absent: GPU metrics unavailable

### `nixl_gpu_ecc_volatile_total`

- Type: `counter`
- Labels: `index`, `uuid`
- Unit: ECC errors
- Source: `${NVIDIA_SMI}`
- When absent: ECC unavailable

### `nixl_gpu_bar1_used_bytes`

- Type: `gauge`
- Labels: `index`, `uuid`
- Unit: bytes
- Source: `${NVIDIA_SMI}`
- When absent: BAR1 metrics unavailable
- Interpretation: BAR1 aperture pressure

### `nixl_gpu_bar1_total_bytes`

- Type: `gauge`
- Labels: `index`, `uuid`
- Unit: bytes
- Source: `${NVIDIA_SMI}`
- When absent: BAR1 metrics unavailable

## Disk and Filesystem Exporter

### `nixl_disk_scrape_success`

- Type: `gauge`
- Labels: none
- Unit: boolean `0/1`
- Source: `scripts/disk-filesystem-exporter.sh`

### `nixl_diskstat_total`

- Type: `counter`
- Labels: `device`, `field`
- Unit: kernel diskstats units
- Source: `${PROC_ROOT}/diskstats`
- When absent: diskstats unavailable
- Interpretation: selected disk I/O counters

### `nixl_filesystem_bytes`

- Type: `gauge`
- Labels: `filesystem`, `mount`, `fstype`, `field`
- Unit: bytes
- Source: `${DF} -B1 -P -T`
- When absent: `df` unavailable
- Interpretation: filesystem capacity and headroom

### `nixl_file_nr`

- Type: `gauge`
- Labels: `field`
- Unit: handles
- Source: `${PROC_ROOT}/sys/fs/file-nr`
- When absent: proc sysctl unavailable
- Interpretation: system-wide file handle pressure

### `nixl_inode_nr`

- Type: `gauge`
- Labels: `field`
- Unit: inodes
- Source: `${PROC_ROOT}/sys/fs/inode-nr`
- When absent: proc sysctl unavailable
- Interpretation: inode pressure

## Network Stack Exporter

### `nixl_network_stack_scrape_success`

- Type: `gauge`
- Labels: none
- Unit: boolean `0/1`
- Source: `scripts/network-stack-exporter.sh`

### `nixl_netdev_total`

- Type: `counter`
- Labels: `iface`, `field`
- Unit: bytes, packets, or errors depending on field
- Source: `${PROC_ROOT}/net/dev`
- When absent: `/proc/net/dev` unavailable
- Interpretation: generic host network interface activity

### `nixl_softnet_stat_total`

- Type: `counter`
- Labels: `cpu`, `field`
- Unit: events
- Source: `${PROC_ROOT}/net/softnet_stat`
- When absent: softnet stats unavailable
- Interpretation: per-CPU network backlog and drop pressure

### `nixl_snmp_total`

- Type: `counter`
- Labels: `protocol`, `field`
- Unit: protocol counters
- Source: `${PROC_ROOT}/net/snmp`
- When absent: SNMP stats unavailable
- Interpretation: transport- and IP-level network errors

## Process Memory Exporter

### `nixl_process_memory_scrape_success`

- Type: `gauge`
- Labels: none
- Unit: boolean `0/1`
- Source: `scripts/process-memory-exporter.sh`

### `nixl_process_locked_bytes`

- Type: `gauge`
- Labels: `pid`, `comm`
- Unit: bytes
- Source: `${PROC_ROOT}/<pid>/smaps_rollup`
- When absent: no process with locked pages or permission denied
- Interpretation: top locked-memory processes

### `nixl_process_vm_lck_bytes`

- Type: `gauge`
- Labels: `pid`, `comm`
- Unit: bytes
- Source: `${PROC_ROOT}/<pid>/status`
- When absent: no process with VmLck
- Interpretation: user-visible locked-memory footprint

### `nixl_process_pinned_candidates`

- Type: `gauge`
- Labels: none
- Unit: count
- Source: derived from process scan
- When absent: exporter failed
- Interpretation: count of processes with non-zero locked memory

## PCIe, VFIO, and IOMMU Exporter

### `nixl_pcie_scrape_success`

- Type: `gauge`
- Labels: none
- Unit: boolean `0/1`
- Source: `scripts/pcie-vfio-exporter.sh`

### `nixl_pcie_device_info`

- Type: `gauge`
- Labels: `bdf`, `driver`, `vendor`, `device`, `numa_node`
- Unit: constant `1`
- Source: `${SYS_ROOT}/bus/pci/devices/*`
- When absent: no matching device or regex excludes drivers
- Interpretation: PCIe device inventory of interest

### `nixl_vfio_group_devices`

- Type: `gauge`
- Labels: `group`
- Unit: count
- Source: `${SYS_ROOT}/kernel/iommu_groups/*/devices`
- When absent: no IOMMU groups
- Interpretation: devices per IOMMU group

### `nixl_iommu_group_total`

- Type: `gauge`
- Labels: none
- Unit: count
- Source: `${SYS_ROOT}/kernel/iommu_groups`
- When absent: IOMMU groups unavailable
- Interpretation: overall IOMMU group count

### `nixl_module_loaded`

- Type: `gauge`
- Labels: `module`
- Unit: boolean `0/1`
- Source: `${PROC_ROOT}/modules`
- When absent: proc modules unavailable
- Interpretation: whether selected driver modules are loaded

