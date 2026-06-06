#!/usr/bin/env bash
set -euo pipefail

# Export host-side memory pressure signals that are useful for diagnosing
# guest-driven RDMA registration blowups such as multi-HCA NIXL/UCX fan-out.

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

emit_help "nixl_host_scrape_success" "gauge" "Whether the exporter completed successfully."
emit_metric "nixl_host_scrape_success" "0"

emit_help "nixl_host_fw_pages_total" "gauge" "mlx5 firmware pages currently allocated per device."
emit_help "nixl_host_fw_pages_devices" "gauge" "Number of mlx5 devices with fw_pages_total available."

fw_total=0
fw_devices=0
shopt -s nullglob
for path in /sys/kernel/debug/mlx5/*/pages/fw_pages_total; do
  dev="$(basename "$(dirname "$(dirname "$path")")")"
  value="$(<"$path")"
  emit_metric "nixl_host_fw_pages_total" "$value" "device=\"$dev\""
  fw_total=$((fw_total + value))
  fw_devices=$((fw_devices + 1))
done
shopt -u nullglob

emit_help "nixl_host_fw_pages_sum" "gauge" "Sum of mlx5 firmware pages across all visible devices."
emit_metric "nixl_host_fw_pages_sum" "$fw_total"
emit_metric "nixl_host_fw_pages_devices" "$fw_devices"

emit_help "nixl_host_meminfo_bytes" "gauge" "Selected /proc/meminfo values converted to bytes."
while read -r key value unit; do
  case "$key" in
    MemAvailable:|MemFree:|SwapFree:|Buffers:|Cached:)
      metric_key="$(tr '[:upper:]' '[:lower:]' <<<"${key%:}")"
      emit_metric "nixl_host_meminfo_bytes" "$((value * 1024))" "field=\"$metric_key\""
      ;;
  esac
done < /proc/meminfo

emit_help "nixl_host_memory_psi_avg" "gauge" "Memory PSI rolling averages from /proc/pressure/memory."
emit_help "nixl_host_memory_psi_total" "counter" "Memory PSI total stall time in microseconds."
while read -r scope rest; do
  avg10=""
  avg60=""
  avg300=""
  total=""
  for token in $rest; do
    case "$token" in
      avg10=*) avg10="${token#avg10=}" ;;
      avg60=*) avg60="${token#avg60=}" ;;
      avg300=*) avg300="${token#avg300=}" ;;
      total=*) total="${token#total=}" ;;
    esac
  done
  emit_metric "nixl_host_memory_psi_avg" "$avg10" "scope=\"$scope\",window=\"10s\""
  emit_metric "nixl_host_memory_psi_avg" "$avg60" "scope=\"$scope\",window=\"60s\""
  emit_metric "nixl_host_memory_psi_avg" "$avg300" "scope=\"$scope\",window=\"300s\""
  emit_metric "nixl_host_memory_psi_total" "$total" "scope=\"$scope\""
done < /proc/pressure/memory

emit_help "nixl_host_vmstat" "counter" "Selected memory-pressure counters from /proc/vmstat."
while read -r key value; do
  case "$key" in
    pgscan_kswapd|pgscan_direct|pgsteal_kswapd|pgsteal_direct|pswpin|pswpout)
      emit_metric "nixl_host_vmstat" "$value" "field=\"$key\""
      ;;
  esac
done < /proc/vmstat

if [[ -n "${CGROUP_PATH:-}" && -d "${CGROUP_PATH:-}" ]]; then
  emit_help "nixl_host_cgroup_memory_current_bytes" "gauge" "memory.current for the configured cgroup path."
  emit_help "nixl_host_cgroup_memory_events" "counter" "Selected memory.events counters for the configured cgroup path."
  emit_help "nixl_host_cgroup_memory_pressure_avg" "gauge" "Memory PSI rolling averages for the configured cgroup path."
  emit_help "nixl_host_cgroup_memory_pressure_total" "counter" "Memory PSI total stall time in microseconds for the configured cgroup path."

  if [[ -f "${CGROUP_PATH}/memory.current" ]]; then
    emit_metric "nixl_host_cgroup_memory_current_bytes" "$(<"${CGROUP_PATH}/memory.current")" "path=\"${CGROUP_PATH}\""
  fi

  if [[ -f "${CGROUP_PATH}/memory.events" ]]; then
    while read -r key value; do
      case "$key" in
        low|high|max|oom|oom_kill)
          emit_metric "nixl_host_cgroup_memory_events" "$value" "path=\"${CGROUP_PATH}\",event=\"$key\""
          ;;
      esac
    done < "${CGROUP_PATH}/memory.events"
  fi

  if [[ -f "${CGROUP_PATH}/memory.pressure" ]]; then
    while read -r scope rest; do
      avg10=""
      avg60=""
      avg300=""
      total=""
      for token in $rest; do
        case "$token" in
          avg10=*) avg10="${token#avg10=}" ;;
          avg60=*) avg60="${token#avg60=}" ;;
          avg300=*) avg300="${token#avg300=}" ;;
          total=*) total="${token#total=}" ;;
        esac
      done
      emit_metric "nixl_host_cgroup_memory_pressure_avg" "$avg10" "path=\"${CGROUP_PATH}\",scope=\"$scope\",window=\"10s\""
      emit_metric "nixl_host_cgroup_memory_pressure_avg" "$avg60" "path=\"${CGROUP_PATH}\",scope=\"$scope\",window=\"60s\""
      emit_metric "nixl_host_cgroup_memory_pressure_avg" "$avg300" "path=\"${CGROUP_PATH}\",scope=\"$scope\",window=\"300s\""
      emit_metric "nixl_host_cgroup_memory_pressure_total" "$total" "path=\"${CGROUP_PATH}\",scope=\"$scope\""
    done < "${CGROUP_PATH}/memory.pressure"
  fi
fi

emit_metric "nixl_host_scrape_success" "1"
