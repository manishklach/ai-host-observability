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

emit_psi_metrics() {
  local path="$1"
  local avg_metric="$2"
  local total_metric="$3"
  local -a extra_labels=("${@:4}")

  [[ -r "$path" ]] || return 0

  while read -r scope rest; do
    local avg10="" avg60="" avg300="" total="" token
    for token in $rest; do
      case "$token" in
        avg10=*) avg10="${token#avg10=}" ;;
        avg60=*) avg60="${token#avg60=}" ;;
        avg300=*) avg300="${token#avg300=}" ;;
        total=*) total="${token#total=}" ;;
      esac
    done
    is_number "$avg10" && emit_metric "$avg_metric" "$avg10" "${extra_labels[@]}" "scope=${scope}" "window=10s"
    is_number "$avg60" && emit_metric "$avg_metric" "$avg60" "${extra_labels[@]}" "scope=${scope}" "window=60s"
    is_number "$avg300" && emit_metric "$avg_metric" "$avg300" "${extra_labels[@]}" "scope=${scope}" "window=300s"
    is_integer "$total" && emit_metric "$total_metric" "$total" "${extra_labels[@]}" "scope=${scope}"
  done <"$path"

  return 0
}

prom_begin_scrape "nixl_host_scrape_success" "Whether the host memory exporter completed successfully."
if ! require_directory "$PROC_ROOT" "PROC_ROOT"; then
  exit 0
fi

emit_help "nixl_host_fw_pages_total" gauge "mlx5 firmware pages currently allocated per device."
emit_help "nixl_host_fw_pages_devices" gauge "Number of mlx5 devices with fw_pages_total available."
emit_help "nixl_host_fw_pages_sum" gauge "Sum of mlx5 firmware pages across all visible devices."

