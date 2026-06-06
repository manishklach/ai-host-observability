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

to_bytes_from_mib() {
  awk -v v="$1" 'BEGIN { printf "%.0f", v * 1024 * 1024 }'
}

emit_help "nixl_gpu_scrape_success" "gauge" "Whether the GPU exporter completed successfully."
emit_metric "nixl_gpu_scrape_success" "0"

emit_help "nixl_gpu_info" "gauge" "Static GPU metadata keyed by index."
emit_help "nixl_gpu_utilization_percent" "gauge" "GPU utilization percent."
emit_help "nixl_gpu_memory_used_bytes" "gauge" "GPU memory used in bytes."
emit_help "nixl_gpu_memory_total_bytes" "gauge" "GPU memory total in bytes."
emit_help "nixl_gpu_temperature_celsius" "gauge" "GPU temperature in Celsius."
emit_help "nixl_gpu_power_draw_watts" "gauge" "GPU power draw in watts."
emit_help "nixl_gpu_pcie_link_gen" "gauge" "Current PCIe link generation."
emit_help "nixl_gpu_pcie_link_width" "gauge" "Current PCIe link width."
emit_help "nixl_gpu_ecc_volatile_total" "counter" "Volatile ECC error count when available."
emit_help "nixl_gpu_bar1_used_bytes" "gauge" "BAR1 memory used in bytes when available."
emit_help "nixl_gpu_bar1_total_bytes" "gauge" "BAR1 memory total in bytes when available."

if command -v nvidia-smi >/dev/null 2>&1; then
  query="index,uuid,name,pci.bus_id,utilization.gpu,memory.used,memory.total,temperature.gpu,power.draw,pcie.link.gen.current,pcie.link.width.current,ecc.errors.volatile.total,bar1_memory.used,bar1_memory.total"
  nvidia-smi --query-gpu="$query" --format=csv,noheader,nounits 2>/dev/null | \
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

    emit_metric "nixl_gpu_info" "1" "index=\"$index\",uuid=\"$uuid\",name=\"$name\",pci_bus=\"$pci_bus\""
    [[ "$util" =~ ^[0-9]+([.][0-9]+)?$ ]] && emit_metric "nixl_gpu_utilization_percent" "$util" "index=\"$index\",uuid=\"$uuid\""
    [[ "$mem_used" =~ ^[0-9]+([.][0-9]+)?$ ]] && emit_metric "nixl_gpu_memory_used_bytes" "$(to_bytes_from_mib "$mem_used")" "index=\"$index\",uuid=\"$uuid\""
    [[ "$mem_total" =~ ^[0-9]+([.][0-9]+)?$ ]] && emit_metric "nixl_gpu_memory_total_bytes" "$(to_bytes_from_mib "$mem_total")" "index=\"$index\",uuid=\"$uuid\""
    [[ "$temp" =~ ^[0-9]+([.][0-9]+)?$ ]] && emit_metric "nixl_gpu_temperature_celsius" "$temp" "index=\"$index\",uuid=\"$uuid\""
    [[ "$power" =~ ^[0-9]+([.][0-9]+)?$ ]] && emit_metric "nixl_gpu_power_draw_watts" "$power" "index=\"$index\",uuid=\"$uuid\""
    [[ "$gen" =~ ^[0-9]+([.][0-9]+)?$ ]] && emit_metric "nixl_gpu_pcie_link_gen" "$gen" "index=\"$index\",uuid=\"$uuid\""
    [[ "$width" =~ ^[0-9]+([.][0-9]+)?$ ]] && emit_metric "nixl_gpu_pcie_link_width" "$width" "index=\"$index\",uuid=\"$uuid\""
    [[ "$ecc" =~ ^[0-9]+$ ]] && emit_metric "nixl_gpu_ecc_volatile_total" "$ecc" "index=\"$index\",uuid=\"$uuid\""
    [[ "$bar1_used" =~ ^[0-9]+([.][0-9]+)?$ ]] && emit_metric "nixl_gpu_bar1_used_bytes" "$(to_bytes_from_mib "$bar1_used")" "index=\"$index\",uuid=\"$uuid\""
    [[ "$bar1_total" =~ ^[0-9]+([.][0-9]+)?$ ]] && emit_metric "nixl_gpu_bar1_total_bytes" "$(to_bytes_from_mib "$bar1_total")" "index=\"$index\",uuid=\"$uuid\""
  done
fi

emit_metric "nixl_gpu_scrape_success" "1"
