# Ops Guide

## Day-1 Setup Checklist

### Sysctls for AI training nodes

- `net.core.rmem_max=268435456`
- `net.core.wmem_max=268435456`
- `net.core.netdev_max_backlog=10000` or higher for bursty NIC load
- `net.ipv4.tcp_rmem=4096 131072 268435456`
- `net.ipv4.tcp_wmem=4096 131072 268435456`
- `net.ipv4.tcp_slow_start_after_idle=0`
- `net.core.somaxconn=4096` or higher
- `net.ipv4.tcp_max_syn_backlog=8192` or higher
- `kernel.numa_balancing=0` on dedicated GPU training nodes
- `vm.zone_reclaim_mode=0`
- `vm.nr_hugepages` sized for pinned-buffer and registration needs
- `vm.nr_overcommit_hugepages` sized if you expect dynamic hugepage pressure
- `kernel.perf_event_paranoid<=1` if non-root tracing and perf tooling should work during incident response

### Ulimits

- `memlock`: ideally unlimited, otherwise clearly above your worst-case pinned-memory footprint
- `nofile`: high enough for data loader, checkpoint, and fabric fan-out patterns
- `nproc`: high enough for launcher plus worker model
- `stack`: avoid unusually small limits that break debug tooling
- `core`: enable if you rely on post-mortem crash analysis

### Hugepages and THP

- Pre-allocate hugepages when the workload benefits from fewer page mappings and more stable registration behavior.
- Watch `nixl_hugepages_*`, `nixl_thp_fault_fallback_total`, and `nixl_thp_enabled_info` after rollout to confirm the host is actually using the intended page strategy.

### NUMA and reclaim

- Disable automatic NUMA balancing on dedicated GPU nodes unless you have a workload-specific reason not to.
- Keep `vm.zone_reclaim_mode=0` so the host prefers remote memory over local reclaim storms.

### GPU / peer-memory path

- Load the expected GDR-related module path for the platform, such as `nvidia_peermem` or legacy `nv_peer_mem`, and validate that the module inventory is consistent across hosts.

### NVMe and storage

- Use the queue scheduler recommended by the platform team for your NVMe stack, typically `none` or `mq-deadline`.
- Validate checkpoint paths and free space before a long run.

### Fabric expectations

- Set and document the expected IB link rate for the environment, for example with an `IB_EXPECTED_RATE_GBPS` operational convention, so drift is obvious during triage.

## Alert Response Cascades

### Memory pressure cascade

Watch the sequence `PSI -> fw_pages -> reclaim -> compaction -> OOM`. If `nixl_host_memory_psi_avg` rises first, then `nixl_host_fw_pages_sum` and reclaim counters follow, treat the host as unhealthy even if the GPU still looks productive.

### GPU degradation cascade

Watch `GPU XID -> ECC / retired pages -> throttle reasons -> P-state drop`. A healthy utilization graph can hide a device that is already degrading from a reliability standpoint.

### Fabric failure cascade

Watch `IB down / retransmits -> NCCL timeout symptoms -> job heartbeat stalls`. If the job heartbeat exporter says progress stopped while the network-flow exporter shows retransmit pressure, suspect the interconnect before blaming model code.

### Storage failure cascade

Watch `NVMe wear / filesystem pressure -> checkpoint freshness -> job stall`. Stale checkpoints with active GPUs are often a storage or pathing problem rather than a framework deadlock.

### Node eviction cascade

Watch `EDAC UE -> kernel panic / drain action -> scheduler eviction`. Hardware fault alerts should trigger node isolation workflows quickly, not just human investigation.

## Tuning the Anomaly Baselines

- Reset the learned baselines by deleting `${OUT_DIR}/.baseline/` and `${OUT_DIR}/.baseline-state/`.
- Increase or decrease `BASELINE_WINDOW_SIZE` depending on how quickly you want the host to relearn a new normal.
- Tune `STALE_THRESHOLD`, `CHECKPOINT_WINDOW_SECONDS`, and `STALL_THRESHOLD_SECONDS` together so freshness and stall alerts match the workload cadence.
- Add a new `metric_id` by teaching `scripts/anomaly-baseline-exporter.sh` how to read the current value and whether it should treat the source as a gauge or a per-scrape counter proxy.
- Read z-scores as deviation-from-normal, and p99 breaches as rare-but-not-yet-critical behavior. A node can exceed p99 without being three standard deviations out if the baseline is noisy.

## Cardinality Management

- The highest-cardinality exporters are typically per-process GPU memory, job logs, and any future per-host drift tables.
- Disable exporters at runtime by setting `EXPORTERS="..."` in the systemd service environment or by maintaining a reduced wrapper set for smaller nodes.
- Avoid adding permanent per-PID or per-logfile labels unless the signal is truly operationally important.
- Use the collector-health exporter to watch `nixl_collector_unique_series_estimate` after enabling new domains.

## Multi-Host Deployment Patterns

- For fleets above roughly fifty nodes, plan for Prometheus federation or remote-write architecture rather than pushing all raw high-cardinality history into a single server.
- Use Thanos, Cortex, or equivalent long-term retention for the `nixl:*` recording rules if you want week-over-week drift and trend comparisons.
- Keep host consistency metrics on every node so PromQL can answer drift questions without any cluster-side inventory service.
- Useful cross-host PromQL examples:
  `count by (version) (nixl_host_kernel_version_info) > 1`
  `count by (version) (nixl_host_driver_version_info{driver="nvidia"}) > 1`
  `nixl_host_sysctl{name="kernel.numa_balancing"} == 1`
  `nixl_host_sysctl{name="vm.zone_reclaim_mode"} != 0`
