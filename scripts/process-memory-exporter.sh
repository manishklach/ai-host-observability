#!/usr/bin/env bash
set -euo pipefail

timestamp="$(date +%s)"
top_n="${TOP_N:-20}"

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

emit_help "nixl_process_memory_scrape_success" "gauge" "Whether the process memory exporter completed successfully."
emit_metric "nixl_process_memory_scrape_success" "0"

emit_help "nixl_process_locked_bytes" "gauge" "Top processes by locked memory from /proc/<pid>/smaps_rollup."
emit_help "nixl_process_vm_lck_bytes" "gauge" "Top processes by VmLck from /proc/<pid>/status."
emit_help "nixl_process_pinned_candidates" "gauge" "Number of processes with non-zero locked memory."

tmpfile="$(mktemp)"
trap 'rm -f "$tmpfile"' EXIT

for procdir in /proc/[0-9]*; do
  pid="$(basename "$procdir")"
  [[ -r "$procdir/status" ]] || continue

  comm="$(awk '/^Name:/ {print $2}' "$procdir/status" 2>/dev/null || true)"
  vm_lck_kb="$(awk '/^VmLck:/ {print $2}' "$procdir/status" 2>/dev/null || printf '0')"
  locked_kb="0"
  if [[ -r "$procdir/smaps_rollup" ]]; then
    locked_kb="$(awk '/^Locked:/ {print $2}' "$procdir/smaps_rollup" 2>/dev/null || printf '0')"
  fi

  vm_lck_kb="${vm_lck_kb:-0}"
  locked_kb="${locked_kb:-0}"
  [[ "$vm_lck_kb" =~ ^[0-9]+$ ]] || vm_lck_kb="0"
  [[ "$locked_kb" =~ ^[0-9]+$ ]] || locked_kb="0"
  printf '%s\t%s\t%s\t%s\n' "$locked_kb" "$vm_lck_kb" "$pid" "${comm:-unknown}" >>"$tmpfile"
done

pinned_count="$(awk '$1 > 0 || $2 > 0 {count++} END {print count + 0}' "$tmpfile")"
emit_metric "nixl_process_pinned_candidates" "$pinned_count"

sort -rn "$tmpfile" | head -n "$top_n" | while IFS=$'\t' read -r locked_kb vm_lck_kb pid comm; do
  if (( locked_kb > 0 )); then
    emit_metric "nixl_process_locked_bytes" "$((locked_kb * 1024))" "pid=\"$pid\",comm=\"$comm\""
  fi
  if (( vm_lck_kb > 0 )); then
    emit_metric "nixl_process_vm_lck_bytes" "$((vm_lck_kb * 1024))" "pid=\"$pid\",comm=\"$comm\""
  fi
done

emit_metric "nixl_process_memory_scrape_success" "1"
