#!/usr/bin/env bats
# shellcheck disable=SC2154  # Bats populates TEST_TMPDIR/FIXTURE_DIR/ROOT_DIR via setup hooks and loaded helpers.

load './helpers.bash'

setup() {
  setup_test_env
}

teardown() {
  teardown_test_env
}

@test "nixl_collector direct fixture run emits file health metrics" {
  out_dir="${TEST_TMPDIR}/collector-prom"
  mkdir -p "${out_dir}"
  cp "${FIXTURE_DIR}/prom-input/host-memory.prom" "${out_dir}/nixl_host_mem.prom"
  cp "${FIXTURE_DIR}/prom-input/gpu.prom" "${out_dir}/nixl_gpu.prom"
  printf '# HELP ai_host_exporter_duration_seconds Exporter execution duration in seconds.\n# TYPE ai_host_exporter_duration_seconds gauge\nai_host_exporter_duration_seconds{exporter="nixl_gpu"} 0.123 1999999900\n' >>"${out_dir}/nixl_gpu.prom"

  run env OUT_DIR="${out_dir}" NOW_EPOCH=2000000000 PS_CMD="${FIXTURE_DIR}/bin/ps-node-exporter" bash "${ROOT_DIR}/scripts/collector-health-exporter.sh"
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *'nixl_collector_exporters_total 2 '* ]]
  [[ "${output}" == *'nixl_collector_node_exporter_running 1 '* ]]
  [[ "${output}" == *'nixl_collector_prom_file_metric_count{exporter="nixl_gpu"}'* ]]
}

@test "nixl_collector missing OUT_DIR emits scrape success 0" {
  run env OUT_DIR="${TEST_TMPDIR}/missing-collector-dir" bash "${ROOT_DIR}/scripts/collector-health-exporter.sh"
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *'nixl_collector_scrape_success 0 '* ]]
}

@test "nixl_collector respects OUT_DIR via collect-all" {
  out_dir="${TEST_TMPDIR}/collector-out"
  mkdir -p "${out_dir}"
  cp "${FIXTURE_DIR}/prom-input/network.prom" "${out_dir}/nixl_network_stack.prom"
  run env OUT_DIR="${out_dir}" EXPORTERS="nixl_collector" NOW_EPOCH=2000000000 PS_CMD="${FIXTURE_DIR}/bin/ps-node-exporter" bash "${ROOT_DIR}/scripts/collect-all.sh"
  [[ "${status}" -eq 0 ]]
  [[ -f "${out_dir}/nixl_collector.prom" ]]
  grep -Fq 'nixl_collector_exporters_total 1' "${out_dir}/nixl_collector.prom"
}
