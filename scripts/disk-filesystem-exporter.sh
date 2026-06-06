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

emit_help "nixl_disk_scrape_success" "gauge" "Whether the disk/filesystem exporter completed successfully."
emit_metric "nixl_disk_scrape_success" "0"

emit_help "nixl_diskstat_total" "counter" "Selected /proc/diskstats counters."
while read -r major minor dev reads_completed reads_merged sectors_read ms_reading writes_completed writes_merged sectors_written ms_writing ios_in_progress ms_io weighted_ms_io _; do
  case "$dev" in
    loop*|ram*|fd*|sr*) continue ;;
  esac
  emit_metric "nixl_diskstat_total" "$reads_completed" "device=\"$dev\",field=\"reads_completed\""
  emit_metric "nixl_diskstat_total" "$sectors_read" "device=\"$dev\",field=\"sectors_read\""
  emit_metric "nixl_diskstat_total" "$writes_completed" "device=\"$dev\",field=\"writes_completed\""
  emit_metric "nixl_diskstat_total" "$sectors_written" "device=\"$dev\",field=\"sectors_written\""
  emit_metric "nixl_diskstat_total" "$ms_io" "device=\"$dev\",field=\"ms_io\""
  emit_metric "nixl_diskstat_total" "$weighted_ms_io" "device=\"$dev\",field=\"weighted_ms_io\""
done < /proc/diskstats

emit_help "nixl_filesystem_bytes" "gauge" "Filesystem size, used, and available bytes by mountpoint."
while read -r filesystem fstype size used avail pcent mount; do
  case "$fstype" in
    tmpfs|devtmpfs|overlay|squashfs) continue ;;
  esac
  emit_metric "nixl_filesystem_bytes" "$size" "mount=\"$mount\",fstype=\"$fstype\",field=\"size\""
  emit_metric "nixl_filesystem_bytes" "$used" "mount=\"$mount\",fstype=\"$fstype\",field=\"used\""
  emit_metric "nixl_filesystem_bytes" "$avail" "mount=\"$mount\",fstype=\"$fstype\",field=\"avail\""
done < <(df -B1 --output=source,fstype,size,used,avail,pcent,target | tail -n +2)

emit_help "nixl_file_nr" "gauge" "Allocated, unused, and maximum file handles from /proc/sys/fs/file-nr."
read -r allocated unused max < /proc/sys/fs/file-nr
emit_metric "nixl_file_nr" "$allocated" "field=\"allocated\""
emit_metric "nixl_file_nr" "$unused" "field=\"unused\""
emit_metric "nixl_file_nr" "$max" "field=\"max\""

emit_help "nixl_inode_nr" "gauge" "Allocated and free inodes from /proc/sys/fs/inode-nr."
read -r inode_alloc inode_free < /proc/sys/fs/inode-nr
emit_metric "nixl_inode_nr" "$inode_alloc" "field=\"allocated\""
emit_metric "nixl_inode_nr" "$inode_free" "field=\"free\""

emit_metric "nixl_disk_scrape_success" "1"
