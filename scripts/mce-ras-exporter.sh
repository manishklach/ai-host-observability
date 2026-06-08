#!/usr/bin/env bash
set -euo pipefail
# shellcheck disable=SC2250,SC2310,SC2312  # Compact fallback reads are intentional in exporter code.

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/prom.sh
source "${SCRIPT_DIR}/lib/prom.sh"

PROC_ROOT="${PROC_ROOT:-/proc}"
SYS_ROOT="${SYS_ROOT:-/sys}"
RASDAEMON="${RASDAEMON:-rasdaemon}"
RAS_MC_CTL="${RAS_MC_CTL:-ras-mc-ctl}"
MCELOG_PATH="${MCELOG_PATH:-/dev/mcelog}"

emit_help "nixl_mce_scrape_success" gauge "Whether the MCE and RAS exporter collected counters for a given source."
emit_metric "nixl_mce_scrape_success" 0 "source=edac"
emit_metric "nixl_mce_scrape_success" 0 "source=edac_cpu"
emit_metric "nixl_mce_scrape_success" 0 "source=rasdaemon"
emit_metric "nixl_mce_scrape_success" 0 "source=mcelog"

if ! require_directory "${SYS_ROOT}" "SYS_ROOT"; then
  exit 0
fi

emit_help "nixl_edac_correctable_errors_total" counter "Correctable EDAC errors per memory controller and DIMM/channel."
emit_help "nixl_edac_uncorrectable_errors_total" counter "Uncorrectable EDAC errors per memory controller and DIMM/channel."
emit_help "nixl_edac_ce_noinfo_count" counter "Correctable EDAC events without DIMM channel attribution."
emit_help "nixl_edac_ue_noinfo_count" counter "Uncorrectable EDAC events without DIMM channel attribution."
emit_help "nixl_edac_cpu_ce_count" counter "Per-bank CPU correctable EDAC errors."
emit_help "nixl_edac_cpu_ue_count" counter "Per-bank CPU uncorrectable EDAC errors."
emit_help "nixl_rasdaemon_ce_total" counter "rasdaemon-reported correctable memory errors by DIMM."
emit_help "nixl_rasdaemon_ue_total" counter "rasdaemon-reported uncorrectable memory errors by DIMM."
emit_help "nixl_mcelog_events_total" counter "mcelog events grouped by bank and MCG status."

edac_ok=0
shopt -s nullglob
for mc_dir in "${SYS_ROOT}/devices/system/edac/mc"/mc*; do
  [[ -d "${mc_dir}" ]] || continue
  controller="$(basename "${mc_dir}")"
  any_controller_counter=0

  for dimm_dir in "${mc_dir}"/dimm* "${mc_dir}"/rank* "${mc_dir}"/csrow*; do
    [[ -d "${dimm_dir}" ]] || continue
    channel="$(basename "${dimm_dir}")"
    ce_count="$(safe_read_file "${dimm_dir}/dimm_ce_count" || safe_read_file "${dimm_dir}/ce_count" || true)"
    ue_count="$(safe_read_file "${dimm_dir}/dimm_ue_count" || safe_read_file "${dimm_dir}/ue_count" || true)"

    if is_integer "${ce_count}"; then
      emit_metric "nixl_edac_correctable_errors_total" "${ce_count}" "controller=${controller}" "channel=${channel}"
      any_controller_counter=1
    fi
    if is_integer "${ue_count}"; then
      emit_metric "nixl_edac_uncorrectable_errors_total" "${ue_count}" "controller=${controller}" "channel=${channel}"
      any_controller_counter=1
    fi
  done

  ce_noinfo="$(safe_read_file "${mc_dir}/ce_noinfo_count" || true)"
  ue_noinfo="$(safe_read_file "${mc_dir}/ue_noinfo_count" || true)"
  if is_integer "${ce_noinfo}"; then
    emit_metric "nixl_edac_ce_noinfo_count" "${ce_noinfo}" "controller=${controller}"
    any_controller_counter=1
  fi
  if is_integer "${ue_noinfo}"; then
    emit_metric "nixl_edac_ue_noinfo_count" "${ue_noinfo}" "controller=${controller}"
    any_controller_counter=1
  fi

  if [[ "${any_controller_counter}" -eq 1 ]]; then
    edac_ok=1
  fi