fw_total=0
fw_devices=0
shopt -s nullglob
for path in "${DEBUGFS_ROOT}"/mlx5/*/pages/fw_pages_total; do
  value="$(safe_read_file "$path" || true)"
  dev="$(basename "$(dirname "$(dirname "$path")")")"
  if is_integer "$value"; then
    emit_metric "nixl_host_fw_pages_total" "$value" "device=${dev}"
    fw_total=$((fw_total + value))
    fw_devices=$((fw_devices + 1))
  fi
done
shopt -u nullglob

emit_metric "nixl_host_fw_pages_sum" "$fw_total"
emit_metric "nixl_host_fw_pages_devices" "$fw_devices"

emit_help "nixl_host_meminfo_bytes" gauge "Selected ${PROC_ROOT}/meminfo values converted to bytes."
if [[ -r "${PROC_ROOT}/meminfo" ]]; then
  while read -r key value _unit; do
    case "$key" in
      MemAvailable:|MemFree:|SwapFree:|Buffers:|Cached:)
        if is_integer "$value"; then
          emit_metric "nixl_host_meminfo_bytes" "$((value * 1024))" "field=$(tr '[:upper:]' '[:lower:]' <<<"${key%:}")"
        fi
        ;;
    esac
  done <"${PROC_ROOT}/meminfo"
fi

emit_help "nixl_host_uptime_seconds" gauge "Host uptime in seconds from /proc/uptime."
emit_help "nixl_host_boot_time_seconds" gauge "Host boot timestamp (unix epoch) derived from uptime."
if [[ -r "${PROC_ROOT}/uptime" ]]; then
  read -r uptime_sec _ <"${PROC_ROOT}/uptime"
  if is_number "$uptime_sec"; then
    emit_metric "nixl_host_uptime_seconds" "$uptime_sec"
    boot_time="$(awk -v up="$uptime_sec" 'BEGIN {printf "%.0f", systime() - up}')"
    emit_metric "nixl_host_boot_time_seconds" "$boot_time"
  fi
fi

emit_help "nixl_host_memory_psi_avg" gauge "Memory PSI rolling averages from ${PROC_ROOT}/pressure/memory."
emit_help "nixl_host_memory_psi_total" counter "Memory PSI total stall time in microseconds."
emit_psi_metrics "${PROC_ROOT}/pressure/memory" "nixl_host_memory_psi_avg" "nixl_host_memory_psi_total"

emit_help "nixl_host_vmstat" counter "Selected memory-pressure counters from ${PROC_ROOT}/vmstat."
if [[ -r "${PROC_ROOT}/vmstat" ]]; then
  while read -r key value; do
    case "$key" in
      pgscan_kswapd|pgscan_direct|pgsteal_kswapd|pgsteal_direct|pswpin|pswpout)
        is_integer "$value" && emit_metric "nixl_host_vmstat" "$value" "field=${key}"
        ;;
    esac
  done <"${PROC_ROOT}/vmstat"
fi

detect_cgroup_version() {
  local path="$1"
  if [[ -f "${path}/memory.current" && -f "${path}/memory.events" ]]; then
    echo "v2"
  elif [[ -f "${path}/memory/memory.usage_in_bytes" && -f "${path}/memory/memory.events" ]]; then
    echo "v1"
  else
    echo "unknown"
  fi
}

read_cgroup_v1_memory() {
  local path="$1"
  local current events_file
  current="$(safe_read_file "${path}/memory/memory.usage_in_bytes" || true)"
  is_integer "$current" && emit_metric "nixl_host_cgroup_memory_current_bytes" "$current" "path=${path}"

  events_file="${path}/memory/memory.events"
  if [[ -r "$events_file" ]]; then
    while read -r key value; do
      case "$key" in
        low|high|max|oom|oom_kill)
          is_integer "$value" && emit_metric "nixl_host_cgroup_memory_events" "$value" "path=${path}" "event=${key}"
          ;;
      esac
    done <"$events_file"
  fi

  emit_psi_metrics \
    "${path}/memory/memory.pressure" \
    "nixl_host_cgroup_memory_pressure_avg" \
    "nixl_host_cgroup_memory_pressure_total" \
    "path=${path}"
}

read_cgroup_v2_memory() {
  local path="$1"
  local value
  value="$(safe_read_file "${path}/memory.current" || true)"
  is_integer "$value" && emit_metric "nixl_host_cgroup_memory_current_bytes" "$value" "path=${path}"

  if [[ -r "${path}/memory.events" ]]; then
    while read -r key value; do
      case "$key" in
        low|high|max|oom|oom_kill)
          is_integer "$value" && emit_metric "nixl_host_cgroup_memory_events" "$value" "path=${path}" "event=${key}"
          ;;
      esac
    done <"${path}/memory.events"
  fi

  emit_psi_metrics \
    "${path}/memory.pressure" \
    "nixl_host_cgroup_memory_pressure_avg" \
    "nixl_host_cgroup_memory_pressure_total" \
    "path=${path}"
}

if [[ -n "${CGROUP_PATH:-}" && -d "${CGROUP_PATH}" ]]; then
  emit_help "nixl_host_cgroup_memory_current_bytes" gauge "memory.current for the configured cgroup path (cgroup v1/v2)."
  emit_help "nixl_host_cgroup_memory_events" counter "Selected memory.events counters for the configured cgroup path."
  emit_help "nixl_host_cgroup_memory_pressure_avg" gauge "Memory PSI rolling averages for the configured cgroup path."
  emit_help "nixl_host_cgroup_memory_pressure_total" counter "Memory PSI total stall time in microseconds for the configured cgroup path."

  cgroup_version="$(detect_cgroup_version "${CGROUP_PATH}")"
  case "$cgroup_version" in
    v1)
      read_cgroup_v1_memory "${CGROUP_PATH}"
      ;;
    v2)
      read_cgroup_v2_memory "${CGROUP_PATH}"
      ;;
    *)
      ;;
  esac
fi

prom_end_scrape "nixl_host_scrape_success"
