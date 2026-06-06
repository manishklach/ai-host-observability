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

sanitize_stat_name() {
  tr ' /-' '___' <<<"$1"
}

prom_begin_scrape "nixl_rdma_scrape_success" "Whether the RDMA and NIC exporter completed successfully."

emit_help "nixl_net_up" gauge "Whether the network interface is operationally up."
emit_help "nixl_net_speed_mbps" gauge "Interface speed in megabits per second when available."
emit_help "nixl_net_carrier" gauge "Whether the network interface reports carrier."
emit_help "nixl_net_ethtool_stat" counter "Selected ethtool counters per interface."
emit_help "nixl_infiniband_port_state" gauge "Infiniband port state encoded as the state number."
emit_help "nixl_infiniband_rate_gbps" gauge "Infiniband link rate in Gbps when available."
emit_help "nixl_infiniband_counter" counter "Selected Infiniband hardware counters."

interfaces=()
if [[ -n "${NET_IFACES:-}" ]]; then
  read -r -a interfaces <<<"${NET_IFACES}"
elif [[ -d "${SYS_ROOT}/class/net" ]]; then
  mapfile -t interfaces < <(find "${SYS_ROOT}/class/net" -mindepth 1 -maxdepth 1 -printf '%f\n' 2>/dev/null | sort)
fi

for iface in "${interfaces[@]}"; do
  [[ -d "${SYS_ROOT}/class/net/${iface}" ]] || continue

  operstate="$(safe_read_file "${SYS_ROOT}/class/net/${iface}/operstate" || true)"
  carrier="$(safe_read_file "${SYS_ROOT}/class/net/${iface}/carrier" || printf '0')"
  speed="$(safe_read_file "${SYS_ROOT}/class/net/${iface}/speed" || printf '%s' '-1')"

  emit_metric "nixl_net_up" "$([[ "${operstate}" == "up" ]] && printf '1' || printf '0')" "iface=${iface}"
  is_integer "$carrier" && emit_metric "nixl_net_carrier" "$carrier" "iface=${iface}"
  is_integer "$speed" && emit_metric "nixl_net_speed_mbps" "$speed" "iface=${iface}"

  if command_exists "$ETHTOOL"; then
    while IFS=':' read -r key value; do
      key="$(xargs <<<"$key")"
      value="$(xargs <<<"$value")"
      case "$(sanitize_stat_name "$key")" in
        rx_discards_phy|tx_discards_phy|rx_errors|tx_errors|rx_crc_errors_phy|link_down_events_phy|rx_prio0_buf_discard|tx_timeout|rx_out_of_buffer)
          is_integer "$value" && emit_metric "nixl_net_ethtool_stat" "$value" "iface=${iface}" "stat=$(sanitize_stat_name "$key")"
          ;;
      esac
    done < <("$ETHTOOL" -S "$iface" 2>/dev/null || true)
  fi
done

shopt -s nullglob
for ibdev in "${SYS_ROOT}"/class/infiniband/*; do
  [[ -d "$ibdev" ]] || continue
  dev="$(basename "$ibdev")"
  for portdir in "$ibdev"/ports/*; do
    [[ -d "$portdir" ]] || continue
    port="$(basename "$portdir")"

    state_code="$(awk '{print $1}' "$portdir/state" 2>/dev/null || printf '%s' '-1')"
    is_integer "$state_code" && emit_metric "nixl_infiniband_port_state" "$state_code" "device=${dev}" "port=${port}"

    rate_gbps="$(grep -oE '[0-9]+' "$portdir/rate" 2>/dev/null | head -n 1 || true)"
    is_integer "$rate_gbps" && emit_metric "nixl_infiniband_rate_gbps" "$rate_gbps" "device=${dev}" "port=${port}"

    for counter in port_rcv_errors port_xmit_discards port_rcv_packets port_xmit_packets port_rcv_data port_xmit_data symbol_error unicast_rcv_packets unicast_xmit_packets; do
      value="$(safe_read_file "${portdir}/counters/${counter}" || true)"
      is_integer "$value" && emit_metric "nixl_infiniband_counter" "$value" "device=${dev}" "port=${port}" "counter=${counter}"
    done
  done
done
shopt -u nullglob

prom_end_scrape "nixl_rdma_scrape_success"
