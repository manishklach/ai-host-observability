# Testing

This repo is designed for Linux hosts, but it can be partially validated from Windows using WSL.

## Install Bats

`bats-core` is the supported test runner for this repo.

Ubuntu / Debian:

```bash
sudo apt-get update
sudo apt-get install -y bats
```

macOS:

```bash
brew install bats-core
```

## What Was Verified in WSL

Using `Ubuntu-24.04` in WSL:

- All shell scripts passed `bash -n`
- `collect-all.sh` ran successfully with a writable `OUT_DIR`
- All expected `.prom` files were generated
- Exporters degraded cleanly when GPUs, RDMA devices, or VFIO-related modules were not present

## WSL Validation Commands

Syntax-check all scripts:

```bash
cd /mnt/c/Users/ManishKL/Documents/Playground/ai-host-observability
find scripts -name '*.sh' -print0 | xargs -0 -n1 bash -n
```

Run the full collector into a temporary output directory:

```bash
cd /mnt/c/Users/ManishKL/Documents/Playground/ai-host-observability
OUT_DIR=/tmp/ai-host-observability-prom bash scripts/collect-all.sh
ls -1 /tmp/ai-host-observability-prom
```

Inspect a few outputs:

```bash
sed -n '1,30p' /tmp/ai-host-observability-prom/nixl_host_mem.prom
sed -n '1,20p' /tmp/ai-host-observability-prom/nixl_gpu.prom
sed -n '1,25p' /tmp/ai-host-observability-prom/nixl_rdma_link.prom
tail -n 5 /tmp/ai-host-observability-prom/nixl_pcie_vfio.prom
```

## Native Linux Validation

On a real Linux host, run the same syntax checks:

```bash
cd /path/to/ai-host-observability
find scripts -name '*.sh' -print0 | xargs -0 -n1 bash -n
```

Run the collector manually:

```bash
cd /path/to/ai-host-observability
OUT_DIR=/tmp/ai-host-observability-prom bash scripts/collect-all.sh
ls -1 /tmp/ai-host-observability-prom
```

Run the bats test suite:

```bash
make test-bats
```

## Deployment Validation

If using `node_exporter` textfile collection:

```bash
sudo mkdir -p /var/lib/node_exporter/textfile_collector
sudo OUT_DIR=/var/lib/node_exporter/textfile_collector bash scripts/collect-all.sh
ls -1 /var/lib/node_exporter/textfile_collector
```

If using the provided `systemd` timer:

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now ai-host-observability.timer
systemctl status ai-host-observability.timer
systemctl status ai-host-observability.service
```

## Things to Check on Real Hardware

- `nixl_host_fw_pages_total` populates when `mlx5` debugfs counters are available
- GPU metrics populate when `nvidia-smi` is installed and GPUs are visible
- RDMA/InfiniBand counters populate on hosts with relevant devices
- Kernel log counters reflect real host events from `journalctl -k -b`
- `.prom` files are readable by Prometheus or `node_exporter`

## Notes

- `collect-all.sh` defaults to `/var/lib/node_exporter/textfile_collector`, which may require root privileges.
- Hardware-specific exporters are expected to emit help text and a success metric even when the hardware is absent.
