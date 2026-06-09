#!/usr/bin/env bats
# shellcheck disable=SC2154  # Bats populates TEST_TMPDIR/FIXTURE_DIR/ROOT_DIR via setup hooks and loaded helpers.

load './helpers.bash'

setup() {
  setup_test_env
}

teardown() {
  teardown_test_env
}

@test "nixl_gpumem direct fixture run emits process and fragmentation metrics" {
  run env NVIDIA_SMI="${FIXTURE_DIR}/bin/nvidia-smi" bash "${ROOT_DIR}/scripts/gpu-mem-pressure-exporter.sh"
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *'nixl_gpu_process_memory_bytes{index="0",uuid="GPU-123",pid="4242",process_name="python"} 6442450944 '* ]]
  [[ "${output}" == *'nixl_gpu_memory_fragmentation_ratio{index="0",uuid="GPU-123"} 0.125000 '* ]]
  [[ "${output}" == *'nixl_gpu_retired_pages_pending{index="0",uuid="GPU-123"} 1 '* ]]
}

@test "nixl_gpumem missing nvidia-smi emits scrape success 0" {
  run env NVIDIA_SMI="${TEST_TMPDIR}/missing-nvidia-smi" bash "${ROOT_DIR}/scripts/gpu-mem-pressure-exporter.sh"
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *'nixl_gpumem_scrape_success 0 '* ]]
}

@test "nixl_gpumem respects OUT_DIR via collect-all" {
  out_dir="${TEST_TMPDIR}/gpumem-out"
  mkdir -p "${out_dir}"
  run env OUT_DIR="${out_dir}" EXPORTERS="nixl_gpumem" NVIDIA_SMI="${FIXTURE_DIR}/bin/nvidia-smi" bash "${ROOT_DIR}/scripts/collect-all.sh"
  [[ "${status}" -eq 0 ]]
  [[ -f "${out_dir}/nixl_gpumem.prom" ]]
  grep -Fq 'nixl_gpu_process_count{index="0",uuid="GPU-123"} 2' "${out_dir}/nixl_gpumem.prom"
}
