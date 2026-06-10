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
DF="${DF:-df}"

disk_device_allowed() {
  local device="$1"
  case "$device" in
  nvme* | sd* | xvd* | vd* | hd*) return 0 ;;
  dm-*)
    [[ -r "${SYS_ROOT}/block/${device}/dm/name" ]]
    return
    ;;
  *) return 1 ;;
  esac
}

emit_diskstat_metric() {
  local metric="$1"
  local value="$2"
  local device="$3"
  is_integer "$value" && emit_metric "$metric" "$value" "device=${device}"
  return 0
}

emit_queue_metric() {
  local metric="$1"
  local device="$2"
  local file="$3"
  local value
  value="$(safe_read_file "${SYS_ROOT}/block/${device}/queue/${file}" || true)"
  is_integer "$value" && emit_metric "$metric" "$value" "device=${device}"
  return 0
}

prom_begin_scrape "nixl_disk_scrape_success" "Whether the disk and filesystem exporter completed successfully."
if ! require_directory "$PROC_ROOT" "PROC_ROOT"; then
  exit 0
fi

emit_help "nixl_diskstat_total" counter "Selected ${PROC_ROOT}/diskstats counters."
emit_help "nixl_diskstat_reads_completed_total" counter "Completed disk reads from ${PROC_ROOT}/diskstats."
emit_help "nixl_diskstat_reads_merged_total" counter "Merged disk reads from ${PROC_ROOT}/diskstats."
emit_help "nixl_diskstat_sectors_read_total" counter "Disk sectors read from ${PROC_ROOT}/diskstats."
emit_help "nixl_diskstat_read_time_ms_total" counter "Milliseconds spent reading from ${PROC_ROOT}/diskstats."
emit_help "nixl_diskstat_writes_completed_total" counter "Completed disk writes from ${PROC_ROOT}/diskstats."
emit_help "nixl_diskstat_writes_merged_total" counter "Merged disk writes from ${PROC_ROOT}/diskstats."
emit_help "nixl_diskstat_sectors_written_total" counter "Disk sectors written from ${PROC_ROOT}/diskstats."
emit_help "nixl_diskstat_write_time_ms_total" counter "Milliseconds spent writing from ${PROC_ROOT}/diskstats."
emit_help "nixl_diskstat_io_in_progress" gauge "Current in-flight I/O requests from ${PROC_ROOT}/diskstats."
emit_help "nixl_diskstat_io_time_ms_total" counter "Milliseconds spent doing I/O from ${PROC_ROOT}/diskstats."
emit_help "nixl_diskstat_weighted_io_time_ms_total" counter "Weighted milliseconds spent doing I/O from ${PROC_ROOT}/diskstats."
emit_help "nixl_diskstat_discards_completed_total" counter "Completed disk discards from ${PROC_ROOT}/diskstats."
emit_help "nixl_diskstat_discards_merged_total" counter "Merged disk discards from ${PROC_ROOT}/diskstats."
emit_help "nixl_diskstat_discard_sectors_total" counter "Disk discard sectors from ${PROC_ROOT}/diskstats."
emit_help "nixl_diskstat_discard_time_ms_total" counter "Milliseconds spent discarding from ${PROC_ROOT}/diskstats."
emit_help "nixl_diskstat_flush_requests_total" counter "Completed disk flush requests from ${PROC_ROOT}/diskstats."
emit_help "nixl_diskstat_flush_time_ms_total" counter "Milliseconds spent flushing from ${PROC_ROOT}/diskstats."
emit_help "nixl_block_queue_depth" gauge "Block device request queue depth from sysfs."
emit_help "nixl_block_rotational" gauge "Whether the block device is rotational from sysfs."
emit_help "nixl_block_physical_block_size_bytes" gauge "Block device physical block size from sysfs."
emit_help "nixl_block_hw_sector_size_bytes" gauge "Block device hardware sector size from sysfs."
emit_help "nixl_block_discard_granularity_bytes" gauge "Block device discard granularity from sysfs."
emit_help "nixl_block_scheduler_info" gauge "Active block scheduler label from sysfs."
emit_help "nixl_block_max_segments" gauge "Block device max segment count from sysfs."
emit_help "nixl_block_max_segment_size_bytes" gauge "Block device max segment size from sysfs."
emit_help "nixl_block_inflight_reads" gauge "In-flight read requests from sysfs block stat."
emit_help "nixl_block_inflight_writes" gauge "In-flight write requests from sysfs block stat."
if [[ -r "${PROC_ROOT}/diskstats" ]]; then
  while read -r _major _minor device reads_completed reads_merged sectors_read read_time_ms writes_completed writes_merged sectors_written write_time_ms io_in_progress io_time_ms weighted_io_time_ms discards_completed discards_merged discard_sectors discard_time_ms flush_requests flush_time_ms _rest; do
    disk_device_allowed "$device" || continue
    emit_diskstat_metric "nixl_diskstat_reads_completed_total" "$reads_completed" "$device"
    emit_diskstat_metric "nixl_diskstat_reads_merged_total" "$reads_merged" "$device"
    emit_diskstat_metric "nixl_diskstat_sectors_read_total" "$sectors_read" "$device"
    emit_diskstat_metric "nixl_diskstat_read_time_ms_total" "$read_time_ms" "$device"
    emit_diskstat_metric "nixl_diskstat_writes_completed_total" "$writes_completed" "$device"
    emit_diskstat_metric "nixl_diskstat_writes_merged_total" "$writes_merged" "$device"
    emit_diskstat_metric "nixl_diskstat_sectors_written_total" "$sectors_written" "$device"
    emit_diskstat_metric "nixl_diskstat_write_time_ms_total" "$write_time_ms" "$device"
    emit_diskstat_metric "nixl_diskstat_io_in_progress" "$io_in_progress" "$device"
    emit_diskstat_metric "nixl_diskstat_io_time_ms_total" "$io_time_ms" "$device"
    emit_diskstat_metric "nixl_diskstat_weighted_io_time_ms_total" "$weighted_io_time_ms" "$device"
    emit_diskstat_metric "nixl_diskstat_discards_completed_total" "${discards_completed:-}" "$device"
    emit_diskstat_metric "nixl_diskstat_discards_merged_total" "${discards_merged:-}" "$device"
    emit_diskstat_metric "nixl_diskstat_discard_sectors_total" "${discard_sectors:-}" "$device"
    emit_diskstat_metric "nixl_diskstat_discard_time_ms_total" "${discard_time_ms:-}" "$device"
    emit_diskstat_metric "nixl_diskstat_flush_requests_total" "${flush_requests:-}" "$device"
    emit_diskstat_metric "nixl_diskstat_flush_time_ms_total" "${flush_time_ms:-}" "$device"

    is_integer "$reads_completed" && emit_metric "nixl_diskstat_total" "$reads_completed" "device=${device}" "field=reads_completed"
    is_integer "$sectors_read" && emit_metric "nixl_diskstat_total" "$sectors_read" "device=${device}" "field=sectors_read"
    is_integer "$writes_completed" && emit_metric "nixl_diskstat_total" "$writes_completed" "device=${device}" "field=writes_completed"
    is_integer "$sectors_written" && emit_metric "nixl_diskstat_total" "$sectors_written" "device=${device}" "field=sectors_written"
    is_integer "$io_time_ms" && emit_metric "nixl_diskstat_total" "$io_time_ms" "device=${device}" "field=ms_io"
    is_integer "$weighted_io_time_ms" && emit_metric "nixl_diskstat_total" "$weighted_io_time_ms" "device=${device}" "field=weighted_ms_io"

    emit_queue_metric "nixl_block_queue_depth" "$device" "nr_requests"
    emit_queue_metric "nixl_block_rotational" "$device" "rotational"
    emit_queue_metric "nixl_block_physical_block_size_bytes" "$device" "physical_block_size"
    emit_queue_metric "nixl_block_hw_sector_size_bytes" "$device" "hw_sector_size"
    emit_queue_metric "nixl_block_discard_granularity_bytes" "$device" "discard_granularity"
    emit_queue_metric "nixl_block_max_segments" "$device" "max_segments"
    emit_queue_metric "nixl_block_max_segment_size_bytes" "$device" "max_segment_size"

    scheduler="$(safe_read_file "${SYS_ROOT}/block/${device}/queue/scheduler" || true)"
    if [[ "$scheduler" =~ \[([^]]+)\] ]]; then
      emit_metric "nixl_block_scheduler_info" 1 "device=${device}" "scheduler=${BASH_REMATCH[1]}"
    fi

    if [[ -r "${SYS_ROOT}/block/${device}/inflight" ]]; then
      read -r inflight_reads inflight_writes <"${SYS_ROOT}/block/${device}/inflight"
      is_integer "$inflight_reads" && emit_metric "nixl_block_inflight_reads" "$inflight_reads" "device=${device}"
      is_integer "$inflight_writes" && emit_metric "nixl_block_inflight_writes" "$inflight_writes" "device=${device}"
    fi
  done <"${PROC_ROOT}/diskstats"
