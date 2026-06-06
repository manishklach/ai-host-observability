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

emit_help "nixl_cpu_scrape_success" "gauge" "Whether the exporter completed successfully."
emit_metric "nixl_cpu_scrape_success" "0"

emit_help "nixl_cpu_psi_avg" "gauge" "CPU PSI rolling averages from /proc/pressure/cpu."
emit_help "nixl_cpu_psi_total" "counter" "CPU PSI total stall time in microseconds."
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
  emit_metric "nixl_cpu_psi_avg" "$avg10" "scope=\"$scope\",window=\"10s\""
  emit_metric "nixl_cpu_psi_avg" "$avg60" "scope=\"$scope\",window=\"60s\""
  emit_metric "nixl_cpu_psi_avg" "$avg300" "scope=\"$scope\",window=\"300s\""
  emit_metric "nixl_cpu_psi_total" "$total" "scope=\"$scope\""
done < /proc/pressure/cpu

emit_help "nixl_softirq_total" "counter" "Softirq counters from /proc/softirqs aggregated across CPUs."
while read -r line; do
  [[ "$line" == *:* ]] || continue
  irq_name="${line%%:*}"
  irq_name="$(xargs <<<"$irq_name")"
  total=0
  for value in ${line#*:}; do
    [[ "$value" =~ ^[0-9]+$ ]] || continue
    total=$((total + value))
  done
  emit_metric "nixl_softirq_total" "$total" "type=\"${irq_name}\""
done < /proc/softirqs

emit_help "nixl_irq_total" "counter" "Selected IRQ counters aggregated across CPUs."
while read -r line; do
  [[ "$line" == *:* ]] || continue
  irq_id="${line%%:*}"
  rest="${line#*:}"
  if [[ "$rest" != *mlx5* && "$rest" != *nv* && "$rest" != *pciehp* ]]; then
    continue
  fi
  irq_desc="$(awk '{for (i=NF-1; i<=NF; i++) if (i > 0) printf "%s%s", $i, (i < NF ? "_" : "")}' <<<"$rest" | tr ' /-' '___')"
  total=0
  for value in $rest; do
    [[ "$value" =~ ^[0-9]+$ ]] || continue
    total=$((total + value))
  done
  emit_metric "nixl_irq_total" "$total" "irq=\"$(xargs <<<"$irq_id")\",source=\"$irq_desc\""
done < /proc/interrupts

if [[ -f /proc/loadavg ]]; then
  read -r load1 load5 load15 _ < /proc/loadavg
  emit_help "nixl_loadavg" "gauge" "System load average."
  emit_metric "nixl_loadavg" "$load1" "window=\"1m\""
  emit_metric "nixl_loadavg" "$load5" "window=\"5m\""
  emit_metric "nixl_loadavg" "$load15" "window=\"15m\""
fi

emit_metric "nixl_cpu_scrape_success" "1"
