# Metrics

This document is the metric contract for `ai-host-observability`.

## Stability Policy

- Metric names are considered stable after `v0.1`.
- Labels may be added, but existing labels should not be removed without a changelog note.
- Missing hardware should emit exporter scrape success and zero or absent hardware-specific metrics rather than hard-fail the exporter.

## Cardinality Guidance

The following metrics can produce high cardinality depending on your environment. Consider relabeling or dropping in Prometheus `metric_relabel_configs` if cardinality becomes an issue.

| Metric | Cardinality Source | Typical Cardinality | Recommendation |
|--------|-------------------|---------------------|----------------|
| `nixl_process_locked_bytes` | `pid`, `comm` | O(processes) ~ 100-1000 | Drop if not needed; keep top-N by value via `topk` |
| `nixl_process_vm_lck_bytes` | `pid`, `comm` | O(processes) ~ 100-1000 | Same as above |
| `nixl_infiniband_counter` | `device`, `port`, `counter` | O(devices × ports × counters) ~ 10-50 | Usually fine |
| `nixl_net_ethtool_stat` | `iface`, `stat` | O(interfaces × stats) ~ 20-200 | Usually fine |
| `nixl_numa_stat` | `node`, `field` | O(nodes × fields) ~ 10-50 | Usually fine |
| `nixl_pcie_device_info` | `bdf`, `driver`, `vendor`, `device`, `numa_node` | O(pci_devices) ~ 10-100 | Usually fine |
| `nixl_gpu_*` | `vendor`, `index`, `uuid` | O(gpus) ~ 1-8 | Usually fine |
| `nixl_softnet_stat_total` | `cpu`, `field` | O(cpus) ~ 1-256 | Usually fine |
| `nixl_irq_total` | `irq`, `source` | O(irqs) ~ 50-500 | Drop if not needed |

For `nixl_process_*` metrics, consider adding a `metric_relabel_configs` rule to keep only processes with locked memory > threshold:

```yaml
metric_relabel_configs:
  - source_labels: [__name__]
    regex: 'nixl_process_locked_bytes'
    action: keep
  - source_labels: [__name__, pid]
    regex: 'nixl_process_locked_bytes;(.+)'
    action: labeldrop
    # Or use metric_relabel to drop low-value series
```

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

### `ai_host_exporter_duration_seconds`

- Type: `gauge`
- Labels: `exporter`
- Unit: seconds
- Source: `scripts/collect-all.sh`
- When absent: wrapper did not run the exporter
- Interpretation: wall-clock runtime for each exporter invocation, including failure paths
- Example alert: `ai_host_exporter_duration_seconds > 30`

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
- Interpretation: selected host memory components including capacity and free-memory signals
- Example alert: `nixl_host_meminfo_bytes{field="memavailable"} < 8e9`

### `nixl_hugepages_total`

- Type: `gauge`
- Labels: `size`
- Unit: pages
- Source: `${PROC_ROOT}/meminfo`
- When absent: hugepage fields unavailable
- Interpretation: total configured hugepage pool by page size
- Example alert: `nixl_hugepages_total{size="2048kB"} > 0`

### `nixl_hugepages_free`

- Type: `gauge`
- Labels: `size`
- Unit: pages
- Source: `${PROC_ROOT}/meminfo`
- When absent: hugepage fields unavailable
- Interpretation: free hugepages remaining by page size
- Example alert: `nixl_hugepages_free{size="2048kB"} == 0`

### `nixl_hugepages_rsvd`

- Type: `gauge`
- Labels: `size`
- Unit: pages
- Source: `${PROC_ROOT}/meminfo`
- When absent: hugepage fields unavailable
- Interpretation: reserved hugepages not yet faulted in

### `nixl_hugepages_surp`

- Type: `gauge`
- Labels: `size`
- Unit: pages
- Source: `${PROC_ROOT}/meminfo`
- When absent: hugepage fields unavailable
- Interpretation: surplus hugepages above the persistent pool

### `nixl_host_uptime_seconds`

- Type: `gauge`
- Labels: none
- Unit: seconds
- Source: `${PROC_ROOT}/uptime`
- When absent: uptime unavailable
- Interpretation: host uptime in seconds
- Use case: detect recent reboots, correlate with incident start time

### `nixl_host_boot_time_seconds`

- Type: `gauge`
- Labels: none
- Unit: unix timestamp (seconds)
- Source: derived from `${PROC_ROOT}/uptime`
- When absent: uptime unavailable
- Interpretation: host boot time as unix epoch
- Use case: join with other boot-time metrics, detect unexpected reboots

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
- Interpretation: reclaim, major-fault, and swap pressure
- Example alert: `rate(nixl_host_vmstat{field="pgscan_direct"}[5m]) > 100`

### `nixl_thp_fault_alloc_total`

- Type: `counter`
- Labels: none
- Unit: events
- Source: `${PROC_ROOT}/vmstat`
- When absent: THP vmstat unavailable
- Interpretation: successful THP fault allocations
- Example alert: `rate(nixl_thp_fault_alloc_total[5m])`

### `nixl_thp_fault_fallback_total`

- Type: `counter`
- Labels: none
- Unit: events
- Source: `${PROC_ROOT}/vmstat`
- When absent: THP vmstat unavailable
- Interpretation: THP fault fallbacks to small pages
- Example alert: `rate(nixl_thp_fault_fallback_total[5m])`

### `nixl_thp_collapse_alloc_total`

- Type: `counter`
- Labels: none
- Unit: events
- Source: `${PROC_ROOT}/vmstat`
- When absent: THP vmstat unavailable
- Interpretation: THP collapse allocation successes

### `nixl_thp_split_page_total`

- Type: `counter`
- Labels: none
- Unit: events
- Source: `${PROC_ROOT}/vmstat`
- When absent: THP vmstat unavailable
- Interpretation: THP splits back to base pages

### `nixl_thp_deferred_split_page_total`

- Type: `counter`
- Labels: none
- Unit: events
- Source: `${PROC_ROOT}/vmstat`
- When absent: THP vmstat unavailable
- Interpretation: deferred THP split activity

### `nixl_thp_enabled_info`

- Type: `gauge`
- Labels: `mode`
- Unit: constant `1`
- Source: `${SYS_ROOT}/kernel/mm/transparent_hugepage/enabled`
- When absent: THP mode file unavailable
- Interpretation: active THP policy mode
- Example alert: `nixl_thp_enabled_info{mode="never"} == 1`

### `nixl_host_cgroup_memory_current_bytes`

- Type: `gauge`
- Labels: `path`
- Unit: bytes
- Source: `${CGROUP_PATH}/memory.current` (cgroup v2) or `${CGROUP_PATH}/memory/memory.usage_in_bytes` (cgroup v1)
- When absent: `CGROUP_PATH` unset or file missing
- Interpretation: cgroup memory footprint (supports both cgroup v1 and v2)

