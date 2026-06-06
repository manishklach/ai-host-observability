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

emit_help "nixl_network_stack_scrape_success" "gauge" "Whether the network stack exporter completed successfully."
emit_metric "nixl_network_stack_scrape_success" "0"

emit_help "nixl_netdev_total" "counter" "Selected /proc/net/dev counters per interface."
tail -n +3 /proc/net/dev | while read -r iface rest; do
  iface="${iface%:}"
  read -r rx_bytes rx_packets rx_errs rx_drop _ _ _ _ tx_bytes tx_packets tx_errs tx_drop _ _ _ _ <<<"$rest"
  emit_metric "nixl_netdev_total" "$rx_bytes" "iface=\"$iface\",field=\"rx_bytes\""
  emit_metric "nixl_netdev_total" "$rx_packets" "iface=\"$iface\",field=\"rx_packets\""
  emit_metric "nixl_netdev_total" "$rx_errs" "iface=\"$iface\",field=\"rx_errs\""
  emit_metric "nixl_netdev_total" "$rx_drop" "iface=\"$iface\",field=\"rx_drop\""
  emit_metric "nixl_netdev_total" "$tx_bytes" "iface=\"$iface\",field=\"tx_bytes\""
  emit_metric "nixl_netdev_total" "$tx_packets" "iface=\"$iface\",field=\"tx_packets\""
  emit_metric "nixl_netdev_total" "$tx_errs" "iface=\"$iface\",field=\"tx_errs\""
  emit_metric "nixl_netdev_total" "$tx_drop" "iface=\"$iface\",field=\"tx_drop\""
done

emit_help "nixl_softnet_stat_total" "counter" "Selected /proc/net/softnet_stat counters per CPU."
cpu=0
while read -r processed dropped time_squeezed rest; do
  emit_metric "nixl_softnet_stat_total" "$((16#$processed))" "cpu=\"$cpu\",field=\"processed\""
  emit_metric "nixl_softnet_stat_total" "$((16#$dropped))" "cpu=\"$cpu\",field=\"dropped\""
  emit_metric "nixl_softnet_stat_total" "$((16#$time_squeezed))" "cpu=\"$cpu\",field=\"time_squeezed\""
  cpu=$((cpu + 1))
done < /proc/net/softnet_stat

emit_help "nixl_snmp_total" "counter" "Selected SNMP counters from /proc/net/snmp."
awk '
  NR % 2 == 1 { proto=$1; sub(":", "", proto); for (i=2; i<=NF; i++) keys[i]=$i; next }
  {
    for (i=2; i<=NF; i++) {
      key=keys[i]
      if (key ~ /RetransSegs|InErrs|OutRsts|InSegs|OutSegs|InDiscards|OutDiscards|ReasmFails/) {
        printf "%s %s %s\n", proto, key, $i
      }
    }
  }
' /proc/net/snmp | while read -r proto key value; do
  emit_metric "nixl_snmp_total" "$value" "protocol=\"$proto\",field=\"$key\""
done

emit_metric "nixl_network_stack_scrape_success" "1"
