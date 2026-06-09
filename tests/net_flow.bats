#!/usr/bin/env bats
# shellcheck disable=SC2154  # Bats populates TEST_TMPDIR/FIXTURE_DIR/ROOT_DIR via setup hooks and loaded helpers.

load './helpers.bash'

setup() {
  setup_test_env
}

teardown() {
  teardown_test_env
}

@test "nixl_netflow direct fixture run emits TCP, retransmit, and netstat metrics" {
  run env PROC_ROOT="${FIXTURE_DIR}/proc" SYS_ROOT="${FIXTURE_DIR}/sys" OUT_DIR="${TEST_TMPDIR}/netflow-state" SS_CMD="${FIXTURE_DIR}/bin/ss" NOW_EPOCH=2000000000 bash "${ROOT_DIR}/scripts/net-flow-exporter.sh"
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *'nixl_netflow_tcp_established_total{local_port_class="nccl"} 1 '* ]]
  [[ "${output}" == *'nixl_netflow_tcp_retrans_total{local_port_class="rdma"} 1 '* ]]
  [[ "${output}" == *'nixl_netstat_ext{field="TCPSynRetrans"} 14 '* ]]
}

@test "nixl_netflow missing ss command emits scrape success 0" {
  run env PROC_ROOT="${FIXTURE_DIR}/proc" OUT_DIR="${TEST_TMPDIR}/netflow-missing" SS_CMD="${TEST_TMPDIR}/missing-ss" bash "${ROOT_DIR}/scripts/net-flow-exporter.sh"
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *'nixl_netflow_scrape_success 0 '* ]]
}

@test "nixl_netflow respects OUT_DIR via collect-all" {
  out_dir="${TEST_TMPDIR}/netflow-out"
  mkdir -p "${out_dir}"
  run env PROC_ROOT="${FIXTURE_DIR}/proc" SYS_ROOT="${FIXTURE_DIR}/sys" OUT_DIR="${out_dir}" EXPORTERS="nixl_netflow" SS_CMD="${FIXTURE_DIR}/bin/ss" NOW_EPOCH=2000000000 bash "${ROOT_DIR}/scripts/collect-all.sh"
  [[ "${status}" -eq 0 ]]
  [[ -f "${out_dir}/nixl_netflow.prom" ]]
  grep -Fq 'nixl_netflow_tcp_time_wait_total 2' "${out_dir}/nixl_netflow.prom"
}
