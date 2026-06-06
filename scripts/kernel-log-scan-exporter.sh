#!/usr/bin/env bash
set -euo pipefail

timestamp="$(date +%s)"
tmpfile="$(mktemp)"
trap 'rm -f "$tmpfile"' EXIT

emit_help() {
  local name="$1"
  local type="$2"
  local help="$3"
  printf '# HELP %s %s\n' "$name" "$help"
  printf '# TYPE %s %s\n' "$name" "$type"
}

emit_metric() {
  local name="$1"
  local value="$2"
  local labels="${3:-}"
  if [[ -n "$labels" ]]; then
    printf '%s{%s} %s %s\n' "$name" "$labels" "$value" "$timestamp"
  else
    printf '%s %s %s\n' "$name" "$value" "$timestamp"
  fi
}

if command -v journalctl >/dev/null 2>&1; then
  journalctl -k -b --no-pager >"$tmpfile" 2>/dev/null || true
else
  dmesg >"$tmpfile" 2>/dev/null || true
fi

emit_help "nixl_kernel_log_scan_success" "gauge" "Whether the exporter completed successfully."
emit_metric "nixl_kernel_log_scan_success" "0"

emit_help "nixl_kernel_log_pattern_total" "counter" "Count of matching kernel-log patterns since boot."

patterns=(
  "oom|out of memory|oom-kill"
  "aer:|pcie bus error|corrected error|uncorrected error"
  "vfio|vfio-pci"
  "iommu|dma map|dma fault"
  "mlx5|infiniband|rdma"
  "xid|nvrm"
)

names=(
  "oom"
  "pcie_aer"
  "vfio"
  "iommu_dma"
  "rdma_mlx5"
  "gpu_driver"
)

for i in "${!patterns[@]}"; do
  count="$(grep -Eic "${patterns[$i]}" "$tmpfile" || true)"
  emit_metric "nixl_kernel_log_pattern_total" "$count" "pattern=\"${names[$i]}\""
done

emit_metric "nixl_kernel_log_scan_success" "1"