done

cpu_edac_ok=0
for cpu_dir in "${SYS_ROOT}/devices/system/edac/cpu"/cpu*; do
  [[ -d "${cpu_dir}" ]] || continue
  cpu="$(basename "${cpu_dir}")"
  for bank_dir in "${cpu_dir}"/bank*; do
    [[ -d "${bank_dir}" ]] || continue
    bank="$(basename "${bank_dir}")"
    ce_count="$(safe_read_file "${bank_dir}/ce_count" || true)"
    ue_count="$(safe_read_file "${bank_dir}/ue_count" || true)"
    if is_integer "${ce_count}"; then
      emit_metric "nixl_edac_cpu_ce_count" "${ce_count}" "cpu=${cpu}" "bank=${bank}"
      cpu_edac_ok=1
    fi
    if is_integer "${ue_count}"; then
      emit_metric "nixl_edac_cpu_ue_count" "${ue_count}" "cpu=${cpu}" "bank=${bank}"
      cpu_edac_ok=1
    fi
  done
done
shopt -u nullglob

ras_ok=0
if command_exists "${RASDAEMON}" && command_exists "${RAS_MC_CTL}" && "${RASDAEMON}" --version >/dev/null 2>&1; then
  while IFS= read -r line; do
    line_lower="$(tr '[:upper:]' '[:lower:]' <<<"${line}")"
    count="$(grep -oE '[0-9]+' <<<"${line}" | head -n 1 || true)"
    dimm="$(sed -nE 's/.*(DIMM[^ ,;]*).*/\1/p' <<<"${line}" | head -n 1 || true)"
    [[ -n "${dimm}" ]] || dimm="unknown"

    if [[ "${line_lower}" == *" ce "* || "${line_lower}" == ce:* || "${line_lower}" == *"correctable"* ]]; then
      if is_integer "${count}"; then
        emit_metric "nixl_rasdaemon_ce_total" "${count}" "dimm=${dimm}"
        ras_ok=1
      fi
    elif [[ "${line_lower}" == *" ue "* || "${line_lower}" == ue:* || "${line_lower}" == *"uncorrectable"* ]]; then
      if is_integer "${count}"; then
        emit_metric "nixl_rasdaemon_ue_total" "${count}" "dimm=${dimm}"
        ras_ok=1
      fi
    fi
  done < <("${RAS_MC_CTL}" --errors 2>/dev/null | tail -n 30 || true)
fi

mcelog_ok=0
if [[ -r "${MCELOG_PATH}" ]]; then
  awk '
    BEGIN {
      bank = "unknown"
      mcg = "unknown"
    }
    /bank[[:space:]]+[0-9]+/ {
      match($0, /bank[[:space:]]+([0-9]+)/, arr)
      if (arr[1] != "") {
        bank = arr[1]
      }
    }
    /MCG status:/ {
      match($0, /MCG status:[[:space:]]*([^[:space:]]+)/, arr)
      if (arr[1] != "") {
        mcg = arr[1]
      }
      counts[bank "|" mcg]++
    }
    END {
      for (key in counts) {
        split(key, parts, /\|/)
        printf "%s %s %s\n", parts[1], parts[2], counts[key]
      }
    }
  ' "${MCELOG_PATH}" | while read -r bank mcg_status count; do
    if is_integer "${count}"; then
      emit_metric "nixl_mcelog_events_total" "${count}" "bank=${bank}" "mcg_status=${mcg_status}"
      mcelog_ok=1
    fi
  done
fi

emit_metric "nixl_mce_scrape_success" "${edac_ok}" "source=edac"
emit_metric "nixl_mce_scrape_success" "${cpu_edac_ok}" "source=edac_cpu"
emit_metric "nixl_mce_scrape_success" "${ras_ok}" "source=rasdaemon"
emit_metric "nixl_mce_scrape_success" "${mcelog_ok}" "source=mcelog"
