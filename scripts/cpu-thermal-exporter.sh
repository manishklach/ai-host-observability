#!/usr/bin/env bash
set -euo pipefail
# shellcheck disable=SC2250,SC2310,SC2312  # Compact fallback reads are intentional in exporter code.

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/prom.sh
source "${SCRIPT_DIR}/lib/prom.sh"

SYS_ROOT="${SYS_ROOT:-/sys}"

prom_begin_scrape "nixl_thermal_scrape_success" "Whether the CPU thermal exporter completed successfully."
if ! require_directory "${SYS_ROOT}" "SYS_ROOT"; then
  exit 0
fi

emit_help "nixl_thermal_zone_temp_celsius" gauge "Thermal zone temperature in Celsius."
emit_help "nixl_thermal_zone_trip_point_celsius" gauge "Thermal zone trip point temperatures in Celsius."
emit_help "nixl_cpu_thermal_throttle_total" counter "CPU thermal throttle counters by CPU and scope."
emit_help "nixl_cpu_freq_current_khz" gauge "Current CPU frequency aggregated per package."
emit_help "nixl_cpu_freq_max_khz" gauge "Maximum rated CPU frequency per package."
emit_help "nixl_cpu_freq_min_khz" gauge "Minimum rated CPU frequency per package."
emit_help "nixl_cpu_freq_governor_info" gauge "Governor label for each CPU frequency package."

thermal_ok=0
shopt -s nullglob
for zone_dir in "${SYS_ROOT}/class/thermal"/thermal_zone*; do
  [[ -d "${zone_dir}" ]] || continue
  zone="$(basename "${zone_dir}")"
  zone_type="$(safe_read_file "${zone_dir}/type" || true)"
  [[ -n "${zone_type}" ]] || zone_type="unknown"
  temp_millic="$(safe_read_file "${zone_dir}/temp" || true)"
  if is_integer "${temp_millic}"; then
    emit_metric "nixl_thermal_zone_temp_celsius" "$(awk -v v="${temp_millic}" 'BEGIN {printf "%.3f", v / 1000}')" "zone=${zone}" "type=${zone_type}"
    thermal_ok=1
  fi

  for trip_file in "${zone_dir}"/trip_point_*_temp; do
    [[ -f "${trip_file}" ]] || continue
    trip_name="$(basename "${trip_file}")"
    trip="${trip_name#trip_point_}"
    trip="${trip%_temp}"
    trip_type="$(safe_read_file "${zone_dir}/trip_point_${trip}_type" || true)"
    [[ -n "${trip_type}" ]] || trip_type="unknown"
    trip_temp="$(safe_read_file "${trip_file}" || true)"
    if is_integer "${trip_temp}"; then
      emit_metric "nixl_thermal_zone_trip_point_celsius" "$(awk -v v="${trip_temp}" 'BEGIN {printf "%.3f", v / 1000}')" "zone=${zone}" "trip=${trip}" "type=${trip_type}"
      thermal_ok=1
    fi
  done
done

throttle_ok=0
for cpu_dir in "${SYS_ROOT}/devices/system/cpu"/cpu[0-9]*; do
  [[ -d "${cpu_dir}" ]] || continue
  cpu="$(basename "${cpu_dir}")"
  core_throttle="$(safe_read_file "${cpu_dir}/thermal_throttle/core_throttle_count" || true)"
  package_throttle="$(safe_read_file "${cpu_dir}/thermal_throttle/package_throttle_count" || true)"
  if is_integer "${core_throttle}"; then
    emit_metric "nixl_cpu_thermal_throttle_total" "${core_throttle}" "cpu=${cpu}" "scope=core"
    throttle_ok=1
  fi
  if is_integer "${package_throttle}"; then
    emit_metric "nixl_cpu_thermal_throttle_total" "${package_throttle}" "cpu=${cpu}" "scope=package"
    throttle_ok=1
  fi
done

declare -A package_sum=()
declare -A package_count=()
declare -A package_min=()
declare -A package_max=()
declare -A package_max_freq=()
declare -A package_min_freq=()
declare -A package_governor=()
freq_ok=0

for cpu_dir in "${SYS_ROOT}/devices/system/cpu"/cpu[0-9]*; do
  [[ -d "${cpu_dir}" ]] || continue
  [[ -d "${cpu_dir}/cpufreq" ]] || continue
  cpu="$(basename "${cpu_dir}")"
  package="$(safe_read_file "${cpu_dir}/topology/physical_package_id" || true)"
  [[ -n "${package}" ]] || package="0"
  package="package${package}"

  cur_freq="$(safe_read_file "${cpu_dir}/cpufreq/scaling_cur_freq" || true)"
  max_freq="$(safe_read_file "${cpu_dir}/cpufreq/cpuinfo_max_freq" || true)"
  min_freq="$(safe_read_file "${cpu_dir}/cpufreq/cpuinfo_min_freq" || true)"
  governor="$(safe_read_file "${cpu_dir}/cpufreq/scaling_governor" || true)"

  if is_integer "${cur_freq}"; then
    if [[ -z "${package_min[${package}]:-}" || "${cur_freq}" -lt "${package_min[${package}]}" ]]; then
      package_min["${package}"]="${cur_freq}"
    fi
    if [[ -z "${package_max[${package}]:-}" || "${cur_freq}" -gt "${package_max[${package}]}" ]]; then
      package_max["${package}"]="${cur_freq}"
    fi
    package_sum["${package}"]=$((${package_sum["${package}"]:-0} + cur_freq))
    package_count["${package}"]=$((${package_count["${package}"]:-0} + 1))
    freq_ok=1
  fi
  is_integer "${max_freq}" && package_max_freq["${package}"]="${max_freq}"
  is_integer "${min_freq}" && package_min_freq["${package}"]="${min_freq}"
  [[ -n "${governor}" ]] && package_governor["${package}"]="${governor}"
done
shopt -u nullglob

for package in "${!package_count[@]}"; do
  emit_metric "nixl_cpu_freq_current_khz" "${package_min[${package}]}" "package=${package}" "stat=min"
  emit_metric "nixl_cpu_freq_current_khz" "${package_max[${package}]}" "package=${package}" "stat=max"
  emit_metric "nixl_cpu_freq_current_khz" "$(awk -v sum="${package_sum[${package}]}" -v count="${package_count[${package}]}" 'BEGIN {printf "%.0f", sum / count}')" "package=${package}" "stat=mean"
  [[ -n "${package_max_freq[${package}]:-}" ]] && emit_metric "nixl_cpu_freq_max_khz" "${package_max_freq[${package}]}" "package=${package}"
  [[ -n "${package_min_freq[${package}]:-}" ]] && emit_metric "nixl_cpu_freq_min_khz" "${package_min_freq[${package}]}" "package=${package}"
  [[ -n "${package_governor[${package}]:-}" ]] && emit_metric "nixl_cpu_freq_governor_info" 1 "package=${package}" "governor=${package_governor[${package}]}"
done

if [[ "${thermal_ok}" -eq 1 || "${throttle_ok}" -eq 1 || "${freq_ok}" -eq 1 ]]; then
  prom_end_scrape "nixl_thermal_scrape_success"
fi
