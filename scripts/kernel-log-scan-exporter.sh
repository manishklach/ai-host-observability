#!/usr/bin/env bash
set -euo pipefail
# shellcheck disable=SC2250,SC2310,SC2312  # Compact conditionals and fallback reads are intentional in exporter code.

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/prom.sh
source "${SCRIPT_DIR}/lib/prom.sh"

PROC_ROOT="${PROC_ROOT:-/proc}"
SYS_ROOT="${SYS_ROOT:-/sys}"
DEBUGFS_ROOT="${DEBUGFS_ROOT:-/sys/kernel/debug}"
RUN_ROOT="${RUN_ROOT:-/run}"
JOURNALCTL="${JOURNALCTL:-journalctl}"
NVIDIA_SMI="${NVIDIA_SMI:-nvidia-smi}"
ETHTOOL="${ETHTOOL:-ethtool}"
DMESG="${DMESG:-dmesg}"

prom_begin_scrape "nixl_kernel_log_scan_success" "Whether the kernel log pattern scanner completed successfully."
if ! require_directory "$PROC_ROOT" "PROC_ROOT"; then
  exit 0
fi
emit_help "nixl_kernel_log_pattern_total" counter "Count of matching kernel log patterns since boot."

tmpfile="$(mktemp)"
trap 'rm -f -- "$tmpfile"' EXIT

if command_exists "$JOURNALCTL"; then
  "$JOURNALCTL" -k -b --no-pager >"$tmpfile" 2>/dev/null || true
elif command_exists "$DMESG"; then
  "$DMESG" >"$tmpfile" 2>/dev/null || true
fi

patterns=(
  "oom|out of memory|oom-kill"
  "aer:|pcie bus error|corrected error|uncorrected error"
  "vfio|vfio-pci"
  "iommu|dma map|dma fault"
  "mlx5|infiniband|rdma"
  "xid|nvrm"
  "NVRM: Xid"
  "NVRM: Xid.*79"
  "NVRM: Xid.*74"
  "NVRM: Xid.*48"
  "NVRM: Xid.*45"
  "nvlink.*error|NVLink.*error"
  "nvlink.*fatal|NVLink.*fatal"
  "nvswitch.*error|NVSwitch.*error"
  "Hardware Exception|GPU Exception"
  "GPU-.*reset|resetting GPU|XID.*reset"
)

names=(
  "oom"
  "pcie_aer"
  "vfio"
  "iommu_dma"
  "rdma_mlx5"
  "gpu_driver"
  "gpu_xid"
  "gpu_xid_79"
  "gpu_xid_74"
  "gpu_xid_48"
  "gpu_xid_45"
  "nvlink_error"
  "nvlink_fatal"
  "nvsw_error"
  "hw_exception"
  "gpu_reset"
)

for idx in "${!patterns[@]}"; do
  count="$(grep -Eic "${patterns[$idx]}" "$tmpfile" || true)"
  emit_metric "nixl_kernel_log_pattern_total" "$count" "pattern=${names[$idx]}"
done

prom_end_scrape "nixl_kernel_log_scan_success"
