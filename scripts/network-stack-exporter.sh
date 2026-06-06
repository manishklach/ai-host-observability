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

require_directory "$PROC_ROOT" "PROC_ROOT"

prom_begin_scrape "nixl_network_stack_scrape_success" "Whether the generic network stack exporter completed successfully."

emit_help "nixl_netdev_total" counter "Selected ${PROC_ROOT}/net/dev counters per interface."
if [[ -r "${PROC_ROOT}/net/dev" ]]; then
  while IFS= read -r line; do
    iface="$(xargs <<<"${line%%:*}")"
    rest="${line#*:}"
    read -r rx_bytes rx_packets rx_errs rx_drop _ _ _ _ tx_bytes tx_packets tx_errs tx_drop _ _ _ _ <<<"$rest"
    for item in rx_bytes rx_packets rx_errs rx_drop tx_bytes tx_packets tx_errs tx_drop; do
      value="${!item}"
      is_integer "$value" && emit_metric "nixl_netdev_total" "$value" "iface=${iface}" "field=${item}"
    done
  done < <(tail -n +3 "${PROC_ROOT}/net/dev")
fi

emit_help "nixl_softnet_stat_total" counter "Selected ${PROC_ROOT}/net/softnet_stat counters per CPU."
if [[ -r "${PROC_ROOT}/net/softnet_stat" ]]; then
  cpu=0
  while read -r processed dropped time_squeezed _rest; do
    [[ -n "${processed}" ]] || continue
    emit_metric "nixl_softnet_stat_total" "$((16#${processed}))" "cpu=${cpu}" "field=processed"
    emit_metric "nixl_softnet_stat_total" "$((16#${dropped}))" "cpu=${cpu}" "field=dropped"
    emit_metric "nixl_softnet_stat_total" "$((16#${time_squeezed}))" "cpu=${cpu}" "field=time_squeezed"
    cpu=$((cpu + 1))
  done <"${PROC_ROOT}/net/softnet_stat"
fi

emit_help "nixl_snmp_total" counter "Selected SNMP counters from ${PROC_ROOT}/net/snmp."
if [[ -r "${PROC_ROOT}/net/snmp" ]]; then
  while read -r proto key value; do
    is_integer "$value" && emit_metric "nixl_snmp_total" "$value" "protocol=${proto}" "field=${key}"
  done < <(awk '
    NR % 2 == 1 { proto=$1; sub(":", "", proto); for (i=2; i<=NF; i++) keys[i]=$i; next }
    {
      for (i=2; i<=NF; i++) {
        key=keys[i]
        if (key ~ /RetransSegs|InErrs|OutRsts|InSegs|OutSegs|InDiscards|OutDiscards|ReasmFails/) {
          printf "%s %s %s\n", proto, key, $i
        }
      }
    }
  ' "${PROC_ROOT}/net/snmp")
fi

prom_end_scrape
