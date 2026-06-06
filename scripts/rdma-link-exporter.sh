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

interfaces=()
if [[ -n "${NET_IFACES:-}" ]]; then
  read -r -a interfaces <<<"${NET_IFACES}"
else
  while IFS= read -r iface; do
    interfaces+=("$iface")
  done < <(find /sys/class/net -mindepth 1 -maxdepth 1 -type l -printf '%f\n' 2>/dev/null | sort)
fi

emit_help "nixl_rdma_scrape_success" "gauge" "Whether the exporter completed successfully."
emit_metric "nixl_rdma_scrape_success" "0"

emit_help "nixl_net_up" "gauge" "Whether the network interface is operationally up."
emit_help "nixl_net_speed_mbps" "gauge" "Interface speed in megabits per second when available."
emit_help "nixl_net_carrier" "gauge" "Whether the network interface reports carrier."
emit_help "nixl_net_ethtool_stat" "counter" "Selected ethtool counters per interface."
emit_help "nixl_infiniband_port_state" "gauge" "Infiniband port state encoded as a small integer."
emit_help "nixl_infiniband_rate_gbps" "gauge" "Infiniband link rate in Gbps when available."
emit_help "nixl_infiniband_counter" "counter" "Selected Infiniband hardware counters."

for iface in "${interfaces[@]}"; do
  [[ -d "/sys/class/net/${iface}" ]] || continue

  operstate="$(<"/sys/class/net/${iface}/operstate")"
  carrier="0"
  [[ -f "/sys/class/net/${iface}/carrier" ]] && carrier="$(<"/sys/class/net/${iface}/carrier")"
  speed="-1"
  if [[ -f "/sys/class/net/${iface}/speed" ]]; then
    speed="$(cat "/sys/class/net/${iface}/speed" 2>/dev/null || printf '%s' '-1')"
  fi

  up="0"
  [[ "$operstate" == "up" ]] && up="1"

  emit_metric "nixl_net_up" "$up" "iface=\"$iface\""
  emit_metric "nixl_net_carrier" "$carrier" "iface=\"$iface\""
  emit_metric "nixl_net_speed_mbps" "$speed" "iface=\"$iface\""

  if command -v ethtool >/dev/null 2>&1; then
    while IFS=':' read -r key value; do
      stat_name="$(xargs <<<"$key" | tr ' /-' '___')"
      stat_value="$(xargs <<<"$value")"
      [[ "$stat_value" =~ ^[0-9]+$ ]] || continue
      case "$stat_name" in
        rx_discards_phy|tx_discards_phy|rx_errors|tx_errors|rx_crc_errors_phy|link_down_events_phy|rx_prio0_buf_discard|tx_timeout|rx_out_of_buffer)
          emit_metric "nixl_net_ethtool_stat" "$stat_value" "iface=\"$iface\",stat=\"$stat_name\""
          ;;
      esac
    done < <(ethtool -S "$iface" 2>/dev/null || true)
  fi
done

shopt -s nullglob
for ibdev in /sys/class/infiniband/*; do
  dev="$(basename "$ibdev")"
  for portdir in "$ibdev"/ports/*; do
    [[ -d "$portdir" ]] || continue
    port="$(basename "$portdir")"

    state_code="-1"
    if [[ -f "$portdir/state" ]]; then
      state_code="$(awk '{print $1}' "$portdir/state")"
    fi
    emit_metric "nixl_infiniband_port_state" "$state_code" "device=\"$dev\",port=\"$port\""

    if [[ -f "$portdir/rate" ]]; then
      rate_gbps="$(grep -oE '[0-9]+' "$portdir/rate" | head -n1 || true)"
      [[ -n "$rate_gbps" ]] && emit_metric "nixl_infiniband_rate_gbps" "$rate_gbps" "device=\"$dev\",port=\"$port\""
    fi

    for counter in port_rcv_errors port_xmit_discards port_rcv_packets port_xmit_packets port_rcv_data port_xmit_data symbol_error unicast_rcv_packets unicast_xmit_packets; do
      path="$portdir/counters/$counter"
      [[ -f "$path" ]] || continue
      value="$(<"$path")"
      [[ "$value" =~ ^[0-9]+$ ]] || continue
      emit_metric "nixl_infiniband_counter" "$value" "device=\"$dev\",port=\"$port\",counter=\"$counter\""
    done
  done
done
shopt -u nullglob

emit_metric "nixl_rdma_scrape_success" "1"
