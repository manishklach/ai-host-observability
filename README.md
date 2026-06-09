# AI Host Observability

[![CI](https://github.com/manishklach/ai-host-observability/actions/workflows/ci.yml/badge.svg)](https://github.com/manishklach/ai-host-observability/actions/workflows/ci.yml)
[![Grafana Dashboard](https://img.shields.io/badge/Grafana-dashboard-F46800?logo=grafana&logoColor=white)](grafana/ai-host-overview.json)

Prometheus-friendly Linux host observability for AI and GPU infrastructure, built for the pressure signals that show up between the GPU, NIC, PCIe, VFIO, and the host kernel.

AI and GPU servers often fail on the host side before the GPU looks unhealthy. Hidden pressure can build in memory reclaim, PSI, RDMA registration footprint, IRQ load, BAR1 usage, cgroup growth, or kernel log patterns while GPU HBM still looks fine.

This repo focuses on that seam layer: the host-side failure modes that DCGM and generic `node_exporter` setups do not always emphasize out of the box. For the positioning and tradeoffs, see [Why not just use DCGM or node_exporter?](docs/why-not-dcgm-or-node-exporter.md).

It is intentionally lightweight: shell collectors, systemd scheduling, Prometheus textfile output, and docs that help operators debug the host side before they end up blaming the GPU for the wrong problem.

## Collection Architecture

```mermaid
flowchart LR
  A["Linux host surfaces"] --> B["Exporter scripts"]
  A1["/proc"] --> B
  A2["/sys + debugfs + trace-adjacent surfaces"] --> B
  A3["journalctl / dmesg"] --> B
  A4["nvidia-smi / ethtool"] --> B
  B --> C["collect-all.sh"]
  C --> D["node_exporter textfile collector"]
  D --> E["Prometheus"]
  E --> F["Grafana / alerts / runbooks"]
```

## What It Monitors

- host memory pressure from `/proc/meminfo`
- memory and CPU PSI from `/proc/pressure/*`
- reclaim and swap counters from `/proc/vmstat`
- `mlx5` `fw_pages_total` from debugfs
- hardware memory errors from EDAC, rasdaemon, and `mcelog`
- cgroup v2 memory current, events, and pressure
- RDMA / InfiniBand counters
- selected `ethtool -S` counters
- softirq and selected IRQ counters
- CPU thermal throttling and package frequency stability
- NUMA memory and hit/miss counters
- kernel log patterns for OOM, PCIe/AER, VFIO, IOMMU, RDMA, GPU XID, watchdog, soft lockup, and RCU stall events
- NVIDIA GPU telemetry through `nvidia-smi`
- GPU throttle reasons, P-state, and NVLink fabric health
- GPU memory fragmentation, retired pages, remapped rows, and per-process HBM footprint
- disk/filesystem pressure
- generic `/proc/net` network stack counters
- TCP flow classes, retransmit pressure, and interface utilization ratios
- per-process locked memory
- hugepage inventory and THP fallback behavior
- NTP and chrony synchronisation and offset health
- PCIe/VFIO/IOMMU visibility
- tracefs event inventory and perf/profiling readiness
- training heartbeat, checkpoint freshness, and job stall suspicion
- exporter self-telemetry and collection pipeline health
- host drift facts for kernel, driver, BIOS, sysctl, and ulimit consistency checks
- host-local anomaly baselines and Prometheus long-term recording rules

## Quick Triage Workflow

1. Check `nixl_host_meminfo_bytes{field="memavailable"}` and `nixl_host_memory_psi_avg`.
2. Check `nixl_host_fw_pages_sum` for hidden RDMA registration growth.
3. Compare GPU HBM and BAR1 signals against host memory pressure.
4. Inspect softnet drops, IRQ load, and NIC/RDMA errors.
5. Correlate with kernel log pattern counters.

## Start Here If You Are Debugging An Incident

- [Host memory pressure runbook](docs/runbooks/host-memory-pressure.md)
- [RDMA registration growth runbook](docs/runbooks/rdma-registration-growth.md)
- [GPU looks fine, host is sick demo and walkthrough](docs/demos/host-oom-before-gpu-oom.md)

## Install

### Requirements

- Linux host
- Bash
- `node_exporter` textfile collector
- `journalctl` recommended
- `ethtool` recommended
- `nvidia-smi` optional
- `debugfs` mounted if you want `fw_pages_total`

### Quick Install From A Release Tarball

```bash
# Latest tagged release
VERSION=v0.3.0
curl -fsSL "https://github.com/manishklach/ai-host-observability/releases/download/${VERSION}/ai-host-observability-${VERSION#v}.tar.gz" \
  | tar xz
cd "ai-host-observability-${VERSION#v}"
sudo make install
sudo systemctl daemon-reload
sudo systemctl enable --now ai-host-observability.timer
```

### Manual Install

```bash
git clone https://github.com/manishklach/ai-host-observability.git
cd ai-host-observability
make test
sudo make install
sudo systemctl daemon-reload
sudo systemctl enable --now ai-host-observability.timer
```

### node_exporter Textfile Collector

Make sure `node_exporter` is started with a textfile collector directory such as:

```bash
--collector.textfile.directory=/var/lib/node_exporter/textfile_collector
```

Run the collector manually:

```bash
OUT_DIR=/var/lib/node_exporter/textfile_collector bash scripts/collect-all.sh
```

### systemd Timer

The timer runs every minute and writes `.prom` files into `/var/lib/node_exporter/textfile_collector` by default.

```bash
sudo systemctl status ai-host-observability.timer
sudo systemctl status ai-host-observability.service
```

### Container / Kubernetes

For containerized deployments, the repo includes both a local `docker-compose` path and a Kubernetes DaemonSet path.

Docker Compose:

```bash
cd deploy/docker
docker compose up --build
```

This starts the collector with host `/proc` and `/sys` mounted read-only, writes `.prom` files into a shared volume, and points a bundled `node-exporter` instance at that textfile collector directory.

Kubernetes:

```bash
kubectl apply -f deploy/kubernetes/rbac.yaml
kubectl apply -f deploy/kubernetes/daemonset.yaml
```

The DaemonSet runs one collector pod per node in the `monitoring` namespace, mounts host `/proc`, `/sys`, and `/var/lib/node_exporter/textfile_collector`, and uses a liveness probe to catch stalled collection loops.

### Prometheus

Prometheus scrapes `node_exporter`; this repo does not expose its own HTTP server. Import the alert rules from `prometheus/alerts.yml`.

## Grafana

Import `grafana/ai-host-overview.json` for the broad host view and `grafana/ai-host-anomaly.json` for anomaly detection, job heartbeat, long-term trends, and collection pipeline health.

## Sample Metrics

```text
nixl_host_fw_pages_sum 1234 1710000000
nixl_host_meminfo_bytes{field="memavailable"} 2147483648 1710000000
nixl_gpu_bar1_used_bytes{index="0",uuid="GPU-123"} 536870912 1710000000
ai_host_exporter_last_run_success{exporter="nixl_host_mem"} 1 1710000000
```

More realistic textfile examples live in [examples/sample-output](examples/sample-output).

## Tested Environments

- WSL `Ubuntu-24.04` for syntax and fixture-backed tests
- generic Linux hosts without requiring RDMA or GPU hardware for CI

## Limitations

- hardware-specific metrics remain absent when the hardware is absent
- some counters depend on kernel, driver, and firmware support
- PCIe and VFIO depth is intentionally lightweight and log-oriented
- this is a textfile collector toolkit, not a long-running agent

## Optional Dependencies

- `shellcheck` for linting
- `jq` for dashboard validation and formatting
- `systemd-analyze` for unit validation
- `shfmt` for shell formatting

## Documentation

- [Metrics contract](docs/metrics.md)
- [Operations guide](docs/ops-guide.md)
- [Runbooks](docs/runbooks)
- [Incident demo: GPU looks fine, host is dying](docs/demos/host-oom-before-gpu-oom.md)
- [Why not just use DCGM or node_exporter?](docs/why-not-dcgm-or-node-exporter.md)
- [Sample Prometheus outputs](examples/sample-output)
- [Kernel debugging guide](KERNEL_DEBUGGING.md)
- [Release process](RELEASE.md)
- [Testing guide](TESTING.md)
- [Signal cheat sheet](docs/signals.md)
