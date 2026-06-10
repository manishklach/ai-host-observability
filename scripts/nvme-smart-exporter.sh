#!/usr/bin/env bash
set -euo pipefail
# shellcheck disable=SC2250,SC2310,SC2312  # Compact guarded parsing keeps this hardware-gated exporter readable.

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/prom.sh
source "${SCRIPT_DIR}/lib/prom.sh"

DEV_ROOT="${DEV_ROOT:-/dev}"
NVME_CMD="${NVME_CMD:-nvme}"

json_number() {
  local key="$1"
  awk -v key="\"${key}\"" '
    index($0, key) {
      line=$0
      sub(".*" key "[ \t]*:[ \t]*", "", line)
      sub("[,}].*", "", line)
      gsub(/"/, "", line)
      gsub(/^[ \t]+|[ \t]+$/, "", line)
      print line
      exit
    }
  '
}

json_string() {
  local key="$1"
  awk -v key="\"${key}\"" '
    index($0, key) {
      line=$0
      sub(".*" key "[ \t]*:[ \t]*\"", "", line)
      sub("\".*", "", line)
      print line
      exit
    }
  '
}

truncate_label() {
  local value="$1"
  printf '%s' "${value:0:32}"
}

emit_nvme_metric() {
  local metric="$1"
  local value="$2"
  local device="$3"
  local model="$4"
  local serial="$5"
  is_number "$value" && emit_metric "$metric" "$value" "device=${device}" "model=${model}" "serial=${serial}"
  return 0
}

emit_temp() {
  local value="$1"
  local sensor="$2"
  local device="$3"
  local model="$4"
  local serial="$5"
  if is_number "$value" && awk -v value="$value" 'BEGIN { exit !(value > 0) }'; then
    celsius="$(awk -v kelvin="$value" 'BEGIN { printf "%.0f", kelvin - 273 }')"
    emit_metric "nixl_nvme_temperature_celsius" "$celsius" "device=${device}" "model=${model}" "serial=${serial}" "sensor=${sensor}"
  fi
}

prom_begin_scrape "nixl_nvme_scrape_success" "Whether the NVMe SMART exporter completed successfully."
if ! command_exists "${NVME_CMD}"; then
  exit 0
fi

shopt -s nullglob
nvme_nodes=("${DEV_ROOT}"/nvme*)
shopt -u nullglob
if ((${#nvme_nodes[@]} == 0)); then
  exit 0
fi

emit_help "nixl_nvme_percentage_used" gauge "NVMe SMART percentage used."
emit_help "nixl_nvme_available_spare_percent" gauge "NVMe SMART available spare percentage."
emit_help "nixl_nvme_available_spare_threshold_percent" gauge "NVMe SMART available spare threshold percentage."
emit_help "nixl_nvme_data_read_bytes_total" counter "NVMe SMART data units read converted to bytes."
emit_help "nixl_nvme_data_written_bytes_total" counter "NVMe SMART data units written converted to bytes."
emit_help "nixl_nvme_host_read_commands_total" counter "NVMe host read commands."
emit_help "nixl_nvme_host_write_commands_total" counter "NVMe host write commands."
emit_help "nixl_nvme_power_on_seconds_total" counter "NVMe power-on time in seconds."
emit_help "nixl_nvme_power_cycles_total" counter "NVMe power cycle count."
emit_help "nixl_nvme_unsafe_shutdowns_total" counter "NVMe unsafe shutdown count."
emit_help "nixl_nvme_controller_busy_seconds_total" counter "NVMe controller busy time in seconds."
emit_help "nixl_nvme_media_errors_total" counter "NVMe media and data integrity errors."
emit_help "nixl_nvme_error_log_entries_total" counter "NVMe error log entries."
emit_help "nixl_nvme_critical_warning" gauge "NVMe critical warning bitmask."
emit_help "nixl_nvme_warn_spare_low" gauge "NVMe critical warning bit 0."
emit_help "nixl_nvme_warn_temp_threshold" gauge "NVMe critical warning bit 1."
emit_help "nixl_nvme_warn_reliability_degraded" gauge "NVMe critical warning bit 2."
emit_help "nixl_nvme_warn_read_only" gauge "NVMe critical warning bit 3."
emit_help "nixl_nvme_warn_volatile_backup_failed" gauge "NVMe critical warning bit 4."
emit_help "nixl_nvme_temperature_celsius" gauge "NVMe SMART temperature in Celsius."
emit_help "nixl_nvme_physical_size_bytes" gauge "NVMe physical size in bytes."
emit_help "nixl_nvme_used_size_bytes" gauge "NVMe used size in bytes."

inventory="$("${NVME_CMD}" list --output-format=json 2>/dev/null || true)"
if [[ -z "${inventory}" ]]; then
  exit 0
fi

if command_exists jq; then
  mapfile -t devices < <(jq -r '.Devices[]? | [.DevicePath, (.ModelNumber // "unknown"), (.SerialNumber // "unknown"), (.PhysicalSize // 0), (.UsedBytes // 0)] | @tsv' <<<"${inventory}" 2>/dev/null)
else
  mapfile -t devices < <(awk '
    /DevicePath/ { device=$0; sub(/.*"DevicePath"[ \t]*:[ \t]*"/, "", device); sub(/".*/, "", device) }
    /ModelNumber/ { model=$0; sub(/.*"ModelNumber"[ \t]*:[ \t]*"/, "", model); sub(/".*/, "", model) }
    /SerialNumber/ { serial=$0; sub(/.*"SerialNumber"[ \t]*:[ \t]*"/, "", serial); sub(/".*/, "", serial) }
    /PhysicalSize/ { size=$0; sub(/.*"PhysicalSize"[ \t]*:[ \t]*/, "", size); sub(/,.*/, "", size) }
    /UsedBytes/ { used=$0; sub(/.*"UsedBytes"[ \t]*:[ \t]*/, "", used); sub(/[,}].*/, "", used); print device "\t" model "\t" serial "\t" size "\t" used }
  ' <<<"${inventory}")
fi

for row in "${devices[@]}"; do
  IFS=$'\t' read -r device model serial physical_size used_size <<<"${row}"
  [[ -n "${device}" ]] || continue
  model="$(truncate_label "${model:-unknown}")"
  serial="$(truncate_label "${serial:-unknown}")"

  smart="$("${NVME_CMD}" smart-log "${device}" --output-format=json 2>/dev/null || true)"
  [[ -n "${smart}" ]] || continue

  if command_exists jq; then
    percentage_used="$(jq -r '.percentage_used // empty' <<<"${smart}")"
    available_spare="$(jq -r '.available_spare // empty' <<<"${smart}")"
    spare_threshold="$(jq -r '.available_spare_threshold // empty' <<<"${smart}")"
    data_read="$(jq -r '.data_units_read // empty' <<<"${smart}")"
    data_written="$(jq -r '.data_units_written // empty' <<<"${smart}")"
    host_reads="$(jq -r '.host_read_commands // empty' <<<"${smart}")"
    host_writes="$(jq -r '.host_write_commands // empty' <<<"${smart}")"
    power_on_hours="$(jq -r '.power_on_hours // empty' <<<"${smart}")"
    power_cycles="$(jq -r '.power_cycles // empty' <<<"${smart}")"
    unsafe_shutdowns="$(jq -r '.unsafe_shutdowns // empty' <<<"${smart}")"
    busy_minutes="$(jq -r '.controller_busy_time // empty' <<<"${smart}")"
    media_errors="$(jq -r '.media_errors // empty' <<<"${smart}")"
    error_entries="$(jq -r '.num_err_log_entries // empty' <<<"${smart}")"
    critical_warning="$(jq -r '.critical_warning // empty' <<<"${smart}")"
    composite_temp="$(jq -r '.temperature // empty' <<<"${smart}")"
  else
    percentage_used="$(json_number percentage_used <<<"${smart}")"
    available_spare="$(json_number available_spare <<<"${smart}")"
    spare_threshold="$(json_number available_spare_threshold <<<"${smart}")"
    data_read="$(json_number data_units_read <<<"${smart}")"
    data_written="$(json_number data_units_written <<<"${smart}")"
    host_reads="$(json_number host_read_commands <<<"${smart}")"
    host_writes="$(json_number host_write_commands <<<"${smart}")"
    power_on_hours="$(json_number power_on_hours <<<"${smart}")"
    power_cycles="$(json_number power_cycles <<<"${smart}")"
    unsafe_shutdowns="$(json_number unsafe_shutdowns <<<"${smart}")"
    busy_minutes="$(json_number controller_busy_time <<<"${smart}")"
    media_errors="$(json_number media_errors <<<"${smart}")"
    error_entries="$(json_number num_err_log_entries <<<"${smart}")"
    critical_warning="$(json_number critical_warning <<<"${smart}")"
    composite_temp="$(json_number temperature <<<"${smart}")"
  fi

  emit_nvme_metric "nixl_nvme_percentage_used" "${percentage_used}" "${device}" "${model}" "${serial}"
  emit_nvme_metric "nixl_nvme_available_spare_percent" "${available_spare}" "${device}" "${model}" "${serial}"
  emit_nvme_metric "nixl_nvme_available_spare_threshold_percent" "${spare_threshold}" "${device}" "${model}" "${serial}"
  is_number "$data_read" && emit_nvme_metric "nixl_nvme_data_read_bytes_total" "$(awk -v value="$data_read" 'BEGIN { printf "%.0f", value * 512000 }')" "${device}" "${model}" "${serial}"
  is_number "$data_written" && emit_nvme_metric "nixl_nvme_data_written_bytes_total" "$(awk -v value="$data_written" 'BEGIN { printf "%.0f", value * 512000 }')" "${device}" "${model}" "${serial}"
  emit_nvme_metric "nixl_nvme_host_read_commands_total" "${host_reads}" "${device}" "${model}" "${serial}"
  emit_nvme_metric "nixl_nvme_host_write_commands_total" "${host_writes}" "${device}" "${model}" "${serial}"
  is_number "$power_on_hours" && emit_nvme_metric "nixl_nvme_power_on_seconds_total" "$(awk -v value="$power_on_hours" 'BEGIN { printf "%.0f", value * 3600 }')" "${device}" "${model}" "${serial}"
  emit_nvme_metric "nixl_nvme_power_cycles_total" "${power_cycles}" "${device}" "${model}" "${serial}"
  emit_nvme_metric "nixl_nvme_unsafe_shutdowns_total" "${unsafe_shutdowns}" "${device}" "${model}" "${serial}"
  is_number "$busy_minutes" && emit_nvme_metric "nixl_nvme_controller_busy_seconds_total" "$(awk -v value="$busy_minutes" 'BEGIN { printf "%.0f", value * 60 }')" "${device}" "${model}" "${serial}"
  emit_nvme_metric "nixl_nvme_media_errors_total" "${media_errors}" "${device}" "${model}" "${serial}"
  emit_nvme_metric "nixl_nvme_error_log_entries_total" "${error_entries}" "${device}" "${model}" "${serial}"
  emit_nvme_metric "nixl_nvme_critical_warning" "${critical_warning}" "${device}" "${model}" "${serial}"

  warning="${critical_warning:-0}"
  if is_integer "$warning"; then
    emit_nvme_metric "nixl_nvme_warn_spare_low" "$((warning & 1 ? 1 : 0))" "${device}" "${model}" "${serial}"
    emit_nvme_metric "nixl_nvme_warn_temp_threshold" "$((warning & 2 ? 1 : 0))" "${device}" "${model}" "${serial}"
    emit_nvme_metric "nixl_nvme_warn_reliability_degraded" "$((warning & 4 ? 1 : 0))" "${device}" "${model}" "${serial}"
    emit_nvme_metric "nixl_nvme_warn_read_only" "$((warning & 8 ? 1 : 0))" "${device}" "${model}" "${serial}"
    emit_nvme_metric "nixl_nvme_warn_volatile_backup_failed" "$((warning & 16 ? 1 : 0))" "${device}" "${model}" "${serial}"
  fi

  emit_temp "${composite_temp}" "composite" "${device}" "${model}" "${serial}"
  for idx in 1 2 3 4 5 6 7 8; do
    if command_exists jq; then
      sensor_value="$(jq -r ".temperature_sensor_${idx} // empty" <<<"${smart}")"
    else
      sensor_value="$(json_number "temperature_sensor_${idx}" <<<"${smart}")"
    fi
    emit_temp "${sensor_value}" "sensor_${idx}" "${device}" "${model}" "${serial}"
  done

  emit_nvme_metric "nixl_nvme_physical_size_bytes" "${physical_size:-0}" "${device}" "${model}" "${serial}"
  emit_nvme_metric "nixl_nvme_used_size_bytes" "${used_size:-0}" "${device}" "${model}" "${serial}"
done

prom_end_scrape "nixl_nvme_scrape_success"
