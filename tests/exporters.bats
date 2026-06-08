#!/usr/bin/env bats
# shellcheck disable=SC2154  # Bats populates TEST_TMPDIR/FIXTURE_DIR/ROOT_DIR via setup hooks and loaded helpers.

load './helpers.bash'

setup() {
  setup_test_env
}

teardown() {
  teardown_test_env
}

assert_exporter_direct() {
  local script_name="$1"
  local expected_metric="$2"
  local output_file="${TEST_TMPDIR}/${script_name}.prom"

  run run_exporter_direct "${script_name}" "${output_file}"
  [[ "${status}" -eq 0 ]]
  [[ -s "${output_file}" ]]
  run assert_valid_metric_line "${output_file}"
  [[ "${status}" -eq 0 ]]
  run assert_metric_present "${expected_metric}" "${output_file}"
  [[ "${status}" -eq 0 ]]
}

assert_exporter_missing_proc() {
  local script_name="$1"
  local scrape_metric="$2"
  local output_file="${TEST_TMPDIR}/${script_name}-missing.prom"

  run run_exporter_direct_missing_roots "${script_name}" "${output_file}"
  [[ "${status}" -eq 0 ]]
  [[ -f "${output_file}" ]]
  run assert_scrape_success_zero "${scrape_metric}" "${output_file}"
  [[ "${status}" -eq 0 ]]
}

assert_exporter_out_dir() {
  local exporter="$1"
  local output_dir="${TEST_TMPDIR}/${exporter}-out"
  mkdir -p "${output_dir}"

  run run_collect_one "${exporter}" "${FIXTURE_DIR}/proc" "${output_dir}"
  [[ "${status}" -eq 0 ]]
  [[ -f "${output_dir}/${exporter}.prom" ]]
  [[ -s "${output_dir}/${exporter}.prom" ]]
}

@test "nixl_host_mem direct fixture run emits Prometheus metrics" {
  assert_exporter_direct "nixl-host-mem-exporter.sh" 'nixl_host_fw_pages_sum '
  run assert_metric_present 'nixl_host_meminfo_bytes{field="memavailable"}' "${TEST_TMPDIR}/nixl-host-mem-exporter.sh.prom"
  [[ "${status}" -eq 0 ]]
}

@test "nixl_host_mem missing proc path emits wrapper failure metric" {
  assert_exporter_missing_proc "nixl-host-mem-exporter.sh" "nixl_host_scrape_success"
}

@test "nixl_host_mem respects OUT_DIR via collect-all" {
  assert_exporter_out_dir "nixl_host_mem"
}

@test "nixl_rdma_link direct fixture run emits Prometheus metrics" {
  assert_exporter_direct "rdma-link-exporter.sh" 'nixl_infiniband_counter{device="mlx5_0",port="1",counter="port_rcv_errors"}'
}

@test "nixl_rdma_link missing proc path emits wrapper failure metric" {
  assert_exporter_missing_proc "rdma-link-exporter.sh" "nixl_rdma_scrape_success"
}

@test "nixl_rdma_link respects OUT_DIR via collect-all" {
  assert_exporter_out_dir "nixl_rdma_link"
}

@test "nixl_cpu_irq direct fixture run emits Prometheus metrics" {
  assert_exporter_direct "cpu-irq-exporter.sh" 'nixl_cpu_psi_avg{scope="some",window="60s"}'
}

@test "nixl_cpu_irq missing proc path emits wrapper failure metric" {
  assert_exporter_missing_proc "cpu-irq-exporter.sh" "nixl_cpu_scrape_success"
}

@test "nixl_cpu_irq respects OUT_DIR via collect-all" {
  assert_exporter_out_dir "nixl_cpu_irq"
}

@test "nixl_numa direct fixture run emits Prometheus metrics" {
  assert_exporter_direct "numa-exporter.sh" 'nixl_numa_meminfo_bytes{node="node0",field="memfree"}'
}

@test "nixl_numa missing proc path emits wrapper failure metric" {
  assert_exporter_missing_proc "numa-exporter.sh" "nixl_numa_scrape_success"
}

@test "nixl_numa respects OUT_DIR via collect-all" {
  assert_exporter_out_dir "nixl_numa"
}

@test "nixl_kernel_log direct fixture run emits Prometheus metrics" {
  assert_exporter_direct "kernel-log-scan-exporter.sh" 'nixl_kernel_log_pattern_total{pattern="oom"}'
}

@test "nixl_kernel_log missing proc path emits wrapper failure metric" {
  assert_exporter_missing_proc "kernel-log-scan-exporter.sh" "nixl_kernel_log_scan_success"
}

@test "nixl_kernel_log respects OUT_DIR via collect-all" {
  assert_exporter_out_dir "nixl_kernel_log"
}

@test "nixl_gpu direct fixture run emits Prometheus metrics" {
  assert_exporter_direct "gpu-exporter.sh" 'nixl_gpu_memory_used_bytes{vendor="nvidia",index="0",uuid="GPU-123"}'
}

@test "nixl_gpu missing proc path emits wrapper failure metric" {
  assert_exporter_missing_proc "gpu-exporter.sh" "nixl_gpu_scrape_success"
}

@test "nixl_gpu respects OUT_DIR via collect-all" {
  assert_exporter_out_dir "nixl_gpu"
}

@test "nixl_disk direct fixture run emits Prometheus metrics" {
  assert_exporter_direct "disk-filesystem-exporter.sh" 'nixl_inode_nr{field="allocated"}'
}

