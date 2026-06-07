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

prom_begin_scrape "nixl_cpu_scrape_success" "Whether the CPU and IRQ exporter completed successfully."
if ! require_directory "$PROC_ROOT" "PROC_ROOT"; then
  exit 0
fi

emit_help "nixl_cpu_psi_avg" gauge "CPU PSI rolling averages from ${PROC_ROOT}/pressure/cpu."
emit_help "nixl_cpu_psi_total" counter "CPU PSI total stall time in microseconds."
if [[ -r "${PROC_ROOT}/pressure/cpu" ]]; then
  while read -r scope rest; do
    avg10="" avg60="" avg300="" total=""
    for token in $rest; do
      case "$token" in
        avg10=*) avg10="${token#avg10=}" ;;
        avg60=*) avg60="${token#avg60=}" ;;
        avg300=*) avg300="${token#avg300=}" ;;
        total=*) total="${token#total=}" ;;
      esac
    done
    is_number "$avg10" && emit_metric "nixl_cpu_psi_avg" "$avg10" "scope=${scope}" "window=10s"
    is_number "$avg60" && emit_metric "nixl_cpu_psi_avg" "$avg60" "scope=${scope}" "window=60s"
    is_number "$avg300" && emit_metric "nixl_cpu_psi_avg" "$avg300" "scope=${scope}" "window=300s"
    is_integer "$total" && emit_metric "nixl_cpu_psi_total" "$total" "scope=${scope}"
  done <"${PROC_ROOT}/pressure/cpu"
fi

emit_help "nixl_softirq_total" counter "Softirq counters from ${PROC_ROOT}/softirqs aggregated across CPUs."
if [[ -r "${PROC_ROOT}/softirqs" ]]; then
  while IFS= read -r line; do
    [[ "$line" == *:* ]] || continue
    irq_name="$(xargs <<<"${line%%:*}")"
    total=0
    for value in ${line#*:}; do
      is_integer "$value" && total=$((total + value))
    done
    emit_metric "nixl_softirq_total" "$total" "type=${irq_name}"
  done <"${PROC_ROOT}/softirqs"
fi

emit_help "nixl_irq_total" counter "Selected IRQ counters aggregated across CPUs."
if [[ -r "${PROC_ROOT}/interrupts" ]]; then
  while IFS= read -r line; do
    [[ "$line" == *:* ]] || continue
    rest="${line#*:}"
    if [[ "$rest" != *mlx5* && "$rest" != *nv* && "$rest" != *pciehp* ]]; then
      continue
    fi
    irq_id="$(xargs <<<"${line%%:*}")"
    source_label="$(awk '{for (i=NF-1; i<=NF; i++) if (i > 0) printf "%s%s", $i, (i < NF ? "_" : "")}' <<<"$rest" | tr ' /-' '___')"
    total=0
    for value in $rest; do
      is_integer "$value" && total=$((total + value))
    done
    emit_metric "nixl_irq_total" "$total" "irq=${irq_id}" "source=${source_label}"
  done <"${PROC_ROOT}/interrupts"
fi

emit_help "nixl_loadavg" gauge "System load averages from ${PROC_ROOT}/loadavg."
if [[ -r "${PROC_ROOT}/loadavg" ]]; then
  read -r load1 load5 load15 _ <"${PROC_ROOT}/loadavg"
  is_number "$load1" && emit_metric "nixl_loadavg" "$load1" "window=1m"
  is_number "$load5" && emit_metric "nixl_loadavg" "$load5" "window=5m"
  is_number "$load15" && emit_metric "nixl_loadavg" "$load15" "window=15m"
fi

prom_end_scrape "nixl_cpu_scrape_success"