### `nixl_host_cgroup_memory_events`

- Type: `counter`
- Labels: `path`, `event`
- Unit: events
- Source: `${CGROUP_PATH}/memory.events` (cgroup v2) or `${CGROUP_PATH}/memory/memory.events` (cgroup v1)
- When absent: `CGROUP_PATH` unset or file missing
- Interpretation: cgroup low/high/max/oom activity
- Example alert: `increase(nixl_host_cgroup_memory_events{event="oom_kill"}[10m]) > 0`

### `nixl_host_cgroup_memory_pressure_avg`

- Type: `gauge`
- Labels: `path`, `scope`, `window`
- Unit: percent
- Source: `${CGROUP_PATH}/memory.pressure` (cgroup v2) or `${CGROUP_PATH}/memory/memory.pressure` (cgroup v1)
- When absent: `CGROUP_PATH` unset or file missing
- Interpretation: cgroup-specific memory pressure

### `nixl_host_cgroup_memory_pressure_total`

- Type: `counter`
- Labels: `path`, `scope`
- Unit: microseconds
- Source: `${CGROUP_PATH}/memory.pressure` (cgroup v2) or `${CGROUP_PATH}/memory/memory.pressure` (cgroup v1)
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
- Interpretation: boot-window pattern counts for OOM, AER, VFIO, IOMMU, RDMA, GPU XID, NVLink, watchdog, lockup, and panic events

## Reliability: MCE / EDAC / RAS Exporter

### `nixl_mce_scrape_success`

- Type: `gauge`
- Labels: `source`
- Unit: boolean `0/1`
- Source: `scripts/mce-ras-exporter.sh`
- When absent: exporter failed before emitting output
- Interpretation: whether the named reliability source yielded counters

### `nixl_edac_correctable_errors_total`

- Type: `counter`
- Labels: `controller`, `channel`
- Unit: errors
- Source: `${SYS_ROOT}/devices/system/edac/mc/*`
- When absent: EDAC memory-controller counters unavailable
- Interpretation: correctable memory errors by controller and DIMM/channel
- Example alert: `increase(nixl_edac_correctable_errors_total[1h]) > 10`

### `nixl_edac_uncorrectable_errors_total`

- Type: `counter`
- Labels: `controller`, `channel`
- Unit: errors
- Source: `${SYS_ROOT}/devices/system/edac/mc/*`
- When absent: EDAC memory-controller counters unavailable
- Interpretation: uncorrectable memory errors by controller and DIMM/channel
- Example alert: `increase(nixl_edac_uncorrectable_errors_total[10m]) > 0`

### `nixl_edac_ce_noinfo_count`

- Type: `counter`
- Labels: `controller`
- Unit: errors
- Source: `${SYS_ROOT}/devices/system/edac/mc/*/ce_noinfo_count`
- When absent: counter unavailable
- Interpretation: correctable errors without channel attribution

### `nixl_edac_ue_noinfo_count`

- Type: `counter`
- Labels: `controller`
- Unit: errors
- Source: `${SYS_ROOT}/devices/system/edac/mc/*/ue_noinfo_count`
- When absent: counter unavailable
- Interpretation: uncorrectable errors without channel attribution

### `nixl_edac_cpu_ce_count`

- Type: `counter`
- Labels: `cpu`, `bank`
- Unit: errors
- Source: `${SYS_ROOT}/devices/system/edac/cpu/*`
- When absent: CPU EDAC counters unavailable
- Interpretation: per-bank CPU correctable error counts

### `nixl_edac_cpu_ue_count`

- Type: `counter`
- Labels: `cpu`, `bank`
- Unit: errors
- Source: `${SYS_ROOT}/devices/system/edac/cpu/*`
- When absent: CPU EDAC counters unavailable
- Interpretation: per-bank CPU uncorrectable error counts

### `nixl_rasdaemon_ce_total`

- Type: `counter`
- Labels: `dimm`
- Unit: errors
- Source: `${RAS_MC_CTL} --errors`
- When absent: `rasdaemon` or `ras-mc-ctl` unavailable
- Interpretation: rasdaemon-reported correctable DIMM errors

### `nixl_rasdaemon_ue_total`

- Type: `counter`
- Labels: `dimm`
- Unit: errors
- Source: `${RAS_MC_CTL} --errors`
- When absent: `rasdaemon` or `ras-mc-ctl` unavailable
- Interpretation: rasdaemon-reported uncorrectable DIMM errors

### `nixl_mcelog_events_total`

- Type: `counter`
- Labels: `bank`, `mcg_status`
- Unit: events
- Source: `${MCELOG_PATH}`
- When absent: mcelog device unavailable
- Interpretation: machine-check log events by bank and global status class

## Reliability: CPU Thermal Exporter

### `nixl_thermal_scrape_success`

- Type: `gauge`
- Labels: none
- Unit: boolean `0/1`
- Source: `scripts/cpu-thermal-exporter.sh`
- When absent: exporter failed before emitting output
- Interpretation: exporter completed with at least one thermal or frequency source

### `nixl_thermal_zone_temp_celsius`

- Type: `gauge`
- Labels: `zone`, `type`
- Unit: Celsius
- Source: `${SYS_ROOT}/class/thermal/thermal_zone*`
- When absent: thermal zones unavailable
- Interpretation: current thermal-zone temperature

### `nixl_thermal_zone_trip_point_celsius`

- Type: `gauge`
- Labels: `zone`, `trip`, `type`
- Unit: Celsius
- Source: `${SYS_ROOT}/class/thermal/thermal_zone*/trip_point_*`
- When absent: trip points unavailable
- Interpretation: thermal trip thresholds

### `nixl_cpu_thermal_throttle_total`

- Type: `counter`
- Labels: `cpu`, `scope`
- Unit: throttle events
- Source: `${SYS_ROOT}/devices/system/cpu/cpu*/thermal_throttle`
- When absent: thermal throttle counters unavailable
- Interpretation: core or package throttling events
- Example alert: `rate(nixl_cpu_thermal_throttle_total[5m]) > 0`

### `nixl_cpu_freq_current_khz`

- Type: `gauge`
- Labels: `package`, `stat`
- Unit: kHz
- Source: `${SYS_ROOT}/devices/system/cpu/cpu*/cpufreq/scaling_cur_freq`
- When absent: cpufreq unavailable
- Interpretation: current package frequency distribution
- Example alert: `nixl_cpu_freq_current_khz{stat="mean"} / nixl_cpu_freq_max_khz < 0.85`

### `nixl_cpu_freq_max_khz`

- Type: `gauge`
- Labels: `package`
- Unit: kHz
- Source: `${SYS_ROOT}/devices/system/cpu/cpu*/cpufreq/cpuinfo_max_freq`
- When absent: cpufreq unavailable
- Interpretation: rated package maximum frequency

