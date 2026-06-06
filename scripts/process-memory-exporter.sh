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
TOP_N="${TOP_N:-20}"

require_directory "$PROC_ROOT" "PROC_ROOT"

prom_begin_scrape "nixl_process_memory_scrape_success" "Whether the process memory exporter completed successfully."

emit_help "nixl_process_locked_bytes" gauge "Top processes by locked memory from ${PROC_ROOT}/<pid>/smaps_rollup."
emit_help "nixl_process_vm_lck_bytes" gauge "Top processes by VmLck from ${PROC_ROOT}/<pid>/status."
emit_help "nixl_process_pinned_candidates" gauge "Number of processes with non-zero locked memory."

tmpfile="$(mktemp)"
trap 'rm -f -- "$tmpfile"' EXIT

shopt -s nullglob
for procdir in "${PROC_ROOT}"/[0-9]*; do
  pid="$(basename "$procdir")"
  [[ -r "$procdir/status" ]] || continue

  comm="$(awk '/^Name:/ {print $2}' "$procdir/status" 2>/dev/null || printf '%s' 'unknown')"
  vm_lck_kb="$(awk '/^VmLck:/ {print $2}' "$procdir/status" 2>/dev/null || printf '%s' '0')"
  locked_kb="0"
  if [[ -r "$procdir/smaps_rollup" ]]; then
    locked_kb="$(awk '/^Locked:/ {print $2}' "$procdir/smaps_rollup" 2>/dev/null || printf '%s' '0')"
  fi
  is_integer "$locked_kb" || locked_kb=0
  is_integer "$vm_lck_kb" || vm_lck_kb=0
  printf '%s\t%s\t%s\t%s\n' "$locked_kb" "$vm_lck_kb" "$pid" "$comm" >>"$tmpfile"
done
shopt -u nullglob

pinned_count="$(awk '$1 > 0 || $2 > 0 { count++ } END { print count + 0 }' "$tmpfile")"
emit_metric "nixl_process_pinned_candidates" "$pinned_count"

while IFS=$'\t' read -r locked_kb vm_lck_kb pid comm; do
  ((locked_kb > 0)) && emit_metric "nixl_process_locked_bytes" "$((locked_kb * 1024))" "pid=${pid}" "comm=${comm}"
  ((vm_lck_kb > 0)) && emit_metric "nixl_process_vm_lck_bytes" "$((vm_lck_kb * 1024))" "pid=${pid}" "comm=${comm}"
done < <(sort -rn "$tmpfile" | head -n "$TOP_N")

prom_end_scrape
