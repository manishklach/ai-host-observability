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

emit_help "nixl_numa_scrape_success" "gauge" "Whether the exporter completed successfully."
emit_metric "nixl_numa_scrape_success" "0"

emit_help "nixl_numa_meminfo_bytes" "gauge" "Selected per-node meminfo values converted to bytes."
emit_help "nixl_numa_hugepages" "gauge" "Selected per-node hugepage counts."
shopt -s nullglob
for meminfo in /sys/devices/system/node/node*/meminfo; do
  node="$(basename "$(dirname "$meminfo")")"
  while read -r _ key value unit; do
    case "$key" in
      MemFree:|MemUsed:|FilePages:)
        field="$(tr '[:upper:]' '[:lower:]' <<<"${key%:}")"
        emit_metric "nixl_numa_meminfo_bytes" "$((value * 1024))" "node=\"$node\",field=\"$field\""
        ;;
      HugePages_Total:|HugePages_Free:)
        field="$(tr '[:upper:]' '[:lower:]' <<<"${key%:}")"
        emit_metric "nixl_numa_hugepages" "$value" "node=\"$node\",field=\"$field\""
        ;;
    esac
  done < "$meminfo"
done

emit_help "nixl_numa_stat" "counter" "Selected NUMA hit and miss counters from /sys/devices/system/node/node*/numastat."
for numastat in /sys/devices/system/node/node*/numastat; do
  node="$(basename "$(dirname "$numastat")")"
  while read -r key value; do
    case "$key" in
      numa_hit|numa_miss|numa_foreign|interleave_hit|local_node|other_node)
        emit_metric "nixl_numa_stat" "$value" "node=\"$node\",field=\"$key\""
        ;;
    esac
  done < "$numastat"
done
shopt -u nullglob

emit_metric "nixl_numa_scrape_success" "1"
