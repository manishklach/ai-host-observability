#!/usr/bin/env bats
# shellcheck disable=SC2154  # Bats populates TEST_TMPDIR/FIXTURE_DIR/ROOT_DIR via setup hooks and loaded helpers.

load './helpers.bash'

setup() {
  setup_test_env
}

teardown() {
  teardown_test_env
}

@test "nixl_consistency direct fixture run emits kernel, driver, and sysctl facts" {
  run env PROC_ROOT="${FIXTURE_DIR}/proc" NVIDIA_SMI="${FIXTURE_DIR}/bin/nvidia-smi" MODINFO_CMD="${FIXTURE_DIR}/bin/modinfo" DMIDECODE_CMD="${FIXTURE_DIR}/bin/dmidecode" HOSTNAME_CMD="${FIXTURE_DIR}/bin/hostname-fixture" UNAME_CMD="${FIXTURE_DIR}/bin/uname-fixture" bash "${ROOT_DIR}/scripts/host-consistency-exporter.sh"
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *'nixl_host_kernel_version_info{version="6.5.0-45-generic",major="6",minor="5",patch="0"} 1 '* ]]
  [[ "${output}" == *'nixl_host_driver_version_info{driver="nvidia",version="550.54.15"} 1 '* ]]
  [[ "${output}" == *'nixl_host_sysctl{name="net.core.rmem_max"} 134217728 '* ]]
}

@test "nixl_consistency missing proc path emits scrape success 0" {
  run env PROC_ROOT="${TEST_TMPDIR}/missing-proc" bash "${ROOT_DIR}/scripts/host-consistency-exporter.sh"
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *'nixl_consistency_scrape_success 0 '* ]]
}

@test "nixl_consistency respects OUT_DIR via collect-all" {
  out_dir="${TEST_TMPDIR}/consistency-out"
  mkdir -p "${out_dir}"
  run env OUT_DIR="${out_dir}" EXPORTERS="nixl_consistency" PROC_ROOT="${FIXTURE_DIR}/proc" NVIDIA_SMI="${FIXTURE_DIR}/bin/nvidia-smi" MODINFO_CMD="${FIXTURE_DIR}/bin/modinfo" DMIDECODE_CMD="${FIXTURE_DIR}/bin/dmidecode" HOSTNAME_CMD="${FIXTURE_DIR}/bin/hostname-fixture" UNAME_CMD="${FIXTURE_DIR}/bin/uname-fixture" bash "${ROOT_DIR}/scripts/collect-all.sh"
  [[ "${status}" -eq 0 ]]
  [[ -f "${out_dir}/nixl_consistency.prom" ]]
  grep -Fq 'nixl_host_identity_info{hostname="gpu-node-01",fqdn="gpu-node-01.example.net",arch="x86_64"} 1' "${out_dir}/nixl_consistency.prom"
}
