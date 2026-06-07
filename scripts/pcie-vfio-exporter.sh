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
INTERESTING_DRIVERS_REGEX="${INTERESTING_DRIVERS_REGEX:-mlx5_core|nvidia|vfio-pci|nvme}"

prom_begin_scrape "nixl_pcie_scrape_success" "Whether the PCIe, VFIO, and IOMMU exporter completed successfully."
if ! require_directory "$PROC_ROOT" "PROC_ROOT"; then
  exit 0
fi

emit_help "nixl_pcie_device_info" gauge "PCIe device metadata for devices bound to interesting drivers."
emit_help "nixl_vfio_group_devices" gauge "Number of devices in each VFIO IOMMU group."
emit_help "nixl_iommu_group_total" gauge "Number of IOMMU groups on the host."
emit_help "nixl_module_loaded" gauge "Whether a selected kernel module is currently loaded."

shopt -s nullglob
for devpath in "${SYS_ROOT}"/bus/pci/devices/*; do
  [[ -d "$devpath" ]] || continue
  bdf="$(basename "$devpath")"
  driver="unbound"
  if [[ -L "$devpath/driver" ]]; then
    driver="$(basename "$(readlink "$devpath/driver")")"
  fi
  [[ "$driver" =~ $INTERESTING_DRIVERS_REGEX ]] || continue

  vendor="$(safe_read_file "$devpath/vendor" || true)"
  device="$(safe_read_file "$devpath/device" || true)"
  numa_node="$(safe_read_file "$devpath/numa_node" || printf '%s' '-1')"
  emit_metric "nixl_pcie_device_info" 1 "bdf=${bdf}" "driver=${driver}" "vendor=${vendor}" "device=${device}" "numa_node=${numa_node}"
done

group_count=0
for grouppath in "${SYS_ROOT}"/kernel/iommu_groups/*; do
  [[ -d "$grouppath" ]] || continue
  group="$(basename "$grouppath")"
  count="$(find "$grouppath/devices" -mindepth 1 -maxdepth 1 2>/dev/null | wc -l | xargs)"
  emit_metric "nixl_vfio_group_devices" "$count" "group=${group}"
  group_count=$((group_count + 1))
done
shopt -u nullglob

emit_metric "nixl_iommu_group_total" "$group_count"

if [[ -r "${PROC_ROOT}/modules" ]]; then
  for module in vfio_pci vfio_iommu_type1 mlx5_core nvidia nvidia_uvm; do
    if grep -q "^${module} " "${PROC_ROOT}/modules"; then
      emit_metric "nixl_module_loaded" 1 "module=${module}"
    else
      emit_metric "nixl_module_loaded" 0 "module=${module}"
    fi
  done
fi

prom_end_scrape "nixl_pcie_scrape_success"
