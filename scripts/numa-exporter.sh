#!/usr/bin/env bash
set -euo pipefail
# shellcheck disable=SC2250,SC2310,SC2312  # Compact conditionals and fallback reads are intentional in exporter code.

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

prom_begin_scrape "nixl_numa_scrape_success" "Whether the NUMA exporter completed successfully."
if ! require_directory "$PROC_ROOT" "PROC_ROOT"; then
  exit 0
fi

emit_help "nixl_numa_meminfo_bytes" gauge "Selected per-node meminfo values converted to bytes."
emit_help "nixl_numa_hugepages" gauge "Selected per-node hugepage counts."

shopt -s nullglob
for meminfo in "${SYS_ROOT}"/devices/system/node/node*/meminfo; do
  node="$(basename "$(dirname "$meminfo")")"
  while read -r _node _id key value _unit; do
    case "$key" in
    MemFree: | MemUsed: | FilePages:)
      is_integer "$value" && emit_metric "nixl_numa_meminfo_bytes" "$((value * 1024))" "node=${node}" "field=$(tr '[:upper:]' '[:lower:]' <<<"${key%:}")"
      ;;
    HugePages_Total: | HugePages_Free:)
      is_integer "$value" && emit_metric "nixl_numa_hugepages" "$value" "node=${node}" "field=$(tr '[:upper:]' '[:lower:]' <<<"${key%:}")"
      ;;
    esac
  done <"$meminfo"
done

emit_help "nixl_numa_stat" counter "Selected NUMA hit and miss counters from ${SYS_ROOT}/devices/system/node/node*/numastat."
for numastat in "${SYS_ROOT}"/devices/system/node/node*/numastat; do
  node="$(basename "$(dirname "$numastat")")"
  while read -r key value; do
    case "$key" in
    numa_hit | numa_miss | numa_foreign | interleave_hit | local_node | other_node)
      is_integer "$value" && emit_metric "nixl_numa_stat" "$value" "node=${node}" "field=${key}"
      ;;
    esac
  done <"$numastat"
done
shopt -u nullglob

prom_end_scrape "nixl_numa_scrape_success"
