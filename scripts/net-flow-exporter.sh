#!/usr/bin/env bash
set -euo pipefail
# shellcheck disable=SC2250,SC2310,SC2312  # Compact conditionals and fallback reads are intentional in exporter code.

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/prom.sh
source "${SCRIPT_DIR}/lib/prom.sh"

PROC_ROOT="${PROC_ROOT:-/proc}"
SYS_ROOT="${SYS_ROOT:-/sys}"
OUT_DIR="${OUT_DIR:-/var/lib/node_exporter/textfile_collector}"
STATE_DIR="${STATE_DIR:-${OUT_DIR}/.netflow}"
SS_CMD="${SS_CMD:-ss}"
NOW_EPOCH="${NOW_EPOCH:-$(date +%s)}"

port_class() {
  local port="$1"
  case "${port}" in
    4791) printf 'rdma\n' ;;
    22) printf 'ssh\n' ;;
    40000|4[0-9][0-9][0-9][0-9]|50000|5[0-9][0-9][0-9][0-9]|60000) printf 'nccl\n' ;;
    *) printf 'other\n' ;;
  esac
}

remote_host_prefix() {
  local endpoint="$1"
  local host_part="${endpoint%:*}"
  awk -F. 'NF == 4 { printf "%s.%s.%s.0/24\n", $1, $2, $3 }' <<<"${host_part}"
}

current_state_value() {
  local key="$1"
  local raw_value="$2"
  local state_file="${STATE_DIR}/${key}.state"
  local rate_value="0"
  mkdir -p "${STATE_DIR}"
  if [[ -r "${state_file}" ]]; then
    read -r previous_value previous_time <"${state_file}"
    if is_number "${previous_value}" && is_integer "${previous_time}" && ((NOW_EPOCH > previous_time)); then
      rate_value="$(awk -v curr="${raw_value}" -v prev="${previous_value}" -v now="${NOW_EPOCH}" -v then="${previous_time}" 'BEGIN {
        delta = curr - prev
        elapsed = now - then
        if (delta < 0 || elapsed <= 0) {
          print 0
        } else {
          printf "%.6f", delta / elapsed
        }
      }')"
    fi
  fi
  printf '%s %s\n' "${raw_value}" "${NOW_EPOCH}" >"${state_file}"
  printf '%s\n' "${rate_value}"
}

prom_begin_scrape "nixl_netflow_scrape_success" "Whether the network flow exporter completed successfully."
if ! command_exists "${SS_CMD}" || [[ ! -r "${PROC_ROOT}/net/tcp" ]]; then
  exit 0
fi

emit_help "nixl_netflow_tcp_established_total" gauge "Established TCP socket count grouped by local port class."
emit_help "nixl_netflow_tcp_close_wait_total" gauge "Count of TCP sockets in CLOSE-WAIT."
emit_help "nixl_netflow_tcp_time_wait_total" gauge "Count of TCP sockets in TIME-WAIT."
emit_help "nixl_netflow_udp_established_total" gauge "Count of established UDP sockets."
emit_help "nixl_netflow_tcp_retrans_total" counter "Per-scrape TCP retransmit proxy grouped by local port class."
emit_help "nixl_netflow_iface_rx_utilization_ratio" gauge "Interface RX utilization ratio based on byte deltas and link speed."
emit_help "nixl_netflow_iface_tx_utilization_ratio" gauge "Interface TX utilization ratio based on byte deltas and link speed."
emit_help "nixl_netflow_nccl_connections_detected" gauge "Count of likely NCCL TCP connections using ephemeral high ports."
emit_help "nixl_netflow_nccl_remote_hosts_total" gauge "Distinct remote hosts involved in likely NCCL TCP connections."
emit_help "nixl_netstat_ext" counter "Selected extended TCP counters from /proc/net/netstat."

declare -A tcp_counts=()
declare -A retrans_counts=()
declare -A nccl_hosts=()
nccl_connections=0

while read -r state _q1 _q2 local_addr remote_addr _rest; do
  [[ -n "${state}" ]] || continue
  local_port="${local_addr##*:}"
  remote_prefix="$(remote_host_prefix "${remote_addr}")"
  class="$(port_class "${local_port}")"
  tcp_counts["${class}"]=$(( ${tcp_counts["${class}"]:-0} + 1 ))
  if [[ "${class}" == "nccl" ]]; then
    nccl_connections=$((nccl_connections + 1))
    [[ -n "${remote_prefix}" ]] && nccl_hosts["${remote_prefix}"]=1
  fi
  retrans="$(grep -o 'retrans:[0-9]\+' <<<"${_rest}" | head -n1 | cut -d: -f2)"
  if is_integer "${retrans}"; then
    retrans_counts["${class}"]=$(( ${retrans_counts["${class}"]:-0} + retrans ))
  fi
