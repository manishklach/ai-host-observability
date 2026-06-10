#!/usr/bin/env bash
set -euo pipefail
# shellcheck disable=SC2250,SC2310,SC2312  # Compact optional-source parsing is intentional in this hardware-gated exporter.

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/prom.sh
source "${SCRIPT_DIR}/lib/prom.sh"

PROC_ROOT="${PROC_ROOT:-/proc}"
SYS_ROOT="${SYS_ROOT:-/sys}"
LVS_CMD="${LVS_CMD:-lvs}"

prom_begin_scrape "nixl_raid_scrape_success" "Whether the RAID and LVM exporter completed successfully."

emit_help "nixl_md_state" gauge "Software RAID array state, where 1 is active or clean and 0 is degraded or failed."
emit_help "nixl_md_degraded" gauge "Whether the software RAID array is degraded."
emit_help "nixl_md_disks_total" gauge "Expected disk count for the software RAID array."
emit_help "nixl_md_disks_active" gauge "Active disk count for the software RAID array."
emit_help "nixl_md_disks_failed" gauge "Failed disk count for the software RAID array."
emit_help "nixl_md_disks_spare" gauge "Spare disk count for the software RAID array."
emit_help "nixl_md_array_size_bytes" gauge "Software RAID array size in bytes."
emit_help "nixl_md_sync_action" gauge "Current software RAID sync action."
emit_help "nixl_md_sync_speed_kbps" gauge "Software RAID sync speed in KiB per second."
emit_help "nixl_md_mismatch_count" counter "Software RAID mismatch count."
emit_help "nixl_lvm_lv_size_bytes" gauge "LVM logical volume size in bytes."
emit_help "nixl_lvm_thin_data_percent" gauge "LVM thin pool data usage percentage."
emit_help "nixl_lvm_thin_metadata_percent" gauge "LVM thin pool metadata usage percentage."

source_found=0
if [[ -r "${PROC_ROOT}/mdstat" ]]; then
  source_found=1
  current_device=""
  current_level="unknown"
  while IFS= read -r line; do
    if [[ "$line" =~ ^(md[0-9]+)[[:space:]]*:[[:space:]]*(active|inactive)[[:space:]]+([^[:space:]]+) ]]; then
      current_device="${BASH_REMATCH[1]}"
      state_word="${BASH_REMATCH[2]}"
      current_level="${BASH_REMATCH[3]}"
      state_value="$([[ "${state_word}" == "active" ]] && printf '1' || printf '0')"
      emit_metric "nixl_md_state" "${state_value}" "device=${current_device}" "level=${current_level}"

      active_disks="$(grep -oE '\[[0-9]+/[0-9]+\]' <<<"${line}" | head -n1 | tr -d '[]' || true)"
      if [[ -n "${active_disks}" ]]; then
        total="${active_disks%%/*}"
        active="${active_disks##*/}"
        emit_metric "nixl_md_disks_total" "${total}" "device=${current_device}"
        emit_metric "nixl_md_disks_active" "${active}" "device=${current_device}"
        degraded="$((active < total ? 1 : 0))"
        emit_metric "nixl_md_degraded" "${degraded}" "device=${current_device}"
      fi

      failed="$(grep -o '\(F\)' <<<"${line}" | wc -l | xargs || true)"
      spare="$(grep -o '\(S\)' <<<"${line}" | wc -l | xargs || true)"
      emit_metric "nixl_md_disks_failed" "${failed}" "device=${current_device}"
      emit_metric "nixl_md_disks_spare" "${spare}" "device=${current_device}"
      continue
    fi

    if [[ -n "${current_device}" ]]; then
      active_disks="$(grep -oE '\[[0-9]+/[0-9]+\]' <<<"${line}" | head -n1 | tr -d '[]' || true)"
      if [[ -n "${active_disks}" ]]; then
        total="${active_disks%%/*}"
        active="${active_disks##*/}"
        emit_metric "nixl_md_disks_total" "${total}" "device=${current_device}"
        emit_metric "nixl_md_disks_active" "${active}" "device=${current_device}"
        emit_metric "nixl_md_degraded" "$((active < total ? 1 : 0))" "device=${current_device}"
      fi
    fi

    if [[ -n "${current_device}" && "$line" =~ ([0-9]+)[[:space:]]+blocks ]]; then
      size_bytes="$((BASH_REMATCH[1] * 1024))"
      emit_metric "nixl_md_array_size_bytes" "${size_bytes}" "device=${current_device}"
    fi
  done <"${PROC_ROOT}/mdstat"

  shopt -s nullglob
  for mdpath in "${SYS_ROOT}"/block/md*/md; do
    [[ -d "${mdpath}" ]] || continue
    device="$(basename "$(dirname "${mdpath}")")"
    action="$(safe_read_file "${mdpath}/sync_action" || printf 'idle')"
    emit_metric "nixl_md_sync_action" 1 "device=${device}" "action=${action}"
    speed="$(safe_read_file "${mdpath}/sync_speed" || true)"
    speed="${speed%% *}"
    is_integer "$speed" && emit_metric "nixl_md_sync_speed_kbps" "$speed" "device=${device}"
    mismatch="$(safe_read_file "${mdpath}/mismatch_cnt" || true)"
    is_integer "$mismatch" && emit_metric "nixl_md_mismatch_count" "$mismatch" "device=${device}"
    size="$(safe_read_file "${SYS_ROOT}/block/${device}/size" || true)"
    is_integer "$size" && emit_metric "nixl_md_array_size_bytes" "$((size * 512))" "device=${device}"
  done
  shopt -u nullglob
fi

if command_exists "${LVS_CMD}"; then
  source_found=1
  while read -r lv vg attr size data_percent metadata_percent; do
    [[ -n "${lv}" && -n "${vg}" ]] || continue
    size="${size%B}"
    is_number "${size}" && emit_metric "nixl_lvm_lv_size_bytes" "${size}" "vg=${vg}" "lv=${lv}"
    if [[ "${attr:0:1}" == "t" ]]; then
      data_percent="${data_percent%%%}"
      metadata_percent="${metadata_percent%%%}"
      is_number "${data_percent}" && emit_metric "nixl_lvm_thin_data_percent" "${data_percent}" "vg=${vg}" "lv=${lv}"
      is_number "${metadata_percent}" && emit_metric "nixl_lvm_thin_metadata_percent" "${metadata_percent}" "vg=${vg}" "lv=${lv}"
    fi
  done < <("${LVS_CMD}" --noheadings --units b --nosuffix -o lv_name,vg_name,lv_attr,lv_size,data_percent,metadata_percent 2>/dev/null || true)
fi

if ((source_found == 0)); then
  exit 0
fi

prom_end_scrape "nixl_raid_scrape_success"