@test "nixl_disk missing proc path emits wrapper failure metric" {
  assert_exporter_missing_proc "disk-filesystem-exporter.sh" "nixl_disk_scrape_success"
}

@test "nixl_disk respects OUT_DIR via collect-all" {
  assert_exporter_out_dir "nixl_disk"
}

@test "nixl_network_stack direct fixture run emits Prometheus metrics" {
  assert_exporter_direct "network-stack-exporter.sh" 'nixl_softnet_stat_total{cpu="0",field="dropped"}'
}

@test "nixl_network_stack missing proc path emits wrapper failure metric" {
  assert_exporter_missing_proc "network-stack-exporter.sh" "nixl_network_stack_scrape_success"
}

@test "nixl_network_stack respects OUT_DIR via collect-all" {
  assert_exporter_out_dir "nixl_network_stack"
}

@test "nixl_process_memory direct fixture run emits Prometheus metrics" {
  assert_exporter_direct "process-memory-exporter.sh" 'nixl_process_locked_bytes{pid="100",comm="testproc"}'
}

@test "nixl_process_memory missing proc path emits wrapper failure metric" {
  assert_exporter_missing_proc "process-memory-exporter.sh" "nixl_process_memory_scrape_success"
}

@test "nixl_process_memory respects OUT_DIR via collect-all" {
  assert_exporter_out_dir "nixl_process_memory"
}

@test "nixl_pcie_vfio direct fixture run emits Prometheus metrics" {
  assert_exporter_direct "pcie-vfio-exporter.sh" 'nixl_pcie_device_info{bdf="0000_af_00.0",driver="unbound"'
}

@test "nixl_pcie_vfio missing proc path emits wrapper failure metric" {
  assert_exporter_missing_proc "pcie-vfio-exporter.sh" "nixl_pcie_scrape_success"
}

@test "nixl_pcie_vfio respects OUT_DIR via collect-all" {
  assert_exporter_out_dir "nixl_pcie_vfio"
}

@test "nixl_mce direct fixture run emits Prometheus metrics" {
  assert_exporter_direct "mce-ras-exporter.sh" 'nixl_edac_correctable_errors_total{controller="mc0",channel="dimm0"}'
  run assert_metric_present 'nixl_rasdaemon_ce_total{dimm="DIMM_A1"}' "${TEST_TMPDIR}/mce-ras-exporter.sh.prom"
  [[ "${status}" -eq 0 ]]
}

@test "nixl_mce missing proc path emits degraded scrape success" {
  local output_file="${TEST_TMPDIR}/mce-ras-exporter.sh-missing.prom"

  while IFS= read -r assignment; do
    local name="${assignment%%=*}"
    local value="${assignment#*=}"
    export "${name}=${value}"
  done < <(common_env)

  run env SYS_ROOT="/nonexistent" MCELOG_PATH="/nonexistent" bash "${ROOT_DIR}/scripts/mce-ras-exporter.sh"
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *'nixl_mce_scrape_success{source="edac"} 0 '* ]]
}

@test "nixl_mce respects OUT_DIR via collect-all" {
  assert_exporter_out_dir "nixl_mce"
}

@test "nixl_amd_gpu direct fixture run emits Prometheus metrics" {
  assert_exporter_direct "collect-amd-gpu.sh" 'nixl_gpu_memory_used_bytes{vendor="amd",index="0",uuid="AMD-000"}'
}

@test "nixl_amd_gpu missing proc path emits wrapper failure metric" {
  assert_exporter_missing_proc "collect-amd-gpu.sh" "nixl_amd_gpu_scrape_success"
}

@test "nixl_amd_gpu respects OUT_DIR via collect-all" {
  assert_exporter_out_dir "nixl_amd_gpu"
}

@test "nixl_amd_gpu emits success 0 when rocm-smi is absent" {
  local output_file="${TEST_TMPDIR}/collect-amd-gpu.sh.prom"

  while IFS= read -r assignment; do
    local name="${assignment%%=*}"
    local value="${assignment#*=}"
    export "${name}=${value}"
  done < <(common_env)

  run env ROCM_SMI="${TEST_TMPDIR}/missing-rocm-smi" bash "${ROOT_DIR}/scripts/collect-amd-gpu.sh"
  [[ "${status}" -eq 0 ]]
  [[ "$output" == *'nixl_amd_gpu_scrape_success 0 '* ]]
}

@test "nixl_intel_gpu direct fixture run emits Prometheus metrics" {
  assert_exporter_direct "collect-intel-gpu.sh" 'nixl_gpu_utilization_percent{vendor="intel",index="0",uuid="intel-0"}'
}

@test "nixl_intel_gpu missing proc path emits wrapper failure metric" {
  assert_exporter_missing_proc "collect-intel-gpu.sh" "nixl_intel_gpu_scrape_success"
}

@test "nixl_intel_gpu respects OUT_DIR via collect-all" {
  assert_exporter_out_dir "nixl_intel_gpu"
}

@test "nixl_intel_gpu emits success 0 when intel_gpu_top is absent" {
  while IFS= read -r assignment; do
    local name="${assignment%%=*}"
    local value="${assignment#*=}"
    export "${name}=${value}"
  done < <(common_env)

  run env INTEL_GPU_TOP="${TEST_TMPDIR}/missing-intel-gpu-top" bash "${ROOT_DIR}/scripts/collect-intel-gpu.sh"
  [[ "${status}" -eq 0 ]]
  [[ "$output" == *'nixl_intel_gpu_scrape_success 0 '* ]]
}