done < <("${SS_CMD}" --no-header --tcp --info state established 2>/dev/null || true)

for class in nccl rdma ssh other; do
  emit_metric "nixl_netflow_tcp_established_total" "${tcp_counts["${class}"]:-0}" "local_port_class=${class}"
  emit_metric "nixl_netflow_tcp_retrans_total" "${retrans_counts["${class}"]:-0}" "local_port_class=${class}"
done

time_wait_total="$("${SS_CMD}" --no-header --tcp --info state time-wait 2>/dev/null | awk 'NF > 0 { count++ } END { print count + 0 }')"
close_wait_total="$("${SS_CMD}" --no-header --tcp --info state close-wait 2>/dev/null | awk 'NF > 0 { count++ } END { print count + 0 }')"
udp_total="$("${SS_CMD}" --no-header --udp state established 2>/dev/null | awk 'NF > 0 { count++ } END { print count + 0 }')"
emit_metric "nixl_netflow_tcp_time_wait_total" "${time_wait_total}"
emit_metric "nixl_netflow_tcp_close_wait_total" "${close_wait_total}"
emit_metric "nixl_netflow_udp_established_total" "${udp_total}"
emit_metric "nixl_netflow_nccl_connections_detected" "${nccl_connections}"
emit_metric "nixl_netflow_nccl_remote_hosts_total" "${#nccl_hosts[@]}"

if [[ -r "${PROC_ROOT}/net/dev" ]]; then
  while IFS= read -r line; do
    iface="$(xargs <<<"${line%%:*}")"
    [[ -n "${iface}" && "${iface}" != "lo" ]] || continue
    rest="${line#*:}"
    read -r rx_bytes _rx_packets _rx_errs _rx_drop _a _b _c _d tx_bytes _tx_packets _tx_errs _tx_drop _e _f _g _h <<<"${rest}"
    speed_file="${SYS_ROOT}/class/net/${iface}/speed"
    speed_mbps="$(safe_read_file "${speed_file}" || true)"
    if ! is_integer "${speed_mbps}" || ((speed_mbps <= 0)); then
      continue
    fi
    speed_bytes_per_sec="$(awk -v speed_mbps="${speed_mbps}" 'BEGIN { printf "%.6f", (speed_mbps * 1000000) / 8 }')"
    rx_rate="$(current_state_value "${iface}_rx_bytes" "${rx_bytes}")"
    tx_rate="$(current_state_value "${iface}_tx_bytes" "${tx_bytes}")"
    rx_util="$(awk -v rate="${rx_rate}" -v capacity="${speed_bytes_per_sec}" 'BEGIN { if (capacity <= 0) print 0; else printf "%.6f", rate / capacity }')"
    tx_util="$(awk -v rate="${tx_rate}" -v capacity="${speed_bytes_per_sec}" 'BEGIN { if (capacity <= 0) print 0; else printf "%.6f", rate / capacity }')"
    emit_metric "nixl_netflow_iface_rx_utilization_ratio" "${rx_util}" "iface=${iface}"
    emit_metric "nixl_netflow_iface_tx_utilization_ratio" "${tx_util}" "iface=${iface}"
  done < <(tail -n +3 "${PROC_ROOT}/net/dev")
fi

if [[ -r "${PROC_ROOT}/net/netstat" ]]; then
  awk '
    /^TcpExt:/ && header_seen == 0 {
      for (i = 2; i <= NF; i++) {
        headers[i] = $i
      }
      header_seen = 1
      next
    }
    /^TcpExt:/ && header_seen == 1 {
      for (i = 2; i <= NF; i++) {
        key = headers[i]
        if (key ~ /TCPSynRetrans|TCPRetransFail|TCPSchedulerFailed|TCPTIMEOUTS|TCPSpuriousRTOs|TCPLostRetransmit|TCPFastRetrans|TCPSlowStartRetrans|TCPForwardRetrans|TCPFromZeroWindowAdv|TCPToZeroWindowAdv|TCPWantZeroWindowAdv|TCPSackRetrans/) {
          printf "%s %s\n", key, $i
        }
      }
      exit
    }
  ' "${PROC_ROOT}/net/netstat" | while read -r field value; do
    is_integer "${value}" && emit_metric "nixl_netstat_ext" "${value}" "field=${field}"
  done
fi

prom_end_scrape "nixl_netflow_scrape_success"
