#!/usr/bin/env bats
# shellcheck disable=SC2154  # Bats populates TEST_TMPDIR/FIXTURE_DIR/ROOT_DIR via setup hooks and loaded helpers.

load './helpers.bash'

setup() {
  setup_test_env
}

teardown() {
  teardown_test_env
}

@test "nixl_baseline direct fixture run emits rolling baseline metrics" {
  out_dir="${TEST_TMPDIR}/baseline-prom"
  mkdir -p "${out_dir}"
  cp "${FIXTURE_DIR}"/prom-input/*.prom "${out_dir}/"

  run env OUT_DIR="${out_dir}" BASELINE_WINDOW_SIZE=8 bash "${ROOT_DIR}/scripts/anomaly-baseline-exporter.sh"
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *'nixl_baseline_mean{metric_id="fw_pages_sum"}'* ]]
  [[ "${output}" == *'nixl_baseline_current{metric_id="gpu_util_mean"}'* ]]
  [[ "${output}" == *'nixl_baseline_window_size{metric_id="softnet_drops"}'* ]]
}

@test "nixl_baseline missing OUT_DIR emits scrape success 0" {
  run env OUT_DIR="${TEST_TMPDIR}/does-not-exist" bash "${ROOT_DIR}/scripts/anomaly-baseline-exporter.sh"
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *'nixl_baseline_scrape_success 0 '* ]]
}

@test "nixl_baseline respects OUT_DIR via collect-all" {
  out_dir="${TEST_TMPDIR}/baseline-out"
  mkdir -p "${out_dir}"
  cp "${FIXTURE_DIR}"/prom-input/*.prom "${out_dir}/"

  run env OUT_DIR="${out_dir}" EXPORTERS="nixl_baseline" bash "${ROOT_DIR}/scripts/collect-all.sh"
  [[ "${status}" -eq 0 ]]
  [[ -f "${out_dir}/nixl_baseline.prom" ]]
  grep -Fq 'nixl_baseline_mean{metric_id="psi_mem_some_60"}' "${out_dir}/nixl_baseline.prom"
}
