#!/usr/bin/env bash
set -euo pipefail
# shellcheck disable=SC2250  # Compact inline checks keep the triage output easier to follow.

OUT_DIR="${OUT_DIR:-/var/lib/node_exporter/textfile_collector}"

usage() {
  cat <<'EOF'
Usage: ai-host-triage.sh [--prom-dir PATH] [--help]

Read Prometheus textfile collector outputs and print a human-readable AI host
incident summary. The script tolerates missing groups and prints "insufficient
data" when a signal family is unavailable.

Options:
  --prom-dir PATH   Read .prom files from PATH instead of $OUT_DIR
  --help            Show this help text
EOF
}

while (($# > 0)); do
  case "$1" in
  --prom-dir)
    shift
    [[ $# -gt 0 ]] || {
      printf 'error: --prom-dir requires a path\n' >&2
      exit 2
    }
    OUT_DIR="$1"
    ;;
  --help|-h)
    usage
    exit 0
    ;;
  *)
    printf 'error: unknown argument: %s\n' "$1" >&2
    usage >&2
    exit 2
    ;;
  esac
  shift
done

shopt -s nullglob
PROM_FILES=("${OUT_DIR}"/*.prom)
shopt -u nullglob

if ((${#PROM_FILES[@]} == 0)); then
  printf 'AI Host Triage Summary\n'
  printf '======================\n\n'
  printf 'Prometheus directory: %s\n' "$OUT_DIR"
  printf 'No .prom files found. Status: insufficient data.\n'
  exit 0
fi

read_metric_value() {
  local metric_name="$1"
  local label_filter="${2:-}"
  awk -v metric_name="$metric_name" -v label_filter="$label_filter" '
    index($0, "#") == 1 { next }
    $1 !~ "^" metric_name "([{| ]|$)" { next }
    label_filter != "" && index($1, label_filter) == 0 { next }
    { value = $2 }
    END {
      if (value != "") {
        print value
      }
    }
  ' "${PROM_FILES[@]}"
}

sum_metric_values() {
  local metric_name="$1"
  local label_filter="${2:-}"
  awk -v metric_name="$metric_name" -v label_filter="$label_filter" '
    index($0, "#") == 1 { next }
    $1 !~ "^" metric_name "([{| ]|$)" { next }
    label_filter != "" && index($1, label_filter) == 0 { next }
    { sum += $2; seen = 1 }
    END {
      if (seen) {
        print sum
      }
    }
  ' "${PROM_FILES[@]}"
}

max_metric_value() {
  local metric_name="$1"
  local label_filter="${2:-}"
  awk -v metric_name="$metric_name" -v label_filter="$label_filter" '
    index($0, "#") == 1 { next }
    $1 !~ "^" metric_name "([{| ]|$)" { next }
    label_filter != "" && index($1, label_filter) == 0 { next }
    {
      if (!seen || $2 > max) {
        max = $2
      }
      seen = 1
    }
    END {
      if (seen) {
        print max
      }
    }
  ' "${PROM_FILES[@]}"
}

status_for_value() {
  local value="$1"
  local warn_threshold="$2"
  local crit_threshold="$3"
  awk -v value="$value" -v warn="$warn_threshold" -v crit="$crit_threshold" 'BEGIN {
    if (value >= crit) {
      print "CRITICAL"
    } else if (value >= warn) {
      print "WARN"
    } else {
      print "OK"
    }
  }'
}

status_for_low_value() {
  local value="$1"
  local warn_threshold="$2"
  local crit_threshold="$3"
  awk -v value="$value" -v warn="$warn_threshold" -v crit="$crit_threshold" 'BEGIN {
    if (value <= crit) {
      print "CRITICAL"
    } else if (value <= warn) {
      print "WARN"
    } else {
      print "OK"
    }
  }'
}

bytes_to_gib() {
  awk -v value="${1:-0}" 'BEGIN { printf "%.2f", value / 1073741824 }'
}

to_percent() {
  awk -v value="${1:-0}" 'BEGIN { printf "%.1f", value * 100 }'
}

has_metric() {
  local metric_name="$1"
  grep -Eq "^${metric_name}([{| ]|$)" "${PROM_FILES[@]}" 2>/dev/null
}

print_group_header() {
  printf '%s:\n' "$1"
}

print_line() {
  printf '  %s\n' "$1"
}

diagnosis="No strong diagnosis yet."
declare -a next_steps=()

printf 'AI Host Triage Summary\n'
printf '======================\n\n'
printf 'Prometheus directory: %s\n\n' "$OUT_DIR"

print_group_header "Host memory"
mem_available="$(read_metric_value "nixl_host_meminfo_bytes" 'field="memavailable"' || true)"
mem_free="$(read_metric_value "nixl_host_meminfo_bytes" 'field="memfree"' || true)"
swap_free="$(read_metric_value "nixl_host_meminfo_bytes" 'field="swapfree"' || true)"
if [[ -n "$mem_available" ]]; then
  mem_status="$(status_for_low_value "$mem_available" 8589934592 4294967296)"
  print_line "MemAvailable: $(bytes_to_gib "$mem_available") GiB [$mem_status]"
  [[ -n "$mem_free" ]] && print_line "MemFree: $(bytes_to_gib "$mem_free") GiB"
  [[ -n "$swap_free" ]] && print_line "SwapFree: $(bytes_to_gib "$swap_free") GiB"
else
  print_line "insufficient data"
fi
printf '\n'

print_group_header "PSI / reclaim / swap"
psi_some60="$(read_metric_value "nixl_host_memory_psi_avg" 'scope="some",window="60s"' || true)"
psi_full60="$(read_metric_value "nixl_host_memory_psi_avg" 'scope="full",window="60s"' || true)"
pgscan_direct="$(read_metric_value "nixl_host_vmstat" 'field="pgscan_direct"' || true)"
pswpout="$(read_metric_value "nixl_host_vmstat" 'field="pswpout"' || true)"
if [[ -n "$psi_some60" || -n "$pgscan_direct" || -n "$pswpout" ]]; then
  [[ -n "$psi_some60" ]] && print_line "Memory PSI some avg60: ${psi_some60}% [$(status_for_value "$psi_some60" 1 5)]"
  [[ -n "$psi_full60" ]] && print_line "Memory PSI full avg60: ${psi_full60}% [$(status_for_value "$psi_full60" 0.1 0.3)]"
  [[ -n "$pgscan_direct" ]] && print_line "Direct reclaim counter: $pgscan_direct [$(status_for_value "$pgscan_direct" 10 100)]"
  [[ -n "$pswpout" ]] && print_line "Swap out counter: $pswpout [$(status_for_value "$pswpout" 1 10)]"
else
  print_line "insufficient data"
fi
printf '\n'

print_group_header "RDMA / mlx5 firmware pages"
fw_pages_sum="$(read_metric_value "nixl_host_fw_pages_sum" || true)"
fw_pages_zscore="$(read_metric_value "nixl_baseline_zscore" 'metric_id="fw_pages_sum"' || true)"
ib_rcv_errors="$(sum_metric_values "nixl_infiniband_counter" 'counter="port_rcv_errors"' || true)"
if [[ -n "$fw_pages_sum" || -n "$ib_rcv_errors" ]]; then
  if [[ -n "$fw_pages_sum" ]]; then
    fw_status="OK"
    if [[ -n "$fw_pages_zscore" ]]; then
      fw_status="$(status_for_value "$fw_pages_zscore" 2 3)"
      print_line "mlx5 fw_pages_total sum: $fw_pages_sum [${fw_status}]"
      print_line "fw_pages z-score: $fw_pages_zscore"
    else
      fw_status="$(status_for_value "$fw_pages_sum" 4096 16384)"
      print_line "mlx5 fw_pages_total sum: $fw_pages_sum [${fw_status}]"
    fi
  fi
  [[ -n "$ib_rcv_errors" ]] && print_line "InfiniBand receive errors: $ib_rcv_errors [$(status_for_value "$ib_rcv_errors" 1 10)]"
else
  print_line "insufficient data"
fi
printf '\n'

print_group_header "GPU / BAR1 / ECC / clocks"
gpu_mem_used="$(sum_metric_values "nixl_gpu_memory_used_bytes" || true)"
gpu_bar1_used="$(sum_metric_values "nixl_gpu_bar1_used_bytes" || true)"
gpu_bar1_total="$(sum_metric_values "nixl_gpu_bar1_total_bytes" || true)"
gpu_ecc="$(sum_metric_values "nixl_gpu_ecc_volatile_total" || true)"
gpu_pstate="$(awk '/^nixl_gpu_pstate\{/ { if (match($1, /pstate="[^"]+"/)) { print substr($1, RSTART + 8, RLENGTH - 9); exit } }' "${PROM_FILES[@]}" 2>/dev/null || true)"
gpu_hw_slow="$(sum_metric_values "nixl_gpu_throttle_reason" 'reason="hw_slowdown"' || true)"
if [[ -n "$gpu_mem_used" || -n "$gpu_bar1_used" || -n "$gpu_ecc" ]]; then
  [[ -n "$gpu_mem_used" ]] && print_line "GPU memory used: $(bytes_to_gib "$gpu_mem_used") GiB"
  if [[ -n "$gpu_bar1_used" && -n "$gpu_bar1_total" && "$gpu_bar1_total" != "0" ]]; then
    bar1_ratio="$(awk -v used="$gpu_bar1_used" -v total="$gpu_bar1_total" 'BEGIN { if (total <= 0) print 0; else printf "%.4f", used / total }')"
    print_line "BAR1 usage: $(to_percent "$bar1_ratio")% [$(status_for_value "$bar1_ratio" 0.80 0.90)]"
  fi
  [[ -n "$gpu_ecc" ]] && print_line "GPU ECC counter sum: $gpu_ecc [$(status_for_value "$gpu_ecc" 1 10)]"
  [[ -n "$gpu_pstate" ]] && print_line "P-state: $gpu_pstate"
  [[ -n "$gpu_hw_slow" ]] && print_line "HW slowdown flags: $gpu_hw_slow [$(status_for_value "$gpu_hw_slow" 1 1)]"
else
  print_line "insufficient data"
fi
printf '\n'

print_group_header "NUMA locality"
numa_miss="$(sum_metric_values "nixl_numa_stat" 'field="numa_miss"' || true)"
other_node="$(sum_metric_values "nixl_numa_stat" 'field="other_node"' || true)"
if [[ -n "$numa_miss" || -n "$other_node" ]]; then
  [[ -n "$numa_miss" ]] && print_line "numa_miss counter: $numa_miss [$(status_for_value "$numa_miss" 1 100)]"
  [[ -n "$other_node" ]] && print_line "other_node allocations: $other_node [$(status_for_value "$other_node" 1 100)]"
else
  print_line "insufficient data"
fi
printf '\n'

print_group_header "NIC / softirq / IRQ"
softnet_drops="$(sum_metric_values "nixl_softnet_stat_total" 'field="dropped"' || true)"
net_rx="$(read_metric_value "nixl_softirq_total" 'type="NET_RX"' || true)"
irq_total="$(sum_metric_values "nixl_irq_total" || true)"
if [[ -n "$softnet_drops" || -n "$net_rx" || -n "$irq_total" ]]; then
  [[ -n "$softnet_drops" ]] && print_line "softnet drops: $softnet_drops [$(status_for_value "$softnet_drops" 1 50)]"
  [[ -n "$net_rx" ]] && print_line "NET_RX softirq total: $net_rx"
  [[ -n "$irq_total" ]] && print_line "Selected IRQ total: $irq_total"
else
  print_line "insufficient data"
fi
printf '\n'

print_group_header "PCIe / VFIO / IOMMU / kernel events"
oom_events="$(read_metric_value "nixl_kernel_log_pattern_total" 'pattern="oom"' || true)"
pcie_aer_events="$(read_metric_value "nixl_kernel_log_pattern_total" 'pattern="pcie_aer"' || true)"
vfio_events="$(read_metric_value "nixl_kernel_log_pattern_total" 'pattern="vfio"' || true)"
iommu_events="$(read_metric_value "nixl_kernel_log_pattern_total" 'pattern="iommu_dma"' || true)"
mlx5_events="$(read_metric_value "nixl_kernel_log_pattern_total" 'pattern="rdma_mlx5"' || true)"
if [[ -n "$oom_events" || -n "$pcie_aer_events" || -n "$vfio_events" || -n "$iommu_events" || -n "$mlx5_events" ]]; then
  [[ -n "$oom_events" ]] && print_line "Kernel OOM pattern counter: $oom_events [$(status_for_value "$oom_events" 1 1)]"
  [[ -n "$pcie_aer_events" ]] && print_line "PCIe AER pattern counter: $pcie_aer_events [$(status_for_value "$pcie_aer_events" 1 5)]"
  [[ -n "$vfio_events" ]] && print_line "VFIO pattern counter: $vfio_events [$(status_for_value "$vfio_events" 1 5)]"
  [[ -n "$iommu_events" ]] && print_line "IOMMU DMA pattern counter: $iommu_events [$(status_for_value "$iommu_events" 1 5)]"
  [[ -n "$mlx5_events" ]] && print_line "RDMA mlx5 pattern counter: $mlx5_events [$(status_for_value "$mlx5_events" 1 5)]"
else
  print_line "insufficient data"
fi
printf '\n'

print_group_header "Disk / filesystem pressure"
disk_ms_io="$(sum_metric_values "nixl_diskstat_total" 'field="ms_io"' || true)"
fs_avail="$(read_metric_value "nixl_filesystem_bytes" 'field="avail"' || true)"
inode_allocated="$(read_metric_value "nixl_inode_nr" 'field="allocated"' || true)"
if [[ -n "$disk_ms_io" || -n "$fs_avail" || -n "$inode_allocated" ]]; then
  [[ -n "$disk_ms_io" ]] && print_line "Disk IO time counter: $disk_ms_io [$(status_for_value "$disk_ms_io" 1000 10000)]"
  [[ -n "$fs_avail" ]] && print_line "Filesystem available: $(bytes_to_gib "$fs_avail") GiB [$(status_for_low_value "$fs_avail" 21474836480 5368709120)]"
  [[ -n "$inode_allocated" ]] && print_line "Allocated inodes: $inode_allocated"
else
  print_line "insufficient data"
fi
printf '\n'

print_group_header "Process locked memory"
locked_bytes="$(sum_metric_values "nixl_process_locked_bytes" || true)"
vm_lck_bytes="$(sum_metric_values "nixl_process_vm_lck_bytes" || true)"
if [[ -n "$locked_bytes" || -n "$vm_lck_bytes" ]]; then
  [[ -n "$locked_bytes" ]] && print_line "Locked memory from smaps_rollup: $(bytes_to_gib "$locked_bytes") GiB [$(status_for_value "$locked_bytes" 1073741824 4294967296)]"
  [[ -n "$vm_lck_bytes" ]] && print_line "VmLck total: $(bytes_to_gib "$vm_lck_bytes") GiB [$(status_for_value "$vm_lck_bytes" 1073741824 4294967296)]"
else
  print_line "insufficient data"
fi
printf '\n'

if [[ -n "$mem_available" && -n "$psi_some60" ]] && awk -v mem="$mem_available" -v psi="$psi_some60" 'BEGIN { exit !((mem < 8589934592) && (psi >= 1)) }'; then
  diagnosis="Hidden host memory pressure is building. MemAvailable is low while memory PSI is elevated."
  next_steps+=("Check reclaim counters, cgroup memory growth, and swap activity.")
fi

if [[ -n "$fw_pages_sum" ]] && { [[ -n "$fw_pages_zscore" ]] && awk -v value="$fw_pages_zscore" 'BEGIN { exit !(value >= 2) }'; }; then
  diagnosis="Hidden host memory pressure likely includes RDMA registration growth via mlx5 firmware page expansion."
  next_steps+=("Check RDMA registration users and compare fw_pages_total across HCAs.")
fi

if [[ -n "$gpu_bar1_used" && -n "$gpu_bar1_total" && "$gpu_bar1_total" != "0" ]] && awk -v used="$gpu_bar1_used" -v total="$gpu_bar1_total" 'BEGIN { exit !((used / total) >= 0.80) }'; then
  diagnosis="GPU BAR1 pressure is elevated and may be contributing to host-side mapping strain."
  next_steps+=("Compare BAR1 usage with locked memory, host PSI, and PCIe-side kernel signals.")
fi

if [[ -n "$numa_miss" ]] && awk -v value="$numa_miss" 'BEGIN { exit !(value > 0) }'; then
  diagnosis="NUMA locality degradation is visible. Cross-node allocations or page migrations may be hurting consistency."
  next_steps+=("Check GPU/NIC/NUMA placement and whether automatic NUMA balancing is enabled.")
fi

if [[ -n "$softnet_drops" ]] && awk -v value="$softnet_drops" 'BEGIN { exit !(value > 0) }'; then
  diagnosis="Host networking pressure is visible through softnet drops and may be affecting collective traffic."
  next_steps+=("Inspect IRQ placement, NIC queue pressure, and network retransmit signals.")
fi

if [[ -n "$oom_events" ]] && awk -v value="$oom_events" 'BEGIN { exit !(value > 0) }'; then
  diagnosis="Kernel-level incident signals are already present, including OOM-related log patterns."
  next_steps+=("Inspect kernel logs, cgroup events, and the top locked-memory or runaway processes.")
fi

if [[ -n "$locked_bytes" ]] && awk -v value="$locked_bytes" 'BEGIN { exit !(value >= 1073741824) }'; then
  next_steps+=("Check pinned or locked process memory to find host RAM consumers that GPU dashboards may miss.")
fi

printf 'Likely diagnosis:\n'
printf '  %s\n\n' "$diagnosis"

printf 'Suggested next steps:\n'
if ((${#next_steps[@]} == 0)); then
  printf '  1. Compare the raw host metrics against the matching runbooks.\n'
  printf '  2. Re-run collection if major signal groups are missing.\n'
  printf '  3. Correlate the host view with GPU and application telemetry.\n'
else
  step_number=1
  declare -A seen_steps=()
  for step in "${next_steps[@]}"; do
    [[ -n "${seen_steps[$step]:-}" ]] && continue
    printf '  %d. %s\n' "$step_number" "$step"
    seen_steps["$step"]=1
    step_number=$((step_number + 1))
  done
fi