### `nixl_cpu_freq_min_khz`

- Type: `gauge`
- Labels: `package`
- Unit: kHz
- Source: `${SYS_ROOT}/devices/system/cpu/cpu*/cpufreq/cpuinfo_min_freq`
- When absent: cpufreq unavailable
- Interpretation: rated package minimum frequency

### `nixl_cpu_freq_governor_info`

- Type: `gauge`
- Labels: `package`, `governor`
- Unit: constant `1`
- Source: `${SYS_ROOT}/devices/system/cpu/cpu*/cpufreq/scaling_governor`
- When absent: cpufreq unavailable
- Interpretation: active CPU frequency governor by package

## Reliability: NVLink Exporter

### `nixl_nvlink_scrape_success`

- Type: `gauge`
- Labels: none
- Unit: boolean `0/1`
- Source: `scripts/nvlink-exporter.sh`
- When absent: exporter failed before emitting output
- Interpretation: whether NVLink status and counters were available

### `nixl_nvlink_state`

- Type: `gauge`
- Labels: `index`, `link`, `state`
- Unit: boolean `0/1`
- Source: `${NVIDIA_SMI} nvlink --status`
- When absent: no NVLink-capable NVIDIA GPU or command unavailable
- Interpretation: active/inactive NVLink state
- Example alert: `nixl_nvlink_state == 0`

### `nixl_nvlink_replay_errors_total`

- Type: `counter`
- Labels: `index`, `link`
- Unit: errors
- Source: `${NVIDIA_SMI} nvlink --errorcounters`
- When absent: NVLink error counters unavailable
- Interpretation: replay errors per NVLink

### `nixl_nvlink_recovery_errors_total`

- Type: `counter`
- Labels: `index`, `link`
- Unit: errors
- Source: `${NVIDIA_SMI} nvlink --errorcounters`
- When absent: NVLink error counters unavailable
- Interpretation: recovery errors per NVLink

### `nixl_nvlink_crc_flit_errors_total`

- Type: `counter`
- Labels: `index`, `link`
- Unit: errors
- Source: `${NVIDIA_SMI} nvlink --errorcounters`
- When absent: NVLink error counters unavailable
- Interpretation: flit CRC errors per NVLink

### `nixl_nvlink_crc_data_errors_total`

- Type: `counter`
- Labels: `index`, `link`
- Unit: errors
- Source: `${NVIDIA_SMI} nvlink --errorcounters`
- When absent: NVLink error counters unavailable
- Interpretation: data CRC errors per NVLink

### `nixl_nvlink_error_total`

- Type: `counter`
- Labels: `index`, `type`
- Unit: errors
- Source: aggregated from NVLink link counters
- When absent: NVLink error counters unavailable
- Interpretation: per-GPU aggregate NVLink error totals by class
- Example alert: `rate(nixl_nvlink_error_total[5m]) > 0`

## Reliability: Watchdog Exporter

### `nixl_watchdog_scrape_success`

- Type: `gauge`
- Labels: none
- Unit: boolean `0/1`
- Source: `scripts/watchdog-exporter.sh`
- When absent: exporter failed before emitting output
- Interpretation: exporter completed with at least one watchdog-related sysctl

### `nixl_kernel_watchdog_enabled`

- Type: `gauge`
- Labels: none
- Unit: boolean `0/1`
- Source: `${PROC_ROOT}/sys/kernel/watchdog`
- When absent: sysctl unavailable
- Interpretation: whether the kernel watchdog is enabled

### `nixl_kernel_watchdog_thresh_seconds`

- Type: `gauge`
- Labels: none
- Unit: seconds
- Source: `${PROC_ROOT}/sys/kernel/watchdog_thresh`
- When absent: sysctl unavailable
- Interpretation: soft/hard lockup threshold

### `nixl_kernel_hung_task_timeout_seconds`

- Type: `gauge`
- Labels: none
- Unit: seconds
- Source: `${PROC_ROOT}/sys/kernel/hung_task_timeout_secs`
- When absent: sysctl unavailable
- Interpretation: blocked-task warning threshold

### `nixl_kernel_nmi_watchdog_enabled`

- Type: `gauge`
- Labels: none
- Unit: boolean `0/1`
- Source: `${PROC_ROOT}/sys/kernel/nmi_watchdog`
- When absent: sysctl unavailable
- Interpretation: whether the NMI watchdog is enabled

### `nixl_kernel_softlockup_panic`

- Type: `gauge`
- Labels: none
- Unit: boolean `0/1`
- Source: `${PROC_ROOT}/sys/kernel/softlockup_panic`
- When absent: sysctl unavailable
- Interpretation: whether soft lockups trigger panic

### `nixl_kernel_panic_timeout_seconds`

- Type: `gauge`
- Labels: none
- Unit: seconds
- Source: `${PROC_ROOT}/sys/kernel/panic`
- When absent: sysctl unavailable
- Interpretation: reboot delay after panic

## Reliability: Timesync Exporter

### `nixl_timesync_scrape_success`

- Type: `gauge`
- Labels: none
- Unit: boolean `0/1`
- Source: `scripts/timesync-exporter.sh`
- When absent: exporter failed before emitting output
- Interpretation: timesync state was collected from chrony or timedatectl

### `nixl_timesync_synchronized`

- Type: `gauge`
- Labels: none
- Unit: boolean `0/1`
- Source: `${TIMEDATECTL}` or `${CHRONYC}`
- When absent: neither timesync source is available
- Interpretation: whether the system clock is synchronised
- Example alert: `nixl_timesync_synchronized == 0`

### `nixl_timesync_offset_seconds`

- Type: `gauge`
- Labels: none
- Unit: seconds
- Source: `${CHRONYC} tracking`
- When absent: chronyc unavailable
- Interpretation: signed current clock offset
- Example alert: `abs(nixl_timesync_offset_seconds) > 0.01`

### `nixl_timesync_rms_offset_seconds`

- Type: `gauge`
- Labels: none
- Unit: seconds
- Source: `${CHRONYC} tracking`
- When absent: chronyc unavailable
- Interpretation: RMS offset from the time source

### `nixl_timesync_freq_error_ppm`

- Type: `gauge`
- Labels: none
- Unit: ppm
- Source: `${CHRONYC} tracking`
- When absent: chronyc unavailable
- Interpretation: clock frequency correction magnitude

### `nixl_timesync_stratum`

- Type: `gauge`
- Labels: none
- Unit: stratum level
- Source: `${CHRONYC} tracking`
- When absent: chronyc unavailable
- Interpretation: NTP stratum quality indicator
- Example alert: `nixl_timesync_stratum > 3`

### `nixl_timesync_reference_id_info`

- Type: `gauge`
- Labels: `ref_id`, `ref_name`
- Unit: constant `1`
- Source: `${CHRONYC} tracking`
- When absent: chronyc unavailable
- Interpretation: current time-source identity

