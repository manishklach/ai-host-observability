#!/usr/bin/env bash
set -euo pipefail
# shellcheck disable=SC2250,SC2310,SC2312  # Compact fallback reads are intentional in exporter code.

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/prom.sh
source "${SCRIPT_DIR}/lib/prom.sh"

PROC_ROOT="${PROC_ROOT:-/proc}"
CHRONYC="${CHRONYC:-chronyc}"
TIMEDATECTL="${TIMEDATECTL:-timedatectl}"

prom_begin_scrape "nixl_timesync_scrape_success" "Whether the timesync exporter collected clock synchronisation state."
if ! require_directory "${PROC_ROOT}" "PROC_ROOT"; then
  exit 0
fi

emit_help "nixl_timesync_synchronized" gauge "Whether the system clock is synchronised."
emit_help "nixl_timesync_offset_seconds" gauge "Current clock offset in seconds."
emit_help "nixl_timesync_rms_offset_seconds" gauge "Clock RMS offset in seconds."
emit_help "nixl_timesync_freq_error_ppm" gauge "Clock frequency error in parts per million."
emit_help "nixl_timesync_stratum" gauge "Clock stratum."
emit_help "nixl_timesync_reference_id_info" gauge "Reference clock identity labels."
emit_help "nixl_timesync_last_update_seconds" gauge "Seconds since the last chrony update."

if ! command_exists "${CHRONYC}" && ! command_exists "${TIMEDATECTL}"; then
  exit 0
fi

sync_value=0
timedatectl_present=0
if command_exists "${TIMEDATECTL}"; then
  timedatectl_present=1
  ntp_sync="$("${TIMEDATECTL}" show --property=NTPSynchronized --value 2>/dev/null || true)"
  [[ "${ntp_sync}" == "yes" ]] && sync_value=1
fi

chrony_ok=0
if command_exists "${CHRONYC}"; then
  tracking="$("${CHRONYC}" tracking 2>/dev/null || true)"
  if [[ -n "${tracking}" ]]; then
    chrony_ok=1
    system_time_line="$(grep -F 'System time' <<<"${tracking}" || true)"
    rms_line="$(grep -F 'RMS offset' <<<"${tracking}" || true)"
    freq_line="$(grep -F 'Frequency' <<<"${tracking}" || true)"
    stratum_line="$(grep -F 'Stratum' <<<"${tracking}" || true)"
    ref_line="$(grep -F 'Reference ID' <<<"${tracking}" || true)"
    update_line="$(grep -F 'Update interval' <<<"${tracking}" || true)"

    if [[ "${system_time_line}" =~ ([0-9.]+)[[:space:]]+seconds[[:space:]]+(fast|slow) ]]; then
      offset="${BASH_REMATCH[1]}"
      [[ "${BASH_REMATCH[2]}" == "slow" ]] && offset="-${offset}"
      emit_metric "nixl_timesync_offset_seconds" "${offset}"
      sync_value=1
    fi
    if [[ "${rms_line}" =~ ([0-9.]+)[[:space:]]+seconds ]]; then
      emit_metric "nixl_timesync_rms_offset_seconds" "${BASH_REMATCH[1]}"
    fi
    if [[ "${freq_line}" =~ ([+-]?[0-9.]+)[[:space:]]+ppm ]]; then
      emit_metric "nixl_timesync_freq_error_ppm" "${BASH_REMATCH[1]}"
    fi
    if [[ "${stratum_line}" =~ ([0-9]+) ]]; then
      emit_metric "nixl_timesync_stratum" "${BASH_REMATCH[1]}"
    fi
    ref_id="$(sed -nE 's/^Reference ID[[:space:]]*:[[:space:]]*([^[:space:]]+).*/\1/p' <<<"${ref_line}")"
    ref_name="$(sed -nE 's/^Reference ID[[:space:]]*:[[:space:]]*[^[:space:]]+[[:space:]]+\(([^)]+)\).*/\1/p' <<<"${ref_line}")"
    if [[ -n "${ref_id}" && -n "${ref_name}" ]]; then
      emit_metric "nixl_timesync_reference_id_info" 1 "ref_id=${ref_id}" "ref_name=${ref_name}"
    fi
    if [[ "${update_line}" =~ ([0-9.]+)[[:space:]]+seconds ]]; then
      emit_metric "nixl_timesync_last_update_seconds" "${BASH_REMATCH[1]}"
    fi
  fi
fi

emit_metric "nixl_timesync_synchronized" "${sync_value}"
if [[ "${sync_value}" -eq 1 || "${chrony_ok}" -eq 1 || "${timedatectl_present}" -eq 1 ]]; then
  prom_end_scrape "nixl_timesync_scrape_success"
fi
