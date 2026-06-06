#!/usr/bin/env bash
set -euo pipefail

OUT_DIR="${OUT_DIR:-/var/lib/node_exporter/textfile_collector}"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

mkdir -p "$OUT_DIR"

run_exporter() {
  local name="$1"
  local script="$2"
  local tmp="${OUT_DIR}/${name}.prom.$$"
  local final="${OUT_DIR}/${name}.prom"

  "${SCRIPT_DIR}/${script}" >"$tmp"
  mv "$tmp" "$final"
}

run_exporter "nixl_host_mem" "nixl-host-mem-exporter.sh"
run_exporter "nixl_rdma_link" "rdma-link-exporter.sh"
run_exporter "nixl_cpu_irq" "cpu-irq-exporter.sh"
run_exporter "nixl_numa" "numa-exporter.sh"
run_exporter "nixl_kernel_log" "kernel-log-scan-exporter.sh"
run_exporter "nixl_gpu" "gpu-exporter.sh"
run_exporter "nixl_disk" "disk-filesystem-exporter.sh"
run_exporter "nixl_network_stack" "network-stack-exporter.sh"
run_exporter "nixl_process_memory" "process-memory-exporter.sh"
run_exporter "nixl_pcie_vfio" "pcie-vfio-exporter.sh"
