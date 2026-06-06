# AI Host Observability

Linux-first host observability scripts for tracking hidden system pressure on accelerated servers, especially guest-driven GPU/RDMA workloads such as multi-HCA NIXL/UCX memory registration fan-out, plus the surrounding host subsystems that usually degrade alongside them.

## Repository Description

Prometheus-friendly Linux host observability for AI and GPU infrastructure, covering memory pressure, RDMA/NIC health, GPUs, PCIe/VFIO, NUMA, process locked memory, filesystem pressure, network stack behavior, and kernel-event signals.

Short description for GitHub:

`Prometheus-friendly Linux host observability for AI/GPU infrastructure: memory pressure, RDMA/NIC health, GPUs, PCIe/VFIO, NUMA, filesystem pressure, process locked memory, and kernel-event signals.`

## Suggested Topics

Use these as GitHub repository topics if you publish the repo:

- `observability`
- `prometheus`
- `node-exporter`
- `linux`
- `gpu`
- `rdma`
- `infiniband`
- `nvidia`
- `mlx5`
- `numa`
- `vfio`
- `pcie`
- `ai-infrastructure`
- `sre`
- `performance-engineering`

Exact topic string:

`observability,prometheus,node-exporter,linux,gpu,rdma,infiniband,nvidia,mlx5,numa,vfio,pcie,ai-infrastructure,sre,performance-engineering`

The repo is designed for operators who need to answer questions like:

- Why is the host approaching OOM when guest GPU memory looks fine?
- Are `mlx5` firmware pages growing faster than expected?
- Is pressure spilling into RDMA, PCIe, VFIO/IOMMU, CPU softirqs, or NUMA locality?
- Are GPU, filesystem, network stack, or process-level signals corroborating the host-side failure mode?

## What This Monitors

- Host memory pressure from `/proc/meminfo`
- Memory PSI from `/proc/pressure/memory`
- Reclaim and swap activity from `/proc/vmstat`
- `mlx5` firmware page growth from `/sys/kernel/debug/mlx5/*/pages/fw_pages_total`
- Optional cgroup memory signals for isolated VMs or services
- NIC and RDMA counters from `ethtool` and InfiniBand sysfs
- CPU pressure, softirq load, and IRQ distribution
- NUMA free-memory balance and local-vs-remote hit ratios
- Kernel log scans for OOM, PCIe/AER, `vfio`, `iommu`, `mlx5`, and RDMA-related events
- GPU utilization, memory, BAR1, thermals, power, and PCIe link state
- Disk and filesystem pressure from `/proc/diskstats`, `df`, and file/inode tables
- Network stack counters from `/proc/net/dev`, `/proc/net/softnet_stat`, and `/proc/net/snmp`
- Per-process locked-memory clues from `/proc/<pid>/status` and `/proc/<pid>/smaps_rollup`
- PCIe device, IOMMU group, and loaded-module visibility for `vfio`, GPUs, and `mlx5`

## Layout

- `scripts/nixl-host-mem-exporter.sh`: host memory, PSI, reclaim, and `fw_pages_total`
- `scripts/rdma-link-exporter.sh`: NIC and RDMA counters
- `scripts/cpu-irq-exporter.sh`: CPU PSI, softirq counters, and IRQ distribution
- `scripts/numa-exporter.sh`: NUMA node memory and hit/miss counters
- `scripts/kernel-log-scan-exporter.sh`: counts important kernel-log patterns since boot
- `scripts/gpu-exporter.sh`: NVIDIA GPU telemetry via `nvidia-smi`
- `scripts/disk-filesystem-exporter.sh`: disk, filesystem, file-handle, and inode pressure
- `scripts/network-stack-exporter.sh`: generic network stack counters and softnet backlog pressure
- `scripts/process-memory-exporter.sh`: top processes by locked memory
- `scripts/pcie-vfio-exporter.sh`: PCIe device, IOMMU group, and module visibility
- `scripts/collect-all.sh`: convenience wrapper for node_exporter textfile collection

## Requirements

- Linux host
- Bash
- `debugfs` mounted for `fw_pages_total`
- `ethtool` recommended
- `journalctl` recommended for kernel-log scans
- `nvidia-smi` optional for GPU telemetry
- `numastat` optional but useful for corroboration outside these scripts

## Quick Start

Write all metrics into a `node_exporter` textfile collector directory:

```bash
OUT_DIR=/var/lib/node_exporter/textfile_collector \
  ./scripts/collect-all.sh
```

Run a single exporter:

```bash
./scripts/nixl-host-mem-exporter.sh \
  > /var/lib/node_exporter/textfile_collector/nixl_host_mem.prom
```

Optional cgroup-specific scrape:

```bash
CGROUP_PATH=/sys/fs/cgroup/machine.slice/my-vm.scope \
  ./scripts/nixl-host-mem-exporter.sh \
  > /var/lib/node_exporter/textfile_collector/nixl_host_mem.prom
```

Limit NIC scraping to selected interfaces:

```bash
NET_IFACES="ens6f0 ens6f1" ./scripts/rdma-link-exporter.sh
```

Install as a periodic collector with `systemd`:

```bash
sudo install -m 0755 scripts/*.sh /opt/ai-host-observability/
sudo install -m 0644 deploy/systemd/ai-host-observability.service /etc/systemd/system/
sudo install -m 0644 deploy/systemd/ai-host-observability.timer /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now ai-host-observability.timer
```

The timer runs `collect-all.sh` every minute and writes `.prom` files into `/var/lib/node_exporter/textfile_collector` by default.

## Grafana

A starter dashboard lives at `grafana/ai-host-overview.json`. Import it into Grafana and point the panels at your Prometheus data source.

## Testing

Validation steps for WSL and native Linux hosts live in `TESTING.md`.

## Why These Signals Matter

- `fw_pages_total` exposes host-side pinned accounting that guest workloads cannot directly see.
- Memory PSI often rises before the classic OOM path becomes obvious.
- `pgscan*`, `pgsteal*`, `pswpin`, and `pswpout` show reclaim stress building underneath application-level symptoms.
- RDMA/NIC counters help determine whether registration pressure is accompanied by transport-level degradation.
- CPU softirq and IRQ imbalance can reveal networking overhead before throughput visibly drops.
- NUMA imbalance helps explain why topologically poor placement can amplify the cost of multi-HCA traffic.
- Kernel log pattern counts give a compact way to track PCIe, AER, `vfio`, `iommu`, and `mlx5` instability signals.
- GPU BAR1, PCIe link state, ECC, and XID-adjacent signals help compare “host is sick” against “GPU looks fine.”
- Disk, inode, and file-handle pressure help rule out unrelated host resource exhaustion during incident triage.
- Per-process locked-memory snapshots can surface the userspace actors most likely to be contributing pinned-memory pressure.

## Notes

- These scripts are intentionally conservative and dependency-light.
- They are meant as observability helpers, not a replacement for full fleet telemetry.
- Some counters vary by kernel, driver, distro, and NIC generation. Missing files are skipped rather than treated as fatal.
