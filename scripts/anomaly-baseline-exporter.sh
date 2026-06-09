#!/usr/bin/env bash
set -euo pipefail
# shellcheck disable=SC2250,SC2310,SC2312  # Compact conditionals and fallback reads are intentional in exporter code.

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/prom.sh
source "${SCRIPT_DIR}/lib/prom.sh"

OUT_DIR="${OUT_DIR:-/var/lib/node_exporter/textfile_collector}"
BASELINE_DIR="${BASELINE_DIR:-${OUT_DIR}/.baseline}"
BASELINE_STATE_DIR="${BASELINE_STATE_DIR:-${OUT_DIR}/.baseline-state}"
BASELINE_WINDOW_SIZE="${BASELINE_WINDOW_SIZE:-1440}"

prom_files() {
  find "${OUT_DIR}" -maxdepth 1 -type f -name '*.prom' ! -name 'nixl_baseline.prom' 2>/dev/null
}

read_last_value() {
  local metric_name="$1"
  local label_filter="${2:-}"
  local -a files
  mapfile -t files < <(prom_files)
  awk -v metric_name="${metric_name}" -v label_filter="${label_filter}" '
    index($0, "#") == 1 { next }
    $1 !~ "^" metric_name "([{| ]|$)" { next }
    label_filter != "" && index($1, label_filter) == 0 { next }
    { value=$2 }
    END {
      if (value != "") {
        print value
      }
    }
  ' "${files[@]}"
}

aggregate_values() {
  local metric_name="$1"
  local label_filter="${2:-}"
  local mode="$3"
  local -a files
  mapfile -t files < <(prom_files)
  awk -v metric_name="${metric_name}" -v label_filter="${label_filter}" -v mode="${mode}" '
    index($0, "#") == 1 { next }
    $1 !~ "^" metric_name "([{| ]|$)" { next }
    label_filter != "" && index($1, label_filter) == 0 { next }
    {
      value=$2 + 0
      count++
      sum += value
      if (count == 1 || value > max) {
        max = value
      }
    }
    END {
      if (count == 0) {
        print ""
      } else if (mode == "mean") {
        printf "%.6f\n", sum / count
      } else if (mode == "max") {
        printf "%.6f\n", max
      } else {
        printf "%.6f\n", sum
      }
    }
  ' "${files[@]}"
}

counter_proxy_value() {
  local metric_id="$1"
  local raw_value="$2"
  local raw_file="${BASELINE_STATE_DIR}/${metric_id}.raw"
  local current_value="0"
  mkdir -p "${BASELINE_STATE_DIR}"

  if [[ -f "${raw_file}" ]]; then
    previous="$(safe_read_file "${raw_file}" || true)"
    if is_number "${previous}" && awk -v curr="${raw_value}" -v prev="${previous}" 'BEGIN { exit !(curr >= prev) }'; then
      current_value="$(awk -v curr="${raw_value}" -v prev="${previous}" 'BEGIN { printf "%.6f", curr - prev }')"
    fi
  fi

  printf '%s\n' "${raw_value}" >"${raw_file}"
  printf '%s\n' "${current_value}"
}

compute_metric_current() {
  local metric_id="$1"
  case "${metric_id}" in
  psi_mem_some_60)
    read_last_value "nixl_host_memory_psi_avg" 'scope="some",window="60s"'
    ;;
  fw_pages_sum)
    read_last_value "nixl_host_fw_pages_sum"
    ;;
  gpu_util_mean)
    aggregate_values "nixl_gpu_utilization_percent" "" "mean"
    ;;
  gpu_temp_max)
    aggregate_values "nixl_gpu_temperature_celsius" "" "max"
    ;;
  disk_io_time_rate)
    raw="$(aggregate_values "nixl_diskstat_total" 'field="ms_io"' "sum")"
    [[ -n "${raw}" ]] && counter_proxy_value "${metric_id}" "${raw}" || printf '0\n'
    ;;
  softnet_drops)
    raw="$(aggregate_values "nixl_softnet_stat_total" 'field="dropped"' "sum")"
    [[ -n "${raw}" ]] && counter_proxy_value "${metric_id}" "${raw}" || printf '0\n'
    ;;
  ib_rcv_errors)
    raw="$(aggregate_values "nixl_infiniband_counter" 'counter="port_rcv_errors"' "sum")"
    [[ -n "${raw}" ]] && counter_proxy_value "${metric_id}" "${raw}" || printf '0\n'
    ;;
  cpu_psi_some_60)
    read_last_value "nixl_cpu_psi_avg" 'scope="some",window="60s"'
    ;;
  esac
}

