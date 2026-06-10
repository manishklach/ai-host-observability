#!/usr/bin/env bats
# shellcheck disable=SC2154  # Bats populates TEST_TMPDIR/FIXTURE_DIR/ROOT_DIR via setup hooks and loaded helpers.

load './helpers.bash'

setup() {
  setup_test_env
}

teardown() {
  teardown_test_env
}

@test "nixl_nvme direct fixture run emits SMART metrics" {
  output_file="${TEST_TMPDIR}/nvme.prom"

  run env DEV_ROOT="${FIXTURE_DIR}/dev" NVME_CMD="${FIXTURE_DIR}/bin/nvme" bash "${ROOT_DIR}/scripts/nvme-smart-exporter.sh"
  [[ "${status}" -eq 0 ]]
  exporter_output="${output}"
  printf '%s\n' "${exporter_output}" >"${output_file}"
  run assert_valid_metric_line "${output_file}"
  [[ "${status}" -eq 0 ]]
  [[ "${exporter_output}" == *'nixl_nvme_percentage_used{device="/dev/nvme0n1"'* ]]
  [[ "${exporter_output}" == *'nixl_nvme_temperature_celsius{device="/dev/nvme0n1",model="Fixture NVMe Model 1234567890",serial="SN1234567890FIXTURE",sensor="composite"} 70 '* ]]
}

@test "nixl_nvme missing source emits scrape success 0" {
  while IFS= read -r assignment; do
    name="${assignment%%=*}"
    value="${assignment#*=}"
    export "${name}=${value}"
  done < <(common_env)

  run env DEV_ROOT="${TEST_TMPDIR}/missing-dev" NVME_CMD="${TEST_TMPDIR}/missing-nvme" bash "${ROOT_DIR}/scripts/nvme-smart-exporter.sh"
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *'nixl_nvme_scrape_success 0 '* ]]
}

@test "nixl_nvme respects OUT_DIR via collect-all" {
  out_dir="${TEST_TMPDIR}/nvme-out"
  mkdir -p "${out_dir}"

  run run_collect_one "nixl_nvme" "${FIXTURE_DIR}/proc" "${out_dir}"
  [[ "${status}" -eq 0 ]]
  [[ -f "${out_dir}/nixl_nvme.prom" ]]
  grep -Fq 'nixl_nvme_available_spare_percent{device="/dev/nvme0n1"' "${out_dir}/nixl_nvme.prom"
}