### `nixl_timesync_last_update_seconds`

- Type: `gauge`
- Labels: none
- Unit: seconds
- Source: `${CHRONYC} tracking`
- When absent: chronyc unavailable
- Interpretation: seconds since the last chrony update

## GPU Exporter

### `nixl_gpu_scrape_success`

- Type: `gauge`
- Labels: none
- Unit: boolean `0/1`
- Source: `scripts/gpu-exporter.sh`

### `nixl_gpu_info`

- Type: `gauge`
- Labels: `vendor`, `index`, `uuid`, `name`, `pci_bus`
- Unit: constant `1`
- Source: `${NVIDIA_SMI}`
- When absent: `nvidia-smi` missing or no visible GPU
- Interpretation: inventory anchor for joins in dashboards

### `nixl_gpu_utilization_percent`

- Type: `gauge`
- Labels: `vendor`, `index`, `uuid`
- Unit: percent
- Source: `${NVIDIA_SMI}`, `${ROCM_SMI}`, or `${INTEL_GPU_TOP}`
- When absent: GPU metrics unavailable or vendor utility missing
- Interpretation: SM utilization

### `nixl_gpu_memory_used_bytes`

- Type: `gauge`
- Labels: `vendor`, `index`, `uuid`
- Unit: bytes
- Source: `${NVIDIA_SMI}` or `${ROCM_SMI}`
- When absent: GPU metrics unavailable
- Interpretation: device memory in use

### `nixl_gpu_memory_total_bytes`

- Type: `gauge`
- Labels: `vendor`, `index`, `uuid`
- Unit: bytes
- Source: `${NVIDIA_SMI}` or `${ROCM_SMI}`
- When absent: GPU metrics unavailable

### `nixl_gpu_temperature_celsius`

- Type: `gauge`
- Labels: `vendor`, `index`, `uuid`
- Unit: Celsius
- Source: `${NVIDIA_SMI}` or `${ROCM_SMI}`
- When absent: GPU metrics unavailable

### `nixl_gpu_power_draw_watts`

- Type: `gauge`
- Labels: `vendor`, `index`, `uuid`
- Unit: watts
- Source: `${NVIDIA_SMI}`
- When absent: GPU metrics unavailable

### `nixl_gpu_pcie_link_gen`

- Type: `gauge`
- Labels: `vendor`, `index`, `uuid`
- Unit: PCIe generation
- Source: `${NVIDIA_SMI}`
- When absent: GPU metrics unavailable
- Interpretation: current negotiated PCIe generation

### `nixl_gpu_pcie_link_width`

- Type: `gauge`
- Labels: `vendor`, `index`, `uuid`
- Unit: lanes
- Source: `${NVIDIA_SMI}`
- When absent: GPU metrics unavailable

### `nixl_gpu_ecc_volatile_total`

- Type: `counter`
- Labels: `vendor`, `index`, `uuid`
- Unit: ECC errors
- Source: `${NVIDIA_SMI}`
- When absent: ECC unavailable

### `nixl_gpu_bar1_used_bytes`

- Type: `gauge`
- Labels: `vendor`, `index`, `uuid`
- Unit: bytes
- Source: `${NVIDIA_SMI}`
- When absent: BAR1 metrics unavailable
- Interpretation: BAR1 aperture pressure

### `nixl_gpu_bar1_total_bytes`

- Type: `gauge`
- Labels: `vendor`, `index`, `uuid`
- Unit: bytes
- Source: `${NVIDIA_SMI}`
- When absent: BAR1 metrics unavailable

### `nixl_gpu_throttle_reason`

- Type: `gauge`
- Labels: `index`, `uuid`, `reason`
- Unit: boolean `0/1`
- Source: `${NVIDIA_SMI} --query-gpu=clocks_event_reasons.*`
- When absent: throttle-reason query unsupported
- Interpretation: active or inactive throttle reason flags
- Example alert: `nixl_gpu_throttle_reason{reason="hw_slowdown"} == 1`

### `nixl_gpu_pstate`

- Type: `gauge`
- Labels: `index`, `uuid`, `pstate`
- Unit: constant `1`
- Source: `${NVIDIA_SMI} --query-gpu=pstate`
- When absent: pstate query unsupported
- Interpretation: current NVIDIA performance state
- Example alert: `nixl_gpu_pstate{pstate!="P0"} == 1`

### `nixl_gpu_power_limit_watts`

- Type: `gauge`
- Labels: `index`, `uuid`
- Unit: watts
- Source: `${NVIDIA_SMI} --query-gpu=power.limit`
- When absent: query unsupported
- Interpretation: configured software power limit

### `nixl_gpu_power_enforced_limit_watts`

- Type: `gauge`
- Labels: `index`, `uuid`
- Unit: watts
- Source: `${NVIDIA_SMI} --query-gpu=enforced.power.limit`
- When absent: query unsupported
- Interpretation: enforced power limit currently in effect

### `nixl_gpu_clock_sm_mhz`

- Type: `gauge`
- Labels: `index`, `uuid`
- Unit: MHz
- Source: `${NVIDIA_SMI} --query-gpu=clocks.sm`
- When absent: query unsupported
- Interpretation: current SM clock
- Example alert: `nixl_gpu_clock_sm_mhz / nixl_gpu_clock_max_sm_mhz < 0.9`

### `nixl_gpu_clock_mem_mhz`

- Type: `gauge`
- Labels: `index`, `uuid`
- Unit: MHz
- Source: `${NVIDIA_SMI} --query-gpu=clocks.mem`
- When absent: query unsupported
- Interpretation: current memory clock

### `nixl_gpu_clock_max_sm_mhz`

- Type: `gauge`
- Labels: `index`, `uuid`
- Unit: MHz
- Source: `${NVIDIA_SMI} --query-gpu=clocks.max.sm`
- When absent: query unsupported
- Interpretation: rated maximum SM clock

### `nixl_gpu_clock_max_mem_mhz`

- Type: `gauge`
- Labels: `index`, `uuid`
- Unit: MHz
- Source: `${NVIDIA_SMI} --query-gpu=clocks.max.mem`
- When absent: query unsupported
- Interpretation: rated maximum memory clock

### `nixl_gpu_fan_speed_percent`

- Type: `gauge`
- Labels: `index`, `uuid`
- Unit: percent
- Source: `${NVIDIA_SMI} --query-gpu=fan.speed`
- When absent: fan telemetry unavailable or N/A
- Interpretation: current fan duty cycle

### `nixl_amd_gpu_scrape_success`

- Type: `gauge`
- Labels: none
- Unit: boolean `0/1`
- Source: `scripts/collect-amd-gpu.sh`
- When absent: exporter failed before emitting output
- Interpretation: AMD collector completed; `0` may also indicate `rocm-smi` is unavailable

### `nixl_amd_gpu_rocm_smi_version`

