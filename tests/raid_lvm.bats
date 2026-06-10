#!/usr/bin/env bats
# shellcheck disable=SC2154  # Bats populates TEST_TMPDIR/FIXTURE_DIR/ROOT_DIR via setup hooks and loaded helpers.

load './helpers.bash'

setup() {
  setup_test_env
}

teardown() {
  teardown_test_env
}

@test "nixl_raid_lvm direct fixture run emits RAID and LVM metrics" {
  output_file="${TEST_TMPDIR}/raid.prom"

  run env PROC_ROOT="${FIXTURE_DIR}/proc" SYS_ROOT="${FIXTURE_DIR}/sys" LVS_CMD="${FIXTURE_DIR}/bin/lvs" bash "${ROOT_DIR}/scripts/raid-lvm-exporter.sh"
  [[ "${status}" -eq 0 ]]
  exporter_output="${output}"
  printf '%s\n' "${exporter_output}" >"${output_file}"
  run assert_valid_metric_line "${output_file}"
  [[ "${status}" -eq 0 ]]
  [[ "${exporter_output}" == *'nixl_md_degraded{device="md0"} 1 '* ]]
  [[ "${exporter_output}" == *'nixl_lvm_thin_data_percent{vg="vg0",lv="thinpool"} 87.5 '* ]]
}

@test "nixl_raid_lvm missing sources emits scrape success 0" {
  run env PROC_ROOT="${TEST_TMPDIR}/missing-proc" SYS_ROOT="${TEST_TMPDIR}/missing-sys" LVS_CMD="${TEST_TMPDIR}/missing-lvs" bash "${ROOT_DIR}/scripts/raid-lvm-exporter.sh"
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *'nixl_raid_scrape_success 0 '* ]]
}

@test "nixl_raid_lvm respects OUT_DIR via collect-all" {
  out_dir="${TEST_TMPDIR}/raid-out"
  mkdir -p "${out_dir}"

  run run_collect_one "nixl_raid_lvm" "${FIXTURE_DIR}/proc" "${out_dir}"
  [[ "${status}" -eq 0 ]]
  [[ -f "${out_dir}/nixl_raid_lvm.prom" ]]
  grep -Fq 'nixl_md_state{device="md0",level="raid1"}' "${out_dir}/nixl_raid_lvm.prom"
}
