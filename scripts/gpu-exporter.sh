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

to_bytes_from_mib() {
  awk -v value="$1" 'BEGIN { printf "%.0f", value * 1024 * 1024 }'
}

prom_begin_scrape "nixl_gpu_scrape_success" "Whether the GPU exporter completed successfully."
if ! require_directory "$PROC_ROOT" "PROC_ROOT"; then
  exit 0
fi

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
emit_help "nixl_gpu_throttle_reason" gauge "GPU throttle reason activity flags."
emit_help "nixl_gpu_pstate" gauge "Current GPU performance state label."
emit_help "nixl_gpu_power_limit_watts" gauge "Configured GPU power limit in watts."
emit_help "nixl_gpu_power_enforced_limit_watts" gauge "Enforced GPU power limit in watts."
emit_help "nixl_gpu_clock_sm_mhz" gauge "Current SM clock in MHz."
emit_help "nixl_gpu_clock_mem_mhz" gauge "Current memory clock in MHz."
emit_help "nixl_gpu_clock_max_sm_mhz" gauge "Maximum rated SM clock in MHz."
emit_help "nixl_gpu_clock_max_mem_mhz" gauge "Maximum rated memory clock in MHz."
emit_help "nixl_gpu_fan_speed_percent" gauge "GPU fan speed in percent when available."

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

    emit_metric "nixl_gpu_info" 1 "vendor=nvidia" "index=${index}" "uuid=${uuid}" "name=${name}" "pci_bus=${pci_bus}"
    is_number "$util" && emit_metric "nixl_gpu_utilization_percent" "$util" "vendor=nvidia" "index=${index}" "uuid=${uuid}"
    is_number "$mem_used" && emit_metric "nixl_gpu_memory_used_bytes" "$(to_bytes_from_mib "$mem_used")" "vendor=nvidia" "index=${index}" "uuid=${uuid}"
    is_number "$mem_total" && emit_metric "nixl_gpu_memory_total_bytes" "$(to_bytes_from_mib "$mem_total")" "vendor=nvidia" "index=${index}" "uuid=${uuid}"
    is_number "$temp" && emit_metric "nixl_gpu_temperature_celsius" "$temp" "vendor=nvidia" "index=${index}" "uuid=${uuid}"
    is_number "$power" && emit_metric "nixl_gpu_power_draw_watts" "$power" "vendor=nvidia" "index=${index}" "uuid=${uuid}"
    is_number "$gen" && emit_metric "nixl_gpu_pcie_link_gen" "$gen" "vendor=nvidia" "index=${index}" "uuid=${uuid}"
    is_number "$width" && emit_metric "nixl_gpu_pcie_link_width" "$width" "vendor=nvidia" "index=${index}" "uuid=${uuid}"
    is_integer "$ecc" && emit_metric "nixl_gpu_ecc_volatile_total" "$ecc" "vendor=nvidia" "index=${index}" "uuid=${uuid}"
    is_number "$bar1_used" && emit_metric "nixl_gpu_bar1_used_bytes" "$(to_bytes_from_mib "$bar1_used")" "vendor=nvidia" "index=${index}" "uuid=${uuid}"
    is_number "$bar1_total" && emit_metric "nixl_gpu_bar1_total_bytes" "$(to_bytes_from_mib "$bar1_total")" "vendor=nvidia" "index=${index}" "uuid=${uuid}"
  done < <("$NVIDIA_SMI" --query-gpu="$query" --format=csv,noheader,nounits 2>/dev/null || true)

  throttle_query="index,uuid,clocks_event_reasons.gpu_idle,clocks_event_reasons.applications_clocks_setting,clocks_event_reasons.sw_power_cap,clocks_event_reasons.hw_slowdown,clocks_event_reasons.hw_thermal_slowdown,clocks_event_reasons.hw_power_brake_slowdown,clocks_event_reasons.sync_boost,clocks_event_reasons.sw_thermal_slowdown,clocks_event_reasons.display_clocks_setting"
  while IFS=',' read -r index uuid gpu_idle app_clocks sw_power_cap hw_slowdown hw_thermal hw_power_brake sync_boost sw_thermal display_clocks; do
    index="$(xargs <<<"$index")"
    uuid="$(xargs <<<"$uuid")"
    for reason_name in \
      "gpu_idle:${gpu_idle}" \
      "applications_clocks_setting:${app_clocks}" \
      "sw_power_cap:${sw_power_cap}" \
      "hw_slowdown:${hw_slowdown}" \
      "hw_thermal_slowdown:${hw_thermal}" \
      "hw_power_brake_slowdown:${hw_power_brake}" \
      "sync_boost:${sync_boost}" \
      "sw_thermal_slowdown:${sw_thermal}" \
      "display_clocks_setting:${display_clocks}"; do
      reason="${reason_name%%:*}"
      state_raw="${reason_name#*:}"
      state="$(tr '[:upper:]' '[:lower:]' <<<"$(xargs <<<"$state_raw")")"
      value=0
      [[ "${state}" == "active" ]] && value=1
      emit_metric "nixl_gpu_throttle_reason" "${value}" "index=${index}" "uuid=${uuid}" "reason=${reason}"
    done
  done < <("$NVIDIA_SMI" --query-gpu="$throttle_query" --format=csv,noheader,nounits 2>/dev/null || true)

  while IFS=',' read -r index uuid pstate; do
    index="$(xargs <<<"$index")"
    uuid="$(xargs <<<"$uuid")"
    pstate="$(xargs <<<"$pstate")"
    [[ -n "${pstate}" ]] && emit_metric "nixl_gpu_pstate" 1 "index=${index}" "uuid=${uuid}" "pstate=${pstate}"
  done < <("$NVIDIA_SMI" --query-gpu=index,uuid,pstate --format=csv,noheader,nounits 2>/dev/null || true)

  while IFS=',' read -r index uuid power_limit enforced_limit sm_clock mem_clock max_sm_clock max_mem_clock fan_speed; do
    index="$(xargs <<<"$index")"
    uuid="$(xargs <<<"$uuid")"
    power_limit="$(xargs <<<"$power_limit")"
    enforced_limit="$(xargs <<<"$enforced_limit")"
    sm_clock="$(xargs <<<"$sm_clock")"
    mem_clock="$(xargs <<<"$mem_clock")"
    max_sm_clock="$(xargs <<<"$max_sm_clock")"
    max_mem_clock="$(xargs <<<"$max_mem_clock")"
    fan_speed="$(xargs <<<"$fan_speed")"

    is_number "$power_limit" && emit_metric "nixl_gpu_power_limit_watts" "$power_limit" "index=${index}" "uuid=${uuid}"
    is_number "$enforced_limit" && emit_metric "nixl_gpu_power_enforced_limit_watts" "$enforced_limit" "index=${index}" "uuid=${uuid}"
    is_number "$sm_clock" && emit_metric "nixl_gpu_clock_sm_mhz" "$sm_clock" "index=${index}" "uuid=${uuid}"
    is_number "$mem_clock" && emit_metric "nixl_gpu_clock_mem_mhz" "$mem_clock" "index=${index}" "uuid=${uuid}"
    is_number "$max_sm_clock" && emit_metric "nixl_gpu_clock_max_sm_mhz" "$max_sm_clock" "index=${index}" "uuid=${uuid}"
    is_number "$max_mem_clock" && emit_metric "nixl_gpu_clock_max_mem_mhz" "$max_mem_clock" "index=${index}" "uuid=${uuid}"
    fan_speed="${fan_speed%\%}"
    fan_speed="$(xargs <<<"$fan_speed")"
    is_number "$fan_speed" && emit_metric "nixl_gpu_fan_speed_percent" "$fan_speed" "index=${index}" "uuid=${uuid}"
  done < <("$NVIDIA_SMI" --query-gpu=index,uuid,power.limit,enforced.power.limit,clocks.sm,clocks.mem,clocks.max.sm,clocks.max.mem,fan.speed --format=csv,noheader,nounits 2>/dev/null || true)
fi

prom_end_scrape "nixl_gpu_scrape_success"
