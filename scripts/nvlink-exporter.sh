#!/usr/bin/env bash
set -euo pipefail
# shellcheck disable=SC2250,SC2310,SC2312  # Compact fallback reads are intentional in exporter code.

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/prom.sh
source "${SCRIPT_DIR}/lib/prom.sh"

PROC_ROOT="${PROC_ROOT:-/proc}"
NVIDIA_SMI="${NVIDIA_SMI:-nvidia-smi}"

prom_begin_scrape "nixl_nvlink_scrape_success" "Whether the NVLink exporter collected link status and error counters."
if ! require_directory "${PROC_ROOT}" "PROC_ROOT"; then
  exit 0
fi

emit_help "nixl_nvlink_state" gauge "NVLink state per GPU and link."
emit_help "nixl_nvlink_replay_errors_total" counter "NVLink replay errors by GPU and link."
emit_help "nixl_nvlink_recovery_errors_total" counter "NVLink recovery errors by GPU and link."
emit_help "nixl_nvlink_crc_flit_errors_total" counter "NVLink flit CRC errors by GPU and link."
emit_help "nixl_nvlink_crc_data_errors_total" counter "NVLink data CRC errors by GPU and link."
emit_help "nixl_nvlink_error_total" counter "Aggregated NVLink errors by GPU and error type."

if ! command_exists "${NVIDIA_SMI}" || ! "${NVIDIA_SMI}" nvlink --status >/dev/null 2>&1; then
  exit 0
fi

while IFS=',' read -r index _uuid _name _pci_bus _rest; do
  index="$(xargs <<<"${index}")"
  [[ -n "${index}" ]] || continue

  replay_total=0
  recovery_total=0
  crc_flit_total=0
  crc_data_total=0

  while IFS= read -r line; do
    [[ "${line}" =~ Link[[:space:]]+([0-9]+):[[:space:]]+(.+) ]] || continue
    link="${BASH_REMATCH[1]}"
    state_raw="${BASH_REMATCH[2]}"
    state="$(tr '[:upper:]' '[:lower:]' <<<"${state_raw}")"
    value=0
    [[ "${state}" == "active" ]] && value=1
    emit_metric "nixl_nvlink_state" "${value}" "index=${index}" "link=${link}" "state=${state}"
  done < <("${NVIDIA_SMI}" nvlink --status -i "${index}" 2>/dev/null || true)

  while IFS= read -r line; do
    [[ "${line}" =~ Link[[:space:]]+([0-9]+):[[:space:]]+Replay[[:space:]]+([0-9]+),[[:space:]]+Recovery[[:space:]]+([0-9]+),[[:space:]]+CRC[[:space:]]+FLIT[[:space:]]+([0-9]+),[[:space:]]+CRC[[:space:]]+DATA[[:space:]]+([0-9]+) ]] || continue
    link="${BASH_REMATCH[1]}"
    replay="${BASH_REMATCH[2]}"
    recovery="${BASH_REMATCH[3]}"
    crc_flit="${BASH_REMATCH[4]}"
    crc_data="${BASH_REMATCH[5]}"

    emit_metric "nixl_nvlink_replay_errors_total" "${replay}" "index=${index}" "link=${link}"
    emit_metric "nixl_nvlink_recovery_errors_total" "${recovery}" "index=${index}" "link=${link}"
    emit_metric "nixl_nvlink_crc_flit_errors_total" "${crc_flit}" "index=${index}" "link=${link}"
    emit_metric "nixl_nvlink_crc_data_errors_total" "${crc_data}" "index=${index}" "link=${link}"
    replay_total=$((replay_total + replay))
    recovery_total=$((recovery_total + recovery))
    crc_flit_total=$((crc_flit_total + crc_flit))
    crc_data_total=$((crc_data_total + crc_data))
  done < <("${NVIDIA_SMI}" nvlink --errorcounters -i "${index}" 2>/dev/null || true)

  emit_metric "nixl_nvlink_error_total" "${replay_total}" "index=${index}" "type=replay"
  emit_metric "nixl_nvlink_error_total" "${recovery_total}" "index=${index}" "type=recovery"
  emit_metric "nixl_nvlink_error_total" "${crc_flit_total}" "index=${index}" "type=crc_flit"
  emit_metric "nixl_nvlink_error_total" "${crc_data_total}" "index=${index}" "type=crc_data"
done < <("${NVIDIA_SMI}" --query-gpu=index,uuid,name,pci.bus_id --format=csv,noheader,nounits 2>/dev/null || true)

prom_end_scrape "nixl_nvlink_scrape_success"