- Type: `gauge`
- Labels: `version`
- Unit: boolean `0/1`
- Source: `scripts/collect-amd-gpu.sh`
- When absent: `rocm-smi` unavailable
- Interpretation: rocm-smi version detected; `version=unavailable` when binary missing

### `nixl_intel_gpu_scrape_success`

- Type: `gauge`
- Labels: none
- Unit: boolean `0/1`
- Source: `scripts/collect-intel-gpu.sh`
- When absent: exporter failed before emitting output
- Interpretation: Intel collector completed; `0` may also indicate `intel_gpu_top` is unavailable

### `nixl_intel_gpu_intel_gpu_top_version`

- Type: `gauge`
- Labels: `version`
- Unit: boolean `0/1`
- Source: `scripts/collect-intel-gpu.sh`
- When absent: `intel_gpu_top` unavailable
- Interpretation: intel_gpu_top version detected; `version=unavailable` when binary missing

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

### `nixl_diskstat_reads_completed_total`

- Type: `counter`
- Labels: `device`
- Unit: operations
- Source: `${PROC_ROOT}/diskstats`
- When absent: diskstats unavailable or the device is not in the monitored block-device allowlist
- Cardinality estimate: O(block devices)
- Interpretation: completed read operations per block device
- Example alert: `rate(nixl_diskstat_reads_completed_total[5m])`

### `nixl_diskstat_writes_completed_total`

- Type: `counter`
- Labels: `device`
- Unit: operations
- Source: `${PROC_ROOT}/diskstats`
- When absent: diskstats unavailable or the device is not in the monitored block-device allowlist
- Cardinality estimate: O(block devices)
- Interpretation: completed write operations per block device
- Example alert: `rate(nixl_diskstat_writes_completed_total[5m]) == 0 and nixl_diskstat_io_in_progress > 0`

### `nixl_diskstat_io_in_progress`

- Type: `gauge`
- Labels: `device`
- Unit: requests
- Source: `${PROC_ROOT}/diskstats`
- When absent: diskstats unavailable or the device is not in the monitored block-device allowlist
- Cardinality estimate: O(block devices)
- Interpretation: current in-flight I/O requests per block device
- Example alert: `nixl_diskstat_io_in_progress > nixl_block_queue_depth * 0.9`

### `nixl_diskstat_io_time_ms_total`

- Type: `counter`
- Labels: `device`
- Unit: milliseconds
- Source: `${PROC_ROOT}/diskstats`
- When absent: diskstats unavailable or the device is not in the monitored block-device allowlist
- Cardinality estimate: O(block devices)
- Interpretation: cumulative time the block device spent doing I/O
- Example alert: `rate(nixl_diskstat_io_time_ms_total[5m]) / (rate(nixl_diskstat_reads_completed_total[5m]) + rate(nixl_diskstat_writes_completed_total[5m]) + 1) > 100`

### `nixl_diskstat_*_total`

- Type: `counter`
- Labels: `device`
- Unit: operations, sectors, or milliseconds depending on metric
- Source: `${PROC_ROOT}/diskstats`
- When absent: optional kernel fields are missing, diskstats is unavailable, or the device is not in the monitored block-device allowlist
- Cardinality estimate: O(block devices)
- Interpretation: full block-device read, write, discard, flush, and weighted I/O counters
- Example alert: `rate(nixl_diskstat_weighted_io_time_ms_total[5m]) > 0`

### `nixl_block_queue_depth`

- Type: `gauge`
- Labels: `device`
- Unit: requests
- Source: `${SYS_ROOT}/block/<device>/queue/nr_requests`
- When absent: queue attribute unavailable for the device
- Cardinality estimate: O(block devices)
- Interpretation: configured block request queue depth
- Example alert: `nixl_diskstat_io_in_progress > nixl_block_queue_depth * 0.9`

### `nixl_block_scheduler_info`

- Type: `gauge`
- Labels: `device`, `scheduler`
- Unit: constant `1`
- Source: `${SYS_ROOT}/block/<device>/queue/scheduler`
- When absent: scheduler attribute unavailable for the device
- Cardinality estimate: O(block devices)
- Interpretation: active block scheduler selected by the kernel
- Example alert: inspect during storage triage

### `nixl_block_*`

- Type: `gauge`
- Labels: `device`
- Unit: bytes, counts, requests, or boolean depending on metric
- Source: `${SYS_ROOT}/block/<device>/queue/*` and `${SYS_ROOT}/block/<device>/inflight`
- When absent: the specific sysfs attribute is unavailable
- Cardinality estimate: O(block devices)
- Interpretation: block queue shape, sector size, discard support, scheduler, and in-flight read/write split
- Example alert: `nixl_block_rotational == 1`

### `nixl_nvme_scrape_success`

- Type: `gauge`
- Labels: none
- Unit: boolean `0/1`
- Source: `scripts/nvme-smart-exporter.sh`
- When absent: exporter did not run
- Cardinality estimate: 1
- Interpretation: whether NVMe SMART collection completed

### `nixl_nvme_percentage_used`

- Type: `gauge`
- Labels: `device`, `model`, `serial`
- Unit: percent
- Source: `nvme smart-log --output-format=json`
- When absent: `nvme` unavailable, no NVMe devices, or SMART field unavailable
- Cardinality estimate: O(NVMe devices)
- Interpretation: lifetime endurance consumed, where values can exceed 100 on some drives
- Example alert: `nixl_nvme_percentage_used > 80`

### `nixl_nvme_available_spare_percent`

- Type: `gauge`
- Labels: `device`, `model`, `serial`
- Unit: percent
- Source: `nvme smart-log --output-format=json`
- When absent: `nvme` unavailable, no NVMe devices, or SMART field unavailable
- Cardinality estimate: O(NVMe devices)
- Interpretation: remaining spare capacity percentage
- Example alert: `nixl_nvme_available_spare_percent < nixl_nvme_available_spare_threshold_percent`

### `nixl_nvme_critical_warning`

- Type: `gauge`
- Labels: `device`, `model`, `serial`
- Unit: bitmask
- Source: `nvme smart-log --output-format=json`
- When absent: `nvme` unavailable, no NVMe devices, or SMART field unavailable
- Cardinality estimate: O(NVMe devices)
- Interpretation: NVMe critical warning bitmask
- Example alert: `nixl_nvme_critical_warning > 0`

### `nixl_nvme_warn_*`

- Type: `gauge`
- Labels: `device`, `model`, `serial`
- Unit: boolean `0/1`
- Source: decoded `critical_warning` bits from `nvme smart-log`
- When absent: critical warning field unavailable
- Cardinality estimate: O(NVMe devices x warning bits)
- Interpretation: individual NVMe critical warning bits for spare, temperature, reliability, read-only, and volatile backup failure
- Example alert: `nixl_nvme_warn_read_only == 1`

### `nixl_nvme_temperature_celsius`

