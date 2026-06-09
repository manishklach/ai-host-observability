#!/usr/bin/env bash
set -euo pipefail
# shellcheck disable=SC2250,SC2310,SC2312  # Compact conditionals and fallback reads are intentional in exporter code.

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/prom.sh
source "${SCRIPT_DIR}/lib/prom.sh"

OUT_DIR="${OUT_DIR:-/var/lib/node_exporter/textfile_collector}"
STALE_THRESHOLD="${STALE_THRESHOLD:-120}"
PS_CMD="${PS_CMD:-ps}"
STAT_CMD="${STAT_CMD:-stat}"
NOW_EPOCH="${NOW_EPOCH:-$(date +%s)}"

prom_begin_scrape "nixl_collector_scrape_success" "Whether the collector health exporter completed successfully."
if [[ ! -d "${OUT_DIR}" ]]; then
  exit 0
fi

emit_help "nixl_collector_last_run_timestamp" gauge "Last modification timestamp for an exporter .prom file."
emit_help "nixl_collector_last_run_age_seconds" gauge "Age in seconds since an exporter .prom file was last updated."
emit_help "nixl_collector_last_run_duration_seconds" gauge "Exporter duration parsed from the wrapped textfile output when present."
emit_help "nixl_collector_prom_file_size_bytes" gauge "Exporter .prom file size in bytes."
emit_help "nixl_collector_prom_file_lines" gauge "Exporter .prom file line count."
emit_help "nixl_collector_prom_file_metric_count" gauge "Count of non-comment metric lines in an exporter .prom file."
emit_help "nixl_collector_exporters_total" gauge "Total number of exporter .prom files found."
emit_help "nixl_collector_exporters_stale" gauge "Count of exporter .prom files older than the stale threshold."
emit_help "nixl_collector_exporters_empty" gauge "Count of exporter .prom files with zero metric lines."
emit_help "nixl_collector_total_metrics" gauge "Total metric sample count across exporter .prom files."
emit_help "nixl_collector_total_prom_size_bytes" gauge "Total size of exporter .prom files in bytes."
emit_help "nixl_collector_node_exporter_running" gauge "Whether a node_exporter process was detected."
emit_help "nixl_collector_textfile_dir_writable" gauge "Whether the textfile collector directory is writable."
emit_help "nixl_collector_unique_series_estimate" gauge "Approximate unique series count across exporter textfiles."

total_exporters=0
stale_exporters=0
empty_exporters=0
total_metrics=0
total_size=0
unique_series_file="$(mktemp)"
>"${unique_series_file}"

shopt -s nullglob
for prom_file in "${OUT_DIR}"/*.prom; do
  [[ -f "${prom_file}" ]] || continue
  exporter="$(basename "${prom_file}" .prom)"
  total_exporters=$((total_exporters + 1))

  size_bytes="$("${STAT_CMD}" -c '%s' "${prom_file}" 2>/dev/null || true)"
  mtime="$("${STAT_CMD}" -c '%Y' "${prom_file}" 2>/dev/null || true)"
  line_count="$(wc -l <"${prom_file}")"
  metric_count="$(grep -Ecv '^\s*(#|$)' "${prom_file}" || true)"
  duration_value="$(awk '/^ai_host_exporter_duration_seconds/ { value=$2 } END { print value }' "${prom_file}")"

  if ! is_integer "${size_bytes}"; then
    size_bytes=0
  fi
  if ! is_integer "${mtime}"; then
    mtime=0
  fi
  if ! is_integer "${metric_count}"; then
    metric_count=0
  fi

  age_seconds="$(awk -v now="${NOW_EPOCH}" -v mtime="${mtime}" 'BEGIN {
    age = now - mtime
    if (age < 0) {
      age = 0
    }
    printf "%.0f\n", age
  }')"

  ((metric_count == 0)) && empty_exporters=$((empty_exporters + 1))
  ((age_seconds > STALE_THRESHOLD)) && stale_exporters=$((stale_exporters + 1))
  total_metrics=$((total_metrics + metric_count))
  total_size=$((total_size + size_bytes))

  emit_metric "nixl_collector_last_run_timestamp" "${mtime}" "exporter=${exporter}"
  emit_metric "nixl_collector_last_run_age_seconds" "${age_seconds}" "exporter=${exporter}"
  if is_number "${duration_value}"; then
    emit_metric "nixl_collector_last_run_duration_seconds" "${duration_value}" "exporter=${exporter}"
  fi
  emit_metric "nixl_collector_prom_file_size_bytes" "${size_bytes}" "exporter=${exporter}"
  emit_metric "nixl_collector_prom_file_lines" "${line_count}" "exporter=${exporter}"
  emit_metric "nixl_collector_prom_file_metric_count" "${metric_count}" "exporter=${exporter}"

  grep -E '^[a-zA-Z_:][a-zA-Z0-9_:]*(\{[^}]*\})?\s' "${prom_file}" >>"${unique_series_file}" || true
done
shopt -u nullglob

emit_metric "nixl_collector_exporters_total" "${total_exporters}"
emit_metric "nixl_collector_exporters_stale" "${stale_exporters}"
emit_metric "nixl_collector_exporters_empty" "${empty_exporters}"
emit_metric "nixl_collector_total_metrics" "${total_metrics}"
emit_metric "nixl_collector_total_prom_size_bytes" "${total_size}"

textfile_dir_writable=0
[[ -w "${OUT_DIR}" ]] && textfile_dir_writable=1
emit_metric "nixl_collector_textfile_dir_writable" "${textfile_dir_writable}"

node_exporter_running=0
if command_exists "${PS_CMD}" && "${PS_CMD}" -eo comm=,args= 2>/dev/null | grep -q 'node_exporter'; then
  node_exporter_running=1
fi
emit_metric "nixl_collector_node_exporter_running" "${node_exporter_running}"

unique_series_count="$(sort -u "${unique_series_file}" | wc -l)"
rm -f -- "${unique_series_file}"
emit_metric "nixl_collector_unique_series_estimate" "${unique_series_count}"

prom_end_scrape "nixl_collector_scrape_success"
