#!/usr/bin/env bash
set -euo pipefail

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

to_bytes_from_mib() {
  awk -v value="$1" 'BEGIN { printf "%.0f", value * 1024 * 1024 }'
}

prom_begin_scrape "nixl_gpu_scrape_success" "Whether the GPU exporter completed successfully."

emit_help "nixl_gpu_info" gauge "Static GPU metadata keyed by index."
emit_help "nixl_gpu_utilization_percent" gauge "GPU utilization percent."
emit_help "nixl_gpu_memory_used_bytes" gauge "GPU memory used in bytes."
emit_help "nixl_gpu_memory_total_bytes" gauge "GPU memory total in bytes."
emit_help "nixl_gpu_temperature_celsius" gauge "GPU temperature in Celsius."
emit_help "nixl_gpu_power_draw_watts" gauge "GPU power draw in watts."
emit_help "nixl_gpu_pcie_link_gen" gauge "Current PCIe link generation."
emit_help "nixl_gpu_pcie_link_width" gauge "Current PCIe link width."
emit_help "nixl_gpu_ecc_volatile_total" counter "Volatile ECC error count when available."
emit_help "nixl_gpu_bar1_used_bytes" gauge "BAR1 memory used in bytes when available."
emit_help "nixl_gpu_bar1_total_bytes" gauge "BAR1 memory total in bytes when available."

if command_exists "$NVIDIA_SMI"; then
  query="index,uuid,name,pci.bus_id,utilization.gpu,memory.used,memory.total,temperature.gpu,power.draw,pcie.link.gen.current,pcie.link.width.current,ecc.errors.volatile.total,bar1_memory.used,bar1_memory.total"
  while IFS=',' read -r index uuid name pci_bus util mem_used mem_total temp power gen width ecc bar1_used bar1_total; do
    index="$(xargs <<<"$index")"
    uuid="$(xargs <<<"$uuid")"
    name="$(xargs <<<"$name")"
    pci_bus="$(xargs <<<"$pci_bus")"
    util="$(xargs <<<"$util")"
    mem_used="$(xargs <<<"$mem_used")"
    mem_total="$(xargs <<<"$mem_total")"
    temp="$(xargs <<<"$temp")"
    power="$(xargs <<<"$power")"
    gen="$(xargs <<<"$gen")"
    width="$(xargs <<<"$width")"
    ecc="$(xargs <<<"$ecc")"
    bar1_used="$(xargs <<<"$bar1_used")"
    bar1_total="$(xargs <<<"$bar1_total")"

    emit_metric "nixl_gpu_info" 1 "index=${index}" "uuid=${uuid}" "name=${name}" "pci_bus=${pci_bus}"
    is_number "$util" && emit_metric "nixl_gpu_utilization_percent" "$util" "index=${index}" "uuid=${uuid}"
    is_number "$mem_used" && emit_metric "nixl_gpu_memory_used_bytes" "$(to_bytes_from_mib "$mem_used")" "index=${index}" "uuid=${uuid}"
    is_number "$mem_total" && emit_metric "nixl_gpu_memory_total_bytes" "$(to_bytes_from_mib "$mem_total")" "index=${index}" "uuid=${uuid}"
    is_number "$temp" && emit_metric "nixl_gpu_temperature_celsius" "$temp" "index=${index}" "uuid=${uuid}"
    is_number "$power" && emit_metric "nixl_gpu_power_draw_watts" "$power" "index=${index}" "uuid=${uuid}"
    is_number "$gen" && emit_metric "nixl_gpu_pcie_link_gen" "$gen" "index=${index}" "uuid=${uuid}"
    is_number "$width" && emit_metric "nixl_gpu_pcie_link_width" "$width" "index=${index}" "uuid=${uuid}"
    is_integer "$ecc" && emit_metric "nixl_gpu_ecc_volatile_total" "$ecc" "index=${index}" "uuid=${uuid}"
    is_number "$bar1_used" && emit_metric "nixl_gpu_bar1_used_bytes" "$(to_bytes_from_mib "$bar1_used")" "index=${index}" "uuid=${uuid}"
    is_number "$bar1_total" && emit_metric "nixl_gpu_bar1_total_bytes" "$(to_bytes_from_mib "$bar1_total")" "index=${index}" "uuid=${uuid}"
  done < <("$NVIDIA_SMI" --query-gpu="$query" --format=csv,noheader,nounits 2>/dev/null || true)
fi

prom_end_scrape