window_stats() {
  local window_file="$1"
  local sorted_file
  sorted_file="$(mktemp)"
  sort -n "${window_file}" >"${sorted_file}"
  awk -v sorted_file="${sorted_file}" '
    BEGIN {
      while ((getline line < sorted_file) > 0) {
        values[++count] = line + 0
      }
      close(sorted_file)
    }
    {
      samples[++n] = $1 + 0
      sum += samples[n]
    }
    END {
      mean = (n > 0) ? sum / n : 0
      variance = 0
      for (i = 1; i <= n; i++) {
        variance += ((samples[i] - mean) * (samples[i] - mean))
      }
      stddev = (n > 0) ? sqrt(variance / n) : 0
      p50 = percentile(values, count, 0.50)
      p95 = percentile(values, count, 0.95)
      p99 = percentile(values, count, 0.99)
      printf "%.6f %.6f %.6f %.6f %.6f %d\n", mean, stddev, p50, p95, p99, n
    }
    function percentile(values, count, q, rank) {
      if (count == 0) {
        return 0
      }
      rank = int((count - 1) * q) + 1
      if (rank < 1) {
        rank = 1
      }
      if (rank > count) {
        rank = count
      }
      return values[rank]
    }
  ' "${window_file}"
  rm -f -- "${sorted_file}"
}

update_window() {
  local window_file="$1"
  local current_value="$2"
  local tmp_file
  tmp_file="$(mktemp)"
  mkdir -p "${BASELINE_DIR}"
  touch "${window_file}"
  {
    cat -- "${window_file}"
    printf '%s\n' "${current_value}"
  } | tail -n "${BASELINE_WINDOW_SIZE}" >"${tmp_file}"
  mv -f -- "${tmp_file}" "${window_file}"
}

prom_begin_scrape "nixl_baseline_scrape_success" "Whether the anomaly baseline exporter completed successfully."
if [[ ! -d "${OUT_DIR}" ]]; then
  exit 0
fi

mapfile -t PROM_FILES < <(prom_files)
if ((${#PROM_FILES[@]} == 0)); then
  exit 0
fi

emit_help "nixl_baseline_mean" gauge "Rolling baseline mean for the selected metric."
emit_help "nixl_baseline_stddev" gauge "Rolling baseline population standard deviation for the selected metric."
emit_help "nixl_baseline_p50" gauge "Rolling baseline p50 for the selected metric."
emit_help "nixl_baseline_p95" gauge "Rolling baseline p95 for the selected metric."
emit_help "nixl_baseline_p99" gauge "Rolling baseline p99 for the selected metric."
emit_help "nixl_baseline_current" gauge "Current value used for the rolling baseline."
emit_help "nixl_baseline_zscore" gauge "Current value z-score relative to the rolling baseline."
emit_help "nixl_baseline_window_size" gauge "Current rolling baseline window size."

metric_ids=(
  psi_mem_some_60
  fw_pages_sum
  gpu_util_mean
  gpu_temp_max
  disk_io_time_rate
  softnet_drops
  ib_rcv_errors
  cpu_psi_some_60
)

for metric_id in "${metric_ids[@]}"; do
  current_value="$(compute_metric_current "${metric_id}")"
  if ! is_number "${current_value}"; then
    current_value="0"
  fi

  window_file="${BASELINE_DIR}/${metric_id}.window"
  update_window "${window_file}" "${current_value}"
  read -r mean stddev p50 p95 p99 window_size < <(window_stats "${window_file}")

  zscore="0"
  if awk -v stddev="${stddev}" 'BEGIN { exit !(stddev > 0) }'; then
    zscore="$(awk -v current="${current_value}" -v mean="${mean}" -v stddev="${stddev}" 'BEGIN { printf "%.6f", (current - mean) / stddev }')"
  fi

  emit_metric "nixl_baseline_mean" "${mean}" "metric_id=${metric_id}"
  emit_metric "nixl_baseline_stddev" "${stddev}" "metric_id=${metric_id}"
  emit_metric "nixl_baseline_p50" "${p50}" "metric_id=${metric_id}"
  emit_metric "nixl_baseline_p95" "${p95}" "metric_id=${metric_id}"
  emit_metric "nixl_baseline_p99" "${p99}" "metric_id=${metric_id}"
  emit_metric "nixl_baseline_current" "${current_value}" "metric_id=${metric_id}"
  emit_metric "nixl_baseline_zscore" "${zscore}" "metric_id=${metric_id}"
  emit_metric "nixl_baseline_window_size" "${window_size}" "metric_id=${metric_id}"
done

prom_end_scrape "nixl_baseline_scrape_success"
