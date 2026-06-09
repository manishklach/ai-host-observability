#!/usr/bin/env bats
# shellcheck disable=SC2154

load './helpers.bash'

setup() {
  setup_test_env
}

teardown() {
  teardown_test_env
}

@test "triage help works" {
  run bash "${ROOT_DIR}/scripts/ai-host-triage.sh" --help
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *'Usage: ai-host-triage.sh'* ]]
}

@test "triage healthy case is mostly OK" {
  run env OUT_DIR="${FIXTURE_DIR}/prom/healthy" bash "${ROOT_DIR}/scripts/ai-host-triage.sh"
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *'MemAvailable: 48.00 GiB [OK]'* ]]
  [[ "${output}" == *'Likely diagnosis:'* ]]
  [[ "${output}" == *'No strong diagnosis yet.'* ]]
}

@test "triage memory pressure case surfaces critical host pressure" {
  run env OUT_DIR="${FIXTURE_DIR}/prom/memory_pressure" bash "${ROOT_DIR}/scripts/ai-host-triage.sh"
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *'MemAvailable: 2.00 GiB [CRITICAL]'* ]]
  [[ "${output}" == *'Memory PSI some avg60: 7.5% [CRITICAL]'* ]]
  [[ "${output}" == *'Hidden host memory pressure is building.'* ]]
}

@test "triage RDMA growth case mentions mlx5 firmware pages" {
  run env OUT_DIR="${FIXTURE_DIR}/prom/rdma_growth" bash "${ROOT_DIR}/scripts/ai-host-triage.sh"
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *'mlx5 fw_pages_total sum: 18000 [WARN]'* ]]
  [[ "${output}" == *'RDMA registration growth'* ]]
}

@test "triage BAR1 pressure case surfaces GPU host pressure" {
  run env OUT_DIR="${FIXTURE_DIR}/prom/gpu_bar1_pressure" bash "${ROOT_DIR}/scripts/ai-host-triage.sh"
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *'BAR1 usage: 92.0% [CRITICAL]'* ]]
  [[ "${output}" == *'GPU BAR1 pressure is elevated'* ]]
}

@test "triage kernel events case surfaces kernel incident signals" {
  run env OUT_DIR="${FIXTURE_DIR}/prom/kernel_events" bash "${ROOT_DIR}/scripts/ai-host-triage.sh"
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *'Kernel OOM pattern counter: 2 [CRITICAL]'* ]]
  [[ "${output}" == *'Kernel-level incident signals are already present'* ]]
}

@test "triage partial missing case does not fail" {
  run env OUT_DIR="${FIXTURE_DIR}/prom/partial_missing" bash "${ROOT_DIR}/scripts/ai-host-triage.sh"
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *'insufficient data'* ]]
}
