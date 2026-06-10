# Signals Cheat Sheet

## Hidden Host Memory Pressure

- `nixl_host_fw_pages_total`
- `nixl_host_fw_pages_sum`
- `nixl_host_meminfo_bytes{field="memavailable"}`
- `nixl_host_memory_psi_avg{scope="some",window="10s"}`
- `nixl_host_vmstat{field="pgscan_direct"}`

## RDMA / NIC Trouble

- `nixl_net_ethtool_stat{stat="link_down_events_phy"}`
- `nixl_net_ethtool_stat{stat="rx_discards_phy"}`
- `nixl_infiniband_counter{counter="port_rcv_errors"}`
- `nixl_infiniband_counter{counter="port_xmit_discards"}`

## CPU and Interrupt Spillover

- `nixl_cpu_psi_avg`
- `nixl_softirq_total{type="NET_RX"}`
- `nixl_softirq_total{type="NET_TX"}`
- `nixl_irq_total`

## NUMA Locality

- `nixl_numa_stat{field="local_node"}`
- `nixl_numa_stat{field="other_node"}`
- `nixl_numa_stat{field="numa_miss"}`
- `nixl_numa_meminfo_bytes{field="memfree"}`

## Kernel Event Scans

- `nixl_kernel_log_pattern_total{pattern="oom"}`
- `nixl_kernel_log_pattern_total{pattern="pcie_aer"}`
- `nixl_kernel_log_pattern_total{pattern="vfio"}`
- `nixl_kernel_log_pattern_total{pattern="iommu_dma"}`
- `nixl_kernel_log_pattern_total{pattern="rdma_mlx5"}`

## GPU Corroboration

- `nixl_gpu_utilization_percent`
- `nixl_gpu_memory_used_bytes`
- `nixl_gpu_bar1_used_bytes`
- `nixl_gpu_pcie_link_gen`
- `nixl_gpu_pcie_link_width`

## Filesystem and Disk

- `nixl_diskstat_total{field="ms_io"}`
- `nixl_diskstat_io_time_ms_total`
- `nixl_diskstat_io_in_progress`
- `nixl_diskstat_reads_completed_total`
- `nixl_diskstat_writes_completed_total`
- `nixl_block_queue_depth`
- `nixl_block_scheduler_info`
- `nixl_filesystem_bytes{field="avail"}`
- `nixl_file_nr{field="allocated"}`
- `nixl_inode_nr{field="allocated"}`

Recommended PromQL:

```promql
rate(nixl_diskstat_io_time_ms_total[5m])
nixl_diskstat_io_in_progress / nixl_block_queue_depth
rate(nixl_diskstat_reads_completed_total[5m]) + rate(nixl_diskstat_writes_completed_total[5m])
```

## Network Stack

- `nixl_netdev_total{field="rx_drop"}`
- `nixl_netdev_total{field="tx_drop"}`
- `nixl_softnet_stat_total{field="dropped"}`
- `nixl_softnet_stat_total{field="time_squeezed"}`
- `nixl_snmp_total`

## Process-Level Pinned Memory

- `nixl_process_locked_bytes`
- `nixl_process_vm_lck_bytes`
- `nixl_process_pinned_candidates`

## PCIe / VFIO / IOMMU

- `nixl_pcie_device_info`
- `nixl_vfio_group_devices`
- `nixl_iommu_group_total`
- `nixl_module_loaded{module="vfio_pci"}`

## Reliability and Hardware Fault Signals

### Memory Errors (EDAC / RAS)

- `nixl_edac_correctable_errors_total`
- `nixl_edac_uncorrectable_errors_total`
- `nixl_edac_ce_noinfo_count`
- `nixl_edac_cpu_ce_count`
- `nixl_rasdaemon_ce_total`
- `nixl_mcelog_events_total`

### CPU Thermal and Frequency

- `nixl_thermal_zone_temp_celsius`
- `nixl_cpu_thermal_throttle_total`
- `nixl_cpu_freq_current_khz`
- `nixl_cpu_freq_max_khz`
- `nixl_cpu_freq_governor_info`

