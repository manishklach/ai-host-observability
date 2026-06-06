#!/usr/bin/env bash
set -euo pipefail

timestamp="$(date +%s)"

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

emit_help "nixl_pcie_scrape_success" "gauge" "Whether the PCIe/VFIO exporter completed successfully."
emit_metric "nixl_pcie_scrape_success" "0"

emit_help "nixl_pcie_device_info" "gauge" "PCIe device metadata for devices bound to interesting drivers."
emit_help "nixl_vfio_group_devices" "gauge" "Number of devices in each VFIO IOMMU group."
emit_help "nixl_iommu_group_total" "gauge" "Number of IOMMU groups on the host."

interesting_drivers_regex="${INTERESTING_DRIVERS_REGEX:-mlx5_core|nvidia|vfio-pci|nvme}"

shopt -s nullglob
for devpath in /sys/bus/pci/devices/*; do
  bdf="$(basename "$devpath")"
  driver="unbound"
  [[ -L "$devpath/driver" ]] && driver="$(basename "$(readlink "$devpath/driver")")"
  [[ "$driver" =~ $interesting_drivers_regex ]] || continue

  vendor="$(<"$devpath/vendor")"
  device="$(<"$devpath/device")"
  numa_node="-1"
  [[ -f "$devpath/numa_node" ]] && numa_node="$(<"$devpath/numa_node")"
  emit_metric "nixl_pcie_device_info" "1" "bdf=\"$bdf\",driver=\"$driver\",vendor=\"$vendor\",device=\"$device\",numa_node=\"$numa_node\""
done

group_count=0
for grouppath in /sys/kernel/iommu_groups/*; do
  [[ -d "$grouppath" ]] || continue
  group="$(basename "$grouppath")"
  count="$(find "$grouppath/devices" -mindepth 1 -maxdepth 1 | wc -l)"
  emit_metric "nixl_vfio_group_devices" "$count" "group=\"$group\""
  group_count=$((group_count + 1))
done
shopt -u nullglob
emit_metric "nixl_iommu_group_total" "$group_count"

emit_help "nixl_module_loaded" "gauge" "Whether a selected kernel module is currently loaded."
for module in vfio_pci vfio_iommu_type1 mlx5_core nvidia nvidia_uvm; do
  if grep -q "^${module} " /proc/modules 2>/dev/null; then
    emit_metric "nixl_module_loaded" "1" "module=\"$module\""
  else
    emit_metric "nixl_module_loaded" "0" "module=\"$module\""
  fi
done

emit_metric "nixl_pcie_scrape_success" "1"