- Type: `gauge`
- Labels: `device`, `model`, `serial`, `sensor`
- Unit: Celsius
- Source: `nvme smart-log --output-format=json`
- When absent: `nvme` unavailable, no NVMe devices, or temperature field unavailable
- Cardinality estimate: O(NVMe devices x sensors)
- Interpretation: composite and per-sensor NVMe temperatures
- Example alert: `nixl_nvme_temperature_celsius{sensor="composite"} > 70`

### `nixl_nvme_*_total`

- Type: `counter`
- Labels: `device`, `model`, `serial`
- Unit: bytes, commands, seconds, cycles, shutdowns, errors, or log entries depending on metric
- Source: `nvme smart-log --output-format=json`
- When absent: `nvme` unavailable, no NVMe devices, or SMART field unavailable
- Cardinality estimate: O(NVMe devices)
- Interpretation: NVMe lifetime traffic, command, power, busy-time, and reliability counters
- Example alert: `increase(nixl_nvme_media_errors_total[1h]) > 0`

### `nixl_raid_scrape_success`

- Type: `gauge`
- Labels: none
- Unit: boolean `0/1`
- Source: `scripts/raid-lvm-exporter.sh`
- When absent: exporter did not run
- Cardinality estimate: 1
- Interpretation: whether RAID/LVM collection completed

### `nixl_md_*`

- Type: `gauge` or `counter` depending on metric
- Labels: `device`, optionally `level` or `action`
- Unit: booleans, counts, bytes, KiB/s, or mismatch events
- Source: `${PROC_ROOT}/mdstat` and `${SYS_ROOT}/block/md*/md/*`
- When absent: no mdstat file or no md arrays
- Cardinality estimate: O(md arrays)
- Interpretation: md software RAID state, disk counts, size, sync action, sync speed, and mismatch count
- Example alert: `nixl_md_degraded == 1`

### `nixl_lvm_*`

- Type: `gauge`
- Labels: `vg`, `lv`
- Unit: bytes or percent depending on metric
- Source: `lvs --noheadings --units b --nosuffix`
- When absent: `lvs` unavailable or no LVM volumes
- Cardinality estimate: O(logical volumes)
- Interpretation: LVM logical volume size and thin pool data/metadata usage
- Example alert: `nixl_lvm_thin_data_percent > 85`

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

## Statistical Baseline Exporter

### `nixl_baseline_scrape_success`

- Type: `gauge`
- Labels: none
- Unit: boolean `0/1`
- Source: `scripts/anomaly-baseline-exporter.sh`

### `nixl_baseline_mean`

- Type: `gauge`
- Labels: `metric_id`
- Unit: same as source metric
- Source: `${OUT_DIR}/.baseline/*.window`
- Interpretation: rolling mean for a host-local anomaly baseline metric

### `nixl_baseline_stddev`

- Type: `gauge`
- Labels: `metric_id`
- Unit: same as source metric
- Source: `${OUT_DIR}/.baseline/*.window`
- Interpretation: rolling population standard deviation for the same baseline

### `nixl_baseline_p50`

- Type: `gauge`
- Labels: `metric_id`
- Unit: same as source metric
- Source: `${OUT_DIR}/.baseline/*.window`
- Interpretation: rolling median for the selected baseline metric

### `nixl_baseline_p95`

- Type: `gauge`
- Labels: `metric_id`
- Unit: same as source metric
- Source: `${OUT_DIR}/.baseline/*.window`
- Interpretation: rolling p95 for the selected baseline metric

### `nixl_baseline_p99`

- Type: `gauge`
- Labels: `metric_id`
- Unit: same as source metric
- Source: `${OUT_DIR}/.baseline/*.window`
- Interpretation: rolling p99 for the selected baseline metric

### `nixl_baseline_current`

- Type: `gauge`
- Labels: `metric_id`
- Unit: same as source metric
- Source: current `.prom` outputs in `${OUT_DIR}`
- Interpretation: current sample inserted into the rolling baseline window

### `nixl_baseline_zscore`

- Type: `gauge`
- Labels: `metric_id`
- Unit: standard deviations
- Source: derived from current value, mean, and stddev
- Interpretation: how abnormal the current reading is versus recent local history

### `nixl_baseline_window_size`

- Type: `gauge`
- Labels: `metric_id`
- Unit: samples
- Source: `${OUT_DIR}/.baseline/*.window`
- Interpretation: number of retained samples used to compute the rolling baseline

## Training Job Heartbeat Exporter

### `nixl_job_scrape_success`

- Type: `gauge`
- Labels: none
- Unit: boolean `0/1`
- Source: `scripts/job-heartbeat-exporter.sh`

### `nixl_job_training_processes_total`

- Type: `gauge`
- Labels: none
- Unit: count
- Source: training-like process scan
- Interpretation: number of likely training processes currently visible on the host

### `nixl_job_process_uptime_seconds`

- Type: `gauge`
- Labels: `pid`, `cmdline_summary`
- Unit: seconds
- Source: `ps`
- Interpretation: uptime for a detected training-like process

### `nixl_job_process_cpu_percent`

- Type: `gauge`
- Labels: `pid`, `cmdline_summary`
- Unit: percent
- Source: `ps`
- Interpretation: CPU usage for a detected training-like process

### `nixl_job_process_mem_rss_bytes`

- Type: `gauge`
- Labels: `pid`, `cmdline_summary`
- Unit: bytes
- Source: `ps`
- Interpretation: RSS footprint for a detected training-like process

### `nixl_job_checkpoint_files_recent`

- Type: `gauge`
- Labels: `dir`
- Unit: count
- Source: watched checkpoint roots
- Interpretation: checkpoint files modified within the freshness window

### `nixl_job_checkpoint_last_write_age_seconds`

- Type: `gauge`
- Labels: `dir`
- Unit: seconds
- Source: watched checkpoint roots
- Interpretation: age of the newest checkpoint beneath the configured root

### `nixl_job_log_last_step`

- Type: `gauge`
- Labels: `logfile`
- Unit: steps
- Source: watched training log files
- Interpretation: last step-like progress marker found in the recent tail of the log

### `nixl_job_log_last_update_age_seconds`

- Type: `gauge`
- Labels: `logfile`
- Unit: seconds
- Source: watched training log files
- Interpretation: how stale the log file itself is

### `nixl_job_stall_suspected`

- Type: `gauge`
- Labels: none
- Unit: boolean `0/1`
- Source: derived from process presence, GPU activity, checkpoints, and logs
- Interpretation: host-level suspicion that training is active but not making progress

### `nixl_job_stall_duration_seconds`

- Type: `gauge`
- Labels: none
- Unit: seconds
- Source: `${OUT_DIR}/.heartbeat/stall.state`
- Interpretation: duration of the currently suspected stalled state

## Network Flow Exporter

### `nixl_netflow_scrape_success`