### GPU XID and Throttle

- `nixl_kernel_log_pattern_total{pattern="gpu_xid"}`
- `nixl_kernel_log_pattern_total{pattern="gpu_reset"}`
- `nixl_gpu_throttle_reason`
- `nixl_gpu_pstate`
- `nixl_gpu_clock_sm_mhz`
- `nixl_gpu_power_enforced_limit_watts`

### NVLink Fabric

- `nixl_nvlink_state`
- `nixl_nvlink_replay_errors_total`
- `nixl_nvlink_recovery_errors_total`
- `nixl_nvlink_crc_flit_errors_total`
- `nixl_nvlink_error_total`

### Hugepages and THP

- `nixl_hugepages_total`
- `nixl_hugepages_free`
- `nixl_thp_fault_alloc_total`
- `nixl_thp_fault_fallback_total`
- `nixl_thp_enabled_info`

### Watchdog and Lockup

- `nixl_kernel_log_pattern_total{pattern="soft_lockup"}`
- `nixl_kernel_log_pattern_total{pattern="hung_task"}`
- `nixl_kernel_log_pattern_total{pattern="rcu_stall"}`
- `nixl_kernel_watchdog_enabled`
- `nixl_kernel_hung_task_timeout_seconds`

### Clock Sync

- `nixl_timesync_synchronized`
- `nixl_timesync_offset_seconds`
- `nixl_timesync_rms_offset_seconds`
- `nixl_timesync_freq_error_ppm`
- `nixl_timesync_stratum`

## Cross-Host Consistency Checks

- `count by (version) (nixl_host_kernel_version_info) > 1`
- `count by (version) (nixl_host_driver_version_info{driver="nvidia"}) > 1`
- `nixl_host_sysctl{name="net.core.rmem_max"} < 268435456`
- `nixl_host_sysctl{name="kernel.numa_balancing"} == 1`
- `nixl_host_sysctl{name="vm.zone_reclaim_mode"} != 0`

## Anomaly Baselines

- `nixl_baseline_current`
- `nixl_baseline_mean`
- `nixl_baseline_p99`
- `nixl_baseline_zscore`
- `nixl_baseline_window_size`

## Training Job Progress

- `nixl_job_training_processes_total`
- `nixl_job_checkpoint_last_write_age_seconds`
- `nixl_job_log_last_step`
- `nixl_job_stall_suspected`
- `nixl_job_stall_duration_seconds`

## Network Flow and Retransmits

- `nixl_netflow_tcp_established_total`
- `nixl_netflow_tcp_retrans_total`
- `nixl_netflow_iface_rx_utilization_ratio`
- `nixl_netflow_iface_tx_utilization_ratio`
- `nixl_netstat_ext`

## Collection Pipeline Health

- `nixl_collector_last_run_age_seconds`
- `nixl_collector_prom_file_metric_count`
- `nixl_collector_exporters_stale`
- `nixl_collector_node_exporter_running`
- `nixl_collector_unique_series_estimate`

## GPU Memory Pressure and Reliability

- `nixl_gpu_process_memory_bytes`
- `nixl_gpu_process_count`
- `nixl_gpu_memory_reserved_bytes`
- `nixl_gpu_memory_fragmentation_ratio`
- `nixl_gpu_retired_pages_pending`
- `nixl_gpu_remapped_rows_pending`

## Trace and Profiling Readiness

- `nixl_trace_events_enabled_total`
- `nixl_trace_function_hit_total`
- `nixl_trace_mm_page_alloc_total`
- `nixl_perf_event_paranoid`
- `nixl_perf_event_max_sample_rate`

## Long-Term Trending and SLO Views

- `nixl:gpu:utilization_avg_1h`
- `nixl:gpu:utilization_avg_24h`
- `nixl:memory:psi_some_avg_1h`
- `nixl:memory:psi_p95_24h`
- `nixl:host:health_score`
