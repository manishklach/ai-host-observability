# Changelog

## v0.3.0 (2026-06-08)

### Reliability Monitoring
- **Memory errors and RAS**: Added `mce-ras-exporter.sh` for EDAC memory controller counters, CPU-bank EDAC counters, rasdaemon DIMM errors, and `mcelog` event aggregation
- **CPU thermal and frequency stability**: Added `cpu-thermal-exporter.sh` for thermal zones, trip points, throttle counters, package frequency min/max/mean, and governor labeling
- **GPU fabric and failure signals**: Added `nvlink-exporter.sh`, expanded kernel log pattern coverage for GPU XID / NVLink / NVSwitch / reset events, and extended NVIDIA GPU telemetry with throttle reasons, P-state, power limits, clocks, and fan speed
- **Hugepage and THP visibility**: Extended the host memory exporter with hugepage pool inventory, THP fault/fallback/split counters, and active THP mode
- **Watchdog and hang detection**: Added `watchdog-exporter.sh` plus kernel log pattern coverage for soft lockups, hung tasks, RCU stalls, panics, oopses, and stack overflows
- **Clock synchronisation**: Added `timesync-exporter.sh` for chrony / timedatectl sync state, offset, RMS offset, frequency error, stratum, and reference source labels

### Alerts and Runbooks
- Added reliability alerts for EDAC memory errors, CPU thermal throttling, low CPU frequency, NVLink down/errors, hugepage exhaustion, THP fallback rate, soft lockups, hung tasks, RCU stalls, clock synchronisation drift, GPU hardware slowdown, GPU power-cap throttling, non-P0 state, and low GPU clocks
- Added matching runbook stubs under `docs/runbooks/` for all new reliability alerts

### Tests and Fixtures
- Added fixture-backed Bats coverage for all new reliability exporters
- Added reliability fixture data for EDAC, thermal zones, CPU cpufreq, watchdog sysctls, chrony / timedatectl, and enhanced `nvidia-smi` / `journalctl` stubs

### Documentation
- Added a new reliability section to `docs/signals.md`
- Expanded `docs/metrics.md` with contract entries for all new reliability metrics
- Updated the README monitoring summary to include hardware fault, thermal, NVLink, hugepage, watchdog, and time-sync coverage

## v0.2.0 (2026-06-06)

### Collector Improvements
- **Duration metrics**: Added `ai_host_exporter_duration_seconds{exporter="..."}` to track per-exporter execution time (success + failure paths)
- **Parallel execution**: New `PARALLEL=1` and `MAX_PARALLEL=N` env vars enable concurrent exporter runs (default: sequential)
- **Structured logging**: `LOG_FORMAT=json|text` emits JSON logs with timestamp/level/message; falls back to pure bash when `jq` unavailable
- **Dependency check**: New `make check-deps` validates required/optional tools (node_exporter, ethtool, nvidia-smi, rocm-smi, intel_gpu_top, debugfs, cgroup v1/v2)

### New Metrics
- **Host uptime/boot**: `nixl_host_uptime_seconds`, `nixl_host_boot_time_seconds` from `/proc/uptime`
- **GPU tool versions**: `nixl_amd_gpu_rocm_smi_version{version="..."}`, `nixl_intel_gpu_intel_gpu_top_version{version="..."}` with `version="unavailable"` when binary missing
- **cgroup v1/v2 support**: Auto-detects cgroup version; reads `memory.current` (v2) or `memory/memory.usage_in_bytes` (v1) + corresponding events/pressure files

### Packaging & Operations
- **DEB/RPM packages**: Release workflow now builds `.deb` and `.rpm` via `nfpm` with systemd integration (postinst/preun scripts)
- **Systemd drop-ins**: Service reads `/etc/ai-host-observability/collector.conf` (PARALLEL, MAX_PARALLEL, LOG_FORMAT, OUT_DIR, EXPORTERS); timer override via `/etc/systemd/system/ai-host-observability.timer.d/override.conf` for `OnUnitActiveSec`
- **Config examples**: `/etc/ai-host-observability/*.conf.example` installed with packages

### Documentation
- **Cardinality guidance**: New table in `docs/metrics.md` with per-metric cardinality estimates and Prometheus `metric_relabel_configs` examples for high-cardinality metrics (`nixl_process_*`, `nixl_irq_total`, etc.)
- **Updated metric docs**: cgroup v1/v2 sources, GPU version metrics, uptime/boot metrics

### Fixes
- Temp file cleanup: `.with_duration` intermediate files now explicitly removed

## v0.1.0

- Initial public release