- Type: `gauge`
- Labels: none
- Unit: boolean `0/1`
- Source: `scripts/net-flow-exporter.sh`

### `nixl_netflow_tcp_established_total`

- Type: `gauge`
- Labels: `local_port_class`
- Unit: count
- Source: `ss --tcp --info state established`
- Interpretation: established TCP socket count grouped into NCCL, RDMA, SSH, and other classes

### `nixl_netflow_tcp_close_wait_total`

- Type: `gauge`
- Labels: none
- Unit: count
- Source: `ss --tcp --info state close-wait`
- Interpretation: lingering sockets that may indicate application-side close handling issues

### `nixl_netflow_tcp_time_wait_total`

- Type: `gauge`
- Labels: none
- Unit: count
- Source: `ss --tcp --info state time-wait`
- Interpretation: socket churn level from recently closed TCP connections

### `nixl_netflow_udp_established_total`

- Type: `gauge`
- Labels: none
- Unit: count
- Source: `ss --udp state established`
- Interpretation: established UDP socket count

### `nixl_netflow_tcp_retrans_total`

- Type: `counter`
- Labels: `local_port_class`
- Unit: retransmit proxy count
- Source: parsed from `ss --tcp --info state established`
- Interpretation: retransmit activity grouped by socket class

### `nixl_netflow_iface_rx_utilization_ratio`

- Type: `gauge`
- Labels: `iface`
- Unit: ratio `0..1+`
- Source: `/proc/net/dev` byte deltas and `${SYS_ROOT}/class/net/<iface>/speed`
- Interpretation: receive-side interface utilization relative to line rate

### `nixl_netflow_iface_tx_utilization_ratio`

- Type: `gauge`
- Labels: `iface`
- Unit: ratio `0..1+`
- Source: `/proc/net/dev` byte deltas and `${SYS_ROOT}/class/net/<iface>/speed`
- Interpretation: transmit-side interface utilization relative to line rate

### `nixl_netflow_nccl_connections_detected`

- Type: `gauge`
- Labels: none
- Unit: count
- Source: high-port TCP heuristic
- Interpretation: likely NCCL-style TCP connections seen on the host

### `nixl_netflow_nccl_remote_hosts_total`

- Type: `gauge`
- Labels: none
- Unit: count
- Source: high-port TCP heuristic
- Interpretation: distinct remote /24 peers participating in likely NCCL traffic

### `nixl_netstat_ext`

- Type: `counter`
- Labels: `field`
- Unit: counter
- Source: `${PROC_ROOT}/net/netstat`
- Interpretation: selected extended TCP stack counters not surfaced in the generic SNMP view

## Collector Health Exporter

### `nixl_collector_scrape_success`

- Type: `gauge`
- Labels: none
- Unit: boolean `0/1`
- Source: `scripts/collector-health-exporter.sh`

### `nixl_collector_last_run_timestamp`

- Type: `gauge`
- Labels: `exporter`
- Unit: unix timestamp
- Source: `.prom` file modification time
- Interpretation: last write timestamp for an exporter output file

### `nixl_collector_last_run_age_seconds`

- Type: `gauge`
- Labels: `exporter`
- Unit: seconds
- Source: derived from file mtime
- Interpretation: freshness of an exporter output file

### `nixl_collector_last_run_duration_seconds`

- Type: `gauge`
- Labels: `exporter`
- Unit: seconds
- Source: `ai_host_exporter_duration_seconds` parsed from wrapped output
- Interpretation: last observed execution time for an exporter when the wrapper recorded it

### `nixl_collector_prom_file_size_bytes`

- Type: `gauge`
- Labels: `exporter`
- Unit: bytes
- Source: file stat
- Interpretation: on-disk size of an exporter output file

### `nixl_collector_prom_file_lines`

- Type: `gauge`
- Labels: `exporter`
- Unit: lines
- Source: file contents
- Interpretation: total line count of an exporter output file

### `nixl_collector_prom_file_metric_count`

- Type: `gauge`
- Labels: `exporter`
- Unit: count
- Source: file contents
- Interpretation: non-comment metric sample count inside an exporter output file

### `nixl_collector_exporters_total`

- Type: `gauge`
- Labels: none
- Unit: count
- Source: `${OUT_DIR}/*.prom`
- Interpretation: number of exporter outputs currently present

### `nixl_collector_exporters_stale`

- Type: `gauge`
- Labels: none
- Unit: count
- Source: exporter file mtimes
- Interpretation: how many exporter outputs are older than the stale threshold

### `nixl_collector_exporters_empty`

- Type: `gauge`
- Labels: none
- Unit: count
- Source: exporter file contents
- Interpretation: exporter outputs with zero metric samples

### `nixl_collector_total_metrics`

- Type: `gauge`
- Labels: none
- Unit: count
- Source: exporter file contents
- Interpretation: total metric sample count across all exporter outputs

### `nixl_collector_total_prom_size_bytes`

- Type: `gauge`
- Labels: none
- Unit: bytes
- Source: exporter file stats
- Interpretation: total disk footprint of the textfile collector outputs

### `nixl_collector_node_exporter_running`

- Type: `gauge`
- Labels: none
- Unit: boolean `0/1`
- Source: process scan
- Interpretation: whether node_exporter appears to be running locally

### `nixl_collector_textfile_dir_writable`

- Type: `gauge`
- Labels: none
- Unit: boolean `0/1`
- Source: filesystem permission check
- Interpretation: whether the textfile collector directory is writable

### `nixl_collector_unique_series_estimate`

- Type: `gauge`
- Labels: none
- Unit: count
- Source: unique metric lines across exporter outputs
- Interpretation: approximate unique time-series count produced by the current `.prom` corpus

## GPU Memory Pressure Exporter

### `nixl_gpumem_scrape_success`

- Type: `gauge`
- Labels: none
- Unit: boolean `0/1`
- Source: `scripts/gpu-mem-pressure-exporter.sh`

### `nixl_gpu_process_memory_bytes`

- Type: `gauge`
- Labels: `index`, `uuid`, `pid`, `process_name`
- Unit: bytes
- Source: `nvidia-smi --query-compute-apps`
- Interpretation: per-process GPU memory footprint attributed by the NVIDIA driver

### `nixl_gpu_process_count`

- Type: `gauge`
- Labels: `index`, `uuid`
- Unit: count
- Source: `nvidia-smi --query-compute-apps`
- Interpretation: number of visible GPU-using processes per device

### `nixl_gpu_memory_free_bytes`

- Type: `gauge`
- Labels: `index`, `uuid`
- Unit: bytes
- Source: `nvidia-smi --query-gpu`
- Interpretation: free GPU memory reported by the driver

### `nixl_gpu_memory_reserved_bytes`

- Type: `gauge`
- Labels: `index`, `uuid`
- Unit: bytes
- Source: derived from total, used, and free GPU memory
- Interpretation: driver-reserved memory not shown as application-used

