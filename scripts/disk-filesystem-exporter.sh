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
DF="${DF:-df}"

require_directory "$PROC_ROOT" "PROC_ROOT"

prom_begin_scrape "nixl_disk_scrape_success" "Whether the disk and filesystem exporter completed successfully."

emit_help "nixl_diskstat_total" counter "Selected ${PROC_ROOT}/diskstats counters."
if [[ -r "${PROC_ROOT}/diskstats" ]]; then
  while read -r _major _minor device reads_completed _reads_merged sectors_read _ms_reading writes_completed _writes_merged sectors_written _ms_writing _ios_in_progress ms_io weighted_ms_io _rest; do
    case "$device" in
      loop*|ram*|fd*|sr*) continue ;;
    esac
    is_integer "$reads_completed" && emit_metric "nixl_diskstat_total" "$reads_completed" "device=${device}" "field=reads_completed"
    is_integer "$sectors_read" && emit_metric "nixl_diskstat_total" "$sectors_read" "device=${device}" "field=sectors_read"
    is_integer "$writes_completed" && emit_metric "nixl_diskstat_total" "$writes_completed" "device=${device}" "field=writes_completed"
    is_integer "$sectors_written" && emit_metric "nixl_diskstat_total" "$sectors_written" "device=${device}" "field=sectors_written"
    is_integer "$ms_io" && emit_metric "nixl_diskstat_total" "$ms_io" "device=${device}" "field=ms_io"
    is_integer "$weighted_ms_io" && emit_metric "nixl_diskstat_total" "$weighted_ms_io" "device=${device}" "field=weighted_ms_io"
  done <"${PROC_ROOT}/diskstats"
fi

emit_help "nixl_filesystem_bytes" gauge "Filesystem size, used, and available bytes by mountpoint."
if command_exists "$DF"; then
  while read -r filesystem fstype size_bytes used_bytes avail_bytes mount; do
    case "$fstype" in
      tmpfs|devtmpfs|overlay|squashfs) continue ;;
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
