# Changelog

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

