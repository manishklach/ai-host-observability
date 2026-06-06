#!/usr/bin/env bats

load './helpers.bash'

setup() {
  setup_test_env
}

teardown() {
  teardown_test_env
}

assert_exporter_direct() {
  local script_name="$1"
  local output_file="${TEST_TMPDIR}/${script_name}.prom"

  run run_exporter_direct "${script_name}" "${output_file}"
  [ "$status" -eq 0 ]
  [ -s "${output_file}" ]
  run assert_valid_metric_line "${output_file}"
  [ "$status" -eq 0 ]
}

assert_exporter_missing_proc() {
  local exporter="$1"
  local output_dir="${TEST_TMPDIR}/${exporter}-missing"
  mkdir -p "${output_dir}"

  run run_collect_one "${exporter}" "${EMPTY_PROC_ROOT}" "${output_dir}"
  [ "$status" -eq 0 ]
  [ -f "${output_dir}/${exporter}.prom" ]
  run assert_wrapper_failure "${exporter}" "${output_dir}/${exporter}.prom"
  [ "$status" -eq 0 ]
}

assert_exporter_out_dir() {
  local exporter="$1"
  local output_dir="${TEST_TMPDIR}/${exporter}-out"
  mkdir -p "${output_dir}"

  run run_collect_one "${exporter}" "${FIXTURE_DIR}/proc" "${output_dir}"
  [ "$status" -eq 0 ]
  [ -f "${output_dir}/${exporter}.prom" ]
  [ -s "${output_dir}/${exporter}.prom" ]
}

@test "nixl_host_mem direct fixture run emits Prometheus metrics" {
  assert_exporter_direct "nixl-host-mem-exporter.sh"
}

@test "nixl_host_mem missing proc path emits wrapper failure metric" {
  assert_exporter_missing_proc "nixl_host_mem"
}

@test "nixl_host_mem respects OUT_DIR via collect-all" {
  assert_exporter_out_dir "nixl_host_mem"
}

@test "nixl_rdma_link direct fixture run emits Prometheus metrics" {
  assert_exporter_direct "rdma-link-exporter.sh"
}

@test "nixl_rdma_link missing proc path emits wrapper failure metric" {
  assert_exporter_missing_proc "nixl_rdma_link"
}

@test "nixl_rdma_link respects OUT_DIR via collect-all" {
  assert_exporter_out_dir "nixl_rdma_link"
}

@test "nixl_cpu_irq direct fixture run emits Prometheus metrics" {
  assert_exporter_direct "cpu-irq-exporter.sh"
}

@test "nixl_cpu_irq missing proc path emits wrapper failure metric" {
  assert_exporter_missing_proc "nixl_cpu_irq"
}

@test "nixl_cpu_irq respects OUT_DIR via collect-all" {
  assert_exporter_out_dir "nixl_cpu_irq"
}

@test "nixl_numa direct fixture run emits Prometheus metrics" {
  assert_exporter_direct "numa-exporter.sh"
}

@test "nixl_numa missing proc path emits wrapper failure metric" {
  assert_exporter_missing_proc "nixl_numa"
}

@test "nixl_numa respects OUT_DIR via collect-all" {
  assert_exporter_out_dir "nixl_numa"
}

@test "nixl_kernel_log direct fixture run emits Prometheus metrics" {
  assert_exporter_direct "kernel-log-scan-exporter.sh"
}

@test "nixl_kernel_log missing proc path emits wrapper failure metric" {
  assert_exporter_missing_proc "nixl_kernel_log"
}

@test "nixl_kernel_log respects OUT_DIR via collect-all" {
  assert_exporter_out_dir "nixl_kernel_log"
}

@test "nixl_gpu direct fixture run emits Prometheus metrics" {
  assert_exporter_direct "gpu-exporter.sh"
}

@test "nixl_gpu missing proc path emits wrapper failure metric" {
  assert_exporter_missing_proc "nixl_gpu"
}

@test "nixl_gpu respects OUT_DIR via collect-all" {
  assert_exporter_out_dir "nixl_gpu"
}

@test "nixl_disk direct fixture run emits Prometheus metrics" {
  assert_exporter_direct "disk-filesystem-exporter.sh"
}

@test "nixl_disk missing proc path emits wrapper failure metric" {
  assert_exporter_missing_proc "nixl_disk"
}

@test "nixl_disk respects OUT_DIR via collect-all" {
  assert_exporter_out_dir "nixl_disk"
}

@test "nixl_network_stack direct fixture run emits Prometheus metrics" {
  assert_exporter_direct "network-stack-exporter.sh"
}

@test "nixl_network_stack missing proc path emits wrapper failure metric" {
  assert_exporter_missing_proc "nixl_network_stack"
}

@test "nixl_network_stack respects OUT_DIR via collect-all" {
  assert_exporter_out_dir "nixl_network_stack"
}

@test "nixl_process_memory direct fixture run emits Prometheus metrics" {
  assert_exporter_direct "process-memory-exporter.sh"
}

@test "nixl_process_memory missing proc path emits wrapper failure metric" {
  assert_exporter_missing_proc "nixl_process_memory"
}

@test "nixl_process_memory respects OUT_DIR via collect-all" {
  assert_exporter_out_dir "nixl_process_memory"
}

@test "nixl_pcie_vfio direct fixture run emits Prometheus metrics" {
  assert_exporter_direct "pcie-vfio-exporter.sh"
}

@test "nixl_pcie_vfio missing proc path emits wrapper failure metric" {
  assert_exporter_missing_proc "nixl_pcie_vfio"
}

@test "nixl_pcie_vfio respects OUT_DIR via collect-all" {
  assert_exporter_out_dir "nixl_pcie_vfio"
}

