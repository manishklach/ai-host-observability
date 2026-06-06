#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
FIXTURE_DIR="${ROOT_DIR}/tests/fixtures"
TMP_DIR="$(mktemp -d)"
EMPTY_DIR="$(mktemp -d)"

cleanup() {
  rm -rf -- "$TMP_DIR" "$EMPTY_DIR"
}
trap cleanup EXIT

assert_contains() {
  local pattern="$1"
  local file="$2"
  if ! grep -Eq "$pattern" "$file"; then
    echo "expected pattern not found: $pattern in $file" >&2
    exit 1
  fi
}

assert_prom_file() {
  local file="$1"
  assert_contains '^# HELP ' "$file"
  assert_contains '^# TYPE ' "$file"
  assert_contains '^[a-zA-Z_:][a-zA-Z0-9_:]*(\{[^}]*\})? [-0-9.]+ [0-9]+$' "$file"
}

run_exporter() {
  local script_name="$1"
  shift
  local output="${TMP_DIR}/${script_name}.prom"
  (
    cd "$ROOT_DIR"
    env "$@" bash "scripts/${script_name}" >"$output"
  )
  assert_prom_file "$output"
}

find "${ROOT_DIR}/scripts" "${ROOT_DIR}/tests" -name '*.sh' -print0 | xargs -0 -n1 bash -n

if command -v shellcheck >/dev/null 2>&1; then
  find "${ROOT_DIR}/scripts" "${ROOT_DIR}/tests" -name '*.sh' -print0 | xargs -0 shellcheck
fi

escape_output="$(
  cd "$ROOT_DIR"
  bash -lc 'source scripts/lib/prom.sh; prom_set_timestamp 1; emit_metric test_metric 1 "quote=a\"b" "slash=a\\b" "line=one
two"'
)"
if [[ "$escape_output" != *'quote="a\"b"'* || "$escape_output" != *'slash="a\\b"'* || "$escape_output" != *'line="one\ntwo"'* ]]; then
  echo "label escaping test failed" >&2
  exit 1
fi

COMMON_ENV=(
  "PROC_ROOT=${FIXTURE_DIR}/proc"
  "SYS_ROOT=${FIXTURE_DIR}/sys"
  "DEBUGFS_ROOT=${FIXTURE_DIR}/debugfs"
  "CGROUP_PATH=${FIXTURE_DIR}/cgroup/workload"
  "ETHTOOL=${FIXTURE_DIR}/bin/ethtool"
  "NVIDIA_SMI=${FIXTURE_DIR}/bin/nvidia-smi"
  "JOURNALCTL=${FIXTURE_DIR}/bin/journalctl"
  "INTERESTING_DRIVERS_REGEX=.*"
  "NET_IFACES=eth0"
)

run_exporter "nixl-host-mem-exporter.sh" "${COMMON_ENV[@]}"
assert_contains 'nixl_host_fw_pages_total\{device="mlx5_0"\} 1234 ' "${TMP_DIR}/nixl-host-mem-exporter.sh.prom"
assert_contains 'nixl_host_cgroup_memory_current_bytes\{path="' "${TMP_DIR}/nixl-host-mem-exporter.sh.prom"

run_exporter "rdma-link-exporter.sh" "${COMMON_ENV[@]}"
assert_contains 'nixl_infiniband_counter\{device="mlx5_0",port="1",counter="port_rcv_errors"\} 7 ' "${TMP_DIR}/rdma-link-exporter.sh.prom"

run_exporter "cpu-irq-exporter.sh" "${COMMON_ENV[@]}"
assert_contains 'nixl_cpu_psi_avg\{scope="some",window="10s"\} 1\.10 ' "${TMP_DIR}/cpu-irq-exporter.sh.prom"

run_exporter "disk-filesystem-exporter.sh" "${COMMON_ENV[@]}"
assert_contains 'nixl_diskstat_total\{device="sda",field="reads_completed"\} 100 ' "${TMP_DIR}/disk-filesystem-exporter.sh.prom"

run_exporter "gpu-exporter.sh" "${COMMON_ENV[@]}"
assert_contains 'nixl_gpu_info\{index="0",uuid="GPU-123",name="Test GPU A"' "${TMP_DIR}/gpu-exporter.sh.prom"

run_exporter "kernel-log-scan-exporter.sh" "${COMMON_ENV[@]}"
assert_contains 'nixl_kernel_log_pattern_total\{pattern="oom"\} 1 ' "${TMP_DIR}/kernel-log-scan-exporter.sh.prom"

run_exporter "network-stack-exporter.sh" "${COMMON_ENV[@]}"
assert_contains 'nixl_softnet_stat_total\{cpu="0",field="dropped"\} 2 ' "${TMP_DIR}/network-stack-exporter.sh.prom"

run_exporter "numa-exporter.sh" "${COMMON_ENV[@]}"
assert_contains 'nixl_numa_stat\{node="node0",field="numa_hit"\} 100 ' "${TMP_DIR}/numa-exporter.sh.prom"

run_exporter "pcie-vfio-exporter.sh" "${COMMON_ENV[@]}"
assert_contains 'nixl_iommu_group_total 1 ' "${TMP_DIR}/pcie-vfio-exporter.sh.prom"

run_exporter "process-memory-exporter.sh" "${COMMON_ENV[@]}"
assert_contains 'nixl_process_locked_bytes\{pid="100",comm="testproc"\} 32768 ' "${TMP_DIR}/process-memory-exporter.sh.prom"

run_exporter "gpu-exporter.sh" "NVIDIA_SMI=${EMPTY_DIR}/missing-nvidia-smi"
assert_contains 'nixl_gpu_scrape_success 1 ' "${TMP_DIR}/gpu-exporter.sh.prom"

run_exporter "rdma-link-exporter.sh" "SYS_ROOT=${EMPTY_DIR}/sys" "ETHTOOL=${EMPTY_DIR}/missing-ethtool"
assert_contains 'nixl_rdma_scrape_success 1 ' "${TMP_DIR}/rdma-link-exporter.sh.prom"

run_exporter "pcie-vfio-exporter.sh" "PROC_ROOT=${EMPTY_DIR}/proc" "SYS_ROOT=${EMPTY_DIR}/sys"
assert_contains 'nixl_pcie_scrape_success 1 ' "${TMP_DIR}/pcie-vfio-exporter.sh.prom"

echo "test_exporters.sh: ok"
