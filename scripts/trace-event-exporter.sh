#!/usr/bin/env bash
set -euo pipefail
# shellcheck disable=SC2250,SC2310,SC2312  # Compact conditionals and fallback reads are intentional in exporter code.

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/prom.sh
source "${SCRIPT_DIR}/lib/prom.sh"

PROC_ROOT="${PROC_ROOT:-/proc}"
SYS_ROOT="${SYS_ROOT:-/sys}"
TRACING_ROOT="${TRACING_ROOT:-${SYS_ROOT}/kernel/tracing}"

prom_begin_scrape "nixl_trace_scrape_success" "Whether the tracefs inventory exporter completed successfully."
if [[ ! -d "${TRACING_ROOT}/events" ]]; then
  exit 0
fi

emit_help "nixl_trace_events_enabled_total" gauge "Count of enabled trace events per subsystem."
emit_help "nixl_trace_function_hit_total" counter "Top function hit counters from trace_stat when available."
emit_help "nixl_trace_mm_page_alloc_total" counter "Page allocation proxy from vmstat."
emit_help "nixl_trace_mm_page_free_total" counter "Page free proxy from vmstat."
emit_help "nixl_trace_kmem_cache_alloc_total" counter "Slab scan proxy from vmstat."
emit_help "nixl_perf_event_paranoid" gauge "perf_event_paranoid setting."
emit_help "nixl_perf_event_max_sample_rate" gauge "perf_event_max_sample_rate setting."
emit_help "nixl_perf_event_mlock_kb" gauge "perf_event_mlock_kb setting."

declare -A enabled_counts=()
while IFS= read -r enable_file; do
  subsystem="$(basename "$(dirname "$(dirname "${enable_file}")")")"
  enabled_value="$(safe_read_file "${enable_file}" || true)"
  if is_integer "${enabled_value}" && ((enabled_value == 1)); then
    enabled_counts["${subsystem}"]=$(( ${enabled_counts["${subsystem}"]:-0} + 1 ))
  fi
done < <(find "${TRACING_ROOT}/events" -type f -name enable 2>/dev/null || true)

for subsystem in "${!enabled_counts[@]}"; do
  emit_metric "nixl_trace_events_enabled_total" "${enabled_counts["${subsystem}"]}" "subsystem=${subsystem}"
done

function_stats="${TRACING_ROOT}/trace_stat/function0"
if [[ -s "${function_stats}" ]]; then
  head -n 20 "${function_stats}" | awk '
    NF >= 2 {
      count = $1
      fn = $2
      gsub(/[^0-9]/, "", count)
      if (count != "") {
        printf "%s %s\n", fn, count
      }
    }
  ' | while read -r function_name hit_count; do
    is_integer "${hit_count}" && emit_metric "nixl_trace_function_hit_total" "${hit_count}" "function=${function_name}"
  done
fi

if [[ -r "${PROC_ROOT}/vmstat" ]]; then
  while read -r key value; do
    case "${key}" in
      pgalloc_normal)
        is_integer "${value}" && emit_metric "nixl_trace_mm_page_alloc_total" "${value}"
        ;;
      pgfree)
        is_integer "${value}" && emit_metric "nixl_trace_mm_page_free_total" "${value}"
        ;;
      slabs_scanned)
        is_integer "${value}" && emit_metric "nixl_trace_kmem_cache_alloc_total" "${value}"
        ;;
    esac
  done <"${PROC_ROOT}/vmstat"
fi

for perf_knob in perf_event_paranoid perf_event_max_sample_rate perf_event_mlock_kb; do
  value="$(safe_read_file "${PROC_ROOT}/sys/kernel/${perf_knob}" || true)"
  is_integer "${value}" && emit_metric "nixl_${perf_knob}" "${value}"
done

prom_end_scrape "nixl_trace_scrape_success"