fi

emit_help "nixl_filesystem_bytes" gauge "Filesystem size, used, and available bytes by mountpoint."
if command_exists "$DF"; then
  while read -r filesystem fstype size_bytes used_bytes avail_bytes mount; do
    case "$fstype" in
    tmpfs | devtmpfs | overlay | squashfs) continue ;;
    esac
    is_integer "$size_bytes" && emit_metric "nixl_filesystem_bytes" "$size_bytes" "filesystem=${filesystem}" "mount=${mount}" "fstype=${fstype}" "field=size"
    is_integer "$used_bytes" && emit_metric "nixl_filesystem_bytes" "$used_bytes" "filesystem=${filesystem}" "mount=${mount}" "fstype=${fstype}" "field=used"
    is_integer "$avail_bytes" && emit_metric "nixl_filesystem_bytes" "$avail_bytes" "filesystem=${filesystem}" "mount=${mount}" "fstype=${fstype}" "field=avail"
  done < <("$DF" -B1 -P -T 2>/dev/null | awk 'NR > 1 {print $1, $2, $3, $4, $5, $7}')
fi

emit_help "nixl_file_nr" gauge "Allocated, unused, and maximum file handles from ${PROC_ROOT}/sys/fs/file-nr."
if [[ -r "${PROC_ROOT}/sys/fs/file-nr" ]]; then
  read -r allocated unused max <"${PROC_ROOT}/sys/fs/file-nr"
  is_integer "$allocated" && emit_metric "nixl_file_nr" "$allocated" "field=allocated"
  is_integer "$unused" && emit_metric "nixl_file_nr" "$unused" "field=unused"
  is_integer "$max" && emit_metric "nixl_file_nr" "$max" "field=max"
fi

emit_help "nixl_inode_nr" gauge "Allocated and free inode counters from ${PROC_ROOT}/sys/fs/inode-nr."
if [[ -r "${PROC_ROOT}/sys/fs/inode-nr" ]]; then
  read -r allocated free <"${PROC_ROOT}/sys/fs/inode-nr"
  is_integer "$allocated" && emit_metric "nixl_inode_nr" "$allocated" "field=allocated"
  is_integer "$free" && emit_metric "nixl_inode_nr" "$free" "field=free"
fi

prom_end_scrape "nixl_disk_scrape_success"