### `nixl_gpu_memory_fragmentation_ratio`

- Type: `gauge`
- Labels: `index`, `uuid`
- Unit: ratio `0..1`
- Source: derived from reserved and total GPU memory
- Interpretation: approximate memory fragmentation or reserve pressure signal

### `nixl_gpu_compute_mode`

- Type: `gauge`
- Labels: `index`, `uuid`, `mode`
- Unit: constant `1`
- Source: `nvidia-smi --query-gpu`
- Interpretation: current compute mode fingerprint

### `nixl_gpu_mig_mode`

- Type: `gauge`
- Labels: `index`, `uuid`, `mode`
- Unit: constant `1`
- Source: `nvidia-smi --query-gpu`
- Interpretation: current MIG mode fingerprint

### `nixl_gpu_retired_pages_sbe`

- Type: `gauge`
- Labels: `index`, `uuid`
- Unit: pages
- Source: `nvidia-smi --query-gpu`
- Interpretation: retired pages due to single-bit ECC events

### `nixl_gpu_retired_pages_dbe`

- Type: `gauge`
- Labels: `index`, `uuid`
- Unit: pages
- Source: `nvidia-smi --query-gpu`
- Interpretation: retired pages due to double-bit ECC events

### `nixl_gpu_retired_pages_pending`

- Type: `gauge`
- Labels: `index`, `uuid`
- Unit: pages
- Source: `nvidia-smi --query-gpu`
- Interpretation: pages pending retirement that often require maintenance action

### `nixl_gpu_remapped_rows_correctable`

- Type: `gauge`
- Labels: `index`, `uuid`
- Unit: rows
- Source: `nvidia-smi --query-gpu`
- Interpretation: correctable remapped memory rows

### `nixl_gpu_remapped_rows_uncorrectable`

- Type: `gauge`
- Labels: `index`, `uuid`
- Unit: rows
- Source: `nvidia-smi --query-gpu`
- Interpretation: uncorrectable remapped memory rows

### `nixl_gpu_remapped_rows_pending`

- Type: `gauge`
- Labels: `index`, `uuid`
- Unit: rows
- Source: `nvidia-smi --query-gpu`
- Interpretation: rows pending remap that indicate degraded device health

## Trace Event Exporter

### `nixl_trace_scrape_success`

- Type: `gauge`
- Labels: none
- Unit: boolean `0/1`
- Source: `scripts/trace-event-exporter.sh`

### `nixl_trace_events_enabled_total`

- Type: `gauge`
- Labels: `subsystem`
- Unit: count
- Source: `${TRACING_ROOT}/events/*/*/enable`
- Interpretation: number of already-enabled tracepoints per subsystem

### `nixl_trace_function_hit_total`

- Type: `counter`
- Labels: `function`
- Unit: hits
- Source: `${TRACING_ROOT}/trace_stat/function0`
- Interpretation: top function hit counters when trace stats are already populated

### `nixl_trace_mm_page_alloc_total`

- Type: `counter`
- Labels: none
- Unit: allocations
- Source: `${PROC_ROOT}/vmstat`
- Interpretation: page allocation proxy for memory tracing dashboards

### `nixl_trace_mm_page_free_total`

- Type: `counter`
- Labels: none
- Unit: frees
- Source: `${PROC_ROOT}/vmstat`
- Interpretation: page free proxy for memory tracing dashboards

### `nixl_trace_kmem_cache_alloc_total`

- Type: `counter`
- Labels: none
- Unit: scans
- Source: `${PROC_ROOT}/vmstat`
- Interpretation: slab allocator pressure proxy for trace-aligned views

### `nixl_perf_event_paranoid`

- Type: `gauge`
- Labels: none
- Unit: raw sysctl value
- Source: `${PROC_ROOT}/sys/kernel/perf_event_paranoid`
- Interpretation: whether non-root perf and profiling workflows are likely to work

### `nixl_perf_event_max_sample_rate`

- Type: `gauge`
- Labels: none
- Unit: samples per second
- Source: `${PROC_ROOT}/sys/kernel/perf_event_max_sample_rate`
- Interpretation: upper bound for perf sample rate

### `nixl_perf_event_mlock_kb`

- Type: `gauge`
- Labels: none
- Unit: KiB
- Source: `${PROC_ROOT}/sys/kernel/perf_event_mlock_kb`
- Interpretation: locked-memory allowance for perf event buffers

## Host Consistency Exporter

### `nixl_consistency_scrape_success`

- Type: `gauge`
- Labels: none
- Unit: boolean `0/1`
- Source: `scripts/host-consistency-exporter.sh`

### `nixl_host_kernel_version_info`

- Type: `gauge`
- Labels: `version`, `major`, `minor`, `patch`
- Unit: constant `1`
- Source: `uname -r`
- Interpretation: kernel version fingerprint for cross-host drift detection

### `nixl_host_driver_version_info`

- Type: `gauge`
- Labels: `driver`, `version`
- Unit: constant `1`
- Source: `nvidia-smi` and `modinfo`
- Interpretation: driver version fingerprint for NVIDIA and RDMA-related kernel modules

### `nixl_host_cuda_version_info`

- Type: `gauge`
- Labels: `version`
- Unit: constant `1`
- Source: `nvidia-smi`
- Interpretation: CUDA runtime version fingerprint

### `nixl_host_bios_version_info`

- Type: `gauge`
- Labels: `vendor`, `version`, `date`
- Unit: constant `1`
- Source: `dmidecode`
- Interpretation: BIOS or firmware fingerprint for cross-host hardware drift checks

### `nixl_host_cpu_microcode_info`

- Type: `gauge`
- Labels: `family`, `model`, `stepping`, `microcode`
- Unit: constant `1`
- Source: `${PROC_ROOT}/cpuinfo`
- Interpretation: CPU microcode and stepping fingerprint

### `nixl_host_identity_info`

- Type: `gauge`
- Labels: `hostname`, `fqdn`, `arch`
- Unit: constant `1`
- Source: `hostname`, `hostname -f`, `uname -m`
- Interpretation: host identity labels for fleet-wide queries

### `nixl_host_ulimit`

- Type: `gauge`
- Labels: `resource`, `type`
- Unit: raw limit value or `-1` for unlimited
- Source: shell `ulimit`
- Interpretation: process resource limits relevant to AI host behavior

### `nixl_host_sysctl`

- Type: `gauge`
- Labels: `name`
- Unit: raw sysctl value
- Source: `${PROC_ROOT}/sys/*`
- Interpretation: sysctl conformance values for training and transport tuning

### `nixl_module_loaded`

- Type: `gauge`
- Labels: `module`
- Unit: boolean `0/1`
- Source: `${PROC_ROOT}/modules`
- When absent: proc modules unavailable
- Interpretation: whether selected driver modules are loaded
